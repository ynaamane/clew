"""Tests for pilot/run_pilot.py -- decide_verdict() (the actual pre-committed
pass/fail rule from the ticket) and the results/verdict rendering, plus an
end-to-end run() with both engines' transcription mocked."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).parent.parent / "pilot"))

from cha_parser import Utterance
from run_pilot import _load_reference, _render_verdict_md, decide_verdict, run
from wer_measurement import HypothesisSegment


class TestDecideVerdict:
    def test_canary_wins_when_switch_wer_beats_threshold_and_thermal_passes(self):
        wer_results = {
            "whisperx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.5},
            "canary_mlx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.1},
        }
        thermal_results = {"canary_mlx": {"passed": True}}

        verdict = decide_verdict(wer_results, thermal_results)

        assert verdict["default_engine"] == "canary_mlx"
        assert verdict["switch_wer_delta_points"] == 40.0

    def test_whisper_stays_default_when_delta_below_threshold(self):
        wer_results = {
            "whisperx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.20},
            "canary_mlx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.19},
        }
        thermal_results = {"canary_mlx": {"passed": True}}

        verdict = decide_verdict(wer_results, thermal_results)

        assert verdict["default_engine"] == "whisperx"
        assert "< required" in verdict["reason"]

    def test_whisper_stays_default_when_canary_regresses_switch_wer(self):
        wer_results = {
            "whisperx": {"overall": 0.39, "fra": 0.39, "eng": 3.5, "switch": 0.667},
            "canary_mlx": {"overall": 0.39, "fra": 0.49, "eng": 9.25, "switch": 1.333},
        }
        thermal_results = {}

        verdict = decide_verdict(wer_results, thermal_results)

        assert verdict["default_engine"] == "whisperx"
        assert verdict["switch_wer_delta_points"] < 0

    def test_canary_loses_default_even_with_wer_win_if_thermal_fails(self):
        wer_results = {
            "whisperx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.5},
            "canary_mlx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.1},
        }
        thermal_results = {"canary_mlx": {"passed": False, "failure_reason": "thermal warning observed"}}

        verdict = decide_verdict(wer_results, thermal_results)

        assert verdict["default_engine"] == "whisperx"
        assert "thermal" in verdict["reason"].lower()

    def test_canary_missing_from_wer_results_treated_as_nan_fallback(self):
        wer_results = {"whisperx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.5}}
        thermal_results = {}

        verdict = decide_verdict(wer_results, thermal_results)

        assert verdict["default_engine"] == "whisperx"
        assert verdict["switch_wer_delta_points"] is None

    def test_delta_exactly_at_threshold_wins_since_comparison_is_inclusive(self):
        wer_results = {
            "whisperx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.53},
            "canary_mlx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.50},
        }
        thermal_results = {"canary_mlx": {"passed": True}}

        verdict = decide_verdict(wer_results, thermal_results, switch_win_threshold=3.0)

        assert verdict["default_engine"] == "canary_mlx"

    def test_missing_thermal_results_treated_as_not_passed_when_canary_would_otherwise_win(self):
        wer_results = {
            "whisperx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.5},
            "canary_mlx": {"overall": 0.4, "fra": 0.4, "eng": 0.4, "switch": 0.1},
        }
        thermal_results = {}

        verdict = decide_verdict(wer_results, thermal_results)

        assert verdict["default_engine"] == "whisperx"


class TestLoadReference:
    def test_loads_utterances_and_window_start(self, tmp_path):
        reference_data = {
            "window_start_s": 100.5,
            "utterances": [
                {"speaker": "A", "start_ms": 100500, "end_ms": 101000, "words": ["bonjour"], "word_languages": ["fra"]}
            ],
        }
        reference_path = tmp_path / "ref.json"
        reference_path.write_text(json.dumps(reference_data))

        utterances, window_start_s = _load_reference(reference_path)

        assert window_start_s == 100.5
        assert len(utterances) == 1
        assert isinstance(utterances[0], Utterance)
        assert utterances[0].words == ["bonjour"]


class TestRenderVerdictMd:
    def test_includes_default_engine_and_wer_table(self):
        results = {
            "clip_source": "FEBLOC public fallback",
            "audio_duration_s": 30.5,
            "reference_utterance_count": 23,
            "language": "fr",
            "wer_by_engine": {
                "whisperx": {"overall": 0.39, "fra": 0.39, "eng": 3.5, "switch": 0.67},
                "canary_mlx": {"overall": 0.39, "fra": 0.49, "eng": 9.25, "switch": 1.33},
            },
            "thermal_by_engine": {},
            "verdict": {"default_engine": "whisperx", "reason": "switch-span WER delta -66.7 points < required 3.0"},
        }

        markdown = _render_verdict_md(results)

        assert "`whisperx`" in markdown
        assert "canary_mlx" in markdown
        assert "Attribution" in markdown
        assert "diarization-capable" in markdown

    def test_thermal_section_reports_not_run_when_empty(self):
        results = {
            "clip_source": "x",
            "audio_duration_s": 1.0,
            "reference_utterance_count": 1,
            "language": "fr",
            "wer_by_engine": {"whisperx": {"overall": 0.0, "fra": 0.0, "eng": 0.0, "switch": 0.0}},
            "thermal_by_engine": {},
            "verdict": {"default_engine": "whisperx", "reason": "x"},
        }

        markdown = _render_verdict_md(results)

        assert "Not run this invocation" in markdown

    def test_thermal_section_reports_metrics_when_present(self):
        results = {
            "clip_source": "x",
            "audio_duration_s": 1.0,
            "reference_utterance_count": 1,
            "language": "fr",
            "wer_by_engine": {"whisperx": {"overall": 0.0, "fra": 0.0, "eng": 0.0, "switch": 0.0}},
            "thermal_by_engine": {
                "whisperx": {"passed": True, "mean_rtf": 0.5, "peak_rss_mb": 1234.0, "failure_reason": None}
            },
            "verdict": {"default_engine": "whisperx", "reason": "x"},
        }

        markdown = _render_verdict_md(results)

        assert "passed=True" in markdown
        assert "1234" in markdown


class TestRunEndToEnd:
    """Full run() with a real reference + real clip metadata, but both engines'
    transcription mocked -- proves the WER/verdict/output-file wiring without
    needing real models loaded."""

    def _fake_reference(self, out_dir: Path) -> tuple[Path, Path]:
        fallback_dir = out_dir / "fallback_data"
        fallback_dir.mkdir(parents=True)
        unread_clip_path = fallback_dir / "clip.wav"
        unread_clip_path.write_bytes(b"RIFF....WAVEfmt ")
        reference_path = fallback_dir / "reference.json"
        reference_path.write_text(
            json.dumps(
                {
                    "window_start_s": 0.0,
                    "utterances": [
                        {
                            "speaker": "A",
                            "start_ms": 0,
                            "end_ms": 1000,
                            "words": ["bonjour"],
                            "word_languages": ["fra"],
                        },
                        {
                            "speaker": "B",
                            "start_ms": 1000,
                            "end_ms": 2000,
                            "words": ["hello"],
                            "word_languages": ["eng"],
                        },
                    ],
                }
            )
        )
        return unread_clip_path, reference_path

    def test_run_writes_results_json_and_verdict_md(self, tmp_path):
        clip_path, reference_path = self._fake_reference(tmp_path)

        args = mock.MagicMock(
            clip=str(clip_path),
            reference=str(reference_path),
            language="fr",
            thermal_engine="none",
            thermal_duration_s=3600.0,
            out_dir=str(tmp_path / "out"),
        )

        whisperx_segments = [HypothesisSegment(text="bonjour", start_s=0.0, end_s=1.0)]
        canary_segments = [HypothesisSegment(text="hello", start_s=1.0, end_s=2.0)]

        with (
            mock.patch("run_pilot._audio_duration_s", return_value=2.0),
            mock.patch("run_pilot._transcribe_whisperx", return_value=(whisperx_segments, 0.5)),
            mock.patch("run_pilot._transcribe_canary", return_value=(canary_segments, 0.3)),
        ):
            results = run(args)

        out_dir = Path(args.out_dir)
        assert (out_dir / "results.json").exists()
        assert (out_dir / "verdict.md").exists()
        assert results["clip_source"] == "user-provided"
        assert results["wer_by_engine"]["whisperx"]["fra"] == 0.0
        assert results["wer_by_engine"]["canary_mlx"]["eng"] == 0.0

    def test_run_uses_fallback_when_no_clip_and_reference_given(self, tmp_path):
        args = mock.MagicMock(
            clip=None,
            reference=None,
            language="fr",
            thermal_engine="none",
            thermal_duration_s=3600.0,
            out_dir=str(tmp_path / "out"),
        )

        fake_fetch_result = {
            "clip_path": str(tmp_path / "fallback.wav"),
            "reference_path": str(tmp_path / "fallback_ref.json"),
        }
        (tmp_path / "fallback_ref.json").write_text(json.dumps({"window_start_s": 0.0, "utterances": []}))

        with (
            mock.patch("run_pilot.fetch_and_prepare", return_value=fake_fetch_result) as mock_fetch,
            mock.patch("run_pilot._audio_duration_s", return_value=5.0),
            mock.patch("run_pilot._transcribe_whisperx", return_value=([], 0.1)),
            mock.patch("run_pilot._transcribe_canary", return_value=([], 0.1)),
        ):
            results = run(args)

        mock_fetch.assert_called_once()
        assert results["clip_source"] == "FEBLOC public fallback"
