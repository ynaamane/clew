"""Tests for pilot/thermal_test.py."""

from __future__ import annotations

import math
import sys
import time
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent / "pilot"))

from thermal_test import run_thermal_test

_NO_WARNING = (
    "Note: No thermal warning level has been recorded\n"
    "Note: No performance warning level has been recorded\n"
    "Note: No CPU power status has been recorded"
)
_WARNING = "CPU_Speed_Limit\t=\t50\nCPU_Scheduler_Limit\t=\t50"


class TestRunThermalTest:
    def test_loops_until_target_duration_reached(self):
        call_count = 0

        def fast_transcribe(audio_path):
            nonlocal call_count
            call_count += 1
            time.sleep(0.05)

        with mock.patch("subprocess.run", return_value=mock.MagicMock(stdout=_NO_WARNING)):
            result = run_thermal_test(
                fast_transcribe, Path("fake.wav"), audio_duration_s=1.0, target_duration_s=0.3, poll_interval_s=0.1
            )

        assert call_count >= 1
        assert len(result.iterations) == call_count
        assert result.actual_wall_time_s >= 0.3

    def test_passes_when_no_throttle_and_rtf_under_one(self):
        def fast_transcribe(audio_path):
            time.sleep(0.05)

        with mock.patch("subprocess.run", return_value=mock.MagicMock(stdout=_NO_WARNING)):
            result = run_thermal_test(
                fast_transcribe, Path("fake.wav"), audio_duration_s=1.0, target_duration_s=0.2, poll_interval_s=0.1
            )

        assert result.passed is True
        assert result.failure_reason is None
        assert result.mean_rtf < 1.0

    def test_fails_when_a_thermal_warning_is_observed_mid_run(self):
        readings = [_NO_WARNING, _WARNING, _NO_WARNING]

        def fake_run(*args, **kwargs):
            reading = readings.pop(0) if readings else _NO_WARNING
            return mock.MagicMock(stdout=reading)

        def fast_transcribe(audio_path):
            time.sleep(0.05)

        with mock.patch("subprocess.run", side_effect=fake_run):
            result = run_thermal_test(
                fast_transcribe, Path("fake.wav"), audio_duration_s=1.0, target_duration_s=0.2, poll_interval_s=0.05
            )

        assert result.passed is False
        assert "thermal warning" in result.failure_reason

    def test_fails_when_mean_rtf_is_at_or_above_one(self):
        def slow_transcribe(audio_path):
            time.sleep(0.15)

        with mock.patch("subprocess.run", return_value=mock.MagicMock(stdout=_NO_WARNING)):
            result = run_thermal_test(
                slow_transcribe, Path("fake.wav"), audio_duration_s=0.1, target_duration_s=0.2, poll_interval_s=0.1
            )

        assert result.passed is False
        assert "RTF" in result.failure_reason

    def test_mean_and_max_rtf_computed_correctly(self):
        durations = iter([0.05, 0.15])

        def variable_transcribe(audio_path):
            time.sleep(next(durations, 0.05))

        with mock.patch("subprocess.run", return_value=mock.MagicMock(stdout=_NO_WARNING)):
            result = run_thermal_test(
                variable_transcribe, Path("fake.wav"), audio_duration_s=1.0, target_duration_s=0.15, poll_interval_s=0.5
            )

        assert result.max_rtf >= result.mean_rtf

    def test_empty_iterations_report_nan_not_crash(self):
        from thermal_test import ThermalRunResult

        empty = ThermalRunResult(target_duration_s=0.0, actual_wall_time_s=0.0, audio_duration_s=1.0)
        assert math.isnan(empty.mean_rtf)
        assert math.isnan(empty.max_rtf)
