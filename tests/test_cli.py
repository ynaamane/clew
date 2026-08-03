"""Tests for CLI command parsing."""

from __future__ import annotations

from unittest import mock

from click.testing import CliRunner

from ownscribe.cli import cli
from ownscribe.config import Config


def _mock_config(config: Config | None = None):
    """Return a mock that makes Config.load() return a default Config."""
    return mock.patch("ownscribe.cli.Config.load", return_value=config or Config())


class TestMainCommand:
    def test_help(self):
        runner = CliRunner()
        result = runner.invoke(cli, ["--help"])
        assert result.exit_code == 0
        assert "Fully local meeting transcription and summarization" in result.output

    def test_no_summarize_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--no-summarize"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.summarization.enabled is False

    def test_mic_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--mic"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.audio.mic is True

    def test_device_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--device", "USB Mic"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.audio.device == "USB Mic"
            assert config.audio.backend == "sounddevice"

    def test_model_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--model", "large-v3"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.transcription.model == "large-v3"

    def test_language_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--language", "de"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.transcription.language == "de"

    def test_silence_timeout_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--silence-timeout", "60"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.audio.silence_timeout == 60

    def test_silence_timeout_disable(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
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
        assert "Remove ownscribe data from disk" in result.output


class TestKeepRecordingFlag:
    def test_keep_recording_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--no-keep-recording"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.output.keep_recording is False

    def test_keep_recording_default_is_true(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, [])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.output.keep_recording is True


class TestProgressFlag:
    def test_progress_json_flag_sets_config(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
            result = runner.invoke(cli, ["--progress", "json"])
            assert result.exit_code == 0
            config = mock_run.call_args[0][0]
            assert config.progress_mode == "json"

    def test_progress_default_is_tui(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_pipeline") as mock_run:
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

        with _mock_config(), mock.patch("ownscribe.pipeline.run_transcribe") as mock_transcribe:
            result = runner.invoke(cli, ["--progress", "json", "transcribe", str(audio_path)])
            assert result.exit_code == 0
            config = mock_transcribe.call_args[0][0]
            assert config.progress_mode == "json"


class TestWarmupCommand:
    def test_warmup_invokes_pipeline_with_overrides(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_warmup") as mock_warmup:
            result = runner.invoke(cli, ["warmup", "--model", "large-v3", "--language", "de", "--with-diarization"])

        assert result.exit_code == 0
        config = mock_warmup.call_args[0][0]
        assert config.transcription.model == "large-v3"
        assert config.transcription.language == "de"
        assert config.diarization.enabled is True


class TestResumeCommand:
    def test_resume_invokes_pipeline_with_overrides(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_resume") as mock_resume:
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
        with _mock_config(), mock.patch("ownscribe.pipeline.run_resume") as mock_resume:
            result = runner.invoke(cli, ["resume", str(tmp_path), "--diarize"])

        assert result.exit_code == 0
        config = mock_resume.call_args[0][0]
        assert config.diarization.enabled is True

    def test_resume_without_diarize_flag_does_not_enable_diarization(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_resume") as mock_resume:
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
        with _mock_config(), mock.patch("ownscribe.pipeline.run_reprocess") as mock_reprocess:
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
        with _mock_config(), mock.patch("ownscribe.pipeline.run_reprocess") as mock_reprocess:
            result = runner.invoke(cli, ["reprocess", str(tmp_path), "--diarize"])

        assert result.exit_code == 0
        config = mock_reprocess.call_args[0][0]
        assert config.diarization.enabled is True

    def test_reprocess_without_diarize_flag_does_not_enable_diarization(self, tmp_path):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_reprocess") as mock_reprocess:
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
        with _mock_config(), mock.patch("ownscribe.pipeline.run_purge") as mock_purge:
            result = runner.invoke(cli, ["purge"])

        assert result.exit_code == 0
        mock_purge.assert_called_once()
        _config, older_than_days, purge_all, dry_run = mock_purge.call_args[0]
        assert older_than_days is None
        assert purge_all is False
        assert dry_run is False

    def test_purge_older_than_and_dry_run_flags(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_purge") as mock_purge:
            result = runner.invoke(cli, ["purge", "--older-than", "14", "--dry-run"])

        assert result.exit_code == 0
        _, older_than_days, purge_all, dry_run = mock_purge.call_args[0]
        assert older_than_days == 14
        assert purge_all is False
        assert dry_run is True

    def test_purge_all_flag(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_purge") as mock_purge:
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
        with _mock_config(), mock.patch("ownscribe.pipeline.run_backfill") as mock_backfill:
            result = runner.invoke(cli, ["backfill", str(tmp_path)])

        assert result.exit_code == 0
        mock_backfill.assert_called_once()
        _config, directory = mock_backfill.call_args[0]
        assert directory == str(tmp_path)

    def test_backfill_without_directory_forwards_none(self):
        runner = CliRunner()
        with _mock_config(), mock.patch("ownscribe.pipeline.run_backfill") as mock_backfill:
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
        for d in (config_dir, cache_dir, output_dir):
            d.mkdir()
            (d / "file.txt").write_text("data")

        cfg = Config()
        cfg.output.dir = str(output_dir)

        runner = CliRunner()
        with (
            _mock_config(cfg),
            mock.patch("ownscribe.cli._CONFIG_DIR", str(config_dir)),
            mock.patch("ownscribe.cli._CACHE_DIR", str(cache_dir)),
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
        for d in (config_dir, cache_dir, output_dir, audio_dir):
            d.mkdir()
            (d / "file.txt").write_text("data")

        cfg = Config()
        cfg.output.dir = str(output_dir)
        cfg.output.audio_dir = str(audio_dir)

        runner = CliRunner()
        with (
            _mock_config(cfg),
            mock.patch("ownscribe.cli._CONFIG_DIR", str(config_dir)),
            mock.patch("ownscribe.cli._CACHE_DIR", str(cache_dir)),
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
            mock.patch("ownscribe.cli._CONFIG_DIR", str(config_dir)),
            mock.patch("ownscribe.cli._CACHE_DIR", str(cache_dir)),
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
            mock.patch("ownscribe.cli._CONFIG_DIR", str(tmp_path / "no-config")),
            mock.patch("ownscribe.cli._CACHE_DIR", str(tmp_path / "no-cache")),
        ):
            result = runner.invoke(cli, ["cleanup", "--all", "--yes"])

        assert result.exit_code == 0
        assert "not found, skipping" in result.output


class TestInvalidConfigReporting:
    def test_invalid_config_reports_the_problem_without_a_traceback(self):
        runner = CliRunner()
        with mock.patch(
            "ownscribe.cli.Config.load",
            side_effect=ValueError("cpu_threads must be a positive integer, got 'not_a_number'"),
        ):
            result = runner.invoke(cli, ["apps"])

        assert result.exit_code != 0
        assert "Traceback" not in result.output
        assert "cpu_threads must be a positive integer" in result.output
        assert "config.toml" in result.output

    def test_invalid_config_does_not_leak_the_exception_type(self):
        runner = CliRunner()
        with mock.patch("ownscribe.cli.Config.load", side_effect=ValueError("bad value")):
            result = runner.invoke(cli, ["apps"])

        assert "ValueError" not in result.output
        assert result.exception is None or not isinstance(result.exception, ValueError)
