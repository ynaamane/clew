"""Tests for the Canary-1B-v2 MLX pilot transcription engine."""

from __future__ import annotations

import json
from unittest import mock

import pytest

from ownscribe.config import CanaryConfig, Config, TranscriptionConfig


class TestIsAvailable:
    def test_true_when_uv_on_path_and_runs_clean(self):
        from ownscribe.transcription.canary_mlx_transcriber import is_available

        fake_result = mock.MagicMock(returncode=0)
        with mock.patch("subprocess.run", return_value=fake_result) as mock_run:
            assert is_available() is True
        mock_run.assert_called_once_with(["uv", "--version"], capture_output=True)

    def test_false_when_uv_missing_from_path(self):
        from ownscribe.transcription.canary_mlx_transcriber import is_available

        with mock.patch("subprocess.run", side_effect=FileNotFoundError):
            assert is_available() is False

    def test_false_when_uv_exits_nonzero(self):
        from ownscribe.transcription.canary_mlx_transcriber import is_available

        fake_result = mock.MagicMock(returncode=1)
        with mock.patch("subprocess.run", return_value=fake_result):
            assert is_available() is False


class TestCanaryMlxTranscriberInit:
    def test_uses_configured_language(self):
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        transcriber = CanaryMlxTranscriber(TranscriptionConfig(language="en"), CanaryConfig())
        assert transcriber._language == "en"

    def test_falls_back_to_french_when_language_unset(self):
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        transcriber = CanaryMlxTranscriber(TranscriptionConfig(language=""), CanaryConfig())
        assert transcriber._language == "fr"

    def test_prepare_models_overrides_language(self):
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        transcriber = CanaryMlxTranscriber(TranscriptionConfig(language="fr"), CanaryConfig())
        transcriber.prepare_models(language="en")
        assert transcriber._language == "en"

    def test_last_speaker_embeddings_always_empty(self):
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        transcriber = CanaryMlxTranscriber(TranscriptionConfig(), CanaryConfig())
        assert transcriber.last_speaker_embeddings == {}


class TestCanaryMlxTranscriberSubprocessOrchestration:
    """Mocks subprocess.run entirely -- proves the ORCHESTRATION logic (request built
    correctly, response parsed correctly, errors surfaced correctly) without ever
    spawning a real uv overlay or downloading a checkpoint."""

    def _fake_process(self, stdout: str, returncode: int = 0, stderr: str = "") -> mock.MagicMock:
        return mock.MagicMock(returncode=returncode, stdout=stdout, stderr=stderr)

    def test_builds_the_uv_run_with_command_correctly(self, tmp_path, synthetic_wav):
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        transcriber = CanaryMlxTranscriber(TranscriptionConfig(language="fr"), CanaryConfig())
        ok_response = json.dumps({"ok": True, "result": {"segments": [], "duration": 0.5, "language": "fr"}})

        with mock.patch("subprocess.run", return_value=self._fake_process(ok_response)) as mock_run:
            transcriber.transcribe(synthetic_wav)

        called_args = mock_run.call_args[0][0]
        assert called_args[:3] == ["uv", "run", "--with"]
        assert "mlx-audio" in called_args[3]
        assert called_args[-1] == "ownscribe.transcription.canary_mlx_worker"

    def test_passes_config_fields_in_the_request_payload(self, synthetic_wav):
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        canary_config = CanaryConfig(repo="some/repo", max_segment_seconds=20.0, max_tokens_per_segment=99)
        transcriber = CanaryMlxTranscriber(TranscriptionConfig(language="en"), canary_config)
        ok_response = json.dumps({"ok": True, "result": {"segments": [], "duration": 0.5, "language": "en"}})

        with mock.patch("subprocess.run", return_value=self._fake_process(ok_response)) as mock_run:
            transcriber.transcribe(synthetic_wav)

        sent_request = json.loads(mock_run.call_args.kwargs["input"])
        assert sent_request["repo"] == "some/repo"
        assert sent_request["language"] == "en"
        assert sent_request["max_segment_seconds"] == 20.0
        assert sent_request["max_tokens"] == 99
        assert sent_request["audio_path"] == str(synthetic_wav)

    def test_parses_segments_from_a_successful_response(self, synthetic_wav):
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        ok_response = json.dumps(
            {
                "ok": True,
                "result": {
                    "segments": [{"text": "Bonjour", "start": 0.0, "end": 1.2}],
                    "duration": 1.2,
                    "language": "fr",
                },
            }
        )

        transcriber = CanaryMlxTranscriber(TranscriptionConfig(), CanaryConfig())
        with mock.patch("subprocess.run", return_value=self._fake_process(ok_response)):
            result = transcriber.transcribe(synthetic_wav)

        assert result.language == "fr"
        assert result.duration == 1.2
        assert len(result.segments) == 1
        assert result.segments[0].text == "Bonjour"
        assert result.segments[0].start == 0.0
        assert result.segments[0].end == 1.2
        assert result.segments[0].words == []

    def test_raises_when_worker_process_exits_nonzero(self, synthetic_wav):
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        transcriber = CanaryMlxTranscriber(TranscriptionConfig(), CanaryConfig())
        with (
            mock.patch("subprocess.run", return_value=self._fake_process("", returncode=1, stderr="resolver failed")),
            pytest.raises(RuntimeError, match="resolver failed"),
        ):
            transcriber.transcribe(synthetic_wav)

    def test_raises_when_worker_reports_ok_false(self, synthetic_wav):
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        error_response = json.dumps({"ok": False, "error": "ValueError: bad checkpoint"})
        transcriber = CanaryMlxTranscriber(TranscriptionConfig(), CanaryConfig())
        with (
            mock.patch("subprocess.run", return_value=self._fake_process(error_response)),
            pytest.raises(RuntimeError, match="bad checkpoint"),
        ):
            transcriber.transcribe(synthetic_wav)

    def test_raises_when_stdout_is_not_valid_json(self, synthetic_wav):
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        transcriber = CanaryMlxTranscriber(TranscriptionConfig(), CanaryConfig())
        with (
            mock.patch("subprocess.run", return_value=self._fake_process("not json at all")),
            pytest.raises(RuntimeError, match="non-JSON"),
        ):
            transcriber.transcribe(synthetic_wav)


class TestCreateTranscriberEngineSelection:
    def test_default_engine_creates_whisperx_transcriber(self):
        from ownscribe.pipeline import _create_transcriber
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        transcriber = _create_transcriber(Config())
        assert isinstance(transcriber, WhisperXTranscriber)

    def test_canary_mlx_engine_creates_canary_transcriber_when_uv_available(self):
        from ownscribe.pipeline import _create_transcriber
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        config = Config()
        config.transcription.engine = "canary_mlx"

        with mock.patch("ownscribe.transcription.canary_mlx_transcriber.is_available", return_value=True):
            transcriber = _create_transcriber(config)

        assert isinstance(transcriber, CanaryMlxTranscriber)

    def test_canary_mlx_engine_fails_loud_when_uv_unavailable(self):
        from ownscribe.pipeline import _create_transcriber

        config = Config()
        config.transcription.engine = "canary_mlx"

        with (
            mock.patch("ownscribe.transcription.canary_mlx_transcriber.is_available", return_value=False),
            pytest.raises(SystemExit),
        ):
            _create_transcriber(config)


class TestCanaryMlxWorker:
    """Unit tests for the worker's pure segmentation/generation logic, with
    mlx_audio/whisperx/faster_whisper mocked -- these never spawn a real overlay."""

    def _install_fake_modules(self, monkeypatch, *, audio_samples, vad_spans, generate_side_effect):
        import sys
        import types as pytypes

        import numpy as np

        fake_whisperx = pytypes.ModuleType("whisperx")
        fake_whisperx.load_audio = mock.MagicMock(return_value=np.array(audio_samples, dtype=np.float32))

        fake_vad_module = pytypes.ModuleType("faster_whisper.vad")
        fake_vad_module.VadOptions = mock.MagicMock(side_effect=lambda **kw: kw)
        fake_vad_module.get_speech_timestamps = mock.MagicMock(return_value=vad_spans)

        fake_model = mock.MagicMock()
        fake_model.generate.side_effect = generate_side_effect
        fake_load = mock.MagicMock(return_value=fake_model)
        fake_mlx_audio_pkg = pytypes.ModuleType("mlx_audio")
        fake_stt_module = pytypes.ModuleType("mlx_audio.stt")
        fake_stt_module.load = fake_load

        fake_mlx_pkg = pytypes.ModuleType("mlx")
        fake_mx = pytypes.ModuleType("mlx.core")
        fake_mx.float32 = "float32-sentinel"

        monkeypatch.setitem(sys.modules, "whisperx", fake_whisperx)
        monkeypatch.setitem(sys.modules, "faster_whisper.vad", fake_vad_module)
        monkeypatch.setitem(sys.modules, "mlx_audio", fake_mlx_audio_pkg)
        monkeypatch.setitem(sys.modules, "mlx_audio.stt", fake_stt_module)
        monkeypatch.setitem(sys.modules, "mlx", fake_mlx_pkg)
        monkeypatch.setitem(sys.modules, "mlx.core", fake_mx)
        return fake_load, fake_model

    def test_run_skips_empty_spans_and_empty_text(self, monkeypatch):
        from ownscribe.transcription.canary_mlx_worker import _run

        fake_result_text = mock.MagicMock(text="  Bonjour  ")
        fake_result_empty = mock.MagicMock(text="   ")

        self._install_fake_modules(
            monkeypatch,
            audio_samples=[0.0] * 32000,
            vad_spans=[{"start": 0, "end": 0}, {"start": 0, "end": 16000}, {"start": 16000, "end": 32000}],
            generate_side_effect=[fake_result_text, fake_result_empty],
        )

        result = _run(
            audio_path="fake.wav",
            repo="fake/repo",
            language="fr",
            max_segment_seconds=40.0,
            max_tokens=200,
        )

        assert len(result["segments"]) == 1
        assert result["segments"][0]["text"] == "Bonjour"
        assert result["segments"][0]["start"] == 0.0
        assert result["segments"][0]["end"] == 1.0
        assert result["duration"] == 2.0
        assert result["language"] == "fr"

    def test_run_passes_source_and_target_lang_from_the_single_language_field(self, monkeypatch):
        from ownscribe.transcription.canary_mlx_worker import _run

        fake_result = mock.MagicMock(text="Hello")
        _, fake_model = self._install_fake_modules(
            monkeypatch,
            audio_samples=[0.0] * 16000,
            vad_spans=[{"start": 0, "end": 16000}],
            generate_side_effect=[fake_result],
        )

        _run(audio_path="fake.wav", repo="fake/repo", language="en", max_segment_seconds=40.0, max_tokens=200)

        call_kwargs = fake_model.generate.call_args.kwargs
        assert call_kwargs["source_lang"] == "en"
        assert call_kwargs["target_lang"] == "en"
        assert call_kwargs["max_tokens"] == 200

    def test_main_writes_ok_true_json_to_stdout_on_success(self, monkeypatch, capsys):
        from ownscribe.transcription import canary_mlx_worker

        fake_request = {
            "audio_path": "fake.wav",
            "repo": "fake/repo",
            "language": "fr",
            "max_segment_seconds": 40.0,
            "max_tokens": 200,
        }
        monkeypatch.setattr("sys.stdin", mock.MagicMock(read=lambda: json.dumps(fake_request)))
        monkeypatch.setattr(
            canary_mlx_worker,
            "_run",
            lambda **kwargs: {"segments": [], "duration": 1.0, "language": "fr"},
        )

        canary_mlx_worker.main()

        captured = json.loads(capsys.readouterr().out)
        assert captured["ok"] is True
        assert captured["result"]["language"] == "fr"

    def test_main_writes_ok_false_json_on_exception_never_raises(self, monkeypatch, capsys):
        from ownscribe.transcription import canary_mlx_worker

        fake_request = {
            "audio_path": "fake.wav",
            "repo": "fake/repo",
            "language": "fr",
            "max_segment_seconds": 40.0,
            "max_tokens": 200,
        }
        monkeypatch.setattr("sys.stdin", mock.MagicMock(read=lambda: json.dumps(fake_request)))

        def _boom(**kwargs):
            raise ValueError("checkpoint corrupt")

        monkeypatch.setattr(canary_mlx_worker, "_run", _boom)

        canary_mlx_worker.main()

        captured = json.loads(capsys.readouterr().out)
        assert captured["ok"] is False
        assert "checkpoint corrupt" in captured["error"]


@pytest.mark.slow
@pytest.mark.hardware
class TestCanaryMlxRealIntegration:
    """Real, unmocked, end-to-end proof: spawns the actual `uv run --with mlx-audio`
    overlay subprocess, downloads the real Canary-1B-v2 checkpoint (cached after the
    first run), and transcribes a real short clip. Slow (checkpoint load + generation)
    and needs network + uv on PATH -- excluded from the default fast pytest run via
    the `slow`/`hardware` markers already registered in pyproject.toml.
    """

    def test_transcribes_a_real_short_clip(self, tmp_path):

        from ownscribe.transcription.canary_mlx_transcriber import is_available

        if not is_available():
            pytest.skip("uv not on PATH")

        import numpy as np
        import soundfile as sf

        sample_rate = 16000
        t = np.linspace(0, 1.0, sample_rate, endpoint=False)
        tone = (0.1 * np.sin(2 * np.pi * 440 * t)).astype(np.float32)
        wav_path = tmp_path / "tone.wav"
        sf.write(str(wav_path), tone, sample_rate)

        from ownscribe.config import CanaryConfig, TranscriptionConfig
        from ownscribe.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        transcriber = CanaryMlxTranscriber(TranscriptionConfig(language="fr"), CanaryConfig())
        try:
            result = transcriber.transcribe(wav_path)
        except RuntimeError as exc:
            if "ConnectionError" in str(exc) or "offline" in str(exc).lower():
                pytest.skip(f"network unavailable for checkpoint download: {exc}")
            raise

        assert result.language == "fr"
        assert result.duration > 0.0
        assert isinstance(result.segments, list)
