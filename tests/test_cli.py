"""Tests for CLI command parsing."""

from __future__ import annotations

import logging
from unittest import mock

import pytest
from click.testing import CliRunner

import clew.cli as cli_module
from clew.cli import cli
from clew.config import Config


def _mock_config(config: Config | None = None):
    """Return a mock that makes Config.load() return a default Config."""
    return mock.patch("clew.cli.Config.load", return_value=config or Config())


class TestMainCommand:
    def test_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["--help"])
        assert result.exit_code == 0
        assert "Fully local meeting transcription and summarization" in result.output

    def test_no_summarize_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--no-summarize"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.summarization.enabled is False

    def test_mic_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--mic"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.audio.mic is True

    def test_device_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--device", "USB Mic"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.audio.device == "USB Mic"
            assert config.audio.backend == "sounddevice"

    def test_model_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--model", "large-v3"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.transcription.model == "large-v3"

    def test_language_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--language", "de"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.transcription.language == "de"

    def test_silence_timeout_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--silence-timeout", "60"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.audio.silence_timeout == 60

    def test_silence_timeout_disable(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--silence-timeout", "0"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.audio.silence_timeout == 0


class TestSubcommandHelp:
    def test_transcribe_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["transcribe", "--help"])
        assert result.exit_code == 0
        assert "Transcribe an audio file" in result.output

    def test_summarize_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["summarize", "--help"])
        assert result.exit_code == 0
        assert "Summarize a transcript file" in result.output

    def test_devices_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["devices", "--help"])
        assert result.exit_code == 0
        assert "List available audio input devices" in result.output

    def test_config_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["config", "--help"])
        assert result.exit_code == 0
        assert "Open the configuration file" in result.output

    def test_resume_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["resume", "--help"])
        assert result.exit_code == 0
        assert "Resume a partially-completed pipeline" in result.output

    def test_reprocess_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["reprocess", "--help"])
        assert result.exit_code == 0
        assert "Force a full re-transcribe+summarize" in result.output

    def test_purge_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["purge", "--help"])
        assert result.exit_code == 0
        assert "Delete retained audio according to the retention policy" in result.output

    def test_warmup_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["warmup", "--help"])
        assert result.exit_code == 0
        assert "Prefetch WhisperX/pyannote models" in result.output

    def test_cleanup_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["cleanup", "--help"])
        assert result.exit_code == 0
        assert "Remove clew data from disk" in result.output


class TestKeepRecordingFlag:
    def test_keep_recording_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--no-keep-recording"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.output.keep_recording is False

    def test_keep_recording_default_is_true(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, [])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.output.keep_recording is True


class TestProgressFlag:
    def test_progress_json_flag_sets_config(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--progress", "json"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.progress_mode == "json"

    def test_progress_default_is_tui(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, [])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.progress_mode == "tui"

    def test_progress_rejects_unknown_value(self):
        runner = CliRunner()
        with _mock_config():
            result = runner.invoke(cli, ["--progress", "xml"])
            assert result.exit_code != 0

    def test_progress_flag_applies_to_transcribe_subcommand(self, tmp_path):
        runner = CliRunner()
        audio_path = tmp_path / "recording.wav"
        audio_path.touch()

        with _mock_config(), mock.patch("clew.pipeline.run_transcribe") as mock_transcribe:
            result = runner.invoke(cli, ["--progress", "json", "transcribe", str(audio_path)])
            assert result.exit_code == 0
            config = mock_transcribe.call_args[0][0]
            assert config.progress_mode == "json"


class TestWarmupCommand:
    def test_warmup_invokes_pipeline_with_overrides(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_warmup") as mock_warmup:
            result = runner.invoke(cli, ["warmup", "--model", "large-v3", "--language", "de", "--with-diarization"])

        assert result.exit_code == 0
        config = mock_warmup.call_args[0][0]
        assert config.transcription.model == "large-v3"
        assert config.transcription.language == "de"
        assert config.diarization.enabled is True


class TestResumeCommand:
    def test_resume_invokes_pipeline_with_overrides(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_resume") as mock_resume:
            result = runner.invoke(
                cli,
                ["resume", str(tmp_path), "--model", "large-v3", "--language", "fr", "--template", "brief"],
            )

        assert result.exit_code == 0
        config = mock_resume.call_args[0][0]
        assert config.transcription.model == "large-v3"
        assert config.transcription.language == "fr"
        assert config.summarization.template == "brief"
        assert mock_resume.call_args[0][1] == str(tmp_path)

    def test_resume_diarize_flag_enables_diarization(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_resume") as mock_resume:
            result = runner.invoke(cli, ["resume", str(tmp_path), "--diarize"])

        assert result.exit_code == 0
        config = mock_resume.call_args[0][0]
        assert config.diarization.enabled is True

    def test_resume_without_diarize_flag_does_not_enable_diarization(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_resume") as mock_resume:
            result = runner.invoke(cli, ["resume", str(tmp_path)])

        assert result.exit_code == 0
        config = mock_resume.call_args[0][0]
        assert config.diarization.enabled is False

    def test_resume_requires_existing_directory(self):
        runner = CliRunner()
        with _mock_config():
            result = runner.invoke(cli, ["resume", "/no/such/directory"])
        assert result.exit_code != 0


class TestReprocessCommand:
    def test_reprocess_invokes_pipeline_with_overrides(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_reprocess") as mock_reprocess:
            result = runner.invoke(
                cli,
                ["reprocess", str(tmp_path), "--model", "large-v3", "--language", "fr", "--template", "brief"],
            )

        assert result.exit_code == 0
        config = mock_reprocess.call_args[0][0]
        assert config.transcription.model == "large-v3"
        assert config.transcription.language == "fr"
        assert config.summarization.template == "brief"
        assert mock_reprocess.call_args[0][1] == str(tmp_path)

    def test_reprocess_diarize_flag_enables_diarization(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_reprocess") as mock_reprocess:
            result = runner.invoke(cli, ["reprocess", str(tmp_path), "--diarize"])

        assert result.exit_code == 0
        config = mock_reprocess.call_args[0][0]
        assert config.diarization.enabled is True

    def test_reprocess_without_diarize_flag_does_not_enable_diarization(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_reprocess") as mock_reprocess:
            result = runner.invoke(cli, ["reprocess", str(tmp_path)])

        assert result.exit_code == 0
        config = mock_reprocess.call_args[0][0]
        assert config.diarization.enabled is False

    def test_reprocess_requires_existing_directory(self):
        runner = CliRunner()
        with _mock_config():
            result = runner.invoke(cli, ["reprocess", "/no/such/directory"])
        assert result.exit_code != 0


class TestPurgeCommand:
    def test_purge_default_forwards_none_and_false(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_purge") as mock_purge:
            result = runner.invoke(cli, ["purge"])

        assert result.exit_code == 0
        mock_purge.assert_called_once()
        _config, older_than_days, purge_all, dry_run = mock_purge.call_args[0]
        assert older_than_days is None
        assert purge_all is False
        assert dry_run is False

    def test_purge_older_than_and_dry_run_flags(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_purge") as mock_purge:
            result = runner.invoke(cli, ["purge", "--older-than", "14", "--dry-run"])

        assert result.exit_code == 0
        _, older_than_days, purge_all, dry_run = mock_purge.call_args[0]
        assert older_than_days == 14
        assert purge_all is False
        assert dry_run is True

    def test_purge_all_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_purge") as mock_purge:
            result = runner.invoke(cli, ["purge", "--all"])

        assert result.exit_code == 0
        _, _, purge_all, _ = mock_purge.call_args[0]
        assert purge_all is True


class TestBackfillCommand:
    def test_backfill_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["backfill", "--help"])
        assert result.exit_code == 0
        assert "envelope.json" in result.output
        assert "anchors.json" in result.output

    def test_backfill_with_directory_forwards_it(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_backfill") as mock_backfill:
            result = runner.invoke(cli, ["backfill", str(tmp_path)])

        assert result.exit_code == 0
        mock_backfill.assert_called_once()
        _config, directory = mock_backfill.call_args[0]
        assert directory == str(tmp_path)

    def test_backfill_without_directory_forwards_none(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_backfill") as mock_backfill:
            result = runner.invoke(cli, ["backfill"])

        assert result.exit_code == 0
        mock_backfill.assert_called_once()
        _config, directory = mock_backfill.call_args[0]
        assert directory is None

    def test_backfill_requires_existing_directory_when_given(self):
        runner = CliRunner()
        with _mock_config():
            result = runner.invoke(cli, ["backfill", "/no/such/directory"])
        assert result.exit_code != 0


class TestCleanup:
    def test_all_yes_removes_dirs(self, tmp_path):
        config_dir = tmp_path / "config"
        cache_dir = tmp_path / "cache"
        output_dir = tmp_path / "output"
        voiceprint_dir = tmp_path / "voiceprints"
        for d in (config_dir, cache_dir, output_dir, voiceprint_dir):
            d.mkdir()
            (d / "file.txt").write_text("data")

        cfg = Config()
        cfg.output.dir = str(output_dir)

        runner = CliRunner()
        with (
            _mock_config(cfg),
            mock.patch("clew.cli._CONFIG_DIR", str(config_dir)),
            mock.patch("clew.cli._CACHE_DIR", str(cache_dir)),
            mock.patch("clew.cli._VOICEPRINT_DIR", str(voiceprint_dir)),
        ):
            result = runner.invoke(cli, ["cleanup", "--all", "--yes"])

        assert result.exit_code == 0
        assert not config_dir.exists()
        assert not cache_dir.exists()
        assert not output_dir.exists()
        assert "Removed Config" in result.output
        assert "Removed Cache" in result.output
        assert "Removed Output" in result.output

    def test_all_yes_removes_separate_audio_dir(self, tmp_path):
        config_dir = tmp_path / "config"
        cache_dir = tmp_path / "cache"
        output_dir = tmp_path / "output"
        audio_dir = tmp_path / "audio-cache"
        voiceprint_dir = tmp_path / "voiceprints"
        for d in (config_dir, cache_dir, output_dir, audio_dir, voiceprint_dir):
            d.mkdir()
            (d / "file.txt").write_text("data")

        cfg = Config()
        cfg.output.dir = str(output_dir)
        cfg.output.audio_dir = str(audio_dir)

        runner = CliRunner()
        with (
            _mock_config(cfg),
            mock.patch("clew.cli._CONFIG_DIR", str(config_dir)),
            mock.patch("clew.cli._CACHE_DIR", str(cache_dir)),
            mock.patch("clew.cli._VOICEPRINT_DIR", str(voiceprint_dir)),
        ):
            result = runner.invoke(cli, ["cleanup", "--all", "--yes"])

        assert result.exit_code == 0
        assert not output_dir.exists()
        assert not audio_dir.exists()
        assert "Removed Audio" in result.output

    def test_config_only(self, tmp_path):
        config_dir = tmp_path / "config"
        cache_dir = tmp_path / "cache"
        output_dir = tmp_path / "output"
        config_dir.mkdir()
        cache_dir.mkdir()
        output_dir.mkdir()

        cfg = Config()
        cfg.output.dir = str(output_dir)

        runner = CliRunner()
        with (
            _mock_config(cfg),
            mock.patch("clew.cli._CONFIG_DIR", str(config_dir)),
            mock.patch("clew.cli._CACHE_DIR", str(cache_dir)),
        ):
            result = runner.invoke(cli, ["cleanup", "--config", "--yes"])

        assert result.exit_code == 0
        assert not config_dir.exists()
        assert cache_dir.exists()
        assert output_dir.exists()

    def test_output_only_also_removes_audio_dir(self, tmp_path):
        output_dir = tmp_path / "output"
        audio_dir = tmp_path / "audio-cache"
        output_dir.mkdir()
        audio_dir.mkdir()

        cfg = Config()
        cfg.output.dir = str(output_dir)
        cfg.output.audio_dir = str(audio_dir)

        runner = CliRunner()
        with _mock_config(cfg):
            result = runner.invoke(cli, ["cleanup", "--output", "--yes"])

        assert result.exit_code == 0
        assert not output_dir.exists()
        assert not audio_dir.exists()

    def test_skips_missing_dirs(self, tmp_path):
        cfg = Config()
        cfg.output.dir = str(tmp_path / "nonexistent")

        runner = CliRunner()
        with (
            _mock_config(cfg),
            mock.patch("clew.cli._CONFIG_DIR", str(tmp_path / "no-config")),
            mock.patch("clew.cli._CACHE_DIR", str(tmp_path / "no-cache")),
            mock.patch("clew.cli._VOICEPRINT_DIR", str(tmp_path / "no-voiceprints")),
        ):
            result = runner.invoke(cli, ["cleanup", "--all", "--yes"])

        assert result.exit_code == 0
        assert "not found, skipping" in result.output

    def test_all_yes_removes_voiceprints_dir(self, tmp_path):
        """cleanup --all claims to remove everything; voiceprints are biometric
        data and must not survive it (config.py targets ~/.config/clew,
        but voiceprints live in ~/.config/meeting-scribe/voiceprints -
        speakers/base.py)."""
        config_dir = tmp_path / "config"
        cache_dir = tmp_path / "cache"
        output_dir = tmp_path / "output"
        voiceprint_dir = tmp_path / "voiceprints"
        for d in (config_dir, cache_dir, output_dir, voiceprint_dir):
            d.mkdir()
            (d / "file.txt").write_text("data")

        cfg = Config()
        cfg.output.dir = str(output_dir)

        runner = CliRunner()
        with (
            _mock_config(cfg),
            mock.patch("clew.cli._CONFIG_DIR", str(config_dir)),
            mock.patch("clew.cli._CACHE_DIR", str(cache_dir)),
            mock.patch("clew.cli._VOICEPRINT_DIR", str(voiceprint_dir), create=True),
        ):
            result = runner.invoke(cli, ["cleanup", "--all", "--yes"])

        assert result.exit_code == 0
        assert not voiceprint_dir.exists(), "cleanup --all left the voiceprint store on disk"
        assert "Removed Voiceprints" in result.output

    def test_interactive_yes_removes_voiceprints_dir(self, tmp_path):
        """The flagless interactive path (`cleanup --yes`, no --all/--config/--cache/
        --output) builds its own candidate list; it must offer Voiceprints too, not
        just the --all branch."""
        config_dir = tmp_path / "config"
        cache_dir = tmp_path / "cache"
        output_dir = tmp_path / "output"
        voiceprint_dir = tmp_path / "voiceprints"
        for d in (config_dir, cache_dir, output_dir, voiceprint_dir):
            d.mkdir()
            (d / "file.txt").write_text("data")

        cfg = Config()
        cfg.output.dir = str(output_dir)

        runner = CliRunner()
        with (
            _mock_config(cfg),
            mock.patch("clew.cli._CONFIG_DIR", str(config_dir)),
            mock.patch("clew.cli._CACHE_DIR", str(cache_dir)),
            mock.patch("clew.cli._VOICEPRINT_DIR", str(voiceprint_dir)),
        ):
            result = runner.invoke(cli, ["cleanup", "--yes"])

        assert result.exit_code == 0
        assert not voiceprint_dir.exists(), "interactive cleanup left the voiceprint store on disk"
        assert "Removed Voiceprints" in result.output


class TestCliNeverMigrates:
    """The `cli` Click group must never run the legacy-path migration itself --
    only `main()` does, deliberately, so CliRunner-driven tests (this whole file)
    can never trigger a real filesystem move. This is the regression guard for
    that design; see main()'s docstring in clew/cli.py."""

    def test_invoking_cli_never_calls_migrate_legacy_paths(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.cli.migrate_legacy_paths") as mock_migrate:
            runner.invoke(cli, ["--help"])
            runner.invoke(cli, ["apps"])
            runner.invoke(cli, ["cleanup", "--help"])
        mock_migrate.assert_not_called()


class TestMigrateDir:
    """Unit tests for the low-level move-once-if-safe helper. Always uses tmp_path
    on both sides -- never a real HOME path -- per this repo's rule that a test
    must never touch real user data."""

    def test_moves_old_to_new_when_new_absent(self, tmp_path):
        old = tmp_path / "old"
        old.mkdir()
        (old / "file.txt").write_text("data")
        new = tmp_path / "new"

        cli_module._migrate_dir(str(old), str(new), "thing")

        assert not old.exists()
        assert new.exists()
        assert (new / "file.txt").read_text() == "data"

    def test_does_nothing_when_new_already_exists(self, tmp_path):
        old = tmp_path / "old"
        old.mkdir()
        (old / "file.txt").write_text("old-data")
        new = tmp_path / "new"
        new.mkdir()
        (new / "file.txt").write_text("new-data")

        cli_module._migrate_dir(str(old), str(new), "thing")

        assert old.exists(), "must never delete the old dir when it doesn't move it"
        assert (old / "file.txt").read_text() == "old-data"
        assert (new / "file.txt").read_text() == "new-data", "must never overwrite the new dir"

    def test_does_nothing_when_old_absent(self, tmp_path):
        new = tmp_path / "new"

        cli_module._migrate_dir(str(tmp_path / "no-such-old"), str(new), "thing")

        assert not new.exists()

    def test_creates_new_parent_directory(self, tmp_path):
        old = tmp_path / "old"
        old.mkdir()
        new = tmp_path / "nested" / "new"

        cli_module._migrate_dir(str(old), str(new), "thing")

        assert new.exists()


class TestMigrateLegacyPaths:
    """migrate_legacy_paths() orchestrates the config-dir and voiceprint-dir moves
    via the module's patchable string constants -- same pattern TestCleanup already
    uses for _CONFIG_DIR/_CACHE_DIR/_VOICEPRINT_DIR."""

    def test_migrates_config_and_voiceprint_dirs(self, tmp_path):
        legacy_config = tmp_path / "legacy-config"
        legacy_config.mkdir()
        (legacy_config / "config.toml").write_text("[output]\n")
        new_config = tmp_path / "new-config"

        legacy_voiceprints = tmp_path / "legacy-voiceprints"
        legacy_voiceprints.mkdir()
        (legacy_voiceprints / "voiceprints.json").write_text("{}")
        new_voiceprints = tmp_path / "new-voiceprints"

        with (
            mock.patch("clew.cli._LEGACY_CONFIG_DIR", str(legacy_config)),
            mock.patch("clew.cli._CONFIG_DIR", str(new_config)),
            mock.patch("clew.cli._LEGACY_VOICEPRINT_DIR", str(legacy_voiceprints)),
            mock.patch("clew.cli._VOICEPRINT_DIR", str(new_voiceprints)),
        ):
            cli_module.migrate_legacy_paths(None)

        assert not legacy_config.exists()
        assert (new_config / "config.toml").exists()
        assert not legacy_voiceprints.exists()
        assert (new_voiceprints / "voiceprints.json").exists()

    def test_none_cfg_skips_output_dir_migration(self, tmp_path):
        with (
            mock.patch("clew.cli._LEGACY_CONFIG_DIR", str(tmp_path / "no-legacy-config")),
            mock.patch("clew.cli._CONFIG_DIR", str(tmp_path / "no-new-config")),
            mock.patch("clew.cli._LEGACY_VOICEPRINT_DIR", str(tmp_path / "no-legacy-vp")),
            mock.patch("clew.cli._VOICEPRINT_DIR", str(tmp_path / "no-new-vp")),
            mock.patch("clew.cli._migrate_output_dir") as mock_output_migrate,
        ):
            cli_module.migrate_legacy_paths(None)

        mock_output_migrate.assert_not_called()

    def test_cfg_provided_runs_output_dir_migration(self, tmp_path):
        with (
            mock.patch("clew.cli._LEGACY_CONFIG_DIR", str(tmp_path / "no-legacy-config")),
            mock.patch("clew.cli._CONFIG_DIR", str(tmp_path / "no-new-config")),
            mock.patch("clew.cli._LEGACY_VOICEPRINT_DIR", str(tmp_path / "no-legacy-vp")),
            mock.patch("clew.cli._VOICEPRINT_DIR", str(tmp_path / "no-new-vp")),
            mock.patch("clew.cli._migrate_output_dir") as mock_output_migrate,
        ):
            cfg = Config()
            cli_module.migrate_legacy_paths(cfg)

        mock_output_migrate.assert_called_once_with(cfg)


class TestMigrateOutputDir:
    """_migrate_output_dir() only ever moves the shipped default (old literal or new
    literal), and only when the user never pointed `output.dir` somewhere else."""

    def test_migrates_when_dir_is_the_legacy_default(self, tmp_path):
        old = tmp_path / "ownscribe"  # matches the fake expanduser() below
        old.mkdir()
        (old / "meeting").mkdir()
        new = tmp_path / "clew"

        cfg = Config()
        cfg.output.dir = "~/ownscribe"

        with (
            mock.patch("clew.cli._LEGACY_OUTPUT_DEFAULT", "~/ownscribe"),
            mock.patch("clew.cli._NEW_OUTPUT_DEFAULT", "~/clew"),
            mock.patch("pathlib.Path.expanduser", lambda self: tmp_path / str(self).removeprefix("~/")),
            mock.patch("clew.cli._rewrite_legacy_output_default_in_config_file") as mock_rewrite,
        ):
            cli_module._migrate_output_dir(cfg)

        assert not old.exists()
        assert new.exists()
        assert (new / "meeting").exists()
        assert cfg.output.dir == "~/clew"
        mock_rewrite.assert_called_once()

    def test_migrates_when_dir_is_already_the_new_default_but_data_is_at_old_location(self, tmp_path):
        """No config.toml (or one written after the rename): the dataclass default
        already reads "~/clew", but the user's real data may still physically sit
        at the pre-rename path. Move it, but don't touch cfg.output.dir (already
        correct) or rewrite a config file (nothing to rewrite)."""
        old = tmp_path / "ownscribe"  # matches the fake expanduser() below
        old.mkdir()
        new = tmp_path / "clew"

        cfg = Config()
        assert cfg.output.dir == "~/clew"

        with (
            mock.patch("clew.cli._LEGACY_OUTPUT_DEFAULT", "~/ownscribe"),
            mock.patch("clew.cli._NEW_OUTPUT_DEFAULT", "~/clew"),
            mock.patch("pathlib.Path.expanduser", lambda self: tmp_path / str(self).removeprefix("~/")),
            mock.patch("clew.cli._rewrite_legacy_output_default_in_config_file") as mock_rewrite,
        ):
            cli_module._migrate_output_dir(cfg)

        assert not old.exists()
        assert new.exists()
        mock_rewrite.assert_not_called()

    def test_never_touches_a_custom_output_dir(self, tmp_path):
        custom = tmp_path / "my-custom-notes"
        custom.mkdir()

        cfg = Config()
        cfg.output.dir = str(custom)

        with (
            mock.patch("clew.cli._LEGACY_OUTPUT_DEFAULT", "~/ownscribe"),
            mock.patch("clew.cli._NEW_OUTPUT_DEFAULT", "~/clew"),
        ):
            cli_module._migrate_output_dir(cfg)

        assert custom.exists()
        assert cfg.output.dir == str(custom)

    def test_does_nothing_when_neither_default_dir_exists(self, tmp_path):
        cfg = Config()
        cfg.output.dir = "~/ownscribe"

        with (
            mock.patch("clew.cli._LEGACY_OUTPUT_DEFAULT", "~/ownscribe"),
            mock.patch("clew.cli._NEW_OUTPUT_DEFAULT", "~/clew"),
            mock.patch("pathlib.Path.expanduser", lambda self: tmp_path / str(self).removeprefix("~/")),
        ):
            cli_module._migrate_output_dir(cfg)

        assert cfg.output.dir == "~/ownscribe", "nothing to migrate, so nothing should change"


class TestRewriteLegacyOutputDefaultInConfigFile:
    def test_rewrites_the_literal_legacy_default_line(self, tmp_path):
        config_dir = tmp_path / "config"
        config_dir.mkdir()
        config_path = config_dir / "config.toml"
        config_path.write_text('[output]\ndir = "~/ownscribe"       # base output directory\nformat = "markdown"\n')

        with (
            mock.patch("clew.cli._CONFIG_DIR", str(config_dir)),
            mock.patch("clew.cli._LEGACY_OUTPUT_DEFAULT", "~/ownscribe"),
            mock.patch("clew.cli._NEW_OUTPUT_DEFAULT", "~/clew"),
        ):
            cli_module._rewrite_legacy_output_default_in_config_file()

        written = config_path.read_text()
        assert 'dir = "~/clew"       # base output directory' in written
        assert '"~/ownscribe"' not in written

    def test_leaves_a_customized_dir_line_untouched(self, tmp_path):
        config_dir = tmp_path / "config"
        config_dir.mkdir()
        config_path = config_dir / "config.toml"
        original = '[output]\ndir = "/Users/someone/my-notes"\n'
        config_path.write_text(original)

        with (
            mock.patch("clew.cli._CONFIG_DIR", str(config_dir)),
            mock.patch("clew.cli._LEGACY_OUTPUT_DEFAULT", "~/ownscribe"),
            mock.patch("clew.cli._NEW_OUTPUT_DEFAULT", "~/clew"),
        ):
            cli_module._rewrite_legacy_output_default_in_config_file()

        assert config_path.read_text() == original

    def test_no_op_when_config_file_missing(self, tmp_path):
        with (
            mock.patch("clew.cli._CONFIG_DIR", str(tmp_path / "no-config-dir")),
            mock.patch("clew.cli._LEGACY_OUTPUT_DEFAULT", "~/ownscribe"),
            mock.patch("clew.cli._NEW_OUTPUT_DEFAULT", "~/clew"),
        ):
            cli_module._rewrite_legacy_output_default_in_config_file()  # must not raise


class TestMainEntryPoint:
    """main() is the real console-script entry point (clew/ownscribe both point at
    it). It must migrate before dispatching to cli(), and it must never let a
    Config.load() failure prevent the CLI from running (cli() re-loads and reports
    the real error itself)."""

    def test_migrates_then_loads_config_then_dispatches_to_cli(self):
        manager = mock.Mock()
        manager.load.return_value = Config()
        with (
            mock.patch("clew.cli.migrate_legacy_paths", manager.migrate),
            mock.patch("clew.cli.Config.load", manager.load),
            mock.patch("clew.cli.cli", manager.cli),
        ):
            cli_module.main()

        assert manager.mock_calls == [
            mock.call.migrate(None),
            mock.call.load(),
            mock.call.migrate(mock.ANY),
            mock.call.cli(),
        ]

    def test_config_load_failure_still_dispatches_to_cli(self):
        with (
            mock.patch("clew.cli.migrate_legacy_paths") as mock_migrate,
            mock.patch("clew.cli.Config.load", side_effect=ValueError("bad config")),
            mock.patch("clew.cli.cli") as mock_cli,
        ):
            cli_module.main()

        mock_cli.assert_called_once()
        mock_migrate.assert_called_once_with(None)


class TestInvalidConfigReporting:
    def test_invalid_config_reports_the_problem_without_a_traceback(self):
        runner = CliRunner()
        with mock.patch(
            "clew.cli.Config.load",
            side_effect=ValueError("cpu_threads must be a positive integer, got 'not_a_number'"),
        ):
            result = runner.invoke(cli, ["apps"])

        assert result.exit_code != 0
        assert "Traceback" not in result.output
        assert "cpu_threads must be a positive integer" in result.output
        assert "config.toml" in result.output

    def test_invalid_config_does_not_leak_the_exception_type(self):
        runner = CliRunner()
        with mock.patch("clew.cli.Config.load", side_effect=ValueError("bad value")):
            result = runner.invoke(cli, ["apps"])

        assert "ValueError" not in result.output
        assert result.exception is None or not isinstance(result.exception, ValueError)


class TestSummarizationLogging:
    """INFO #12 (2026-08-24 session): the local summarizer's chosen n_ctx was
    invisible in CLI output -- llama_cpp_summarizer.py's logger.info() call had no
    handler attached anywhere (Python's logging module attaches none by default),
    so the message was silently dropped. configure_summarization_logging() gives
    clew.summarization's own diagnostics a handler, scoped narrowly so no unrelated
    logger (root, third-party deps, other clew modules) gains new output."""

    @pytest.fixture(autouse=True)
    def _reset_logger(self):
        logger = logging.getLogger("clew.summarization")
        handlers, level, propagate = list(logger.handlers), logger.level, logger.propagate
        logger.handlers.clear()
        logger.setLevel(logging.NOTSET)
        yield logger
        logger.handlers.clear()
        logger.handlers.extend(handlers)
        logger.setLevel(level)
        logger.propagate = propagate

    def test_attaches_exactly_one_handler_at_info_level(self, _reset_logger):
        from clew.cli import configure_summarization_logging

        configure_summarization_logging()

        assert len(_reset_logger.handlers) == 1
        assert _reset_logger.level == logging.INFO
        assert _reset_logger.propagate is False

    def test_is_idempotent_across_repeated_calls(self, _reset_logger):
        from clew.cli import configure_summarization_logging

        configure_summarization_logging()
        configure_summarization_logging()
        configure_summarization_logging()

        assert len(_reset_logger.handlers) == 1

    def test_chosen_n_ctx_reaches_stderr_once_configured(self, _reset_logger, capsys):
        from clew.cli import configure_summarization_logging

        configure_summarization_logging()

        logging.getLogger("clew.summarization.llama_cpp_summarizer").info(
            "Loading model from %s (n_ctx=%d)", "/fake/model.gguf", 131072
        )

        captured = capsys.readouterr()
        assert "n_ctx=131072" in captured.err

    def test_does_not_alter_the_root_logger(self):
        """'sans spam': scoped to clew.summarization only, never the root logger --
        an unrelated module's logger must not suddenly gain output."""
        root = logging.getLogger()
        root_handlers_before = list(root.handlers)

        from clew.cli import configure_summarization_logging

        configure_summarization_logging()

        assert list(root.handlers) == root_handlers_before

    def test_cli_invocation_wires_it_up(self):
        """The real entry point: any cli() dispatch (not just a dedicated setup call)
        configures the logger, so a real `clew ask`/`clew summarize` run surfaces it.
        Uses `devices --help`, which still runs the group's own cli() callback (the
        subcommand's eager --help exits before touching real audio hardware --
        confirmed: Config.load() is called even though the subcommand body never
        runs)."""
        runner = CliRunner()
        with _mock_config():
            runner.invoke(cli, ["devices", "--help"])

        assert len(logging.getLogger("clew.summarization").handlers) == 1


class TestSuggestEnrollmentCommand:
    """BUILD NEXT #1 tranche 1: a CLI-facing view of the evidence-gated LLM
    arbiter -- never auto-enrolls. pipeline.py stays untouched (another lane's
    scope), so this command loads/builds/arbitrates directly rather than
    delegating to a run_X() there."""

    def test_requires_existing_directory(self):
        # Must be Click's own clean path validation (exit 2, a usage message) --
        # not an unhandled FileNotFoundError from inside the command body
        # bubbling up as a bare traceback (exit 1, empty output).
        runner = CliRunner()
        with _mock_config():
            result = runner.invoke(cli, ["suggest-enrollment", "/no/such/directory"])
        assert result.exit_code == 2
        assert "does not exist" in result.output

    def test_no_suggestions_reports_clearly(self, tmp_path):
        runner = CliRunner()
        with (
            _mock_config(),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()),
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[]),
        ):
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])

        assert result.exit_code == 0
        assert "No enrollment suggestions" in result.output

    def test_confirmed_suggestion_is_echoed(self, tmp_path):
        from clew.speakers.enrollment_suggest import Suggestion

        suggestion = Suggestion(
            cluster="SPEAKER_00", name="Devon", evidence=[mock.Mock(), mock.Mock()], confidence="high"
        )
        runner = CliRunner()
        with (
            _mock_config(),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()),
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[suggestion]),
        ):
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])

        assert result.exit_code == 0
        assert "SPEAKER_00" in result.output
        assert "Devon" in result.output
        assert "high" in result.output

    def test_roster_from_config_is_passed_to_build_and_arbiter(self, tmp_path):
        config = Config()
        config.speakers.known = ["Kamal", "Yanis"]
        runner = CliRunner()
        with (
            _mock_config(config),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()) as mock_build,
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[]) as mock_suggest,
        ):
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])

        assert result.exit_code == 0
        assert mock_build.call_args[1]["roster"] == ["Kamal", "Yanis"]
        assert mock_suggest.call_args[1]["roster"] == ["Kamal", "Yanis"]

    def test_never_calls_any_enroll_or_unenroll_function(self, tmp_path):
        # Never-auto-enroll invariant, verified structurally rather than trusted:
        # patch the real enrollment write paths and assert they are untouched.
        from clew.speakers.enrollment_suggest import Suggestion

        suggestion = Suggestion(cluster="SPEAKER_00", name="Devon", evidence=[], confidence="high")
        runner = CliRunner()
        with (
            _mock_config(),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()),
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[suggestion]),
            mock.patch("clew.pipeline.run_enroll") as mock_enroll,
        ):
            runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])

        mock_enroll.assert_not_called()

    def test_mic_presence_unavailable_when_no_mic_wav(self, tmp_path):
        # No mic.wav in tmp_path.
        runner = CliRunner()
        with (
            _mock_config(),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()) as mock_build,
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[]),
        ):
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])

        assert result.exit_code == 0
        assert "Mic presence: unavailable (no mic.wav)" in result.output
        assert mock_build.call_args[1]["mic_presence"] is None

    def test_mic_presence_unavailable_when_no_hf_token(self, tmp_path):
        (tmp_path / "mic.wav").touch()
        config = Config()
        config.diarization.hf_token = ""
        runner = CliRunner()
        with (
            _mock_config(config),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()) as mock_build,
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[]),
            mock.patch("clew.speakers.mic_presence.cluster_embeddings_for") as mock_cef,
        ):
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])

        assert result.exit_code == 0
        assert "Mic presence: unavailable (no HuggingFace token configured)" in result.output
        assert mock_build.call_args[1]["mic_presence"] is None
        mock_cef.assert_not_called()

    def test_mic_presence_line_reports_a_resolved_match(self, tmp_path):
        from clew.speakers.mic_presence import MicPresence

        (tmp_path / "mic.wav").touch()
        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = "hf_test_token"
        presence = MicPresence(cluster="SPEAKER_00", name="Kamal", score=0.8, start=1.0, end=5.0)
        runner = CliRunner()
        with (
            _mock_config(config),
            mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()) as mock_build,
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[]),
            mock.patch("clew.speakers.mic_presence.cluster_embeddings_for", return_value={"SPEAKER_00": [0.1, 0.2]}),
            mock.patch("clew.speakers.mic_presence.voiced_spans", return_value=[(1.0, 5.0)]),
            mock.patch("clew.speakers.mic_presence.mic_embedding", return_value=[0.1, 0.2]),
            mock.patch("clew.speakers.mic_presence.resolve_mic_presence", return_value=presence) as mock_resolve,
        ):
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])

        assert result.exit_code == 0
        assert "Mic presence: cluster=SPEAKER_00 score=0.800 name=Kamal" in result.output
        assert mock_build.call_args[1]["mic_presence"] == presence
        mock_resolve.assert_called_once()

    def test_mic_presence_line_shows_none_when_no_name_resolved(self, tmp_path):
        from clew.speakers.mic_presence import MicPresence

        (tmp_path / "mic.wav").touch()
        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = "hf_test_token"
        presence = MicPresence(cluster=None, name=None, score=0.2, start=1.0, end=5.0)
        runner = CliRunner()
        with (
            _mock_config(config),
            mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()),
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[]),
            mock.patch("clew.speakers.mic_presence.cluster_embeddings_for", return_value={"SPEAKER_00": [0.1, 0.2]}),
            mock.patch("clew.speakers.mic_presence.voiced_spans", return_value=[(1.0, 5.0)]),
            mock.patch("clew.speakers.mic_presence.mic_embedding", return_value=[0.1, 0.2]),
            mock.patch("clew.speakers.mic_presence.resolve_mic_presence", return_value=presence),
        ):
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])

        assert result.exit_code == 0
        assert "Mic presence: cluster=None score=0.200 name=none" in result.output

    def test_mic_presence_unavailable_when_no_cluster_embeddings(self, tmp_path):
        (tmp_path / "mic.wav").touch()
        config = Config()
        config.diarization.hf_token = "hf_test_token"
        runner = CliRunner()
        with (
            _mock_config(config),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()) as mock_build,
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[]),
            mock.patch("clew.speakers.mic_presence.cluster_embeddings_for", return_value={}),
            mock.patch("clew.speakers.mic_presence.mic_embedding") as mock_mic_emb,
        ):
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])

        assert result.exit_code == 0
        assert "Mic presence: unavailable (no cluster embeddings available)" in result.output
        assert mock_build.call_args[1]["mic_presence"] is None
        mock_mic_emb.assert_not_called()

    def test_mic_presence_unavailable_when_mic_embedding_is_none(self, tmp_path):
        (tmp_path / "mic.wav").touch()
        config = Config()
        config.diarization.hf_token = "hf_test_token"
        runner = CliRunner()
        with (
            _mock_config(config),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()) as mock_build,
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[]),
            mock.patch("clew.speakers.mic_presence.cluster_embeddings_for", return_value={"SPEAKER_00": [0.1, 0.2]}),
            mock.patch("clew.speakers.mic_presence.voiced_spans", return_value=[(1.0, 5.0)]),
            mock.patch("clew.speakers.mic_presence.mic_embedding", return_value=None),
            mock.patch("clew.speakers.mic_presence.resolve_mic_presence") as mock_resolve,
        ):
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])

        assert result.exit_code == 0
        assert "Mic presence: unavailable (mic track has too little voiced audio)" in result.output
        assert mock_build.call_args[1]["mic_presence"] is None
        mock_resolve.assert_not_called()

    def test_write_flag_builds_and_writes_the_report_and_prints_the_path(self, tmp_path):
        report_stub = {"version": 1, "generated_at": "x", "clusters": [], "suggestions": [], "mic_presence": None}
        written_path = tmp_path / "enrollment_suggestions.json"
        runner = CliRunner()
        with (
            _mock_config(),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()),
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[]),
            mock.patch(
                "clew.speakers.enrollment_report.build_enrollment_report", return_value=report_stub
            ) as mock_build_report,
            mock.patch(
                "clew.speakers.enrollment_report.write_enrollment_report", return_value=written_path
            ) as mock_write,
        ):
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path), "--write"])

        assert result.exit_code == 0
        assert f"Wrote {written_path}" in result.output
        mock_build_report.assert_called_once()
        mock_write.assert_called_once()

    def test_without_write_flag_nothing_is_written(self, tmp_path):
        runner = CliRunner()
        with (
            _mock_config(),
            mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
            mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()),
            mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
            mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[]),
            mock.patch("clew.speakers.enrollment_report.write_enrollment_report") as mock_write,
        ):
            before = sorted(p.name for p in tmp_path.iterdir())
            result = runner.invoke(cli, ["suggest-enrollment", str(tmp_path)])
            after = sorted(p.name for p in tmp_path.iterdir())

        assert result.exit_code == 0
        assert before == after
        assert "Wrote" not in result.output
        mock_write.assert_not_called()

    def test_human_output_unchanged_by_the_write_flag(self, tmp_path):
        # Same suggestion lines and "no suggestions" wording print whether or
        # not --write is passed -- --write only adds the report + final line.
        from clew.speakers.enrollment_suggest import Suggestion

        suggestion = Suggestion(cluster="SPEAKER_00", name="Devon", evidence=[], confidence="high")
        runner = CliRunner()

        def _run(args):
            with (
                _mock_config(),
                mock.patch("clew.speakers.enrollment_suggest.load_transcript_result", return_value=mock.Mock()),
                mock.patch("clew.speakers.enrollment_suggest.build_evidence_table", return_value=mock.Mock()),
                mock.patch("clew.summarization.create_summarizer", return_value=mock.MagicMock()),
                mock.patch("clew.speakers.enrollment_suggest.suggest_enrollments", return_value=[suggestion]),
                mock.patch(
                    "clew.speakers.enrollment_report.build_enrollment_report",
                    return_value={
                        "version": 1,
                        "generated_at": "x",
                        "clusters": [],
                        "suggestions": [],
                        "mic_presence": None,
                    },
                ),
                mock.patch(
                    "clew.speakers.enrollment_report.write_enrollment_report",
                    return_value=tmp_path / "enrollment_suggestions.json",
                ),
            ):
                return runner.invoke(cli, args)

        without_write = _run(["suggest-enrollment", str(tmp_path)])
        with_write = _run(["suggest-enrollment", str(tmp_path), "--write"])

        assert "SPEAKER_00 -> Devon" in without_write.output
        assert "SPEAKER_00 -> Devon" in with_write.output
        assert "Wrote" not in without_write.output
        assert "Wrote" in with_write.output


class TestEnrollClusterCommand:
    """BUILD NEXT #1 tranche 2 block A3: the confirm step -- never runs on its own,
    always an explicit `--cluster`/`--name` the user (or a suggest-enrollment
    candidate they accepted) provided."""

    def test_forwards_directory_cluster_and_name_to_run_enroll_cluster(self, tmp_path):
        runner = CliRunner()
        with (
            _mock_config(),
            mock.patch("clew.pipeline.run_enroll_cluster") as mock_run,
        ):
            result = runner.invoke(cli, ["enroll-cluster", str(tmp_path), "--cluster", "SPEAKER_00", "--name", "Alice"])

        assert result.exit_code == 0
        mock_run.assert_called_once()
        _config, directory, cluster, name = mock_run.call_args[0]
        assert directory == str(tmp_path)
        assert cluster == "SPEAKER_00"
        assert name == "Alice"

    def test_requires_existing_directory(self):
        runner = CliRunner()
        with _mock_config():
            result = runner.invoke(
                cli, ["enroll-cluster", "/no/such/directory", "--cluster", "SPEAKER_00", "--name", "Alice"]
            )
        assert result.exit_code == 2
        assert "does not exist" in result.output

    def test_requires_cluster_option(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_enroll_cluster"):
            result = runner.invoke(cli, ["enroll-cluster", str(tmp_path), "--name", "Alice"])
        assert result.exit_code != 0

    def test_requires_name_option(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("clew.pipeline.run_enroll_cluster"):
            result = runner.invoke(cli, ["enroll-cluster", str(tmp_path), "--cluster", "SPEAKER_00"])
        assert result.exit_code != 0
