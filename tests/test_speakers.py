"""Tests for speaker enrollment storage and matching."""

from __future__ import annotations

from unittest import mock

from ownscribe.speakers.base import DEFAULT_MATCH_THRESHOLD, Voiceprint, VoiceprintDB
from ownscribe.speakers.matching import assign_speaker_names, cosine_similarity, match_speaker


class TestVoiceprintDB:
    def test_empty_db_has_no_voiceprints(self):
        db = VoiceprintDB()
        assert db.voiceprints == []

    def test_upsert_adds_new_voiceprint(self):
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0])
        assert db.voiceprints == [Voiceprint(name="Alice", embedding=[1.0, 0.0])]

    def test_upsert_overwrites_existing_by_name(self):
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0])
        db.upsert("Alice", [0.0, 1.0])
        assert len(db.voiceprints) == 1
        assert db.voiceprints[0].embedding == [0.0, 1.0]

    def test_remove_existing_returns_true(self):
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0])
        assert db.remove("Alice") is True
        assert db.voiceprints == []

    def test_remove_missing_returns_false(self):
        db = VoiceprintDB()
        assert db.remove("Nobody") is False

    def test_save_and_load_round_trip(self, tmp_path):
        path = tmp_path / "voiceprints.json"
        db = VoiceprintDB()
        db.upsert("Alice", [0.1, 0.2, 0.3])
        db.upsert("Bob", [0.4, 0.5, 0.6])
        db.save(path)

        loaded = VoiceprintDB.load(path)

        assert loaded.voiceprints == db.voiceprints

    def test_load_missing_file_returns_empty_db(self, tmp_path):
        path = tmp_path / "does-not-exist.json"
        loaded = VoiceprintDB.load(path)
        assert loaded.voiceprints == []

    def test_save_creates_parent_directory(self, tmp_path):
        path = tmp_path / "nested" / "dir" / "voiceprints.json"
        db = VoiceprintDB()
        db.upsert("Alice", [1.0])
        db.save(path)
        assert path.exists()

    def test_default_path_is_patchable_at_call_time(self, tmp_path):
        import ownscribe.speakers.base as base_module

        fake_path = tmp_path / "voiceprints.json"
        fake_path.write_text('{"voiceprints": [{"name": "Patched", "embedding": [1.0]}]}')

        with mock.patch.object(base_module, "VOICEPRINT_DB_PATH", fake_path):
            loaded = VoiceprintDB.load()

        assert loaded.voiceprints == [Voiceprint(name="Patched", embedding=[1.0])]


class TestCosineSimilarity:
    def test_identical_vectors(self):
        assert cosine_similarity([1.0, 0.0, 0.0], [1.0, 0.0, 0.0]) == 1.0

    def test_orthogonal_vectors(self):
        assert cosine_similarity([1.0, 0.0], [0.0, 1.0]) == 0.0

    def test_opposite_vectors(self):
        assert cosine_similarity([1.0, 0.0], [-1.0, 0.0]) == -1.0

    def test_mismatched_length_returns_zero(self):
        assert cosine_similarity([1.0, 0.0], [1.0, 0.0, 0.0]) == 0.0

    def test_empty_vectors_return_zero(self):
        assert cosine_similarity([], []) == 0.0

    def test_zero_vector_returns_zero(self):
        assert cosine_similarity([0.0, 0.0], [1.0, 0.0]) == 0.0


class TestMatchSpeaker:
    def _make_db(self) -> VoiceprintDB:
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0, 0.0])
        db.upsert("Bob", [0.0, 1.0, 0.0])
        return db

    def test_matches_above_threshold(self):
        db = self._make_db()
        assert match_speaker([0.99, 0.01, 0.0], db) == "Alice"

    def test_no_match_below_threshold(self):
        db = self._make_db()
        assert match_speaker([0.0, 0.0, 1.0], db) is None

    def test_never_matches_below_threshold_even_with_lowest_score_present(self):
        db = self._make_db()
        result = match_speaker([-1.0, -1.0, -1.0], db)
        assert result is None

    def test_empty_db_never_matches(self):
        db = VoiceprintDB()
        assert match_speaker([1.0, 0.0, 0.0], db) is None

    def test_custom_threshold_can_reject_a_previously_matching_score(self):
        db = self._make_db()
        moderate_score_embedding = [0.7, 0.3, 0.0]
        assert match_speaker(moderate_score_embedding, db, threshold=0.5) == "Alice"
        assert match_speaker(moderate_score_embedding, db, threshold=0.99) is None

    def test_default_threshold_is_065(self):
        assert DEFAULT_MATCH_THRESHOLD == 0.65


class TestAssignSpeakerNames:
    def test_assigns_known_names_to_matching_clusters(self):
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0, 0.0])
        db.upsert("Bob", [0.0, 1.0, 0.0])

        assignments = assign_speaker_names(
            {
                "SPEAKER_00": [0.99, 0.01, 0.0],
                "SPEAKER_01": [0.0, 0.99, 0.01],
            },
            db,
        )

        assert assignments == {"SPEAKER_00": "Alice", "SPEAKER_01": "Bob"}

    def test_unmatched_clusters_get_sequential_unknown_labels(self):
        db = VoiceprintDB()

        assignments = assign_speaker_names(
            {
                "SPEAKER_00": [1.0, 0.0, 0.0],
                "SPEAKER_01": [0.0, 1.0, 0.0],
            },
            db,
        )

        assert set(assignments.values()) == {"Unknown-1", "Unknown-2"}

    def test_unknown_numbering_does_not_skip_matched_clusters(self):
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0, 0.0])

        assignments = assign_speaker_names(
            {
                "SPEAKER_00": [0.99, 0.01, 0.0],
                "SPEAKER_01": [0.0, 1.0, 0.0],
                "SPEAKER_02": [0.0, 0.0, 1.0],
            },
            db,
        )

        assert assignments["SPEAKER_00"] == "Alice"
        assert assignments["SPEAKER_01"] == "Unknown-1"
        assert assignments["SPEAKER_02"] == "Unknown-2"

    def test_empty_clusters_returns_empty_assignments(self):
        db = VoiceprintDB()
        assert assign_speaker_names({}, db) == {}
