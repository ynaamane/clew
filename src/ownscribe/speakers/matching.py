"""Cosine-similarity matching between diarized speaker clusters and enrolled voiceprints."""

from __future__ import annotations

import math

from ownscribe.speakers.base import DEFAULT_MATCH_THRESHOLD, VoiceprintDB


def cosine_similarity(a: list[float], b: list[float]) -> float:
    if len(a) != len(b) or not a:
        return 0.0
    dot = sum(x * y for x, y in zip(a, b, strict=True))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(y * y for y in b))
    if norm_a == 0.0 or norm_b == 0.0:
        return 0.0
    return dot / (norm_a * norm_b)


def match_speaker(
    embedding: list[float],
    db: VoiceprintDB,
    threshold: float = DEFAULT_MATCH_THRESHOLD,
) -> str | None:
    best_name: str | None = None
    best_score = threshold
    for vp in db.voiceprints:
        score = cosine_similarity(embedding, vp.embedding)
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
