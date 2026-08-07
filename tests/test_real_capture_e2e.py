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


def _production_binary() -> Path:
    """Resolve the binary the PIPELINE runs, not the one a dev just built.

    coreaudio.py:_find_binary() prefers `bin/ownscribe-audio` over anything in
    .build, and `bin/` is gitignored — so a fix can land in Swift, pass every
    test against .build, and never reach production. That is exactly what
    happened with BUG5: bin/ held a binary three days older than the fix and
    still halved playback speed.
    """
    from clew.audio.coreaudio import _BINARY_CANDIDATES

    for candidate in _BINARY_CANDIDATES:
        if candidate.is_file():
            return candidate
    return REPO_ROOT / "swift" / ".build" / "debug" / "ownscribe-audio"


CAPTURE_BINARY = _production_binary()


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
        result = subprocess.run([str(CAPTURE_BINARY), "--help"], capture_output=True, text=True, timeout=60)

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
class TestDualTrackMergeOnRealAudio:
    """--mic reaches mergeAudioFiles, the highest-risk path and the BUG5 code.

    Without --mic the capture writes one track and never merges, so the merge is
    the one thing the rest of this file cannot see.
    """

    def test_the_merged_file_keeps_the_sample_rate_of_its_sources(self, tmp_path):
        output = tmp_path / "recording.wav"

        stderr = _run_capture(output, 4.0, extra=["--mic"])

        assert output.exists(), f"no merged file; stderr: {stderr}"
        mic_track = tmp_path / "mic.wav"
        system_track = tmp_path / "system.wav"
        assert mic_track.exists() and system_track.exists(), (
            f"--mic must retain both source tracks, since redo replays from them. stderr: {stderr}"
        )

        _, merged_rate, merged_duration = _wav_frames(output)
        _, mic_rate, mic_duration = _wav_frames(mic_track)
        _, system_rate, _ = _wav_frames(system_track)

        assert merged_rate == mic_rate == system_rate, (
            f"merged at {merged_rate}Hz from sources at {mic_rate}/{system_rate}Hz. THIS IS BUG5: the "
            f"merge used a hardcoded 24000 while capture writes the hardware rate, so every recording "
            f"played back at half speed with voices deep and slowed, and every logged duration was "
            f"wrong by 2x. A duration bound cannot catch it — 2x of a short capture still looks "
            f"plausible — so the rates must be compared directly"
        )
        assert merged_duration < mic_duration * 1.5, (
            f"merged {merged_duration:.2f}s from a {mic_duration:.2f}s mic track. A merged file much "
            f"longer than its own sources means the frame count was scaled by a rate mismatch"
        )


@pytest.mark.hardware
class TestEnvelopeOnRealAudio:
    def test_the_envelope_reader_survives_a_real_capture(self, tmp_path):
        from clew.audio.envelope import generate_envelope_from_file

        output = tmp_path / "recording.wav"
        _run_capture(output, 3.0)

        envelope = generate_envelope_from_file(output, n_buckets=500)

        assert envelope is not None, "successful capture must produce an envelope, not None"
        assert len(envelope) == 500, (
            f"got {len(envelope)} buckets; the window's timeline assumes exactly the count it asked for"
        )
        assert all(0.0 <= value <= 1.0 for value in envelope), (
            "an RMS value outside 0..1 would render off-canvas in the timeline strip"
        )
        assert not any(value != value for value in envelope), "NaN in the envelope would break the strip"

    def test_the_envelope_file_the_pipeline_writes_is_valid_json(self, tmp_path):
        from clew.audio.envelope import generate_envelope_from_file

        output = tmp_path / "recording.wav"
        _run_capture(output, 2.0)

        envelope = generate_envelope_from_file(output, n_buckets=500)
        assert envelope is not None, "successful capture must produce an envelope, not None"
        envelope_path = tmp_path / "envelope.json"
        envelope_path.write_text(json.dumps({"envelope": envelope.tolist()}))

        loaded = json.loads(envelope_path.read_text())

        assert "envelope" in loaded, "the Swift reader looks for this exact key"
        assert len(loaded["envelope"]) == 500
