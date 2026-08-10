"""Drive Clew's real progress renderers with scripted events to record the README demo GIFs.

This is a demo simulation, not a captured live meeting. The checklist, the
spinners and the user-facing strings are rendered by the same code paths the
real CLI uses (clew.progress.PipelineProgress, clew.progress.Spinner,
clew.search._parse_folder_name), but the events are scripted and every piece
of meeting content is synthetic. No real meeting data is used or shown.

The original upstream demo GIFs were produced the same way, with the tooling
left uncommitted. This version keeps the tooling in the repo so the demos can
be regenerated after any UI change:

    vhs docs/demo/demo-pipeline.tape
    vhs docs/demo/demo-ask.tape

Run vhs from the repo root; the tapes write docs/demo-pipeline.gif and
docs/demo-ask.gif in place.
"""

from __future__ import annotations

import sys
import time

from clew.progress import PipelineProgress, Spinner
from clew.search import _parse_folder_name

OUT_DIR = "/Users/you/clew/2026-08-10_1401"
RENAMED_DIR = "/Users/you/clew/2026-08-10_1401_product-sync"

SUMMARY_MD = """\
## Summary
Weekly product sync. The team reviewed beta feedback and agreed on the
September launch scope.

## Key Points
- Onboarding drop-off is down to 12% after the new tutorial
- Transcription quality is the most cited piece of positive feedback

## Decisions
- Beta launches September 2 with the waitlist cohort only
- Voiceprint enrollment ships behind an opt-in flag

## Action Items
- [ ] Sam: draft the launch announcement by Friday
- [ ] Idris: cap the first cohort at 50 users\
"""

ASK_FOLDERS = ("2026-08-05_1401_product-sync", "2026-07-29_1000_beta-planning")

ASK_ANSWER = """\
The beta launches on September 2, limited to the waitlist cohort.

From the 2026-08-05 product sync: the team agreed to launch on September 2
"with the waitlist cohort only" and to keep voiceprint enrollment behind an
opt-in flag.

From the 2026-07-29 beta planning: Sam proposed capping the first cohort at
50 users, which was accepted.\
"""


def _recording_phase() -> None:
    # Mirrors the strings in clew.pipeline: default config has no mic capture
    # (no mute hint) and a 300s silence timeout.
    print("Starting recording... Auto-stops after 5m of silence. Press Ctrl+C to stop.\n")
    for total in range(8 * 60 + 9, 8 * 60 + 14):
        mins, secs = divmod(total, 60)
        sys.stdout.write(f"\r  Recording: {mins:02d}:{secs:02d}\033[K")
        sys.stdout.flush()
        time.sleep(0.7)
    print("\n\nStopping recording...")
    print(f"Audio saved to {OUT_DIR}/recording.wav\n")


def _checklist_phase() -> None:
    with PipelineProgress(diarize=True, summarize=True) as progress:
        progress.begin("transcribing")
        for i in range(0, 101, 2):
            progress.update("transcribing", i / 100)
            time.sleep(0.05)
        progress.complete("transcribing")

        progress.begin("diarizing")
        for key in ("segmentation", "speaker_counting", "embeddings", "clustering"):
            progress.begin(key)
            for i in range(0, 101, 10):
                progress.update(key, i / 100)
                time.sleep(0.035)
            progress.complete(key)
        progress.complete("diarizing")

        progress.begin("summarizing")
        time.sleep(1.8)
        progress.complete("summarizing")


def run_pipeline_demo() -> None:
    _recording_phase()
    _checklist_phase()
    print(f"Transcript saved to {OUT_DIR}/transcript.md")
    print(f"Summary saved to {RENAMED_DIR}/summary.md")
    print(f"\n{SUMMARY_MD}")


def run_ask_demo() -> None:
    with Spinner("Searching 12 meetings"):
        time.sleep(2.0)
    print("Found 2 relevant meetings:")
    for folder in ASK_FOLDERS:
        parsed = _parse_folder_name(folder)
        assert parsed is not None
        print(f"  - {parsed[1]}")
    with Spinner("Analyzing transcripts"):
        time.sleep(2.2)
    print(ASK_ANSWER)


def main() -> None:
    # Keep stdout ordered with the stderr spinners even when not a TTY.
    sys.stdout.reconfigure(line_buffering=True)  # type: ignore[union-attr]
    mode = sys.argv[1] if len(sys.argv) > 1 else "pipeline"
    if mode == "warm":
        return
    if mode == "ask":
        run_ask_demo()
    else:
        run_pipeline_demo()


if __name__ == "__main__":
    main()
