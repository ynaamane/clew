"""CLI entry point for clew."""

from __future__ import annotations

import logging
import os
import shutil
import subprocess
from pathlib import Path

import click

from clew.config import CONFIG_DIR, LEGACY_CONFIG_DIR, LEGACY_OUTPUT_DEFAULT, Config, ensure_config_file
from clew.speakers.base import LEGACY_VOICEPRINT_DIR, VOICEPRINT_DIR

_SUMMARIZATION_LOGGER_NAME = "clew.summarization"


def configure_summarization_logging() -> None:
    """Give clew.summarization's own INFO-level diagnostics (e.g. the local
    model's chosen n_ctx, llama_cpp_summarizer.py) a handler.

    Python's logging module attaches none by default, so that logger.info() call
    was silently dropped -- invisible in CLI output (INFO #12, 2026-08-24 session).
    Scoped to the clew.summarization namespace only (propagate=False stops it there,
    never reaching the root logger): no unrelated module -- root, third-party deps,
    other clew modules -- suddenly gains new stderr output. Idempotent: safe to call
    on every cli() invocation.
    """
    logger = logging.getLogger(_SUMMARIZATION_LOGGER_NAME)
    if logger.handlers:
        return
    handler = logging.StreamHandler()
    handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    logger.propagate = False


# Canonical paths for cleanup
_CACHE_DIR = os.path.expanduser("~/.local/share/ownscribe")
_CONFIG_DIR = str(CONFIG_DIR)
_VOICEPRINT_DIR = str(VOICEPRINT_DIR)

# Legacy paths from the ownscribe/meeting-scribe era, and the new default they migrate
# to. Only touched by migrate_legacy_paths(), called once from main() -- never from
# cli() itself, so CliRunner-driven tests never trigger a real filesystem move (see
# main()'s docstring).
_LEGACY_CONFIG_DIR = str(LEGACY_CONFIG_DIR)
_LEGACY_VOICEPRINT_DIR = str(LEGACY_VOICEPRINT_DIR)
_LEGACY_OUTPUT_DEFAULT = LEGACY_OUTPUT_DEFAULT
_NEW_OUTPUT_DEFAULT = "~/clew"


def _migrate_dir(old: str, new: str, label: str) -> None:
    """Move old -> new once, only when new is absent and old exists.

    Never overwrites: if the new location already exists (already migrated, or a
    fresh install with no legacy data), this is a no-op. If old doesn't exist either,
    also a no-op. Safe to call on every startup.
    """
    old_path, new_path = Path(old).expanduser(), Path(new).expanduser()
    if new_path.exists() or not old_path.exists():
        return
    new_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(old_path), str(new_path))
    click.echo(f"clew: migrated {label} from {old_path} to {new_path}", err=True)


def _migrate_output_dir(cfg: Config) -> None:
    """Move the default output directory (~/ownscribe -> ~/clew) once, and only for
    users who never customized it away from the shipped default.

    Handles both cases that lead to cfg.output.dir holding a default value: a
    config.toml written before this rename (literal "~/ownscribe") and one written
    after (literal "~/clew", or no config.toml at all -- the dataclass default).
    A custom `dir` value in either form never matches and is never touched.
    """
    if cfg.output.dir not in (_LEGACY_OUTPUT_DEFAULT, _NEW_OUTPUT_DEFAULT):
        return
    old_path, new_path = Path(_LEGACY_OUTPUT_DEFAULT).expanduser(), Path(_NEW_OUTPUT_DEFAULT).expanduser()
    if new_path.exists() or not old_path.exists():
        return
    new_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(old_path), str(new_path))
    click.echo(f"clew: migrated output directory from {old_path} to {new_path}", err=True)
    if cfg.output.dir == _LEGACY_OUTPUT_DEFAULT:
        cfg.output.dir = _NEW_OUTPUT_DEFAULT
        _rewrite_legacy_output_default_in_config_file()


def _rewrite_legacy_output_default_in_config_file() -> None:
    """Patch a persisted config.toml's literal `dir = "~/ownscribe"` default to
    `dir = "~/clew"`, so future runs pick up the new default directly without
    re-running the directory move. A no-op if the file doesn't exist or the user
    already edited that line to something else.
    """
    config_path = Path(_CONFIG_DIR) / "config.toml"
    if not config_path.exists():
        return
    text = config_path.read_text()
    legacy_line = f'dir = "{_LEGACY_OUTPUT_DEFAULT}"'
    if legacy_line not in text:
        return
    config_path.write_text(text.replace(legacy_line, f'dir = "{_NEW_OUTPUT_DEFAULT}"', 1))


def migrate_legacy_paths(cfg: Config | None) -> None:
    """One-time startup migration from the ownscribe/meeting-scribe legacy layout
    (~/.config/ownscribe, ~/.config/meeting-scribe/voiceprints, ~/ownscribe) to the
    clew layout (~/.config/clew, ~/.config/clew/voiceprints, ~/clew).

    Idempotent and additive-only: every step moves a directory exactly once, only
    when the new location is absent and the old one exists, and never overwrites or
    deletes anything. A location the user pointed somewhere else (custom
    `output.dir`) is never touched.
    """
    _migrate_dir(_LEGACY_CONFIG_DIR, _CONFIG_DIR, "config")
    _migrate_dir(_LEGACY_VOICEPRINT_DIR, _VOICEPRINT_DIR, "voiceprints")
    if cfg is not None:
        _migrate_output_dir(cfg)


def _dir_size(path: str) -> str:
    """Human-readable size of a directory tree, or '(not found)' if missing."""
    from pathlib import Path

    p = Path(path)
    if not p.exists():
        return "(not found)"
    total = sum(f.stat().st_size for f in p.rglob("*") if f.is_file())
    for unit in ("B", "KB", "MB", "GB"):
        if total < 1024:
            return f"{total:.1f} {unit}"
        total /= 1024
    return f"{total:.1f} TB"


@click.group(invoke_without_command=True)
@click.option("--device", default=None, help="Audio input device name or index.")
@click.option("--no-summarize", is_flag=True, help="Skip LLM summarization.")
@click.option("--diarize", is_flag=True, help="Enable speaker diarization (needs HF token).")
@click.option("--format", "output_format", type=click.Choice(["markdown", "json"]), default=None, help="Output format.")
@click.option("--model", default=None, help="Whisper model size (tiny, base, small, medium, large-v3).")
@click.option("--language", default=None, help="Language code for transcription (e.g. en, de, fr).")
@click.option("--initial-prompt", default=None, help="Context text to prime Whisper (vocab, speaker names, etc.)")
@click.option("--hotwords", default=None, help="Comma-separated words to boost Whisper recognition.")
@click.option("--mic", is_flag=True, help="Also capture microphone input (mixed with system audio).")
@click.option("--mic-device", default=None, help="Specific mic device name (implies --mic).")
@click.option(
    "--keep-recording/--no-keep-recording",
    default=None,
    help="Keep or delete WAV recordings after transcription.",
)
@click.option("--template", default=None, help="Summarization template (meeting, lecture, brief, or custom).")
@click.option(
    "--silence-timeout",
    default=None,
    type=click.IntRange(min=0),
    help="Seconds of silence before auto-stopping recording (0 to disable).",
)
@click.option(
    "--progress",
    "progress_mode",
    type=click.Choice(["tui", "json"]),
    default=None,
    help="Progress display: 'tui' (default, animated checklist) or 'json' (one NDJSON event per line on stderr).",
)
@click.pass_context
def cli(
    ctx: click.Context,
    device: str | None,
    no_summarize: bool,
    diarize: bool,
    output_format: str | None,
    model: str | None,
    language: str | None,
    initial_prompt: str | None,
    hotwords: str | None,
    mic: bool,
    mic_device: str | None,
    keep_recording: bool | None,
    template: str | None,
    silence_timeout: int | None,
    progress_mode: str | None,
) -> None:
    """Fully local meeting transcription and summarization.

    Run without a subcommand to record, transcribe, and summarize a meeting.
    """
    configure_summarization_logging()
    ctx.ensure_object(dict)
    try:
        config = Config.load()
    except ValueError as e:
        hint = f"Fix it in {CONFIG_DIR}/config.toml, or unset the key to use the default."
        raise click.ClickException(f"{e}\n{hint}") from e

    # Apply CLI overrides
    if device is not None:
        config.audio.device = device
        if config.audio.backend == "coreaudio" and device:
            config.audio.backend = "sounddevice"
    if no_summarize:
        config.summarization.enabled = False
    if diarize:
        config.diarization.enabled = True
    if output_format:
        config.output.format = output_format
    if model:
        config.transcription.model = model
    if language:
        config.transcription.language = language
    if initial_prompt:
        config.transcription.initial_prompt = initial_prompt
    if hotwords:
        config.transcription.hotwords = hotwords
    if mic or mic_device:
        config.audio.mic = True
    if mic_device:
        config.audio.mic_device = mic_device
    if keep_recording is not None:
        config.output.keep_recording = keep_recording
    if template:
        config.summarization.template = template
    if silence_timeout is not None:
        config.audio.silence_timeout = silence_timeout
    if progress_mode:
        config.progress_mode = progress_mode

    ctx.obj["config"] = config

    if ctx.invoked_subcommand is None:
        from clew.pipeline import run_pipeline

        run_pipeline(config)


def main() -> None:
    """Real process entry point (the `clew` / `ownscribe` console script).

    Runs the one-time legacy-path migration, then hands off to the `cli` Click
    group. Deliberately NOT part of cli()'s own callback: cli() is also what
    CliRunner.invoke(cli, ...) drives in tests, and a Click group's callback runs
    on every invocation including `--help` on a subcommand. Keeping migration in
    this separate wrapper means the test suite -- which calls `cli` directly and
    never `main()` -- can never trigger a real filesystem move, with no per-test
    mocking required. See migrate_legacy_paths()'s docstring for the migration
    itself.
    """
    migrate_legacy_paths(None)
    try:
        cfg = Config.load()
    except ValueError:
        cfg = None  # let cli() surface the real error message; migration is best-effort
    if cfg is not None:
        migrate_legacy_paths(cfg)
    cli()


@cli.command()
@click.argument("question")
@click.option("--since", default=None, help="Only search meetings after this date (YYYY-MM-DD).")
@click.option("--limit", default=None, type=int, help="Max number of recent meetings to search.")
@click.pass_context
def ask(ctx: click.Context, question: str, since: str | None, limit: int | None) -> None:
    """Ask a question across your meeting notes."""
    config = ctx.obj["config"]
    from clew.search import ask as run_ask

    run_ask(config, question, since=since, limit=limit)


@cli.command()
def devices() -> None:
    """List available audio input devices."""
    from clew.audio.coreaudio import CoreAudioRecorder

    recorder = CoreAudioRecorder()
    if recorder.is_available():
        click.echo(recorder.list_devices())
    else:
        import sounddevice as sd

        click.echo("Available audio devices:\n")
        click.echo(sd.query_devices())


@cli.command()
@click.option(
    "--sustained-seconds",
    default=3.0,
    type=float,
    help="Seconds of continuous mic+output activity before starting a recording (default 3).",
)
@click.pass_context
def watch(ctx: click.Context, sustained_seconds: float) -> None:
    """Wait for a meeting to start (sustained mic AND output activity together), then record it."""
    config = ctx.obj["config"]
    from clew.pipeline import run_watch

    run_watch(config, sustained_seconds)


@cli.command()
@click.argument("file", type=click.Path(exists=True))
@click.option("--diarize", is_flag=True, help="Enable speaker diarization.")
@click.option("--model", default=None, help="Whisper model size.")
@click.option("--language", default=None, help="Language code for transcription (e.g. en, de, fr).")
@click.option("--format", "output_format", type=click.Choice(["markdown", "json"]), default=None)
@click.pass_context
def transcribe(
    ctx: click.Context,
    file: str,
    diarize: bool,
    model: str | None,
    language: str | None,
    output_format: str | None,
) -> None:
    """Transcribe an audio file."""
    config = ctx.obj["config"]
    if diarize:
        config.diarization.enabled = True
    if model:
        config.transcription.model = model
    if language:
        config.transcription.language = language
    if output_format:
        config.output.format = output_format

    from clew.pipeline import run_transcribe

    run_transcribe(config, file)


@cli.command()
@click.option("--model", default=None, help="Whisper model size.")
@click.option("--language", default=None, help="Language code to prefetch alignment model for (e.g. en, de, fr).")
@click.option(
    "--with-diarization/--no-diarization",
    "with_diarization",
    default=None,
    help="Override diarization warmup (defaults to config setting).",
)
@click.pass_context
def warmup(
    ctx: click.Context,
    model: str | None,
    language: str | None,
    with_diarization: bool | None,
) -> None:
    """Prefetch WhisperX/pyannote models to avoid first-run stalls."""
    config = ctx.obj["config"]
    if model:
        config.transcription.model = model
    if language:
        config.transcription.language = language
    if with_diarization is not None:
        config.diarization.enabled = with_diarization

    from clew.pipeline import run_warmup

    run_warmup(config)


@cli.command()
@click.argument("file", type=click.Path(exists=True))
@click.option("--template", default=None, help="Summarization template (meeting, lecture, brief, or custom).")
@click.pass_context
def summarize(ctx: click.Context, file: str, template: str | None) -> None:
    """Summarize a transcript file."""
    config = ctx.obj["config"]
    if template:
        config.summarization.template = template

    from clew.pipeline import run_summarize

    run_summarize(config, file)


@cli.command()
@click.argument("directory", type=click.Path(exists=True, file_okay=False))
@click.option("--diarize", is_flag=True, help="Enable speaker diarization (needs HF token).")
@click.option("--model", default=None, help="Whisper model size (tiny, base, small, medium, large-v3).")
@click.option("--language", default=None, help="Language code for transcription (e.g. en, de, fr).")
@click.option("--template", default=None, help="Summarization template (meeting, lecture, brief, or custom).")
@click.pass_context
def resume(
    ctx: click.Context,
    directory: str,
    diarize: bool,
    model: str | None,
    language: str | None,
    template: str | None,
) -> None:
    """Resume a partially-completed pipeline in a meeting directory."""
    config = ctx.obj["config"]
    if diarize:
        config.diarization.enabled = True
    if model:
        config.transcription.model = model
    if language:
        config.transcription.language = language
    if template:
        config.summarization.template = template

    from clew.pipeline import run_resume

    run_resume(config, directory)


@cli.command()
@click.argument("directory", type=click.Path(exists=True, file_okay=False))
@click.option("--diarize", is_flag=True, help="Enable speaker diarization (needs HF token).")
@click.option("--model", default=None, help="Whisper model size (tiny, base, small, medium, large-v3).")
@click.option("--language", default=None, help="Language code for transcription (e.g. en, de, fr).")
@click.option("--template", default=None, help="Summarization template (meeting, lecture, brief, or custom).")
@click.pass_context
def reprocess(
    ctx: click.Context,
    directory: str,
    diarize: bool,
    model: str | None,
    language: str | None,
    template: str | None,
) -> None:
    """Force a full re-transcribe+summarize from retained audio, even if output already exists."""
    config = ctx.obj["config"]
    if diarize:
        config.diarization.enabled = True
    if model:
        config.transcription.model = model
    if language:
        config.transcription.language = language
    if template:
        config.summarization.template = template

    from clew.pipeline import run_reprocess

    run_reprocess(config, directory)


@cli.command()
@click.argument("directory", type=click.Path(exists=True, file_okay=False), required=False)
@click.pass_context
def backfill(ctx: click.Context, directory: str | None) -> None:
    """Add missing envelope.json/anchors.json to meetings that already have transcript+summary.

    Scans every meeting directory when DIRECTORY is omitted. Never re-runs ASR or the LLM,
    and never rewrites or deletes an existing file.
    """
    config = ctx.obj["config"]
    from clew.pipeline import run_backfill

    run_backfill(config, directory)


@cli.command()
@click.option(
    "--older-than",
    "older_than_days",
    default=None,
    type=click.IntRange(min=0),
    help="Purge retained audio older than this many days (overrides retention_days from config).",
)
@click.option("--all", "purge_all", is_flag=True, help="Purge all retained audio regardless of age.")
@click.option("--dry-run", is_flag=True, help="List what would be purged without deleting anything.")
@click.pass_context
def purge(ctx: click.Context, older_than_days: int | None, purge_all: bool, dry_run: bool) -> None:
    """Delete retained audio according to the retention policy (keep-N-days, forever, or --all)."""
    config = ctx.obj["config"]
    from clew.pipeline import run_purge

    run_purge(config, older_than_days, purge_all, dry_run)


@cli.command()
@click.option("--name", required=True, help="Name to enroll this speaker's voice as.")
@click.argument("file", type=click.Path(exists=True))
@click.pass_context
def enroll(ctx: click.Context, name: str, file: str) -> None:
    """Enroll a speaker's voiceprint from a short reference audio clip."""
    config = ctx.obj["config"]
    from clew.pipeline import run_enroll

    run_enroll(config, name, file)


@cli.command()
@click.argument("name")
def unenroll(name: str) -> None:
    """Remove an enrolled speaker's voiceprint."""
    from clew.pipeline import run_unenroll

    run_unenroll(name)


@cli.command("speakers")
def list_speakers() -> None:
    """List all enrolled speaker names."""
    from clew.pipeline import run_list_enrolled

    run_list_enrolled()


@cli.command("enroll-cluster")
@click.argument("directory", type=click.Path(exists=True, file_okay=False))
@click.option("--cluster", required=True, help="Diarized cluster label to enroll (e.g. SPEAKER_00).")
@click.option("--name", required=True, help="Name to enroll this cluster's voice as.")
@click.pass_context
def enroll_cluster_cmd(ctx: click.Context, directory: str, cluster: str, name: str) -> None:
    """Confirm a speaker-name enrollment for one diarized cluster of a
    transcribed meeting -- either a `suggest-enrollment` candidate or a cluster
    you identified yourself. Never runs on its own; this is always an explicit,
    separate confirmation step."""
    config = ctx.obj["config"]
    from clew.pipeline import run_enroll_cluster

    run_enroll_cluster(config, directory, cluster, name)


@cli.command("suggest-enrollment")
@click.argument("directory", type=click.Path(exists=True, file_okay=False))
@click.pass_context
def suggest_enrollment_cmd(ctx: click.Context, directory: str) -> None:
    """Suggest speaker-name enrollments for a meeting, from deterministic evidence
    arbitrated by the local LLM -- gated at >=2 independent evidences, never
    auto-enrolls. Confirm any suggestion with `clew enroll`."""
    config = ctx.obj["config"]
    from pathlib import Path

    from clew.speakers.enrollment_suggest import build_evidence_table, load_transcript_result, suggest_enrollments
    from clew.summarization import create_summarizer

    transcript = load_transcript_result(Path(directory))
    table = build_evidence_table(transcript, roster=config.speakers.known)
    with create_summarizer(config) as summarizer:
        suggestions = suggest_enrollments(table, summarizer, roster=config.speakers.known)

    if not suggestions:
        click.echo("No enrollment suggestions (insufficient independent evidence).")
        return

    for suggestion in suggestions:
        click.echo(
            f"{suggestion.cluster} -> {suggestion.name}  "
            f"(confidence: {suggestion.confidence}, evidence: {len(suggestion.evidence)})"
        )


@cli.command()
def apps() -> None:
    """List running apps with PIDs for use with --pid."""
    from clew.audio.coreaudio import CoreAudioRecorder

    recorder = CoreAudioRecorder()
    click.echo(recorder.list_apps())


@cli.command("config")
def config_cmd() -> None:
    """Open the configuration file in your editor."""
    path = ensure_config_file()
    editor = os.environ.get("EDITOR", "nano")
    click.echo(f"Opening {path} with {editor}...")
    subprocess.run([editor, str(path)])


@cli.command()
@click.option("--yes", "-y", is_flag=True, help="Skip confirmation prompts.")
@click.option("--all", "all_", is_flag=True, help="Remove everything (config + cache + output + voiceprints).")
@click.option("--config", "config_", is_flag=True, help="Remove config directory (~/.config/clew/).")
@click.option("--cache", is_flag=True, help="Remove cached binary (~/.local/share/ownscribe/).")
@click.option("--output", is_flag=True, help="Remove output directory with recordings/transcripts.")
@click.pass_context
def cleanup(
    ctx: click.Context,
    yes: bool,
    all_: bool,
    config_: bool,
    cache: bool,
    output: bool,
) -> None:
    """Remove clew data from disk (config, cache, recordings)."""
    cfg = ctx.obj["config"]
    output_dir = str(cfg.output.resolved_dir)
    audio_dir = str(cfg.output.resolved_audio_dir)

    targets: list[tuple[str, str]] = []

    if all_:
        targets = [
            ("Config", _CONFIG_DIR),
            ("Cache", _CACHE_DIR),
            ("Output", output_dir),
            ("Voiceprints", _VOICEPRINT_DIR),
        ]
        if audio_dir != output_dir:
            targets.append(("Audio", audio_dir))
    elif config_ or cache or output:
        if config_:
            targets.append(("Config", _CONFIG_DIR))
        if cache:
            targets.append(("Cache", _CACHE_DIR))
        if output:
            targets.append(("Output", output_dir))
            if audio_dir != output_dir:
                targets.append(("Audio", audio_dir))
    else:
        candidates = [
            ("Config", _CONFIG_DIR),
            ("Cache", _CACHE_DIR),
            ("Output", output_dir),
            ("Voiceprints", _VOICEPRINT_DIR),
        ]
        if audio_dir != output_dir:
            candidates.append(("Audio", audio_dir))
        # Interactive: prompt for each directory
        for label, path in candidates:
            size = _dir_size(path)
            if size == "(not found)":
                click.echo(f"  {label}: {path} — {size}, skipping")
                continue
            if yes or click.confirm(f"  Remove {label}: {path} ({size})?"):
                targets.append((label, path))
        if not targets:
            click.echo("Nothing to remove.")
        return _remove_targets(targets)

    if not yes:
        click.echo("The following directories will be removed:")
        for label, path in targets:
            click.echo(f"  {label}: {path} ({_dir_size(path)})")
        if not click.confirm("Proceed?"):
            click.echo("Aborted.")
            return

    _remove_targets(targets)


def _remove_targets(targets: list[tuple[str, str]]) -> None:
    """Delete the listed directories."""
    from pathlib import Path

    for label, path in targets:
        p = Path(path)
        if p.exists():
            shutil.rmtree(p)
            click.echo(f"  Removed {label}: {path}")
        else:
            click.echo(f"  {label}: {path} — not found, skipping")
