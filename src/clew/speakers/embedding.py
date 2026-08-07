"""Speaker embedding extraction using the same model pyannote diarization loads internally."""

from __future__ import annotations

from pathlib import Path

_COMMUNITY1_EMBEDDING_MODEL = {
    "checkpoint": "pyannote/speaker-diarization-community-1",
    "subfolder": "embedding",
}


class SpeakerEmbedder:
    def __init__(self, hf_token: str) -> None:
        self._hf_token = hf_token
        self._model = None

    def _load(self):
        from pyannote.audio.pipelines.speaker_verification import PretrainedSpeakerEmbedding

        if self._model is None:
            self._model = PretrainedSpeakerEmbedding(
                _COMMUNITY1_EMBEDDING_MODEL,
                device="cpu",
                token=self._hf_token,
            )
        return self._model

    def embed_file(self, audio_path: Path) -> list[float]:
        import torch
        import whisperx

        model = self._load()
        audio = whisperx.load_audio(str(audio_path), sr=model.sample_rate)
        waveform = torch.from_numpy(audio[None, None, :])
        embedding = model(waveform)
        return embedding[0].tolist()
