"""Tests for transcription helpers."""

from __future__ import annotations

import types
from unittest import mock

import pytest


class TestFfmpegCheck:
    def test_missing_ffmpeg_exits(self):
        from ownscribe.config import TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        transcriber = WhisperXTranscriber(TranscriptionConfig(), None)

        with mock.patch("shutil.which", return_value=None), pytest.raises(SystemExit):
            transcriber.transcribe(mock.MagicMock())


class _FakeProgress:
    def __init__(self) -> None:
        self.calls: list[tuple[str, str]] = []
        self.details: dict[str, str] = {}
        self.updates: list[tuple[str, float]] = []

    def begin(self, key: str) -> None:
        self.calls.append(("begin", key))

    def complete(self, key: str) -> None:
        self.calls.append(("complete", key))

    def fail(self, key: str) -> None:
        self.calls.append(("fail", key))

    def update(self, key: str, fraction: float) -> None:
        self.updates.append((key, fraction))

    def set_detail(self, key: str, text: str | None) -> None:
        if text is None:
            self.details.pop(key, None)
        else:
            self.details[key] = text

    def diarization_hook(self, step_name: str, _artifact, **kwargs) -> None:
        _ = (step_name, _artifact, kwargs)


class TestPrepareModels:
    def test_prepare_models_emits_preparing_models_lifecycle(self):
        from ownscribe.config import TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        progress = _FakeProgress()
        transcriber = WhisperXTranscriber(TranscriptionConfig(language="en"), None, progress=progress)

        def passthrough(stage_label, fn, *args, **kwargs):
            _ = stage_label
            return fn(*args, **kwargs)

        with (
            mock.patch.object(transcriber, "_capture_prep_output", side_effect=passthrough),
            mock.patch.object(transcriber, "_load_model", side_effect=lambda: setattr(transcriber, "_model", object())),
            mock.patch.object(transcriber, "_load_align_model", return_value=(object(), object())),
        ):
            transcriber.prepare_models(language="en")

        assert ("begin", "preparing_models") in progress.calls
        assert ("complete", "preparing_models") in progress.calls
        assert ("fail", "preparing_models") not in progress.calls

    def test_prepare_models_skips_diarization_without_token(self):
        from ownscribe.config import DiarizationConfig, TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        progress = _FakeProgress()
        diar = DiarizationConfig(enabled=True, hf_token="")
        transcriber = WhisperXTranscriber(TranscriptionConfig(language="en"), diar, progress=progress)

        def passthrough(stage_label, fn, *args, **kwargs):
            _ = stage_label
            return fn(*args, **kwargs)

        with (
            mock.patch.object(transcriber, "_capture_prep_output", side_effect=passthrough),
            mock.patch.object(transcriber, "_load_model", side_effect=lambda: setattr(transcriber, "_model", object())),
            mock.patch.object(transcriber, "_load_align_model", return_value=(object(), object())),
            mock.patch.object(transcriber, "_load_diarization_pipeline") as mock_diar_load,
        ):
            transcriber.prepare_models(language="en")

        mock_diar_load.assert_not_called()

    def test_prepare_models_reuses_loaded_whisper_model(self):
        from ownscribe.config import TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        progress = _FakeProgress()
        transcriber = WhisperXTranscriber(TranscriptionConfig(language="en"), None, progress=progress)

        def passthrough(stage_label, fn, *args, **kwargs):
            _ = stage_label
            return fn(*args, **kwargs)

        with (
            mock.patch.object(transcriber, "_capture_prep_output", side_effect=passthrough),
            mock.patch.object(
                transcriber,
                "_load_model",
                side_effect=lambda: setattr(transcriber, "_model", object()),
            ) as mock_load_model,
            mock.patch.object(transcriber, "_load_align_model", return_value=(object(), object())),
        ):
            transcriber.prepare_models(language="en")
            transcriber.prepare_models(language="en")

        assert mock_load_model.call_count == 1


class TestDownloadProgressHooks:
    def test_on_download_progress_updates_detail_and_bar(self):
        from ownscribe.config import TranscriptionConfig
        from ownscribe.progress import DownloadProgressEvent
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        progress = _FakeProgress()
        transcriber = WhisperXTranscriber(TranscriptionConfig(), None, progress=progress)

        transcriber._on_download_progress(
            "preparing_models",
            "Loading Whisper model (base)",
            DownloadProgressEvent(filename="model.bin", percent=25.0),
        )

        assert ("preparing_models", 0.25) in progress.updates
        assert "Loading Whisper model (base)" in progress.details["preparing_models"]
        assert "model.bin" in progress.details["preparing_models"]
        assert "25%" not in progress.details["preparing_models"]

    def test_capture_download_output_resets_bar_to_zero(self):
        from ownscribe.config import TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        progress = _FakeProgress()
        transcriber = WhisperXTranscriber(TranscriptionConfig(), None, progress=progress)

        def fake_loader():
            print("model.bin: 12%|##| 12MB/100MB [00:01<00:08]")

        transcriber._capture_download_output("preparing_models", "Loading Whisper model (base)", fake_loader)

        assert progress.updates
        # Progress bar should only appear once download events fire, not eagerly at 0%
        assert all(frac > 0 for _, frac in progress.updates)

    def test_transcribe_inner_does_not_use_preparing_models_step(self):
        from ownscribe.config import TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        class _Audio:
            shape = (16000,)

        fake_whisperx = types.SimpleNamespace(
            load_audio=lambda _path: _Audio(),
            align=lambda *args, **kwargs: {"segments": []},
        )

        progress = _FakeProgress()
        transcriber = WhisperXTranscriber(TranscriptionConfig(language="en"), None, progress=progress)
        transcriber._model = mock.MagicMock()
        transcriber._model.transcribe.return_value = {"segments": [], "language": "en"}

        with (
            mock.patch.dict("sys.modules", {"whisperx": fake_whisperx}),
            mock.patch.object(transcriber, "_prepare_transcription_models") as mock_prepare_runtime,
            mock.patch.object(transcriber, "_load_align_model", return_value=(object(), object())),
            mock.patch.object(transcriber, "prepare_models") as mock_prepare_models,
        ):
            result = transcriber._transcribe_inner(mock.MagicMock(), want_diarize=False)

        mock_prepare_models.assert_not_called()
        mock_prepare_runtime.assert_called_once_with(
            language="en",
            step_key="transcribing",
            show_deferred_align_note=False,
        )
        assert ("begin", "transcribing") in progress.calls
        assert ("begin", "preparing_models") not in progress.calls
        assert result.language == "en"


class TestDiarizeOverride:
    def test_diarize_false_override_skips_diarization_even_when_configured(self):
        from ownscribe.config import DiarizationConfig, TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        class _Audio:
            shape = (16000,)

        fake_whisperx = types.SimpleNamespace(
            load_audio=lambda _path: _Audio(),
            align=lambda *args, **kwargs: {"segments": []},
        )

        diar = DiarizationConfig(enabled=True, hf_token="hf_test_token")
        transcriber = WhisperXTranscriber(TranscriptionConfig(), diar, progress=_FakeProgress())
        transcriber._model = mock.MagicMock()
        transcriber._model.transcribe.return_value = {"segments": [], "language": "en"}

        with (
            mock.patch("shutil.which", return_value="/usr/bin/ffmpeg"),
            mock.patch.dict("sys.modules", {"whisperx": fake_whisperx}),
            mock.patch.object(transcriber, "_load_align_model", return_value=(object(), object())),
            mock.patch.object(transcriber, "_diarize") as mock_diarize,
        ):
            transcriber.transcribe(mock.MagicMock(), diarize=False)

        mock_diarize.assert_not_called()

    def test_diarize_none_falls_back_to_config_enabled(self):
        from ownscribe.config import DiarizationConfig, TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        class _Audio:
            shape = (16000,)

        fake_whisperx = types.SimpleNamespace(
            load_audio=lambda _path: _Audio(),
            align=lambda *args, **kwargs: {"segments": []},
        )

        diar = DiarizationConfig(enabled=True, hf_token="hf_test_token")
        transcriber = WhisperXTranscriber(TranscriptionConfig(), diar, progress=_FakeProgress())
        transcriber._model = mock.MagicMock()
        transcriber._model.transcribe.return_value = {"segments": [], "language": "en"}

        with (
            mock.patch("shutil.which", return_value="/usr/bin/ffmpeg"),
            mock.patch.dict("sys.modules", {"whisperx": fake_whisperx}),
            mock.patch.object(transcriber, "_load_align_model", return_value=(object(), object())),
            mock.patch.object(transcriber, "_diarize", return_value={"segments": []}) as mock_diarize,
        ):
            transcriber.transcribe(mock.MagicMock())

        mock_diarize.assert_called_once()

    def test_diarize_enabled_without_token_skips_diarize_and_warns(self):
        from ownscribe.config import DiarizationConfig, TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        class _Audio:
            shape = (16000,)

        fake_whisperx = types.SimpleNamespace(
            load_audio=lambda _path: _Audio(),
            align=lambda *args, **kwargs: {"segments": []},
        )

        diar = DiarizationConfig(enabled=True, hf_token="")
        transcriber = WhisperXTranscriber(TranscriptionConfig(), diar, progress=_FakeProgress())
        transcriber._model = mock.MagicMock()
        transcriber._model.transcribe.return_value = {"segments": [], "language": "en"}

        with (
            mock.patch("shutil.which", return_value="/usr/bin/ffmpeg"),
            mock.patch.dict("sys.modules", {"whisperx": fake_whisperx}),
            mock.patch.object(transcriber, "_load_align_model", return_value=(object(), object())),
            mock.patch.object(transcriber, "_diarize") as mock_diarize,
            mock.patch("ownscribe.transcription.whisperx_transcriber.click.echo") as mock_echo,
        ):
            transcriber.transcribe(mock.MagicMock())

        mock_diarize.assert_not_called()
        warnings_seen = [call.args[0] for call in mock_echo.call_args_list if call.args]
        assert any("Diarization requested but no HF token configured" in w for w in warnings_seen)


class TestDiarizationApiCompat:
    def test_load_diarization_pipeline_passes_token_kwarg(self):
        # pyannote.audio 4.0 renamed `use_auth_token` -> `token`.
        from ownscribe.config import DiarizationConfig, TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        diar = DiarizationConfig(enabled=True, hf_token="hf_test_token")
        transcriber = WhisperXTranscriber(TranscriptionConfig(), diar, progress=_FakeProgress())

        fake_pipeline = mock.MagicMock(return_value=mock.sentinel.diarize_model)
        fake_diarize_module = types.SimpleNamespace(DiarizationPipeline=fake_pipeline)

        def passthrough(_step_key, _label, fn, *args, **kwargs):
            return fn(*args, **kwargs)

        with (
            mock.patch.dict("sys.modules", {"whisperx.diarize": fake_diarize_module}),
            mock.patch.object(transcriber, "_capture_download_output", side_effect=passthrough),
        ):
            result = transcriber._load_diarization_pipeline()

        assert result is mock.sentinel.diarize_model
        fake_pipeline.assert_called_once()
        kwargs = fake_pipeline.call_args.kwargs
        assert kwargs.get("token") == "hf_test_token"
        assert "use_auth_token" not in kwargs

    def test_load_diarization_pipeline_always_forces_cpu(self):
        from ownscribe.config import DiarizationConfig, TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        diar = DiarizationConfig(enabled=True, hf_token="hf_test_token")
        transcriber = WhisperXTranscriber(TranscriptionConfig(), diar, progress=_FakeProgress())

        fake_pipeline = mock.MagicMock(return_value=mock.sentinel.diarize_model)
        fake_diarize_module = types.SimpleNamespace(DiarizationPipeline=fake_pipeline)

        def passthrough(_step_key, _label, fn, *args, **kwargs):
            return fn(*args, **kwargs)

        with (
            mock.patch.dict("sys.modules", {"whisperx.diarize": fake_diarize_module}),
            mock.patch.object(transcriber, "_capture_download_output", side_effect=passthrough),
        ):
            transcriber._load_diarization_pipeline()

        kwargs = fake_pipeline.call_args.kwargs
        assert kwargs.get("device") == "cpu"

    def test_diarize_unwraps_speaker_diarization_from_diarize_output(self):
        # pyannote.audio 4.0 wraps the annotation in a DiarizeOutput container;
        # _diarize must read it as `.speaker_diarization.itertracks()`.
        import numpy as np
        import torch  # noqa: F401

        from ownscribe.config import DiarizationConfig, TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        diar = DiarizationConfig(enabled=True, hf_token="hf_test_token")
        transcriber = WhisperXTranscriber(TranscriptionConfig(), diar, progress=_FakeProgress())

        fake_segment = types.SimpleNamespace(start=0.5, end=1.5)
        fake_annotation = mock.MagicMock()
        fake_annotation.itertracks.return_value = [(fake_segment, "track_0", "SPEAKER_00")]
        fake_annotation.labels.return_value = ["SPEAKER_00"]
        # DiarizeOutput stand-in: deliberately no top-level `itertracks` attribute.
        fake_diarize_output = types.SimpleNamespace(
            speaker_diarization=fake_annotation,
            speaker_embeddings=np.array([[0.1, 0.2, 0.3]]),
        )

        fake_diarize_model = mock.MagicMock()
        fake_diarize_model.model.return_value = fake_diarize_output

        fake_whisperx = types.SimpleNamespace(assign_word_speakers=lambda df, res: ("assigned", df, res))

        audio = np.zeros(16000, dtype=np.float32)

        with (
            mock.patch.object(transcriber, "_load_diarization_pipeline", return_value=fake_diarize_model),
            mock.patch.dict("sys.modules", {"whisperx": fake_whisperx}),
        ):
            out = transcriber._diarize(audio, {"segments": []})

        fake_annotation.itertracks.assert_called_once_with(yield_label=True)
        assert out[0] == "assigned"
        assert transcriber.last_speaker_embeddings == {"SPEAKER_00": [0.1, 0.2, 0.3]}


class TestPyannoteAudioIoRealDecode:
    """Real (unmocked) proof that the in-memory {waveform, sample_rate} dict this
    codebase always passes to pyannote never touches torchcodec, regardless of
    whether the venv's torchcodec build can dlopen against the installed FFmpeg.
    No HF token or gated model needed: pyannote.audio.core.io.Audio is the same
    IO helper the real diarization pipeline (SpeakerDiarization) delegates to for
    every audio access, and this test exercises it directly on a real, decoded
    (non-mocked) waveform.
    """

    def test_call_and_crop_succeed_on_real_waveform_dict(self):
        import numpy as np
        import torch
        from pyannote.audio.core.io import Audio
        from pyannote.core import Segment

        waveform = torch.from_numpy(np.random.randn(1, 16000).astype("float32"))
        audio_data = {"waveform": waveform, "sample_rate": 16000}
        io = Audio()

        full_waveform, sample_rate = io(audio_data)
        assert full_waveform.shape == (1, 16000)
        assert sample_rate == 16000

        cropped_waveform, crop_sample_rate = io.crop(audio_data, Segment(0.0, 0.5))
        assert cropped_waveform.shape == (1, 8000)
        assert crop_sample_rate == 16000

    def test_whisperx_load_audio_never_imports_torchcodec(self, tmp_path):
        import sys

        import numpy as np
        import soundfile as sf
        import whisperx

        assert "torchcodec" not in sys.modules, "torchcodec must not already be imported by an earlier test"

        wav_path = tmp_path / "real_tone.wav"
        sf.write(str(wav_path), (np.random.randn(16000) * 0.1).astype("float32"), 16000)

        audio = whisperx.load_audio(str(wav_path))

        assert audio.dtype == np.float32
        assert len(audio) > 0
        assert "torchcodec" not in sys.modules, (
            "whisperx.load_audio shells out to the real ffmpeg CLI directly; "
            "if this starts importing torchcodec, the in-memory-dict workaround "
            "this codebase relies on may no longer be sufficient upstream."
        )


class TestExtractClusterEmbeddings:
    def test_extracts_embeddings_keyed_by_speaker_label(self):
        import numpy as np

        from ownscribe.config import TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        transcriber = WhisperXTranscriber(TranscriptionConfig(), None)

        fake_annotation = mock.MagicMock()
        fake_annotation.labels.return_value = ["SPEAKER_00", "SPEAKER_01"]
        fake_diarization = types.SimpleNamespace(
            speaker_diarization=fake_annotation,
            speaker_embeddings=np.array([[0.1, 0.2], [0.3, 0.4]]),
        )

        result = transcriber._extract_cluster_embeddings(fake_diarization)

        assert result == {"SPEAKER_00": [0.1, 0.2], "SPEAKER_01": [0.3, 0.4]}

    def test_returns_empty_dict_when_embeddings_attribute_missing(self):
        from ownscribe.config import TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        transcriber = WhisperXTranscriber(TranscriptionConfig(), None)

        fake_diarization = types.SimpleNamespace(speaker_diarization=mock.MagicMock())

        result = transcriber._extract_cluster_embeddings(fake_diarization)

        assert result == {}

    def test_returns_empty_dict_when_embeddings_is_none(self):
        from ownscribe.config import TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        transcriber = WhisperXTranscriber(TranscriptionConfig(), None)

        fake_diarization = types.SimpleNamespace(
            speaker_diarization=mock.MagicMock(),
            speaker_embeddings=None,
        )

        result = transcriber._extract_cluster_embeddings(fake_diarization)

        assert result == {}


class TestLastSpeakerEmbeddings:
    def test_defaults_to_empty_dict(self):
        from ownscribe.config import TranscriptionConfig
        from ownscribe.transcription.whisperx_transcriber import WhisperXTranscriber

        transcriber = WhisperXTranscriber(TranscriptionConfig(), None)

        assert transcriber.last_speaker_embeddings == {}
