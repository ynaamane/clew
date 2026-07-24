"""A/B pilot driver: Whisper-large-v3 (whisperx) vs Canary-1B-v2 (canary_mlx).

Deterministic, detached compute -- not part of ownscribe's own pipeline.
Fetches (or accepts) a code-switched FR/EN clip + reference transcript,
transcribes it with both engines, computes WER by reference language span
(overall / fra / eng / switch), and optionally runs the continuous-run
thermal test for one or both engines. Writes results.json + verdict.md.

Usage:
    uv run python pilot/run_pilot.py [--clip PATH --reference PATH]
        [--thermal-engine whisperx|canary_mlx|both|none]
        [--thermal-duration-s SECONDS] [--out-dir DIR]

With no --clip/--reference, downloads and uses the public FEBLOC fallback
clip (see fetch_fallback_clip.py) -- runnable without user-provided audio, per
the ticket's requirement. Pass --clip/--reference (reference in the same
JSON shape fetch_fallback_clip.py writes) to run against a real,
Yanis-provided meeting clip instead.

PRE-COMMITTED pass/fail (from the ticket, applied in decide_verdict()):
Canary replaces Whisper as default ONLY if it wins WER-on-switch-spans by
>= 3 absolute WER points AND does not regress attribution AND passes
thermal. Otherwise Whisper-large-v3 stays default.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from dataclasses import asdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from cha_parser import Utterance
from fetch_fallback_clip import fetch_and_prepare
from thermal_test import run_thermal_test
from wer_measurement import HypothesisSegment, wer_by_span


def _load_reference(reference_path: Path) -> tuple[list[Utterance], float]:
    data = json.loads(reference_path.read_text())
    utterances = [
        Utterance(
            speaker=u["speaker"],
            start_ms=u["start_ms"],
            end_ms=u["end_ms"],
            words=u["words"],
            word_languages=u["word_languages"],
        )
        for u in data["utterances"]
    ]
    return utterances, data["window_start_s"]


def _audio_duration_s(audio_path: Path) -> float:
    import subprocess

    cmd = [
        "ffprobe", "-v", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        str(audio_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return float(result.stdout.strip())


def _transcribe_whisperx(audio_path: Path, language: str) -> tuple[list[HypothesisSegment], float]:
    from ownscribe.config import TranscriptionConfig
    from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

    transcriber = WhisperXTranscriber(TranscriptionConfig(language=language), None)
    t0 = time.time()
    result = transcriber.transcribe(audio_path)
    elapsed = time.time() - t0
    segments = [HypothesisSegment(text=s.text, start_s=s.start, end_s=s.end) for s in result.segments]
    return segments, elapsed


def _transcribe_canary(audio_path: Path, language: str) -> tuple[list[HypothesisSegment], float]:
    from ownscribe.config import CanaryConfig, TranscriptionConfig
    from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

    transcriber = CanaryMlxTranscriber(TranscriptionConfig(language=language), CanaryConfig())
    t0 = time.time()
    result = transcriber.transcribe(audio_path)
    elapsed = time.time() - t0
    segments = [HypothesisSegment(text=s.text, start_s=s.start, end_s=s.end) for s in result.segments]
    return segments, elapsed


def _get_engine_fn(engine_name: str):
    """Look up the transcribe function by name from the current module namespace
    rather than a module-level dict of bound references, so a test (or a caller)
    can monkeypatch `run_pilot._transcribe_whisperx`/`_transcribe_canary` directly
    and have it actually take effect."""
    return {"whisperx": _transcribe_whisperx, "canary_mlx": _transcribe_canary}[engine_name]


def decide_verdict(
    wer_results: dict[str, dict[str, float]],
    thermal_results: dict[str, dict],
    switch_win_threshold: float = 3.0,
) -> dict:
    """Apply the ticket's pre-committed pass/fail rule.

    Canary replaces Whisper as default ONLY if:
      1. Canary's switch-span WER beats Whisper's by >= switch_win_threshold
         ABSOLUTE WER POINTS (WER here is a fraction 0-1+; "points" means
         the raw fraction difference * 100, matching how WER is
         conventionally reported).
      2. Canary does not regress attribution (deferred -- see notes; this
         pilot run cannot measure attribution without a diarization-capable
         HF token, see run() below).
      3. Canary passes the thermal test.
    """
    whisper_switch = wer_results.get("whisperx", {}).get("switch", float("nan"))
    canary_switch = wer_results.get("canary_mlx", {}).get("switch", float("nan"))

    if math.isnan(whisper_switch) or math.isnan(canary_switch):
        return {
            "default_engine": "whisperx",
            "reason": (
                "switch-span WER unavailable for one or both engines (NaN) -- "
                "cannot apply the pre-committed rule, Whisper stays default by fallback"
            ),
            "switch_wer_delta_points": None,
        }

    delta_points = (whisper_switch - canary_switch) * 100
    canary_thermal_passed = thermal_results.get("canary_mlx", {}).get("passed", False)

    if delta_points >= switch_win_threshold and canary_thermal_passed:
        return {
            "default_engine": "canary_mlx",
            "reason": (
                f"Canary wins switch-span WER by {delta_points:.1f} points "
                f"(>= {switch_win_threshold}) and passes thermal"
            ),
            "switch_wer_delta_points": delta_points,
        }

    reasons = []
    if delta_points < switch_win_threshold:
        reasons.append(f"switch-span WER delta {delta_points:.1f} points < required {switch_win_threshold}")
    if not canary_thermal_passed and "canary_mlx" in thermal_results:
        reasons.append(f"Canary failed thermal: {thermal_results['canary_mlx'].get('failure_reason')}")
    return {
        "default_engine": "whisperx",
        "reason": "; ".join(reasons) if reasons else "pre-committed bar not met",
        "switch_wer_delta_points": delta_points,
    }


def run(args: argparse.Namespace) -> dict:
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.clip and args.reference:
        clip_path = Path(args.clip)
        reference_path = Path(args.reference)
        clip_source = "user-provided"
    else:
        fetch_result = fetch_and_prepare(out_dir / "fallback_data")
        clip_path = Path(fetch_result["clip_path"])
        reference_path = Path(fetch_result["reference_path"])
        clip_source = "FEBLOC public fallback"

    reference_utterances, window_start_s = _load_reference(reference_path)
    audio_duration = _audio_duration_s(clip_path)
    language = args.language

    wer_results: dict[str, dict[str, float]] = {}
    engine_wall_times: dict[str, float] = {}
    for engine_name in ("whisperx", "canary_mlx"):
        transcribe_fn = _get_engine_fn(engine_name)
        segments, elapsed = transcribe_fn(clip_path, language)
        engine_wall_times[engine_name] = elapsed
        wer_results[engine_name] = wer_by_span(reference_utterances, segments, window_start_s)

    thermal_results: dict[str, dict] = {}
    thermal_targets = []
    if args.thermal_engine == "both":
        thermal_targets = ["whisperx", "canary_mlx"]
    elif args.thermal_engine in ("whisperx", "canary_mlx"):
        thermal_targets = [args.thermal_engine]

    for engine_name in thermal_targets:
        transcribe_fn = _get_engine_fn(engine_name)

        def _once(audio_path: Path, _fn=transcribe_fn) -> None:
            _fn(audio_path, language)

        thermal_result = run_thermal_test(
            _once, clip_path, audio_duration, target_duration_s=args.thermal_duration_s
        )
        thermal_results[engine_name] = asdict(thermal_result)

    verdict = decide_verdict(wer_results, thermal_results)

    results = {
        "clip_source": clip_source,
        "clip_path": str(clip_path),
        "audio_duration_s": audio_duration,
        "reference_utterance_count": len(reference_utterances),
        "language": language,
        "engine_wall_times_s": engine_wall_times,
        "wer_by_engine": wer_results,
        "thermal_by_engine": thermal_results,
        "verdict": verdict,
    }

    (out_dir / "results.json").write_text(json.dumps(results, indent=2, ensure_ascii=False))
    (out_dir / "verdict.md").write_text(_render_verdict_md(results))

    return results


def _render_verdict_md(results: dict) -> str:
    verdict = results["verdict"]
    lines = [
        "# Pilot verdict: Canary-1B-v2 (MLX) vs Whisper-large-v3 (whisperx)",
        "",
        f"**Clip**: {results['clip_source']}, {results['audio_duration_s']:.1f}s, "
        f"{results['reference_utterance_count']} reference utterances, language={results['language']}",
        "",
        f"**Default engine: `{verdict['default_engine']}`**",
        "",
        verdict["reason"],
        "",
        "## WER by span",
        "",
        "| engine | overall | fra | eng | switch |",
        "|---|---|---|---|---|",
    ]
    for engine_name, wer in results["wer_by_engine"].items():
        lines.append(
            f"| {engine_name} | {wer['overall']:.3f} | {wer['fra']:.3f} | {wer['eng']:.3f} | {wer['switch']:.3f} |"
        )
    lines += ["", "## Thermal", ""]
    if results["thermal_by_engine"]:
        for engine_name, thermal in results["thermal_by_engine"].items():
            mean_rtf = thermal.get("mean_rtf", float("nan"))
            lines.append(
                f"- **{engine_name}**: passed={thermal['passed']}, mean_rtf={mean_rtf:.3f}, "
                f"peak_rss_mb={thermal['peak_rss_mb']:.0f}, reason={thermal.get('failure_reason')}"
            )
    else:
        lines.append("Not run this invocation (`--thermal-engine none`).")
    lines += [
        "",
        "## Attribution",
        "",
        "NOT measured in this run -- requires a diarization-capable HuggingFace "
        "token (gated access to pyannote/speaker-diarization-community-1), which "
        "this environment does not have configured. Wire an HF_TOKEN and re-run "
        "with diarization enabled to complete this criterion.",
    ]
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clip", default=None, help="Path to a real audio clip (needs --reference too)")
    parser.add_argument("--reference", default=None, help="Path to a reference JSON (fetch_fallback_clip.py's format)")
    parser.add_argument("--language", default="fr", help="Language code for both engines (default: fr)")
    parser.add_argument(
        "--thermal-engine", choices=["whisperx", "canary_mlx", "both", "none"], default="none",
        help="Which engine(s) to run the continuous-run thermal test on (default: none -- WER-only run)",
    )
    parser.add_argument(
        "--thermal-duration-s", type=float, default=3600.0,
        help="Thermal test target duration (default: 3600 = 60 min)",
    )
    parser.add_argument(
        "--out-dir", default=str(Path(__file__).parent / "results"),
        help="Output directory for results.json/verdict.md",
    )
    args = parser.parse_args()

    results = run(args)
    print(json.dumps(results["verdict"], indent=2))


if __name__ == "__main__":
    main()
