"""Tests for SpeakerEmbedder's audio decode path."""

from __future__ import annotations

import sys
from unittest import mock

import numpy as np

from ownscribe.speakers.embedding import SpeakerEmbedder


class TestEmbedFileNeverTouchesTorchcodec:
    """embed_file decodes via whisperx.load_audio (real ffmpeg CLI) and hands the
    embedding model a raw torch.Tensor, never a bare file path -- so it never
    reaches pyannote's torchcodec-dependent Audio IO decode path, exactly like the
    diarization path proven in TestPyannoteAudioIoRealDecode (test_transcription.py).
    """

    def test_passes_a_raw_tensor_not_a_path_to_the_embedding_model(self, synthetic_wav):
        fake_model = mock.MagicMock()
        fake_model.sample_rate = 16000
        fake_model.return_value = np.array([[0.1, 0.2, 0.3]])

        embedder = SpeakerEmbedder("fake_token")
        with mock.patch.object(embedder, "_load", return_value=fake_model):
            result = embedder.embed_file(synthetic_wav)

        assert result == [0.1, 0.2, 0.3]
        waveform_arg = fake_model.call_args[0][0]
        import torch

        assert isinstance(waveform_arg, torch.Tensor)
        assert waveform_arg.shape == (1, 1, 8000)

    def test_never_imports_torchcodec(self, synthetic_wav):
        assert "torchcodec" not in sys.modules, "torchcodec must not already be imported by an earlier test"

        fake_model = mock.MagicMock()
        fake_model.sample_rate = 16000
        fake_model.return_value = np.array([[0.1, 0.2, 0.3]])

        embedder = SpeakerEmbedder("fake_token")
        with mock.patch.object(embedder, "_load", return_value=fake_model):
            embedder.embed_file(synthetic_wav)

        assert "torchcodec" not in sys.modules, (
            "embed_file must decode via whisperx.load_audio (real ffmpeg CLI) and "
            "pass a raw tensor to the embedding model; if this starts importing "
            "torchcodec, it now depends on the version-mismatched decode path."
        )
