"""Tests for run_enroll_cluster (BUILD NEXT #1 tranche 2, block A3)."""

from __future__ import annotations

import json
from pathlib import Path
from unittest import mock

import numpy as np
import pytest
import soundfile as sf

from clew.config import Config
from clew.pipeline import SPEAKER_EMBEDDINGS_FILENAME, run_enroll_cluster
from clew.speakers.base import Voiceprint, VoiceprintDB
from clew.speakers.cluster_audio import select_cluster_spans
from clew.speakers.enrollment_suggest import load_transcript_result


def _write_transcript_json(meeting_dir: Path, segments: list[dict], duration: float) -> None:
    meeting_dir.mkdir(parents=True, exist_ok=True)
    (meeting_dir / "transcript.json").write_text(
        json.dumps({"segments": segments, "language": "en", "duration": duration})
    )


def _write_silence_wav(path: Path, seconds: float, sample_rate: int = 50) -> None:
    data = np.zeros(round(seconds * sample_rate), dtype="float32")
    sf.write(str(path), data, sample_rate, subtype="FLOAT")


class _ExplodingSpeakerEmbedder:
    def __init__(self, *args, **kwargs):
        raise AssertionError("SpeakerEmbedder must never be constructed on the persisted-embedding path")


class TestRunEnrollClusterPersistedPath:
    def test_uses_persisted_embedding_and_never_constructs_speaker_embedder(self, tmp_path):
        meeting_dir = tmp_path / "meeting"
        _write_transcript_json(
            meeting_dir,
            [{"text": "hi", "start": 0.0, "end": 1.0, "speaker": "SPEAKER_00", "words": []}],
            duration=10.0,
        )
        (meeting_dir / SPEAKER_EMBEDDINGS_FILENAME).write_text(
            json.dumps({"version": 1, "clusters": {"SPEAKER_00": [0.1, 0.2, 0.3]}, "assignments": {}})
        )

        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = ""  # deliberately empty: proves it's never needed on this path

        with (
            mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path),
            mock.patch("clew.speakers.embedding.SpeakerEmbedder", _ExplodingSpeakerEmbedder),
        ):
            run_enroll_cluster(config, str(meeting_dir), "SPEAKER_00", "Alice")

        db = VoiceprintDB.load(db_path)
        assert db.voiceprints == [Voiceprint(name="Alice", embeddings=[[0.1, 0.2, 0.3]])]

    def test_never_writes_anything_into_the_meeting_directory(self, tmp_path):
        meeting_dir = tmp_path / "meeting"
        _write_transcript_json(
            meeting_dir,
            [{"text": "hi", "start": 0.0, "end": 1.0, "speaker": "SPEAKER_00", "words": []}],
            duration=10.0,
        )
        (meeting_dir / SPEAKER_EMBEDDINGS_FILENAME).write_text(
            json.dumps({"version": 1, "clusters": {"SPEAKER_00": [0.1, 0.2, 0.3]}, "assignments": {}})
        )
        before = sorted(p.name for p in meeting_dir.iterdir())

        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = ""

        with mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path):
            run_enroll_cluster(config, str(meeting_dir), "SPEAKER_00", "Alice")

        after = sorted(p.name for p in meeting_dir.iterdir())
        assert after == before


class TestRunEnrollClusterFallbackPath:
    def test_embeds_a_cut_clip_whose_duration_matches_the_selected_spans(self, tmp_path):
        meeting_dir = tmp_path / "meeting"
        segments = [
            {"text": "filler", "start": 0.0, "end": 0.0, "speaker": "OTHER", "words": []},
            {"text": "monologue", "start": 30.0, "end": 30.0, "speaker": "SPEAKER_00", "words": []},
        ]
        _write_transcript_json(meeting_dir, segments, duration=100.0)
        _write_silence_wav(meeting_dir / "system.wav", seconds=100.0)

        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = "hf_test_token"

        captured = {}

        def fake_embed_file(path):
            info = sf.info(str(path))
            captured["duration"] = info.frames / info.samplerate
            return [0.5, 0.5, 0.5]

        mock_embedder = mock.MagicMock()
        mock_embedder.embed_file.side_effect = fake_embed_file

        with (
            mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path),
            mock.patch("clew.speakers.embedding.SpeakerEmbedder", return_value=mock_embedder),
        ):
            run_enroll_cluster(config, str(meeting_dir), "SPEAKER_00", "Bob")

        assert mock_embedder.embed_file.call_count == 1
        transcript = load_transcript_result(meeting_dir)
        expected_spans = select_cluster_spans(transcript, "SPEAKER_00")
        expected_total = sum(end - start for start, end in expected_spans)
        assert captured["duration"] == pytest.approx(expected_total, abs=0.1)

        db = VoiceprintDB.load(db_path)
        assert db.voiceprints == [Voiceprint(name="Bob", embeddings=[[0.5, 0.5, 0.5]])]

    def test_ignores_a_persisted_file_that_does_not_have_this_cluster(self, tmp_path):
        meeting_dir = tmp_path / "meeting"
        segments = [
            {"text": "filler", "start": 0.0, "end": 0.0, "speaker": "OTHER", "words": []},
            {"text": "monologue", "start": 30.0, "end": 30.0, "speaker": "SPEAKER_00", "words": []},
        ]
        _write_transcript_json(meeting_dir, segments, duration=100.0)
        _write_silence_wav(meeting_dir / "system.wav", seconds=100.0)
        (meeting_dir / SPEAKER_EMBEDDINGS_FILENAME).write_text(
            json.dumps({"version": 1, "clusters": {"SPEAKER_99": [9.9]}, "assignments": {}})
        )

        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = "hf_test_token"

        mock_embedder = mock.MagicMock()
        mock_embedder.embed_file.return_value = [0.7, 0.7, 0.7]

        with (
            mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path),
            mock.patch("clew.speakers.embedding.SpeakerEmbedder", return_value=mock_embedder),
        ):
            run_enroll_cluster(config, str(meeting_dir), "SPEAKER_00", "Carol")

        db = VoiceprintDB.load(db_path)
        assert db.voiceprints == [Voiceprint(name="Carol", embeddings=[[0.7, 0.7, 0.7]])]

    def test_missing_hf_token_exits_with_error(self, tmp_path):
        meeting_dir = tmp_path / "meeting"
        segments = [
            {"text": "filler", "start": 0.0, "end": 0.0, "speaker": "OTHER", "words": []},
            {"text": "monologue", "start": 30.0, "end": 30.0, "speaker": "SPEAKER_00", "words": []},
        ]
        _write_transcript_json(meeting_dir, segments, duration=100.0)
        _write_silence_wav(meeting_dir / "system.wav", seconds=100.0)

        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = ""

        with (
            mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path),
            pytest.raises(SystemExit),
        ):
            run_enroll_cluster(config, str(meeting_dir), "SPEAKER_00", "Dana")

        db = VoiceprintDB.load(db_path)
        assert db.voiceprints == []

    def test_missing_retained_audio_exits_with_retained_audio_message(self, tmp_path, capsys):
        meeting_dir = tmp_path / "meeting"
        segments = [
            {"text": "filler", "start": 0.0, "end": 0.0, "speaker": "OTHER", "words": []},
            {"text": "monologue", "start": 30.0, "end": 30.0, "speaker": "SPEAKER_00", "words": []},
        ]
        _write_transcript_json(meeting_dir, segments, duration=100.0)
        # No system.wav written: retained audio purged.

        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = "hf_test_token"

        with (
            mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path),
            pytest.raises(SystemExit),
        ):
            run_enroll_cluster(config, str(meeting_dir), "SPEAKER_00", "Erin")

        captured = capsys.readouterr()
        assert "retained audio" in captured.err.lower()
        db = VoiceprintDB.load(db_path)
        assert db.voiceprints == []

    def test_no_qualifying_turn_exits_with_error(self, tmp_path, capsys):
        meeting_dir = tmp_path / "meeting"
        # SPEAKER_00's only turn is far too short after trimming.
        segments = [
            {"text": "short", "start": 40.0, "end": 40.0, "speaker": "SPEAKER_00", "words": []},
            {"text": "filler", "start": 41.5, "end": 41.5, "speaker": "OTHER", "words": []},
        ]
        _write_transcript_json(meeting_dir, segments, duration=100.0)
        _write_silence_wav(meeting_dir / "system.wav", seconds=100.0)

        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = "hf_test_token"

        with (
            mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path),
            pytest.raises(SystemExit),
        ):
            run_enroll_cluster(config, str(meeting_dir), "SPEAKER_00", "Frank")

        captured = capsys.readouterr()
        assert "SPEAKER_00" in captured.err
        db = VoiceprintDB.load(db_path)
        assert db.voiceprints == []


class TestRunEnrollClusterValidation:
    def test_errors_when_directory_does_not_exist(self, tmp_path):
        config = Config()
        with pytest.raises(SystemExit):
            run_enroll_cluster(config, str(tmp_path / "does-not-exist"), "SPEAKER_00", "Alice")

    def test_empty_name_exits_with_error(self, tmp_path):
        # A persisted embedding is deliberately present so the run would otherwise
        # succeed with zero further checks -- isolates the empty-name guard itself
        # (without it, this test would still raise SystemExit for an unrelated
        # reason, missing hf_token, and would pass even if the guard were gone).
        meeting_dir = tmp_path / "meeting"
        _write_transcript_json(
            meeting_dir,
            [{"text": "hi", "start": 0.0, "end": 1.0, "speaker": "SPEAKER_00", "words": []}],
            duration=10.0,
        )
        (meeting_dir / SPEAKER_EMBEDDINGS_FILENAME).write_text(
            json.dumps({"version": 1, "clusters": {"SPEAKER_00": [0.1, 0.2, 0.3]}, "assignments": {}})
        )

        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = ""

        with (
            mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path),
            pytest.raises(SystemExit),
        ):
            run_enroll_cluster(config, str(meeting_dir), "SPEAKER_00", "   ")

        db = VoiceprintDB.load(db_path)
        assert db.voiceprints == []

    def test_unknown_cluster_exits_and_lists_speakers_present(self, tmp_path, capsys):
        meeting_dir = tmp_path / "meeting"
        _write_transcript_json(
            meeting_dir,
            [{"text": "hi", "start": 0.0, "end": 1.0, "speaker": "SPEAKER_00", "words": []}],
            duration=10.0,
        )
        db_path = tmp_path / "voiceprints.json"
        config = Config()

        with (
            mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path),
            pytest.raises(SystemExit),
        ):
            run_enroll_cluster(config, str(meeting_dir), "SPEAKER_99", "Alice")

        captured = capsys.readouterr()
        assert "SPEAKER_00" in captured.err
        db = VoiceprintDB.load(db_path)
        assert db.voiceprints == []

    def test_missing_transcript_exits_with_error(self, tmp_path):
        meeting_dir = tmp_path / "meeting"
        meeting_dir.mkdir()
        config = Config()
        with pytest.raises(SystemExit):
            run_enroll_cluster(config, str(meeting_dir), "SPEAKER_00", "Alice")


class TestRunEnrollClusterMultiSample:
    def test_two_enrollments_of_the_same_name_yield_two_samples(self, tmp_path):
        meeting_a = tmp_path / "meeting-a"
        _write_transcript_json(
            meeting_a,
            [{"text": "hi", "start": 0.0, "end": 1.0, "speaker": "SPEAKER_00", "words": []}],
            duration=10.0,
        )
        (meeting_a / SPEAKER_EMBEDDINGS_FILENAME).write_text(
            json.dumps({"version": 1, "clusters": {"SPEAKER_00": [0.1, 0.2, 0.3]}, "assignments": {}})
        )

        meeting_b = tmp_path / "meeting-b"
        _write_transcript_json(
            meeting_b,
            [{"text": "hi", "start": 0.0, "end": 1.0, "speaker": "SPEAKER_01", "words": []}],
            duration=10.0,
        )
        (meeting_b / SPEAKER_EMBEDDINGS_FILENAME).write_text(
            json.dumps({"version": 1, "clusters": {"SPEAKER_01": [0.4, 0.5, 0.6]}, "assignments": {}})
        )

        db_path = tmp_path / "voiceprints.json"
        config = Config()
        config.diarization.hf_token = ""

        with mock.patch("clew.speakers.base.VOICEPRINT_DB_PATH", db_path):
            run_enroll_cluster(config, str(meeting_a), "SPEAKER_00", "Grace")
            run_enroll_cluster(config, str(meeting_b), "SPEAKER_01", "Grace")

        db = VoiceprintDB.load(db_path)
        assert db.voiceprints == [Voiceprint(name="Grace", embeddings=[[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]])]
