"""Build a throwaway fake HOME with synthetic meetings for app screenshots and GIFs.

Usage:

    python docs/demo/make_demo_home.py /path/to/fake-home
    HOME=/path/to/fake-home uv run clew backfill   # real anchors via the product code

The desktop demo captures (docs/demo-app-*.gif) are taken from a Clew.app
instance launched with HOME pointed at this directory, so the library window
only ever shows the synthetic meetings below. No real meeting data is used.
Transcripts follow the exact markdown format of clew.output.markdown, and the
envelope is a deterministic synthetic speech pattern in the same JSON schema
the pipeline writes ({"envelope": [500 floats]}).
"""

from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

PRODUCT_SYNC_TRANSCRIPT = """\
# Transcript

**Language:** en
**Duration:** 08:13

**Sam** [00:04]
[00:04] Alright, let's get started. Main topic today is the beta launch scope.
[00:12] We have the feedback from the pilot cohort and some numbers to look at.

**Maya** [00:21]
[00:21] Quick one from me first. Onboarding drop-off is down to 12% after the new tutorial.
[00:33] That is the best number we have had since we started measuring.

**Idris** [00:40]
[00:40] Nice. The most cited piece of positive feedback is transcription quality.
[00:49] People keep mentioning that names and technical terms come out right.

**Sam** [00:58]
[00:58] Good. So the launch question: do we open the beta to everyone or start smaller?

**Idris** [01:07]
[01:07] I would start with the waitlist cohort only. We can widen it once support load is known.
[01:19] My proposal is that we cap the first cohort at 50 users.

**Maya** [01:26]
[01:26] Agreed on the cap. What about the date?

**Sam** [01:31]
[01:31] Marketing wants something concrete. I propose we launch on September 2.
[01:40] That gives us three weeks for the remaining polish items.

**Idris** [01:47]
[01:47] Works for me. One thing I want to keep out of the first release is voiceprint enrollment.
[01:58] It is useful but it needs more explanation than a beta onboarding can carry.

**Maya** [02:06]
[02:06] Same feeling. Let's ship it behind an opt-in flag and document it properly later.

**Sam** [02:14]
[02:14] Okay, so decided: September 2, waitlist cohort only, voiceprints behind a flag.
[02:24] Maya, anything on the summarization side?

**Maya** [02:29]
[02:29] The new meeting template is stable. Action items extraction got noticeably better.
[02:40] I still want one more pass on lecture mode before the launch.

**Idris** [02:47]
[02:47] I can review that pass on Thursday if you push it before noon.

**Maya** [02:53]
[02:53] Deal.

**Sam** [02:56]
[02:56] Support docs. Who owns the quickstart rewrite?

**Idris** [03:02]
[03:02] I do. Draft is half done, I will finish it this week.

**Sam** [03:09]
[03:09] Then I will take the launch announcement. Draft by Friday so we can review together.

**Maya** [03:18]
[03:18] Add a line about local processing. It is the thing people ask about first.
[03:27] Nothing leaves the machine, and we should say it plainly.

**Sam** [03:34]
[03:34] Noted. Last item: the pricing page stays as is until after the beta.

**Idris** [03:42]
[03:42] Fine by me. We will learn more from fifty real users than from another debate.

**Sam** [03:50]
[03:50] Perfect. Recap: beta launches September 2 with the waitlist cohort only.
[04:00] Idris caps signups at 50, I draft the announcement by Friday.
[04:08] Voiceprint enrollment ships behind an opt-in flag. Anything else?

**Maya** [04:16]
[04:16] All good here.

**Idris** [04:18]
[04:18] Nothing from me. Short and sweet.

**Sam** [04:21]
[04:21] Great, thanks everyone. Back at it next week.
"""

PRODUCT_SYNC_SUMMARY = """\
# Meeting Summary

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
- [ ] Idris: cap the first cohort at 50 users
"""

BETA_PLANNING_TRANSCRIPT = """\
# Transcript

**Language:** en
**Duration:** 05:41

**Sam** [00:03]
[00:03] Goal today: shape of the beta program. Cohort size, channels, support.

**Maya** [00:12]
[00:12] The waitlist is at about three hundred signups, mostly from the demo video.

**Sam** [00:20]
[00:20] We cannot support three hundred on day one. Sam proposed a staged rollout last time.
[00:31] I would rather start small and widen weekly.

**Maya** [00:37]
[00:37] Agreed. First wave from the earliest signups, then weekly batches.

**Sam** [00:44]
[00:44] Support channel stays email for the beta. No community server until launch.

**Maya** [00:52]
[00:52] Fine. I will prepare the welcome email and the feedback form this week.

**Sam** [01:00]
[01:00] Then the open question is the cap for the first wave. We settle it at the product sync.
"""

BETA_PLANNING_SUMMARY = """\
# Meeting Summary

## Summary
Planning session for the beta program: rollout shape, support channel, and
first-wave logistics.

## Key Points
- The waitlist holds about three hundred signups
- Rollout will proceed in weekly batches from the earliest signups

## Decisions
- Support stays on email during the beta
- The first-wave cap will be settled at the product sync

## Action Items
- [ ] Maya: prepare the welcome email and the feedback form
"""

DESIGN_REVIEW_TRANSCRIPT = """\
# Transcript

**Language:** en
**Duration:** 04:02

**Maya** [00:05]
[00:05] Two topics: the library sidebar and the timeline strip.

**Idris** [00:11]
[00:11] Sidebar first. Grouping by week reads better than a flat list in every mock.

**Maya** [00:19]
[00:19] Agreed, shipping the weekly grouping. The strip needs a quieter idle state.

**Idris** [00:27]
[00:27] I will tone the idle color down and keep the speech peaks as they are.
"""

DESIGN_REVIEW_SUMMARY = """\
# Meeting Summary

## Summary
Short design review of the library window.

## Key Points
- Weekly grouping wins over a flat list in the sidebar mocks

## Decisions
- Ship the weekly sidebar grouping
- Quieter idle state for the timeline strip, speech peaks unchanged

## Action Items
- [ ] Idris: tone down the strip idle color
"""

MEETINGS = {
    "2026-08-05_1401_product-sync": (PRODUCT_SYNC_TRANSCRIPT, PRODUCT_SYNC_SUMMARY, 42),
    "2026-07-29_1000_beta-planning": (BETA_PLANNING_TRANSCRIPT, BETA_PLANNING_SUMMARY, 7),
    "2026-07-22_0930_design-review": (DESIGN_REVIEW_TRANSCRIPT, DESIGN_REVIEW_SUMMARY, 13),
}

CONFIG_TOML = """\
[output]
dir = "~/clew"
"""


def synthetic_envelope(seed: int, n_buckets: int = 500) -> list[float]:
    """Deterministic speech-like RMS pattern: talk bursts separated by pauses."""
    rng = random.Random(seed)
    envelope = [0.0] * n_buckets
    i = 0
    while i < n_buckets:
        burst = rng.randint(8, 40)
        pause = rng.randint(2, 10)
        level = rng.uniform(0.25, 0.85)
        for j in range(min(burst, n_buckets - i)):
            wobble = 0.6 + 0.4 * abs(math.sin(j / 3.1 + seed))
            envelope[i + j] = round(min(1.0, level * wobble * rng.uniform(0.75, 1.1)), 4)
        i += burst + pause
    return envelope


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: make_demo_home.py /path/to/fake-home")
    home = Path(sys.argv[1]).resolve()
    (home / ".config" / "clew").mkdir(parents=True, exist_ok=True)
    (home / ".config" / "clew" / "config.toml").write_text(CONFIG_TOML)

    for folder, (transcript, summary, seed) in MEETINGS.items():
        meeting = home / "clew" / folder
        meeting.mkdir(parents=True, exist_ok=True)
        (meeting / "transcript.md").write_text(transcript)
        (meeting / "summary.md").write_text(summary)
        (meeting / "envelope.json").write_text(json.dumps({"envelope": synthetic_envelope(seed)}))

    print(f"Demo home ready at {home}")
    print(f"Now run: HOME={home} uv run clew backfill")


if __name__ == "__main__":
    main()
