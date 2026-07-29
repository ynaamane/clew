---
name: ownscribe-pipeline-traps
description: The Python-side traps in this repo's record→transcribe→summarize pipeline — which binary production actually loads, why absent must never render as zero, the dependency dead-ends that have no config-only fix, and the fixtures that are real user data. Read BEFORE touching src/ownscribe/, the pipeline, anchoring, the envelope, or any test that mocks a boundary.
paths:
  - "src/ownscribe/**"
  - "tests/**"
  - "pilot/**"
  - "rec.sh"
---

# ownscribe pipeline — the traps that shipped

Every item here reached production or survived a green suite. The recurring shape is a value
that is *correct* at every individual link and *dead* at the consumer.

## Ask which artifact production LOADS, not which one you built

`coreaudio.py:_find_binary()` prefers `bin/ownscribe-audio` over anything in `.build`. `bin/` is
**gitignored** and only `swift/build.sh` copies into it. So a Swift fix can land in source, pass
every test, and never reach the running pipeline.

BUG5 shipped that way for three days: `bin/` produced `recording.wav` at **12.81s @24000Hz** from
48 kHz sources while `.build/` gave **5.52s @48000Hz** — voices deep and slowed. The signature is
in the user's own retained meetings (the July 24 ones are 24000Hz).

The e2e tests could not see it, **three independent ways**: they hardcoded the `.build` path;
`--help` is byte-identical between the two binaries, so a smoke test cannot tell them apart; and
they never passed `--mic`, so `mergeAudioFiles` — where the bug lived — was never reached. The
duration bound was useless too: 12.81s from a ~5s capture sits comfortably inside
`1.0 <= d <= 30.0`, while that assertion's own message claimed to guard the 2x class.

- Resolve binaries through production's own lookup (`_BINARY_CANDIDATES`), never a literal path.
- **Pin the observable the bug CHANGES** (a sample rate) rather than one it merely perturbs (a
  duration). A 2x duration bug hides inside any plausible duration bound.
- `scripts/check.sh` gates on `bin/` being newer than every Swift source. If it fires, run
  `bash swift/build.sh`.

## Absent must never render as zero

The anti-hallucination spine of this project. A count whose source file may not exist is `Int?`,
never `Int`: zero of six meetings on disk have `anchors.json`, so rendering absence as `0` claims
*"every claim has evidence"* for a meeting nobody ever checked. Same on the Python side —
`envelope.py` returns `np.ndarray | None` and **must not** fall back to `np.zeros`, because a flat
strip asserts "total silence" over a 17.5-minute conversation.

`pipeline.py` guards with `if envelope is None: return` before writing. When a type encodes
"unknown", **grep every render site for `??`** — a `?? 0` three commits downstream silently
defeated a deliberate `Int?`.

Three states, three renderings, never two: `nil` → "not checked yet" · `[]` → "no evidence found"
· populated → the evidence. Collapsing the first two is the failure.

## Real fixtures, and one that is off-limits

`~/ownscribe/2026-07-27_1536_project-technical-review-key-points/` is a **real 17.5-minute
recording of real colleagues**. Read-only, always: never write, move or delete anything under
`~/ownscribe/`. Do not print transcript content into a report or a commit message. It is the only
real fixture and it is worth using — two tests read from it deliberately — but the repo is private
because it holds biometric voiceprints (GDPR Art. 9, cleared for this use, still private).

`~/ownscribe/2026-07-27_1352/` is the BUG4 artifact: 12,890,112 bytes, 33.56s, **peak 0.0, rms
0.0**. Useful precisely because it is valid-but-empty — the case a presence check calls "fine".

`/tmp/ms-fixture/` is a DERIVED copy of the 27-July meeting, shared by **three** suites (grep it
before assuming, the count keeps growing): Swift's `EnvelopeDocumentTests` (500 buckets, peak 1.0),
Swift's `AnchorEvidenceRealMeetingTests` (the clickable-evidence path against 9 real tokens), and
Python's `test_anchoring_context_contains_token.py`, which exists to defend a context-window fix
against that meeting's **14 real anchors**. It lives in `/tmp`, so it does not survive a reboot;
`scripts/regenerate_fixtures.py` rebuilds it through production functions, reading the real meeting
and writing only under `/tmp`.

**Regenerating it from a different recording is worse than losing it.** The first attempt sourced
`~/ownscribe/scribe_selftest_*`, whose transcript anchors to **0** tokens — so the Python test's
loop body never executes, `missing_token` stays empty, and a fully reverted anchoring fix passes.
Coverage deleted, suite still green. `md5` on `transcript.md`/`summary.md` is the cheap check that a
fixture is the meeting it claims to be. Two rules follow: a fixture generator is production code for
the test suite, and any test whose assertion lives inside a loop needs a non-empty guard **before**
the loop (`assert len(anchors) > 0`) or "found nothing" is indistinguishable from "all correct".
Mutation-check that guard by handing the test an empty summary — it must go red.

**And the fixture itself goes stale.** On 2026-07-29 the on-disk copy predated an anchoring fix:
its `Lambda` context was truncated at 100 chars *before the word it proves*, which is the exact
defect `test_anchoring_context_contains_token.py` exists to catch — the fixture was a snapshot of
the bug. Current production centres the window correctly, and the regeneration script rebuilt it
identically otherwise. So when a real-data test fails, decide FIRST whether the code or the
snapshot is wrong: `anchor_summary_claims` on the live source, compared against the stored
`anchors.json`, settles it in one command. A stale fixture makes a correct fix look broken, and its
mirror image — a fixture regenerated past a real regression — makes a broken fix look correct.

## A green suite cannot see a dead consumer

Five instances of one shape, none visible in a diff:

- `silence_timeout` travelled config → AppState → controller → tap correctly, and the tap fired
  `onSilenceTimeout` into a **nil optional** because the CLI was its only assigner. The app never
  auto-stopped and logged to a stderr nobody reads.
- `isCliAvailable` was computed correctly with **zero consumers** — you could record a whole
  meeting before learning nothing could transcribe it.
- The sidebar counts existed in the model with no writer, so both filters were always empty.
- Claim anchoring returned `{}` on every real run: the call site passed `result.full_text` (one
  line, no timestamps) while six tests hand-built the timestamped markdown production never emits.
- A `Button` wired to an empty function body.

**Trace a feature to its CONSUMER, not to its last assignment.** And parametrise over the config
that changes production's input — `output.format` hid a JSON-only failure through three rounds of
review, because every test ran the default.

## Dependency dead-ends — do not re-litigate these

| Constraint | Why | The only working answer |
|---|---|---|
| **torchcodec fails to load** | venv links FFmpeg 4-7 (libavutil.56-59), machine has FFmpeg 8 (libavutil.60). Upgrading needs torch≥2.9, which conflicts with the torchaudio<2.9 pin | Bypass it: pyannote's `Audio.__call__` accepts a preloaded `{"waveform","sample_rate"}` dict, checked BEFORE the AudioDecoder path — exactly what `_diarize()` and `whisperx.load_audio()` already produce. A test asserts torchcodec never enters `sys.modules` |
| **mlx-audio ↔ whisperx** | mlx-audio≥0.4.1 needs huggingface-hub≥1.0; whisperx caps <1.0. No config-only fix exists — `uv.lock` pins one version project-wide regardless of extras or markers | Subprocess overlay: `uv run --with mlx-audio`. Never add it to `pyproject.toml` |
| **pyannote on MPS** | Returns wrong timestamps; pytorch#181650 (open) crashes pyannote 4.0.4, the pinned version | CPU only. Never `.to('mps')`. Costs nothing — the ASR path is CPU-bound anyway, CTranslate2 has no Metal backend |
| **`transcription.cpu_threads`** | whisperx defaults to `threads=4`; this project sizes to the **performance**-core count | Do not raise to `os.cpu_count()` — the 4 efficiency cores measurably drag the batch (23-25s vs 20.5s) |

Already optimal, do not "fix": `compute_type=int8`, `batch_size=16`, pyannote VAD,
`condition_on_previous_text=False`.

## Model choices that are settled

Whisper **large-v3**, not turbo, not Parakeet, not Canary. Parakeet has no language conditioning
and involuntarily **translates** spontaneous French to English — silent falsification, which is
disqualifying, not a quality trade-off. Canary was a real A/B candidate and lost by 66 points on
code-switch spans. large-v3-turbo is the one open lead worth measuring (`pilot/wer_measurement.py`
scores switch-span WER), and the earlier rejection rested on a bad citation — an SEO blog that
relabelled an English-only number.

Your voice vs the call is **two physical sources**, not diarization: `mic.wav` = "Owner",
`system.wav` = diarized. Perfect separation by construction — but only on headphones; on speakers
the call bleeds into the mic track (`echo_cancellation` mitigates).

## Testing this pipeline

**`.venv/lib/python3.*/site-packages/ownscribe.pth` hardcodes `/Users/yanisnaamane/meeting-scribe/src`.**
So pytest run from a worktree or a copied tree **silently imports the main checkout's production
code**. An entire audit once returned a false "this also passes on the old code". Force
`PYTHONPATH=<tree>/src` and *prove* which tree loaded (assert on `ownscribe.__file__`) before
believing any number.

`timeout` does not exist on this machine — exit 127, reported as success.

Mock-everything suites cannot see a binary that stopped working; BUG4 shipped 33.5s of silence
past a green suite. `tests/test_real_capture_e2e.py` drives the shipped binary
(`@pytest.mark.hardware`, skipped by `check.sh`). Writing it falsified three beliefs 617 mocked
tests had let stand: no `--duration` flag (records until SIGINT), usage on **stderr**, and
**IEEE float32** output that stdlib `wave` rejects with `unknown format: 3` — read via
`soundfile`. It must PLAY audio while capturing (`afplay`): the tap records what the machine
OUTPUTS, so on a silent system it correctly writes a valid header with **zero frames**, and the
first version captured that silence and blamed the binary.

Patch `ownscribe.pipeline.create_summarizer` (imported at module level) when mocking the
summarizer factory in pipeline tests.
