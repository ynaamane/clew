"""Tests for speaker enrollment storage and matching."""

from __future__ import annotations

from unittest import mock

from clew.speakers.base import DEFAULT_MATCH_THRESHOLD, Voiceprint, VoiceprintDB
from clew.speakers.matching import assign_speaker_names, centroid_embedding, cosine_similarity, match_speaker


class TestVoiceprintDB:
    def test_empty_db_has_no_voiceprints(self):
        db = VoiceprintDB()
        assert db.voiceprints == []

    def test_upsert_adds_new_voiceprint_as_its_first_sample(self):
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0])
        assert db.voiceprints == [Voiceprint(name="Alice", embeddings=[[1.0, 0.0]])]

    def test_upsert_appends_a_new_sample_to_an_existing_name(self):
        # Multi-sample VoiceprintDB: re-enrolling must ADD a sample, never replace
        # the existing one(s) -- a single bad clip can no longer wipe out good data.
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0])
        db.upsert("Alice", [0.0, 1.0])
        assert len(db.voiceprints) == 1
        assert db.voiceprints[0].embeddings == [[1.0, 0.0], [0.0, 1.0]]

    def test_upsert_can_add_a_third_sample(self):
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0])
        db.upsert("Alice", [0.0, 1.0])
        db.upsert("Alice", [0.5, 0.5])
        assert db.voiceprints[0].embeddings == [[1.0, 0.0], [0.0, 1.0], [0.5, 0.5]]

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
        db.upsert("Alice", [0.15, 0.25, 0.35])
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
        import clew.speakers.base as base_module

        fake_path = tmp_path / "voiceprints.json"
        fake_path.write_text('{"voiceprints": [{"name": "Patched", "embeddings": [[1.0]]}]}')

        with mock.patch.object(base_module, "VOICEPRINT_DB_PATH", fake_path):
            loaded = VoiceprintDB.load()

        assert loaded.voiceprints == [Voiceprint(name="Patched", embeddings=[[1.0]])]

    def test_save_writes_the_new_multi_sample_format(self, tmp_path):
        path = tmp_path / "voiceprints.json"
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0])
        db.save(path)

        import json

        raw = json.loads(path.read_text())
        assert raw["voiceprints"][0]["embeddings"] == [[1.0, 0.0]]
        assert "embedding" not in raw["voiceprints"][0]


class TestVoiceprintDBBackwardCompat:
    """A pre-multi-sample voiceprints.json (single flat 'embedding' vector per
    name) must keep loading without crashing -- Yanis has to re-enroll his 3
    purged voices into whichever store lands first."""

    def test_load_migrates_old_single_embedding_format(self, tmp_path):
        path = tmp_path / "voiceprints.json"
        path.write_text('{"voiceprints": [{"name": "Kamal", "embedding": [0.1, 0.2, 0.3]}]}')

        loaded = VoiceprintDB.load(path)

        assert loaded.voiceprints == [Voiceprint(name="Kamal", embeddings=[[0.1, 0.2, 0.3]])]

    def test_load_reads_new_multi_embeddings_format_directly(self, tmp_path):
        path = tmp_path / "voiceprints.json"
        path.write_text('{"voiceprints": [{"name": "Kamal", "embeddings": [[0.1, 0.2], [0.15, 0.25]]}]}')

        loaded = VoiceprintDB.load(path)

        assert loaded.voiceprints == [Voiceprint(name="Kamal", embeddings=[[0.1, 0.2], [0.15, 0.25]])]

    def test_load_handles_a_mix_of_old_and_new_format_entries(self, tmp_path):
        # A real migration scenario: some names re-enrolled under the new store
        # (appending), others never touched since the old format.
        path = tmp_path / "voiceprints.json"
        path.write_text(
            '{"voiceprints": ['
            '{"name": "Kamal", "embedding": [0.1, 0.2]}, '
            '{"name": "Devon", "embeddings": [[0.3, 0.4], [0.35, 0.45]]}'
            "]}"
        )

        loaded = VoiceprintDB.load(path)

        assert loaded.voiceprints == [
            Voiceprint(name="Kamal", embeddings=[[0.1, 0.2]]),
            Voiceprint(name="Devon", embeddings=[[0.3, 0.4], [0.35, 0.45]]),
        ]

    def test_load_entry_missing_all_embedding_data_defaults_to_empty(self, tmp_path):
        path = tmp_path / "voiceprints.json"
        path.write_text('{"voiceprints": [{"name": "NoData"}]}')

        loaded = VoiceprintDB.load(path)

        assert loaded.voiceprints == [Voiceprint(name="NoData", embeddings=[])]

    def test_load_old_format_with_empty_embedding_yields_zero_samples(self, tmp_path):
        path = tmp_path / "voiceprints.json"
        path.write_text('{"voiceprints": [{"name": "Empty", "embedding": []}]}')

        loaded = VoiceprintDB.load(path)

        assert loaded.voiceprints == [Voiceprint(name="Empty", embeddings=[])]


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


class TestCentroidEmbedding:
    def test_single_sample_centroid_equals_that_sample(self):
        assert centroid_embedding([[1.0, 2.0, 3.0]]) == [1.0, 2.0, 3.0]

    def test_multiple_samples_centroid_is_the_elementwise_mean(self):
        assert centroid_embedding([[1.0, 0.0], [0.0, 1.0], [2.0, 2.0]]) == [1.0, 1.0]

    def test_empty_samples_returns_empty(self):
        assert centroid_embedding([]) == []


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

    def test_matches_against_the_centroid_of_multiple_samples(self):
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0, 0.0])
        db.upsert("Alice", [0.8, 0.6, 0.0])  # still close to [1,0,0], centroid stays near it

        assert match_speaker([0.99, 0.01, 0.0], db) == "Alice"

    def test_robust_to_one_contaminated_sample_among_clean_ones(self):
        # This is the whole point of multi-sample + CENTROID matching (measured,
        # not guessed -- see the design proposal message): a single sample that
        # leans toward a DIFFERENT person must not be enough, by itself, to make
        # that other person's genuine voice match this name. Under a MAX-only
        # strategy this contaminated sample alone would win the match; centroid
        # dilutes its weight to 1/3 and keeps the score below threshold.
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0, 0.0])
        db.upsert("Alice", [0.95, 0.05, 0.0])
        db.upsert("Alice", [0.0, 1.0, 0.0])  # contaminated: leans toward "Bob"'s direction

        # A genuine Bob utterance: MAX-per-sample would score ~1.0 against the
        # contaminated sample alone and wrongly match "Alice"; centroid must not.
        bob_utterance = [0.02, 0.98, 0.0]
        assert match_speaker(bob_utterance, db) is None

    def test_own_noisy_sample_does_not_break_future_recognition(self):
        # Flip side of the contamination test: one noisy (not adversarial) own
        # sample must not sink recognition of a genuine future utterance -- this
        # is the actual reason multi-sample enrollment exists.
        db = VoiceprintDB()
        db.upsert("Alice", [1.0, 0.0, 0.0])
        db.upsert("Alice", [0.9, 0.1, 0.0])
        db.upsert("Alice", [0.6, -0.3, 0.7])  # noisy own clip, no clean direction

        assert match_speaker([0.98, 0.02, 0.0], db) == "Alice"


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
