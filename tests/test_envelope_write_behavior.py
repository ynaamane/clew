"""Tests for envelope write behavior - absent vs silent distinction."""

from __future__ import annotations

import json

import numpy as np
import soundfile as sf

from clew.audio.envelope import generate_envelope_from_file
from clew.pipeline import _generate_and_save_envelope


class TestEnvelopeWriteBehavior:
    """Test that pipeline distinguishes absent files from silent recordings."""

    def test_missing_file_writes_nothing(self, tmp_path):
        """Missing audio file should NOT write envelope.json."""
        audio_path = tmp_path / "nonexistent.wav"
        out_dir = tmp_path / "output"
        out_dir.mkdir()

        _generate_and_save_envelope(audio_path, out_dir)

        envelope_path = out_dir / "envelope.json"
        assert not envelope_path.exists(), "envelope.json should not exist for missing file"

    def test_corrupt_file_writes_nothing(self, tmp_path):
        """Corrupt audio file should NOT write envelope.json."""
        audio_path = tmp_path / "corrupt.wav"
        audio_path.write_bytes(b"NOT A WAV FILE")
        out_dir = tmp_path / "output"
        out_dir.mkdir()

        _generate_and_save_envelope(audio_path, out_dir)

        envelope_path = out_dir / "envelope.json"
        assert not envelope_path.exists(), "envelope.json should not exist for corrupt file"

    def test_silent_file_writes_valid_zeros(self, tmp_path):
        """Real but silent recording MUST write envelope.json with zeros."""
        audio_path = tmp_path / "silent.wav"
        audio = np.zeros(4800, dtype=np.float32)
        sf.write(audio_path, audio, 48000)

        out_dir = tmp_path / "output"
        out_dir.mkdir()

        _generate_and_save_envelope(audio_path, out_dir)

        envelope_path = out_dir / "envelope.json"
        assert envelope_path.exists(), "envelope.json MUST exist for real silent file"

        data = json.loads(envelope_path.read_text())
        envelope = np.array(data["envelope"])
        assert len(envelope) == 500
        assert np.all(envelope == 0.0), "Silent recording should have all-zero envelope"

    def test_normal_file_writes_valid_envelope(self, tmp_path):
        """Normal audio file writes envelope.json with non-zero values."""
        audio_path = tmp_path / "normal.wav"
        audio = np.random.randn(4800).astype(np.float32) * 0.5
        sf.write(audio_path, audio, 48000)

        out_dir = tmp_path / "output"
        out_dir.mkdir()

        _generate_and_save_envelope(audio_path, out_dir)

        envelope_path = out_dir / "envelope.json"
        assert envelope_path.exists()

        data = json.loads(envelope_path.read_text())
        envelope = np.array(data["envelope"])
        assert len(envelope) == 500
        assert envelope.max() > 0, "Normal audio should have non-zero envelope"


class TestEnvelopeGeneratorDistinction:
    """Test that generate_envelope_from_file signals failure distinctly."""

    def test_missing_file_returns_none(self, tmp_path):
        """Missing file should return None, not zeros."""
        audio_path = tmp_path / "nonexistent.wav"
        result = generate_envelope_from_file(audio_path, n_buckets=10)
        assert result is None, "Missing file should return None"

    def test_corrupt_file_returns_none(self, tmp_path):
        """Corrupt file should return None, not zeros."""
        audio_path = tmp_path / "corrupt.wav"
        audio_path.write_bytes(b"NOT A WAV FILE")
        result = generate_envelope_from_file(audio_path, n_buckets=10)
        assert result is None, "Corrupt file should return None"

    def test_silent_file_returns_zeros_array(self, tmp_path):
        """Real but silent file MUST return valid zeros array."""
        audio_path = tmp_path / "silent.wav"
        audio = np.zeros(4800, dtype=np.float32)
        sf.write(audio_path, audio, 48000)

        result = generate_envelope_from_file(audio_path, n_buckets=10)

        assert result is not None, "Real silent file must return array, not None"
        assert isinstance(result, np.ndarray)
        assert len(result) == 10
        assert np.all(result == 0.0), "Silent recording should be all zeros"
