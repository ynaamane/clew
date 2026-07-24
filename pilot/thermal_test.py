"""Continuous-run thermal/RTF test for the Canary-vs-WhisperX A/B pilot.

The ticket asks for a 60-min continuous run; the only available audio is a
30.5s clip (the FEBLOC fallback, or a real Yanis-provided clip -- either
way, a single clip is never going to be an hour long). Loops transcription
of the same clip back-to-back until the target duration is reached -- the
standard technique for a sustained-load thermal test, since the point is
sustained CPU/GPU utilization, not semantic novelty of the audio.

`sudo powermetrics` needs an interactive password this session has no way
to supply (checked: `sudo -n powermetrics ...` fails immediately with
"a password is required", confirmed non-hanging so it's safe to probe
without risking a hang). Falls back to `pmset -g therm`, sampled every
poll_interval_s DURING the run (not just before/after, since a transient
throttle event could recover before a post-run-only check would see it),
plus Python's own `resource.getrusage` for peak RSS -- both genuinely
measure real system state, neither is a stand-in metric. If `sudo` access
is later supplied, `powermetrics` sampling can be added alongside these
without changing the PASS/FAIL contract below.

PASS bar (from the ticket): completes the full target duration without a
thermal warning at any sample point, AND mean RTF stays < 1.0 (faster than
real-time) across all loop iterations.
"""

from __future__ import annotations

import resource
import subprocess
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class LoopIteration:
    wall_time_s: float
    rtf: float


@dataclass
class ThermalRunResult:
    target_duration_s: float
    actual_wall_time_s: float
    audio_duration_s: float
    iterations: list[LoopIteration] = field(default_factory=list)
    thermal_samples: list[str] = field(default_factory=list)
    peak_rss_mb: float = 0.0
    passed: bool = False
    failure_reason: str | None = None

    @property
    def mean_rtf(self) -> float:
        if not self.iterations:
            return float("nan")
        return sum(it.rtf for it in self.iterations) / len(self.iterations)

    @property
    def max_rtf(self) -> float:
        if not self.iterations:
            return float("nan")
        return max(it.rtf for it in self.iterations)


def _read_thermal_warning() -> str:
    result = subprocess.run(["pmset", "-g", "therm"], capture_output=True, text=True)
    return result.stdout.strip()


def _is_throttled(thermal_reading: str) -> bool:
    return "No thermal warning level" not in thermal_reading


def _peak_rss_mb() -> float:
    return resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / (1024 * 1024)


def run_thermal_test(
    transcribe_once: Callable[[Path], None],
    audio_path: Path,
    audio_duration_s: float,
    target_duration_s: float = 3600.0,
    poll_interval_s: float = 30.0,
) -> ThermalRunResult:
    """Loop `transcribe_once(audio_path)` until target_duration_s of wall time
    has elapsed, sampling thermal state on a background thread every
    poll_interval_s throughout (not just before/after)."""
    result = ThermalRunResult(
        target_duration_s=target_duration_s, actual_wall_time_s=0.0, audio_duration_s=audio_duration_s
    )

    stop_event = threading.Event()

    def _poll_thermal() -> None:
        while not stop_event.is_set():
            result.thermal_samples.append(_read_thermal_warning())
            stop_event.wait(poll_interval_s)

    poller = threading.Thread(target=_poll_thermal, daemon=True)
    poller.start()

    run_start = time.time()
    try:
        while (time.time() - run_start) < target_duration_s:
            iter_start = time.time()
            transcribe_once(audio_path)
            iter_wall = time.time() - iter_start
            result.iterations.append(LoopIteration(wall_time_s=iter_wall, rtf=iter_wall / audio_duration_s))
    finally:
        stop_event.set()
        poller.join(timeout=poll_interval_s + 5.0)
        result.actual_wall_time_s = time.time() - run_start
        result.thermal_samples.append(_read_thermal_warning())
        result.peak_rss_mb = _peak_rss_mb()

    throttled_samples = [s for s in result.thermal_samples if _is_throttled(s)]
    if throttled_samples:
        result.passed = False
        result.failure_reason = f"thermal warning observed during run: {throttled_samples[0]!r}"
    elif result.mean_rtf >= 1.0:
        result.passed = False
        result.failure_reason = f"mean RTF {result.mean_rtf:.2f} >= 1.0 (slower than real-time)"
    else:
        result.passed = True
        result.failure_reason = None

    return result
