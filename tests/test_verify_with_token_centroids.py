"""TDD tests for the per-centroid MPS-vs-CPU comparison cells in verify_with_token.py.

Covers only the GPU-free part: cell construction, zero-norm detection, aggregation,
and formatting -- all driven by synthetic vectors. The full check_mps_vs_cpu_diarization()
still needs a real HF token and real MPS hardware and is exercised directly via
`uv run python scripts/verify_with_token.py`, not by this suite.
"""

from __future__ import annotations

import importlib.util
import math
import sys
from pathlib import Path

import pytest

_MODULE_PATH = Path(__file__).resolve().parent.parent / "scripts" / "verify_with_token.py"


def _load_verify_module():
    spec = importlib.util.spec_from_file_location("verify_with_token", _MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def verify_module():
    return _load_verify_module()


class TestBuildCentroidCells:
    def test_identical_vectors_pass_with_cosine_one(self, verify_module):
        vec = [1.0, 2.0, 3.0]
        cells = verify_module.build_centroid_cells({"SPEAKER_00": vec}, {"SPEAKER_00": vec})
        assert len(cells) == 1
        cell = cells[0]
        assert cell.label == "SPEAKER_00"
        assert cell.zero_norm is False
        assert math.isclose(cell.cosine, 1.0, abs_tol=1e-9)
        assert cell.passed is True

    def test_orthogonal_vectors_fail_cosine_threshold(self, verify_module):
        cpu = {"SPEAKER_00": [1.0, 0.0]}
        mps = {"SPEAKER_00": [0.0, 1.0]}
        cells = verify_module.build_centroid_cells(cpu, mps)
        assert len(cells) == 1
        assert cells[0].zero_norm is False
        assert math.isclose(cells[0].cosine, 0.0, abs_tol=1e-9)
        assert cells[0].passed is False

    def test_zero_norm_on_cpu_side_is_explicit_fail_not_silent_zero_cosine(self, verify_module):
        cpu = {"SPEAKER_00": [0.0, 0.0, 0.0]}
        mps = {"SPEAKER_00": [1.0, 2.0, 3.0]}
        cells = verify_module.build_centroid_cells(cpu, mps)
        assert len(cells) == 1
        cell = cells[0]
        assert cell.zero_norm is True
        assert cell.passed is False
        assert math.isnan(cell.cosine)

    def test_zero_norm_on_mps_side_is_explicit_fail(self, verify_module):
        cpu = {"SPEAKER_00": [1.0, 2.0, 3.0]}
        mps = {"SPEAKER_00": [0.0, 0.0, 0.0]}
        cells = verify_module.build_centroid_cells(cpu, mps)
        assert cells[0].zero_norm is True
        assert cells[0].passed is False
        assert math.isnan(cells[0].cosine)

    def test_near_zero_norm_below_epsilon_is_flagged(self, verify_module):
        cpu = {"SPEAKER_00": [1e-10, 0.0, 0.0]}
        mps = {"SPEAKER_00": [1.0, 2.0, 3.0]}
        cells = verify_module.build_centroid_cells(cpu, mps)
        assert cells[0].zero_norm is True

    def test_only_shared_labels_are_compared(self, verify_module):
        cpu = {"SPEAKER_00": [1.0, 0.0], "SPEAKER_01": [0.0, 1.0]}
        mps = {"SPEAKER_00": [1.0, 0.0]}
        cells = verify_module.build_centroid_cells(cpu, mps)
        assert [c.label for c in cells] == ["SPEAKER_00"]

    def test_no_shared_labels_returns_empty(self, verify_module):
        cpu = {"SPEAKER_00": [1.0, 0.0]}
        mps = {"SPEAKER_01": [0.0, 1.0]}
        cells = verify_module.build_centroid_cells(cpu, mps)
        assert cells == []

    def test_cells_sorted_by_label(self, verify_module):
        cpu = {"SPEAKER_02": [1.0, 0.0], "SPEAKER_00": [1.0, 0.0], "SPEAKER_01": [1.0, 0.0]}
        mps = dict(cpu)
        cells = verify_module.build_centroid_cells(cpu, mps)
        assert [c.label for c in cells] == ["SPEAKER_00", "SPEAKER_01", "SPEAKER_02"]

    def test_just_above_cosine_threshold_passes(self, verify_module):
        # cos(theta) = 0.9995 for a small angle -- pin a case just above the 0.999 bar.
        theta = math.acos(0.9995)
        cpu = {"SPEAKER_00": [1.0, 0.0]}
        mps = {"SPEAKER_00": [math.cos(theta), math.sin(theta)]}
        cells = verify_module.build_centroid_cells(cpu, mps)
        assert cells[0].passed is True

    def test_just_below_cosine_threshold_fails(self, verify_module):
        # cos(theta) = 0.998 -- pin a case just below the 0.999 bar.
        theta = math.acos(0.998)
        cpu = {"SPEAKER_00": [1.0, 0.0]}
        mps = {"SPEAKER_00": [math.cos(theta), math.sin(theta)]}
        cells = verify_module.build_centroid_cells(cpu, mps)
        assert cells[0].passed is False


class TestAllCentroidCellsPass:
    def test_empty_cells_fail_closed(self, verify_module):
        # No shared centroids to compare is NOT a pass: it means extraction produced
        # nothing to verify, which must never read as a silent green.
        assert verify_module.all_centroid_cells_pass([]) is False

    def test_all_passed_cells_is_true(self, verify_module):
        cell = verify_module.CentroidCell(
            label="SPEAKER_00", cpu_norm=1.0, mps_norm=1.0, cosine=1.0, zero_norm=False, passed=True
        )
        assert verify_module.all_centroid_cells_pass([cell]) is True

    def test_one_failed_cell_fails_the_whole_batch(self, verify_module):
        good = verify_module.CentroidCell(
            label="SPEAKER_00", cpu_norm=1.0, mps_norm=1.0, cosine=1.0, zero_norm=False, passed=True
        )
        bad = verify_module.CentroidCell(
            label="SPEAKER_01", cpu_norm=0.0, mps_norm=1.0, cosine=float("nan"), zero_norm=True, passed=False
        )
        assert verify_module.all_centroid_cells_pass([good, bad]) is False


class TestFormatCentroidCells:
    def test_zero_norm_cell_is_labeled_explicitly_in_the_report(self, verify_module):
        cell = verify_module.CentroidCell(
            label="SPEAKER_00", cpu_norm=0.0, mps_norm=1.234, cosine=float("nan"), zero_norm=True, passed=False
        )
        text = verify_module.format_centroid_cells([cell])
        assert "ZERO-NORM" in text
        assert "SPEAKER_00" in text

    def test_passing_cell_reports_its_cosine(self, verify_module):
        cell = verify_module.CentroidCell(
            label="SPEAKER_00", cpu_norm=1.0, mps_norm=1.0, cosine=0.987654321, zero_norm=False, passed=True
        )
        text = verify_module.format_centroid_cells([cell])
        assert "0.987654" in text

    def test_empty_cells_says_so(self, verify_module):
        text = verify_module.format_centroid_cells([])
        assert text != ""
