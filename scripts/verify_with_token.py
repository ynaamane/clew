#!/usr/bin/env python3
"""Single end-of-build verification pass for every check that needs a real HF token,
real audio, or real hardware -- consolidated per team-lead's decision to defer these
to one token-enabled pass instead of blocking each task on it individually.

Usage:
    HF_TOKEN=hf_... uv run python scripts/verify_with_token.py
    HF_TOKEN=hf_... uv run python scripts/verify_with_token.py --clip path/to/real_meeting.wav
    HF_TOKEN=hf_... uv run python scripts/verify_with_token.py --clip-a alice.wav --clip-b bob.wav

Every check is independent: one failing or skipped check does not abort the run.
Exits 0 only if every check that ran (not skipped) passed.
"""

from __future__ import annotations

import argparse
import os
import sys
import traceback
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))


@dataclass
class CheckResult:
    name: str
    status: str
    detail: str


def _pass(name: str, detail: str) -> CheckResult:
    return CheckResult(name, "PASS", detail)


def _fail(name: str, detail: str) -> CheckResult:
    return CheckResult(name, "FAIL", detail)


def _skip(name: str, detail: str) -> CheckResult:
    return CheckResult(name, "SKIP", detail)


def check_community1_real_diarization(hf_token: str, clip: Path | None) -> CheckResult:
    name = "community-1 diarizes a real WAV (proves torchcodec/FFmpeg decode path end-to-end)"
    if not hf_token:
        return _skip(name, "HF_TOKEN env var not set")
    if clip is None:
        return _skip(name, "no --clip provided")
    try:
        from clew.config import DiarizationConfig, TranscriptionConfig
        from clew.progress import PipelineProgress
        from clew.transcription.whisperx_transcriber import WhisperXTranscriber

        diar = DiarizationConfig(enabled=True, hf_token=hf_token)
        transcriber = WhisperXTranscriber(TranscriptionConfig(), diar, progress=PipelineProgress())
        result = transcriber.transcribe(clip)
        speakers = {seg.speaker for seg in result.segments if seg.speaker}
        if not speakers:
            return _fail(
                name, f"diarization ran but produced 0 distinct speaker labels ({len(result.segments)} segments)"
            )
        return _pass(name, f"{len(speakers)} distinct speaker label(s) across {len(result.segments)} segments")
    except Exception as exc:
        return _fail(name, f"{type(exc).__name__}: {exc}")


def check_enrollment_separation(hf_token: str, clip_a: Path | None, clip_b: Path | None) -> CheckResult:
    name = "enrollment: 2 real voices separate at cosine 0.65 threshold"
    if not hf_token:
        return _skip(name, "HF_TOKEN env var not set")
    if clip_a is None or clip_b is None:
        return _skip(name, "needs both --clip-a and --clip-b (short, single-speaker reference clips)")
    try:
        from clew.speakers.embedding import SpeakerEmbedder
        from clew.speakers.matching import cosine_similarity

        embedder = SpeakerEmbedder(hf_token)
        embedding_a1 = embedder.embed_file(clip_a)
        embedding_a2 = embedder.embed_file(clip_a)
        embedding_b = embedder.embed_file(clip_b)

        self_similarity = cosine_similarity(embedding_a1, embedding_a2)
        cross_similarity = cosine_similarity(embedding_a1, embedding_b)

        if self_similarity < 0.65:
            return _fail(
                name,
                f"same-speaker self-similarity {self_similarity:.3f} is BELOW the 0.65 match "
                "threshold -- the same voice would not match itself on re-enrollment",
            )
        if cross_similarity >= 0.65:
            return _fail(
                name,
                f"different speakers scored {cross_similarity:.3f} similarity, ABOVE the 0.65 "
                "match threshold -- clip_a and clip_b would be confused as the same person",
            )
        return _pass(name, f"self={self_similarity:.3f} (>=0.65 OK), cross={cross_similarity:.3f} (<0.65 OK)")
    except Exception as exc:
        return _fail(name, f"{type(exc).__name__}: {exc}")


def check_standalone_and_in_meeting_embedding_space(hf_token: str, clip: Path | None) -> CheckResult:
    name = "standalone-enroll embedding space matches in-meeting diarization embedding space"
    if not hf_token:
        return _skip(name, "HF_TOKEN env var not set")
    if clip is None:
        return _skip(name, "needs --clip (a single-speaker clip that also works as a diarization input)")
    try:
        from clew.config import DiarizationConfig, TranscriptionConfig
        from clew.progress import PipelineProgress
        from clew.speakers.embedding import SpeakerEmbedder
        from clew.speakers.matching import cosine_similarity
        from clew.transcription.whisperx_transcriber import WhisperXTranscriber

        embedder = SpeakerEmbedder(hf_token)
        standalone_embedding = embedder.embed_file(clip)

        diar = DiarizationConfig(enabled=True, hf_token=hf_token)
        transcriber = WhisperXTranscriber(TranscriptionConfig(), diar, progress=PipelineProgress())
        transcriber.transcribe(clip)
        cluster_embeddings = transcriber.last_speaker_embeddings

        if not cluster_embeddings:
            return _fail(name, "in-meeting diarization produced no cluster embeddings to compare against")

        best_similarity = max(
            cosine_similarity(standalone_embedding, cluster_embedding)
            for cluster_embedding in cluster_embeddings.values()
        )
        if best_similarity < 0.65:
            return _fail(
                name,
                f"best cross-space similarity {best_similarity:.3f} is below 0.65 -- standalone "
                "enrollment and in-meeting diarization embeddings may live in different spaces",
            )
        return _pass(name, f"best cross-space cosine similarity {best_similarity:.3f} (>=0.65)")
    except Exception as exc:
        return _fail(name, f"{type(exc).__name__}: {exc}")


def check_owner_mic_labeling(clip_system: Path | None, clip_mic: Path | None) -> CheckResult:
    name = "owner mic-track labeling on a real dual-track capture"
    if clip_system is None or clip_mic is None:
        return _skip(name, "needs --clip-system and --clip-mic (a real captured system.wav + mic.wav pair)")
    try:
        from clew.config import Config
        from clew.pipeline import _transcribe_dual_track
        from clew.progress import PipelineProgress
        from clew.transcription.whisperx_transcriber import WhisperXTranscriber

        config = Config()
        transcriber = WhisperXTranscriber(config.transcription, config.diarization, progress=PipelineProgress())
        result = _transcribe_dual_track(transcriber, clip_system, clip_mic, mic_offset=0.0)

        owner_segments = [seg for seg in result.segments if seg.speaker == "Owner"]
        if not owner_segments:
            return _fail(name, f"0 of {len(result.segments)} segments labeled Owner")
        return _pass(name, f"{len(owner_segments)}/{len(result.segments)} segments labeled Owner")
    except Exception as exc:
        return _fail(name, f"{type(exc).__name__}: {exc}")


def check_canary_mlx_engine(clip_fr: Path | None) -> CheckResult:
    name = "Canary MLX engine transcribes a real FR clip with source_lang (no involuntary FR->EN)"
    try:
        from clew.transcription.canary_mlx_transcriber import CanaryMlxTranscriber
    except ImportError:
        return _skip(name, "CanaryMlxTranscriber not built yet (Task#8 is paused pending team-lead direction)")
    if clip_fr is None:
        return _skip(name, "needs --clip-fr")
    try:
        from clew.transcription.canary_mlx_transcriber import CanaryMlxTranscriber

        transcriber = CanaryMlxTranscriber()
        result = transcriber.transcribe(clip_fr)
        if result.language and result.language != "fr":
            return _fail(name, f"expected language=fr, got language={result.language!r}")
        return _pass(name, f"language={result.language!r}, {len(result.segments)} segment(s)")
    except Exception as exc:
        return _fail(name, f"{type(exc).__name__}: {exc}")


def check_mps_vs_cpu_diarization(hf_token: str, clip: Path | None) -> CheckResult:
    name = "MPS vs CPU diarization on the same clip (catches pyannote/pyannote-audio#1886 wrong-output mode)"
    if not hf_token:
        return _skip(name, "HF_TOKEN env var not set")
    if clip is None:
        return _skip(name, "needs --clip")
    try:
        import torch

        if not torch.backends.mps.is_available():
            return _skip(name, "MPS not available on this machine")

        from clew.config import DiarizationConfig, TranscriptionConfig
        from clew.progress import PipelineProgress
        from clew.transcription.whisperx_transcriber import WhisperXTranscriber

        diar_cpu = DiarizationConfig(enabled=True, hf_token=hf_token)
        cpu_result = WhisperXTranscriber(TranscriptionConfig(), diar_cpu, progress=PipelineProgress()).transcribe(clip)
        cpu_speakers = sorted({seg.speaker for seg in cpu_result.segments if seg.speaker})

        from unittest import mock

        with mock.patch(
            "clew.transcription.whisperx_transcriber.WhisperXTranscriber._load_diarization_pipeline"
        ) as mock_load:
            from whisperx.diarize import DiarizationPipeline

            mps_pipeline = DiarizationPipeline(token=hf_token, device="mps")
            mock_load.return_value = mps_pipeline
            diar_mps = DiarizationConfig(enabled=True, hf_token=hf_token)
            mps_transcriber = WhisperXTranscriber(TranscriptionConfig(), diar_mps, progress=PipelineProgress())
            mps_result = mps_transcriber.transcribe(clip)
        mps_speakers = sorted({seg.speaker for seg in mps_result.segments if seg.speaker})

        if len(mps_speakers) == 1 and len(cpu_speakers) > 1:
            return _fail(
                name,
                f"MPS collapsed to 1 speaker ({mps_speakers}) while CPU found {len(cpu_speakers)} "
                f"({cpu_speakers}) -- this is the all-speaker-0 failure mode from pyannote-audio#1886",
            )
        if mps_speakers != cpu_speakers:
            return _fail(name, f"CPU speakers={cpu_speakers} != MPS speakers={mps_speakers}")
        return _pass(name, f"CPU and MPS agree on speaker set: {cpu_speakers}")
    except Exception as exc:
        return _fail(name, f"{type(exc).__name__}: {exc}")


def check_torchcodec_ffmpeg_decode_path() -> CheckResult:
    name = "in-memory waveform dict never touches torchcodec (regardless of FFmpeg/torchcodec version alignment)"
    try:
        import numpy as np
        import torch
        from pyannote.audio.core.io import Audio
        from pyannote.core import Segment

        waveform = torch.from_numpy(np.random.randn(1, 16000).astype("float32"))
        audio_data = {"waveform": waveform, "sample_rate": 16000}
        io = Audio()
        io(audio_data)
        io.crop(audio_data, Segment(0.0, 0.5))
        return _pass(name, "Audio.__call__ and Audio.crop succeeded on a real in-memory waveform, no torchcodec needed")
    except Exception as exc:
        return _fail(name, f"{type(exc).__name__}: {exc}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clip", type=Path, default=None, help="A real meeting-length WAV/audio clip with 2+ speakers")
    parser.add_argument("--clip-a", type=Path, default=None, help="Short reference clip of speaker A")
    parser.add_argument("--clip-b", type=Path, default=None, help="Short reference clip of speaker B")
    parser.add_argument("--clip-system", type=Path, default=None, help="A real captured system.wav")
    parser.add_argument("--clip-mic", type=Path, default=None, help="A real mic.wav (pairs with --clip-system)")
    parser.add_argument("--clip-fr", type=Path, default=None, help="A real French-language clip for the Canary engine")
    args = parser.parse_args()

    hf_token = os.environ.get("HF_TOKEN", "")

    results: list[CheckResult] = [
        check_torchcodec_ffmpeg_decode_path(),
        check_community1_real_diarization(hf_token, args.clip),
        check_enrollment_separation(hf_token, args.clip_a, args.clip_b),
        check_standalone_and_in_meeting_embedding_space(hf_token, args.clip),
        check_mps_vs_cpu_diarization(hf_token, args.clip),
        check_owner_mic_labeling(args.clip_system, args.clip_mic),
        check_canary_mlx_engine(args.clip_fr),
    ]

    width = max(len(r.name) for r in results)
    print("\n=== verify_with_token.py results ===\n")
    for r in results:
        print(f"[{r.status:4}] {r.name.ljust(width)}  {r.detail}")

    passed = sum(1 for r in results if r.status == "PASS")
    failed = sum(1 for r in results if r.status == "FAIL")
    skipped = sum(1 for r in results if r.status == "SKIP")
    print(f"\n{passed} passed, {failed} failed, {skipped} skipped\n")

    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        traceback.print_exc()
        sys.exit(2)
