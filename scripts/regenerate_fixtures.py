#!/usr/bin/env -S uv run python3
"""Regenerate /tmp/ms-fixture/* from production functions.

Sources the real 27-July meeting from ~/ownscribe/2026-07-27_1536_* (READ-ONLY),
generates anchors + envelope via production functions (generate_envelope_from_file,
anchor_summary_claims, save_anchors), writes to /tmp/ms-fixture/ for both
EnvelopeDocumentTests (Swift) and test_anchoring_context_contains_token (Python).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from ownscribe.audio.envelope import generate_envelope_from_file
from ownscribe.summarization.anchoring import anchor_summary_claims
from ownscribe.summarization.anchors_output import save_anchors


def main() -> None:
    source_dir = Path.home() / "ownscribe" / "2026-07-27_1536_project-technical-review-key-points"

    if not source_dir.exists():
        print(f"Error: source directory not found: {source_dir}", file=sys.stderr)
        sys.exit(1)

    audio_path = source_dir / "recording.wav"
    transcript_path = source_dir / "transcript.md"
    summary_path = source_dir / "summary.md"

    if not audio_path.exists():
        print(f"Error: recording.wav not found in {source_dir}", file=sys.stderr)
        sys.exit(1)
    if not transcript_path.exists():
        print(f"Error: transcript.md not found in {source_dir}", file=sys.stderr)
        sys.exit(1)
    if not summary_path.exists():
        print(f"Error: summary.md not found in {source_dir}", file=sys.stderr)
        sys.exit(1)

    transcript_text = transcript_path.read_text()
    summary_text = summary_path.read_text()

    fixture_dir = Path("/tmp/ms-fixture")
    fixture_dir.mkdir(parents=True, exist_ok=True)

    print(f"Generating envelope from {audio_path}...")
    envelope = generate_envelope_from_file(audio_path, n_buckets=500)
    if envelope is None:
        print("Error: envelope generation returned None", file=sys.stderr)
        sys.exit(1)

    envelope_path = fixture_dir / "envelope.json"
    envelope_path.write_text(json.dumps({"envelope": envelope.tolist()}, indent=2))
    print(f"Wrote {envelope_path}")

    print("Anchoring summary claims...")
    anchors = anchor_summary_claims(summary_text, transcript_text)
    save_anchors(anchors, fixture_dir)
    print(f"Wrote {fixture_dir / 'anchors.json'}")

    (fixture_dir / "transcript.md").write_text(transcript_text)
    (fixture_dir / "summary.md").write_text(summary_text)
    print(f"Wrote {fixture_dir / 'transcript.md'} and {fixture_dir / 'summary.md'}")

    print("\nFixture directory contents:")
    for path in sorted(fixture_dir.iterdir()):
        size = path.stat().st_size
        print(f"  {path.name:20s} {size:>8d} bytes")

    env_list = json.loads(envelope_path.read_text())["envelope"]
    buckets = len(env_list)
    max_val = max(env_list)
    zeros = env_list.count(0.0)
    print(f"\nEnvelope properties: buckets={buckets}, max={max_val:.4f}, zeros={zeros}")


if __name__ == "__main__":
    main()
