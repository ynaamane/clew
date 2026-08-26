"""Cosine-similarity matching between diarized speaker clusters and enrolled voiceprints."""

from __future__ import annotations

import math

from clew.speakers.base import DEFAULT_MATCH_THRESHOLD, VoiceprintDB


def cosine_similarity(a: list[float], b: list[float]) -> float:
    if len(a) != len(b) or not a:
        return 0.0
    dot = sum(x * y for x, y in zip(a, b, strict=True))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(y * y for y in b))
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    return dot / (norm_a * norm_b)


def centroid_embedding(embeddings: list[list[float]]) -> list[float]:
    """Elementwise mean of N enrolled samples.

    Matched with CENTROID rather than MAX-per-sample (measured, not guessed):
    a synthetic simulation calibrated to the empirical Kamal-vs-Devon 0.637
    cosine gave MAX a 40.5% false-positive rate against a single contaminated
    sample, vs 0% for CENTROID at zero false-negative cost either way -- MAX
    only needs ONE bad sample to misfire; CENTROID dilutes it to 1/N weight.
    Simulation: not shipped in this repo; see the 2026-08-26 design proposal
    in the multi-sample VoiceprintDB task thread. Caveat: the calibration is
    synthetic (real enrolled voiceprints were purged before this landed) --
    re-checking against real re-enrolled samples is a follow-up, not done here.
    Cosine similarity is scale-invariant in both arguments, so this doesn't
    need to be re-normalized to unit length before comparison.
    """
    if not embeddings:
        return []
    dim = len(embeddings[0])
    return [sum(sample[i] for sample in embeddings) / len(embeddings) for i in range(dim)]


def match_speaker(
    embedding: list[float],
    db: VoiceprintDB,
    threshold: float = DEFAULT_MATCH_THRESHOLD,
) -> str | None:
    best_name: str | None = None
    best_score = threshold
    for vp in db.voiceprints:
        score = cosine_similarity(embedding, centroid_embedding(vp.embeddings))
        if score >= best_score:
            best_score = score
            best_name = vp.name
    return best_name


def assign_speaker_names(
    cluster_embeddings: dict[str, list[float]],
    db: VoiceprintDB,
    threshold: float = DEFAULT_MATCH_THRESHOLD,
) -> dict[str, str]:
    assignments: dict[str, str] = {}
    unknown_counter = 0
    for cluster_label, embedding in cluster_embeddings.items():
        matched_name = match_speaker(embedding, db, threshold=threshold)
        if matched_name is not None:
            assignments[cluster_label] = matched_name
        else:
            unknown_counter += 1
            assignments[cluster_label] = f"Unknown-{unknown_counter}"
    return assignments
