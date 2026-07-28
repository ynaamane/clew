"""Tests for audio envelope generation."""

from __future__ import annotations

import numpy as np
import pytest

from ownscribe.audio.envelope import compute_rms_envelope, generate_envelope_from_file


class TestComputeRMSEnvelope:
    """Test the pure RMS envelope computation function."""

    def test_constant_tone_produces_uniform_envelope(self):
        """A constant tone should produce a uniform envelope (all values equal)."""
        # 1000 samples at constant amplitude 0.5
        audio = np.full(1000, 0.5, dtype=np.float32)
        n_buckets = 10

        envelope = compute_rms_envelope(audio, n_buckets)

        assert len(envelope) == n_buckets
        # All buckets should have the same normalized value (1.0 since peak = 0.5)
        np.testing.assert_allclose(envelope, 1.0, rtol=1e-5)

    def test_half_silent_produces_half_zeros(self):
        """First half silent, second half at 1.0 → first half should be near 0."""
        audio = np.concatenate([np.zeros(500, dtype=np.float32), np.ones(500, dtype=np.float32)])
        n_buckets = 10

        envelope = compute_rms_envelope(audio, n_buckets)

        assert len(envelope) == n_buckets
        # First 5 buckets should be near 0
        assert np.all(envelope[:5] < 0.01)
        # Last 5 buckets should be near 1.0 (normalized to peak)
        np.testing.assert_allclose(envelope[5:], 1.0, atol=0.01)

    def test_impulse_at_start_produces_peak_at_first_bucket(self):
        """A single impulse at the start should make the first bucket the peak."""
        audio = np.zeros(1000, dtype=np.float32)
        audio[0] = 1.0  # Impulse at start
        n_buckets = 10

        envelope = compute_rms_envelope(audio, n_buckets)

        assert len(envelope) == n_buckets
        # First bucket should be the peak (1.0 after normalization)
        assert envelope[0] == pytest.approx(1.0, abs=0.01)
        # All other buckets should be near 0
        assert np.all(envelope[1:] < 0.01)

    def test_empty_audio_returns_zeros(self):
        """Empty audio should return all zeros."""
        audio = np.array([], dtype=np.float32)
        n_buckets = 10

        envelope = compute_rms_envelope(audio, n_buckets)

        assert len(envelope) == n_buckets
        assert np.all(envelope == 0.0)

    def test_all_zeros_returns_zeros(self):
        """Silent audio (all zeros) should return all zeros."""
        audio = np.zeros(1000, dtype=np.float32)
        n_buckets = 10

        envelope = compute_rms_envelope(audio, n_buckets)

        assert len(envelope) == n_buckets
        assert np.all(envelope == 0.0)

    def test_fewer_samples_than_buckets(self):
        """Audio shorter than bucket count should still return n_buckets."""
        audio = np.ones(5, dtype=np.float32)
        n_buckets = 10

        envelope = compute_rms_envelope(audio, n_buckets)

        assert len(envelope) == n_buckets
        # First 5 buckets should have values, rest should be 0
        assert np.all(envelope[:5] > 0)
        assert np.all(envelope[5:] == 0.0)

    def test_real_file_reference_measurement(self):
        """Validate against the real recording reference measurement."""
        from pathlib import Path

        audio_path = Path(
            "/Users/yanisnaamane/ownscribe/2026-07-27_1536_project-technical-review-key-points/recording.wav"
        )

        if not audio_path.exists():
            pytest.skip("Reference recording not available on this machine")

        envelope = generate_envelope_from_file(audio_path, n_buckets=170)

        # Reference measurements
        assert len(envelope) == 170
        non_silent = (envelope > 0.02).sum()
        assert non_silent == 107, f"Expected 107 non-silent buckets, got {non_silent}"

        # First 5 values (within tolerance)
        expected_first_5 = np.array([0.133, 0.004, 0.142, 0.548, 0.800])
        np.testing.assert_allclose(envelope[:5], expected_first_5, atol=0.001)

        # Peak should be 1.0 and around bucket 136-137
        assert envelope.max() == pytest.approx(1.0, abs=1e-6)
        peak_idx = envelope.argmax()
        assert 135 <= peak_idx <= 138, f"Peak at bucket {peak_idx}, expected ~136-137"


class TestGenerateEnvelopeFromFile:
    """Test the file reader that generates envelopes from audio files."""

    def test_generates_envelope_from_mono_file(self, tmp_path):
        """Should read a mono WAV and generate an envelope."""
        import soundfile as sf

        audio_path = tmp_path / "mono.wav"
        audio = np.random.randn(4800).astype(np.float32) * 0.5
        sf.write(audio_path, audio, 48000)

        envelope = generate_envelope_from_file(audio_path, n_buckets=10)

        assert len(envelope) == 10
        assert envelope.dtype == np.float32
        assert 0 <= envelope.min() <= envelope.max() <= 1.0

    def test_generates_envelope_from_stereo_file(self, tmp_path):
        """Should read a stereo WAV, average channels, and generate an envelope."""
        import soundfile as sf

        audio_path = tmp_path / "stereo.wav"
        left = np.concatenate([np.ones(2400, dtype=np.float32), np.zeros(2400, dtype=np.float32)])
        right = np.concatenate([np.zeros(2400, dtype=np.float32), np.ones(2400, dtype=np.float32)])
        audio = np.column_stack([left, right])
        sf.write(audio_path, audio, 48000)

        envelope = generate_envelope_from_file(audio_path, n_buckets=10)

        assert len(envelope) == 10
        assert envelope.dtype == np.float32
        assert envelope[0] > 0.4
        assert envelope[9] > 0.4
        assert envelope[0] == pytest.approx(envelope[9], rel=0.1)

    def test_handles_missing_file_gracefully(self, tmp_path):
        """Missing audio file should return None without crashing."""
        audio_path = tmp_path / "nonexistent.wav"

        envelope = generate_envelope_from_file(audio_path, n_buckets=10)

        assert envelope is None

    def test_handles_silent_file(self, tmp_path):
        """Completely silent file should return all zeros."""
        import soundfile as sf

        audio_path = tmp_path / "silent.wav"
        audio = np.zeros(4800, dtype=np.float32)
        sf.write(audio_path, audio, 48000)

        envelope = generate_envelope_from_file(audio_path, n_buckets=10)

        assert len(envelope) == 10
        assert np.all(envelope == 0.0)


def test_envelope_json_format_is_compact(tmp_path):
    """Test that envelope JSON is compact and small."""
    import json

    import soundfile as sf

    audio_path = tmp_path / "test.wav"
    audio = np.random.randn(48000).astype(np.float32) * 0.5
    sf.write(audio_path, audio, 48000)

    envelope = generate_envelope_from_file(audio_path, n_buckets=500)

    json_path = tmp_path / "envelope.json"
    json_path.write_text(json.dumps({"envelope": envelope.tolist()}))

    size_kb = json_path.stat().st_size / 1024
    assert size_kb < 20, f"Envelope JSON is {size_kb:.1f} KB, should be < 20 KB"
