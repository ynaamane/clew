"""Tests for configuration loading."""

from __future__ import annotations

import os
from pathlib import Path
from unittest import mock

from ownscribe.config import BILINGUAL_INITIAL_PROMPT, Config, OutputConfig, _merge_toml, ensure_config_file


class TestDefaults:
    def test_default_audio_backend(self):
        cfg = Config()
        assert cfg.audio.backend == "coreaudio"

    def test_default_transcription_model(self):
        cfg = Config()
        assert cfg.transcription.model == "large-v3"

    def test_default_transcription_initial_prompt_is_bilingual(self):
        cfg = Config()
        assert cfg.transcription.initial_prompt == BILINGUAL_INITIAL_PROMPT
        assert cfg.transcription.initial_prompt != ""

    def test_default_summarization_enabled(self):
        cfg = Config()
        assert cfg.summarization.enabled is True

    def test_default_output_format(self):
        cfg = Config()
        assert cfg.output.format == "markdown"

    def test_default_mic_settings(self):
        cfg = Config()
        assert cfg.audio.mic is False
        assert cfg.audio.mic_device == ""

    def test_default_capture_mode_all(self):
        cfg = Config()
        assert cfg.audio.capture_mode == "all"

    def test_default_capture_backend_is_coreaudio_tap(self):
        cfg = Config()
        assert cfg.audio.capture_backend == "coreaudio"

    def test_default_diarization_telemetry_off(self):
        cfg = Config()
        assert cfg.diarization.telemetry is False

    def test_default_summarization_template_empty(self):
        cfg = Config()
        assert cfg.summarization.template == ""

    def test_default_templates_empty(self):
        cfg = Config()
        assert cfg.templates == {}

    def test_default_silence_timeout(self):
        cfg = Config()
        assert cfg.audio.silence_timeout == 300

    def test_default_retention_days_is_keep_forever(self):
        cfg = Config()
        assert cfg.output.retention_days == 0

    def test_default_transcription_engine_is_whisperx(self):
        cfg = Config()
        assert cfg.transcription.engine == "whisperx"

    def test_default_canary_repo(self):
        cfg = Config()
        assert cfg.canary.repo == "CogniSoftOrg/canary-1b-v2-mlx-bf16"

    def test_default_canary_max_segment_seconds(self):
        cfg = Config()
        assert cfg.canary.max_segment_seconds == 10.0

    def test_default_canary_max_tokens_per_segment(self):
        cfg = Config()
        assert cfg.canary.max_tokens_per_segment == 200


class TestMergeToml:
    def test_full_override(self):
        cfg = Config()
        data = {
            "audio": {"backend": "sounddevice", "device": "USB Mic"},
            "transcription": {"model": "large-v3", "language": "de"},
        }
        merged = _merge_toml(cfg, data)
        assert merged.audio.backend == "sounddevice"
        assert merged.audio.device == "USB Mic"
        assert merged.transcription.model == "large-v3"
        assert merged.transcription.language == "de"

    def test_partial_toml_keeps_defaults(self):
        cfg = Config()
        data = {"transcription": {"model": "small"}}
        merged = _merge_toml(cfg, data)
        assert merged.transcription.model == "small"
        # Other sections unchanged
        assert merged.audio.backend == "coreaudio"
        assert merged.summarization.backend == "local"

    def test_mic_settings_from_toml(self):
        cfg = Config()
        data = {"audio": {"mic": True, "mic_device": "MacBook Pro Microphone"}}
        merged = _merge_toml(cfg, data)
        assert merged.audio.mic is True
        assert merged.audio.mic_device == "MacBook Pro Microphone"

    def test_capture_backend_from_toml(self):
        cfg = Config()
        data = {"audio": {"capture_backend": "screencapturekit"}}
        merged = _merge_toml(cfg, data)
        assert merged.audio.capture_backend == "screencapturekit"

    def test_transcription_engine_from_toml(self):
        cfg = Config()
        data = {"transcription": {"engine": "canary_mlx"}}
        merged = _merge_toml(cfg, data)
        assert merged.transcription.engine == "canary_mlx"

    def test_canary_section_from_toml(self):
        cfg = Config()
        data = {"canary": {"repo": "some/other-repo", "max_segment_seconds": 20.0, "max_tokens_per_segment": 50}}
        merged = _merge_toml(cfg, data)
        assert merged.canary.repo == "some/other-repo"
        assert merged.canary.max_segment_seconds == 20.0
        assert merged.canary.max_tokens_per_segment == 50

    def test_diarization_telemetry_from_toml(self):
        cfg = Config()
        data = {"diarization": {"telemetry": True}}
        merged = _merge_toml(cfg, data)
        assert merged.diarization.telemetry is True

    def test_template_from_toml(self):
        cfg = Config()
        data = {"summarization": {"template": "lecture"}}
        merged = _merge_toml(cfg, data)
        assert merged.summarization.template == "lecture"

    def test_retention_days_from_toml(self):
        cfg = Config()
        data = {"output": {"retention_days": 30}}
        merged = _merge_toml(cfg, data)
        assert merged.output.retention_days == 30

    def test_user_templates_from_toml(self):
        cfg = Config()
        data = {
            "templates": {
                "my-notes": {
                    "system_prompt": "You are a custom bot.",
                    "prompt": "Custom: {transcript}",
                }
            }
        }
        merged = _merge_toml(cfg, data)
        assert "my-notes" in merged.templates
        assert merged.templates["my-notes"].system_prompt == "You are a custom bot."
        assert merged.templates["my-notes"].prompt == "Custom: {transcript}"

    def test_user_templates_partial(self):
        cfg = Config()
        data = {
            "templates": {
                "quick": {"prompt": "Summarize briefly: {transcript}"}
            }
        }
        merged = _merge_toml(cfg, data)
        assert merged.templates["quick"].system_prompt == ""
        assert merged.templates["quick"].prompt == "Summarize briefly: {transcript}"

    def test_unknown_keys_ignored(self):
        cfg = Config()
        data = {"audio": {"nonexistent_key": 42}}
        merged = _merge_toml(cfg, data)
        assert not hasattr(merged.audio, "nonexistent_key")


class TestEnvOverrides:
    def test_hf_token_from_env(self):
        with (
            mock.patch.dict(os.environ, {"HF_TOKEN": "hf_test123"}),
            mock.patch("ownscribe.config.CONFIG_PATH") as mock_path,
        ):
            mock_path.exists.return_value = False
            cfg = Config.load()
        assert cfg.diarization.hf_token == "hf_test123"

    def test_ollama_host_from_env(self):
        with (
            mock.patch.dict(os.environ, {"OLLAMA_HOST": "http://remote:11434"}),
            mock.patch("ownscribe.config.CONFIG_PATH") as mock_path,
        ):
            mock_path.exists.return_value = False
            cfg = Config.load()
        assert cfg.summarization.host == "http://remote:11434"

    def test_progress_mode_from_env(self):
        with (
            mock.patch.dict(os.environ, {"OWNSCRIBE_PROGRESS": "json"}),
            mock.patch("ownscribe.config.CONFIG_PATH") as mock_path,
        ):
            mock_path.exists.return_value = False
            cfg = Config.load()
        assert cfg.progress_mode == "json"

    def test_progress_mode_default_is_tui_without_env(self):
        with (
            mock.patch.dict(os.environ, {}, clear=True),
            mock.patch("ownscribe.config.CONFIG_PATH") as mock_path,
        ):
            mock_path.exists.return_value = False
            cfg = Config.load()
        assert cfg.progress_mode == "tui"


class TestEnsureConfigFile:
    def test_creates_file_when_missing(self, tmp_path):
        config_dir = tmp_path / "ownscribe"
        config_path = config_dir / "config.toml"
        with mock.patch("ownscribe.config.CONFIG_DIR", config_dir), \
             mock.patch("ownscribe.config.CONFIG_PATH", config_path):
            result = ensure_config_file()
        assert result.exists()
        written = result.read_text()
        assert "[audio]" in written
        assert BILINGUAL_INITIAL_PROMPT in written
        assert "__BILINGUAL_INITIAL_PROMPT__" not in written

    def test_does_not_overwrite_existing(self, tmp_path):
        config_dir = tmp_path / "ownscribe"
        config_dir.mkdir()
        config_path = config_dir / "config.toml"
        config_path.write_text("# custom config\n")
        with mock.patch("ownscribe.config.CONFIG_DIR", config_dir), \
             mock.patch("ownscribe.config.CONFIG_PATH", config_path):
            ensure_config_file()
        assert config_path.read_text() == "# custom config\n"


class TestResolvedDir:
    def test_expands_tilde(self):
        cfg = OutputConfig(dir="~/ownscribe")
        resolved = cfg.resolved_dir
        assert "~" not in str(resolved)
        assert str(resolved).endswith("ownscribe")

    def test_absolute_path_unchanged(self):
        cfg = OutputConfig(dir="/tmp/notes")
        assert cfg.resolved_dir == Path("/tmp/notes")


class TestResolvedAudioDir:
    def test_expands_tilde(self):
        cfg = OutputConfig(dir="/tmp/notes", audio_dir="~/audio-cache")
        resolved = cfg.resolved_audio_dir
        assert "~" not in str(resolved)
        assert str(resolved).endswith("audio-cache")

    def test_absolute_path_unchanged(self):
        cfg = OutputConfig(dir="/tmp/notes", audio_dir="/tmp/audio-cache")
        assert cfg.resolved_audio_dir == Path("/tmp/audio-cache")
        assert cfg.resolved_audio_dir != cfg.resolved_dir

    def test_falls_back_to_dir_when_empty(self):
        cfg = OutputConfig(dir="/tmp/notes", audio_dir="")
        assert cfg.resolved_audio_dir == cfg.resolved_dir
