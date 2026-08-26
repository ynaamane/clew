#!/usr/bin/env -S uv run python3
"""Measures MAX-per-sample vs CENTROID matching for multi-sample VoiceprintDB
(2026-08-26, `1c6244c` -- speakers/matching.py's CENTROID choice).

The real Kamal/Devon voiceprints that motivated this (TODO.md: "Kamal-print vs
a Devon segment = 0.637, only 0.013 under the 0.65 threshold") were purged from
disk before this landed, so this is a synthetic 256-dim (pyannote community-1's
embedding dimensionality) simulation calibrated to reproduce that same number:
same-person sample-vs-sample cosine tuned to a realistic ~0.81 mean, and a
"contaminated" sample (one enrollment sample that leans toward a DIFFERENT
person -- background bleed, mislabeled clip, atypical recording) tuned so its
cosine to a genuine utterance from that other person lands at 0.60-0.68,
landing at 0.641 mean across trials -- matching the empirical 0.637 almost
exactly.

Two experiments, N_TRIALS=3000 / N_TRIALS_NOISY=2000, produced (2026-08-26):

    strategy          false-negative rate   false-positive rate
    SINGLE (today)    0.0000                0.0000   (baseline: one sample, no contamination possible)
    MAX               0.0000                0.4050   <- 40.5% of trials: impostor wrongly matched
    CENTROID          0.0000                0.0000
    MIN(max,centroid) 0.0000                0.0000

    flip side (one NOISY, non-adversarial own-sample among clean ones, noise=0.5):
    SINGLE (if noisy was the one kept)  FN=1.0000
    MAX / CENTROID / MIN                FN=0.0000

MAX only needs ONE sample to misfire, so a single contaminated sample gives an
impostor a 40.5% chance of a false match; CENTROID dilutes that sample's
influence to 1/N of the average and had zero false positives in the same run,
at no false-negative cost -- it still recovers from a merely noisy (not
adversarial) own-sample exactly like MAX does. CENTROID wins on both axes.

CAVEAT: this calibration is SYNTHETIC. A re-check against real embeddings,
once Yanis has re-enrolled his 3 purged voiceprints, is a follow-up (tracked
in TODO.md) -- not done here.

Not a test: this is an analysis/design-justification script, run manually,
not part of `uv run pytest` (see .claude/skills/*/SKILL.md L3 -- heavy compute
stays out of the fast test gate). Deterministic given its fixed seeds.
"""

from __future__ import annotations

import random

DIM = 256
THRESHOLD = 0.65
N_TRIALS = 3000
N_TRIALS_NOISY = 2000
K_CLEAN_SAMPLES = 3
RECORDING_NOISE = 0.03  # calibrated: two independent same-person samples cosine ~0.81 mean
NOISY_OWN_SAMPLE_NOISE = 0.5  # much noisier than a normal clip (bad mic, background)


def rand_unit(rng: random.Random) -> list[float]:
    v = [rng.gauss(0.0, 1.0) for _ in range(DIM)]
    norm = sum(x * x for x in v) ** 0.5
    return [x / norm for x in v]


def cosine(a: list[float], b: list[float]) -> float:
    dot = sum(x * y for x, y in zip(a, b, strict=True))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(y * y for y in b) ** 0.5
    return dot / (na * nb) if na and nb else 0.0


def normalize(v: list[float]) -> list[float]:
    norm = sum(x * x for x in v) ** 0.5
    return [x / norm for x in v] if norm else v


def perturb(v: list[float], rng: random.Random, noise: float) -> list[float]:
    return normalize([x + rng.gauss(0.0, noise) for x in v])


def slerp_like(a: list[float], b: list[float], t: float) -> list[float]:
    """Linear interpolation + renormalize -- a cheap stand-in for slerp, fine at
    these small angles / high dimension for a calibration search."""
    return normalize([(1 - t) * x + t * y for x, y in zip(a, b, strict=True)])


def make_contaminated_sample(
    a_true: list[float], b_true: list[float], target_cosine_to_b: float, rng: random.Random
) -> list[float]:
    """Binary-search the pull-toward-B amount so the contaminated direction's
    EXPECTED noisy cosine to B (averaged over several noise draws, since that's
    what a real comparison actually sees) lands near target_cosine_to_b."""
    calib_rng = random.Random(rng.random())
    lo, hi = 0.0, 1.0
    pulled = a_true
    for _ in range(16):
        mid = (lo + hi) / 2
        pulled = slerp_like(a_true, b_true, mid)
        avg_cos = (
            sum(
                cosine(perturb(pulled, calib_rng, RECORDING_NOISE), perturb(b_true, calib_rng, RECORDING_NOISE))
                for _ in range(15)
            )
            / 15
        )
        if avg_cos < target_cosine_to_b:
            lo = mid
        else:
            hi = mid
    return perturb(pulled, rng, RECORDING_NOISE)


def centroid(samples: list[list[float]]) -> list[float]:
    summed = [sum(s[i] for s in samples) for i in range(DIM)]
    return normalize(summed)


def score_max(query: list[float], samples: list[list[float]]) -> float:
    return max(cosine(query, s) for s in samples)


def score_centroid(query: list[float], samples: list[list[float]]) -> float:
    return cosine(query, centroid(samples))


def run_contamination_experiment() -> None:
    rng = random.Random(42)

    fn = {"max": 0, "centroid": 0, "min": 0, "single": 0}
    fp = {"max": 0, "centroid": 0, "min": 0, "single": 0}
    contaminated_vs_impostor_cosines = []
    same_person_cosines = []

    for _ in range(N_TRIALS):
        a_true = rand_unit(rng)
        b_true = rand_unit(rng)

        clean_samples = [perturb(a_true, rng, RECORDING_NOISE) for _ in range(K_CLEAN_SAMPLES)]

        target = rng.uniform(0.60, 0.68)  # the empirical driver's band (0.637 observed)
        contaminated = make_contaminated_sample(a_true, b_true, target, rng)

        samples_with_contamination = [*clean_samples, contaminated]

        genuine_a = perturb(a_true, rng, RECORDING_NOISE)
        impostor_b = perturb(b_true, rng, RECORDING_NOISE)

        same_person_cosines.append(cosine(genuine_a, clean_samples[0]))
        contaminated_vs_impostor_cosines.append(cosine(contaminated, impostor_b))

        # today's baseline: single stored sample, most recent enrollment kept
        # (upsert overwrote before 1c6244c) -- use the LAST clean sample as
        # "what's on file"
        single_on_file = clean_samples[-1]
        if cosine(genuine_a, single_on_file) < THRESHOLD:
            fn["single"] += 1
        if cosine(impostor_b, single_on_file) >= THRESHOLD:
            fp["single"] += 1

        mx_a, ce_a = (
            score_max(genuine_a, samples_with_contamination),
            score_centroid(genuine_a, samples_with_contamination),
        )
        mx_b, ce_b = (
            score_max(impostor_b, samples_with_contamination),
            score_centroid(impostor_b, samples_with_contamination),
        )

        if mx_a < THRESHOLD:
            fn["max"] += 1
        if ce_a < THRESHOLD:
            fn["centroid"] += 1
        if min(mx_a, ce_a) < THRESHOLD:
            fn["min"] += 1

        if mx_b >= THRESHOLD:
            fp["max"] += 1
        if ce_b >= THRESHOLD:
            fp["centroid"] += 1
        if min(mx_b, ce_b) >= THRESHOLD:
            fp["min"] += 1

    print(
        f"N_TRIALS={N_TRIALS}, K_CLEAN_SAMPLES={K_CLEAN_SAMPLES}, "
        f"THRESHOLD={THRESHOLD}, RECORDING_NOISE={RECORDING_NOISE}"
    )
    print(f"same-person sample-vs-sample cosine: mean={sum(same_person_cosines) / len(same_person_cosines):.3f}")
    print(
        f"contaminated-sample-vs-genuine-impostor cosine: "
        f"mean={sum(contaminated_vs_impostor_cosines) / len(contaminated_vs_impostor_cosines):.3f} "
        f"min={min(contaminated_vs_impostor_cosines):.3f} max={max(contaminated_vs_impostor_cosines):.3f} "
        f"(target band 0.60-0.68, empirical driver: 0.637)"
    )
    print()
    print(f"{'strategy':<16} {'false-negative rate':<22} {'false-positive rate':<22}")
    for name in ("single", "max", "centroid", "min"):
        label = "SINGLE(today)" if name == "single" else name.upper() if name != "min" else "MIN(max,centroid)"
        print(f"{label:<16} {fn[name] / N_TRIALS:<22.4f} {fp[name] / N_TRIALS:<22.4f}")


def run_noisy_own_sample_experiment() -> None:
    """Flip side: does CENTROID hurt recognition when one of A's OWN samples is
    just poor-quality (not adversarial toward anyone), which is the scenario
    multi-sample enrollment is meant to help with in the first place?"""
    rng = random.Random(7)

    fn = {"max": 0, "centroid": 0, "min": 0, "single_last_bad": 0}

    for _ in range(N_TRIALS_NOISY):
        a_true = rand_unit(rng)
        clean_samples = [perturb(a_true, rng, RECORDING_NOISE) for _ in range(K_CLEAN_SAMPLES - 1)]
        noisy_own_sample = perturb(a_true, rng, NOISY_OWN_SAMPLE_NOISE)
        samples = [*clean_samples, noisy_own_sample]

        genuine_a = perturb(a_true, rng, RECORDING_NOISE)

        # today's baseline: if the noisy enrollment happened to be the LAST one
        # (upsert overwrote before 1c6244c), that's ALL that's on file
        if cosine(genuine_a, noisy_own_sample) < THRESHOLD:
            fn["single_last_bad"] += 1

        mx_a = score_max(genuine_a, samples)
        ce_a = score_centroid(genuine_a, samples)
        if mx_a < THRESHOLD:
            fn["max"] += 1
        if ce_a < THRESHOLD:
            fn["centroid"] += 1
        if min(mx_a, ce_a) < THRESHOLD:
            fn["min"] += 1

    print()
    print("=== Flip side: one NOISY (not adversarial) own-sample among clean ones ===")
    print(f"trials={N_TRIALS_NOISY}, noisy-own-sample noise={NOISY_OWN_SAMPLE_NOISE}")
    print(f"{'strategy':<32} {'false-negative rate':<22}")
    for name, label in [
        ("single_last_bad", "SINGLE(today, if noisy was last)"),
        ("max", "MAX"),
        ("centroid", "CENTROID"),
        ("min", "MIN(max,centroid)"),
    ]:
        print(f"{label:<32} {fn[name] / N_TRIALS_NOISY:<22.4f}")


if __name__ == "__main__":
    run_contamination_experiment()
    run_noisy_own_sample_experiment()
