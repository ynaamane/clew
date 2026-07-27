"""Audio envelope generation for timeline visualization."""

from __future__ import annotations

from pathlib import Path

import numpy as np


def compute_rms_envelope(audio: np.ndarray, n_buckets: int) -> np.ndarray:
    """
    Compute RMS envelope of audio signal.

    Args:
        audio: 1D float32 array of audio samples
        n_buckets: Number of buckets to divide the audio into

    Returns:
        1D array of length n_buckets, normalized to [0, 1] where 1.0 is the peak RMS
    """
    if len(audio) == 0 or n_buckets == 0:
        return np.zeros(n_buckets, dtype=np.float32)

    if np.all(audio == 0):
        return np.zeros(n_buckets, dtype=np.float32)

    bucket_size = len(audio) // n_buckets
    if bucket_size == 0:
        envelope = np.zeros(n_buckets, dtype=np.float32)
        for i in range(min(len(audio), n_buckets)):
            envelope[i] = np.abs(audio[i])
        peak = envelope.max()
        return envelope / peak if peak > 0 else envelope

    envelope = np.zeros(n_buckets, dtype=np.float32)
    for i in range(n_buckets):
        start = i * bucket_size
        end = start + bucket_size
        if start >= len(audio):
            break
        chunk = audio[start:end]
        rms = np.sqrt(np.mean(chunk**2))
        envelope[i] = rms

    peak = envelope.max()
    return envelope / peak if peak > 0 else envelope


def generate_envelope_from_file(audio_path: Path, n_buckets: int) -> np.ndarray:
    """
    Generate RMS envelope from an audio file.

    Handles mono and stereo files (averages channels), missing files, and silent audio.

    Args:
        audio_path: Path to WAV file
        n_buckets: Number of buckets to divide the audio into

    Returns:
        1D array of length n_buckets, normalized to [0, 1]
    """
    try:
        import soundfile as sf

        audio, _sr = sf.read(audio_path, always_2d=True, dtype="float32")

        audio_mono = audio.mean(axis=1) if audio.shape[1] > 1 else audio[:, 0]
        return compute_rms_envelope(audio_mono, n_buckets)

    except (FileNotFoundError, RuntimeError):
        return np.zeros(n_buckets, dtype=np.float32)
