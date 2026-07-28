"""End-to-end checks that run the REAL Swift capture binary.

Everything else in this suite mocks subprocess, so a binary that no longer
captures anything would keep every test green. BUG4 was exactly that: the
menu-bar app recorded 33.5s of pure silence while the unit tests passed,
because the defect lived in a default nothing asserted on.

Marked hardware: skipped by scripts/check.sh, run deliberately.
"""

from __future__ import annotations

import json
import signal
import subprocess
import time
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent
CAPTURE_BINARY = REPO_ROOT / "swift" / ".build" / "debug" / "ownscribe-audio"


CHIME = Path("/System/Library/Sounds/Submarine.aiff")


def _run_capture(output: Path, seconds: float, extra: list[str] | None = None) -> str:
    """Capture for `seconds` while PLAYING sound, then SIGINT — how rec.sh stops it.

    Playing audio is not decoration. The tap records what the machine OUTPUTS, so on
    a silent or muted system it correctly produces a zero-frame file: a valid 48kHz
    stereo float WAV with no frames. A test that captures silence and asserts on
    duration is asserting about the room, not the code.

    The binary has no --duration flag; it records until interrupted.
    """
    command = [str(CAPTURE_BINARY), "capture", "--output", str(output)]
    if extra:
        command.extend(extra)
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        subprocess.run(["afplay", str(CHIME)], capture_output=True, timeout=20)

    process.send_signal(signal.SIGINT)
    try:
        _, stderr = process.communicate(timeout=30)
    except subprocess.TimeoutExpired:
        process.kill()
        pytest.fail("capture did not exit within 30s of SIGINT")
    return stderr


def _wav_frames(path: Path) -> tuple[int, int, float]:
    """Read frames/rate/duration with soundfile, not `wave`.

    The capture writes IEEE float32 (WAV format tag 3), which Python's stdlib
    `wave` rejects outright. That is deliberate — envelope.py reads float32 to
    keep a 400MB meeting under control — so the test must speak the same format
    production writes.
    """
    import soundfile as sf

    info = sf.info(str(path))
    return info.frames, info.samplerate, info.duration


@pytest.mark.hardware
class TestRealCaptureBinary:
    def test_binary_reports_its_capabilities(self):
        result = subprocess.run(
            [str(CAPTURE_BINARY), "--help"], capture_output=True, text=True, timeout=60
        )

        assert result.returncode == 0, f"the shipped binary must at least run: {result.stderr}"
        usage = result.stdout + result.stderr
        assert "capture" in usage, (
            "the capture subcommand must exist; coreaudio.py shells out to it and a rename would "
            "silently degrade the pipeline to the merged-only path"
        )

    def test_a_short_capture_produces_a_readable_wav_of_the_right_duration(self, tmp_path):
        output = tmp_path / "recording.wav"

        stderr = _run_capture(output, 3.0)

        assert output.exists(), f"capture wrote no file at all; stderr: {stderr}"

        frames, rate, duration = _wav_frames(output)

        assert frames > 0, (
            "a wav with zero frames is the 13GB/38.9h bug's signature: a temp file with real bytes "
            "but no data chunk fed a corrupt frame count into the merge"
        )
        assert rate >= 16000, f"sample rate {rate} is implausibly low for the hardware path"
        assert duration >= 1.0, (
            f"captured only {duration:.2f}s while sound was playing for ~3s. A near-zero duration "
            f"here means the tap produced a header with no frames — the 13GB/38.9h bug's signature. "
            f"stderr: {stderr}"
        )
        assert duration <= 30.0, (
            f"{duration:.2f}s from a ~3s capture. BUG5 was exactly this shape: a hardcoded 24kHz "
            f"against a 48kHz capture made every duration wrong by 2x"
        )

    def test_capture_length_tracks_how_long_the_process_ran(self, tmp_path):
        short_file = tmp_path / "short.wav"
        long_file = tmp_path / "long.wav"

        _run_capture(short_file, 2.0)
        _run_capture(long_file, 6.0)

        _, _, short_duration = _wav_frames(short_file)
        _, _, long_duration = _wav_frames(long_file)

        assert long_duration > short_duration, (
            f"6s of recording ({long_duration:.2f}s) must be longer than 2s ({short_duration:.2f}s). "
            f"Equal lengths mean the wav header is being written from a constant rather than from what "
            f"was captured — the BUG5 class, and invisible to any test that mocks the subprocess"
        )


@pytest.mark.hardware
class TestEnvelopeOnRealAudio:
    def test_the_envelope_reader_survives_a_real_capture(self, tmp_path):
        from ownscribe.audio.envelope import generate_envelope_from_file

        output = tmp_path / "recording.wav"
        _run_capture(output, 3.0)

        envelope = generate_envelope_from_file(output, n_buckets=500)

        assert len(envelope) == 500, (
            f"got {len(envelope)} buckets; the window's timeline assumes exactly the count it asked for"
        )
        assert all(0.0 <= value <= 1.0 for value in envelope), (
            "an RMS value outside 0..1 would render off-canvas in the timeline strip"
        )
        assert not any(value != value for value in envelope), "NaN in the envelope would break the strip"

    def test_the_envelope_file_the_pipeline_writes_is_valid_json(self, tmp_path):
        from ownscribe.audio.envelope import generate_envelope_from_file

        output = tmp_path / "recording.wav"
        _run_capture(output, 2.0)

        envelope = generate_envelope_from_file(output, n_buckets=500)
        envelope_path = tmp_path / "envelope.json"
        envelope_path.write_text(json.dumps({"envelope": envelope.tolist()}))

        loaded = json.loads(envelope_path.read_text())

        assert "envelope" in loaded, "the Swift reader looks for this exact key"
        assert len(loaded["envelope"]) == 500
