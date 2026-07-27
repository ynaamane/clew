from __future__ import annotations

from unittest.mock import MagicMock, patch

from ownscribe.config import TranscriptionConfig
from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber, default_cpu_threads


class TestDefaultCpuThreads:
    def test_uses_performance_cores_not_every_core(self):
        with (
            patch("ownscribe.transcription.whisperx_transcriber._performance_core_count", return_value=12),
            patch("os.cpu_count", return_value=16),
        ):
            assert default_cpu_threads() == 12

    def test_falls_back_to_logical_cores_when_performance_count_unavailable(self):
        with (
            patch("ownscribe.transcription.whisperx_transcriber._performance_core_count", return_value=None),
            patch("os.cpu_count", return_value=8),
        ):
            assert default_cpu_threads() == 8

    def test_never_returns_less_than_one(self):
        with (
            patch("ownscribe.transcription.whisperx_transcriber._performance_core_count", return_value=None),
            patch("os.cpu_count", return_value=None),
        ):
            assert default_cpu_threads() >= 1


class TestThreadsArePassedToWhisperx:
    def test_load_model_passes_configured_threads(self):
        config = TranscriptionConfig(cpu_threads=12)
        transcriber = WhisperXTranscriber(config)

        fake_whisperx = MagicMock()
        with patch.dict("sys.modules", {"whisperx": fake_whisperx}):
            transcriber._load_model()

        assert fake_whisperx.load_model.called, "load_model was not called"
        _, kwargs = fake_whisperx.load_model.call_args
        assert kwargs["threads"] == 12, (
            "whisperx.load_model defaults to threads=4, which caps CTranslate2 at a quarter of this "
            "machine's performance cores; the configured value must reach it."
        )

    def test_zero_threads_config_resolves_to_the_machine_default(self):
        config = TranscriptionConfig(cpu_threads=0)
        transcriber = WhisperXTranscriber(config)

        fake_whisperx = MagicMock()
        with (
            patch("ownscribe.transcription.whisperx_transcriber.default_cpu_threads", return_value=12),
            patch.dict("sys.modules", {"whisperx": fake_whisperx}),
        ):
            transcriber._load_model()

        _, kwargs = fake_whisperx.load_model.call_args
        assert kwargs["threads"] == 12
