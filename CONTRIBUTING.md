# Contributing to ownscribe

Thanks for your interest in contributing! This project is fully local meeting transcription and summarization — all processing stays on-device.

## Development setup

```bash
# Clone the repo
git clone https://github.com/ynaamane/meeting-scribe.git
cd meeting-scribe

# Install dependencies (including dev tools)
uv sync --dev

# Build the Swift audio capture helper (macOS only, optional)
bash swift/build.sh

# Run tests
uv run pytest

# Run linter
uv run ruff check src/ tests/ scripts/
```

## Running tests

**CI exists but is not live on `main` yet.** `.github/workflows/ci.yml` is written and pushed on
branch `ci-resurrection`: a `lint-and-test-python` job (ruff + pytest) that runs automatically on
`ubuntu-latest`, and a `full-check-macos` job (the full `scripts/check.sh`) gated to manual
trigger via `workflow_dispatch`, since a hosted macOS runner is not something to burn on every
push. It will start running once the repo goes public and the workflow merges to `main`. Until
then, `scripts/check.sh` is the thing to run before submitting anything non-trivial:

```bash
bash scripts/check.sh   # 10 gates: lint, format, both suites, a RELEASE build, shell syntax
```

The release build matters on its own: a debug build can pass while the release build fails on
optimiser-sensitive code. `check.sh` also gates on `bin/ownscribe-audio` being newer than every
Swift source, because the pipeline loads `bin/`, not `.build/` — a Swift fix once passed every test
while production ran a three-day-old binary. If that gate fires, run `bash swift/build.sh`.

Read its exit code from a **captured variable**, not off the end of a pipeline:
`bash scripts/check.sh > log 2>&1; EXIT=$?` then grep the log. A trailing `grep` makes the shell
report the grep's success, which has hidden a real failure here more than once.

Both test totals move between runs for environment reasons, so check before calling it a regression:
the Swift skips include the hardware-gated suites **and** `DesignRenderTests` (behind
`OWNSCRIBE_RENDER_UI=1`), and Python prints `638 passed` or `637 passed, 1 skipped` depending on
whether `/tmp/ms-fixture` survived the last `/tmp` sweep.

**If your change touches the window, render it and look at it:**

```bash
bash scripts/ui-evidence/render.sh /tmp/ui-render   # off-screen, works with the screen locked
```

Then read the PNGs. A green suite is not a design check, and this repo has shipped that mistake
twice. Read the harness's own CANNOT-VERIFY output too — it is blind to Liquid Glass and to the
selected row, so never certify those on a render (`APP_TEST.md`).

The individual suites:

```bash
uv run pytest -v                    # all tests
uv run pytest -v -m "not hardware"  # what check.sh runs (637 + 1 skipped) — the count differs, so quote the flag
uv run pytest tests/test_search.py::TestRankMeetings::test_speaker_boost   # single test, path form
uv run pytest -v -k "TestRankMeetings and test_speaker_boost"              # -k needs `and`, NOT `::`
cd swift && swift test              # the Swift suite
```

Two measurement traps specific to this repo. `pytest -k "Class::method"` selects **zero** tests and
exits **0** — `-k` takes a boolean expression, so `::` matches nothing and "N deselected" reads
exactly like a pass. And `swift test` prints **two independent totals** (an XCTest summary and a
separate `Test run with N tests` for swift-testing), so reading one understates the suite; never pipe
either run through `tail` to read a total, since inside a `> file` redirect it destroys the number on
disk.

Tests that require macOS are auto-skipped on other platforms. `@pytest.mark.hardware` tests are
skipped by `check.sh`; run them explicitly with `-m hardware`. Some Swift tests mutate the real input
device and are gated behind `OWNSCRIBE_TEST_REAL_MUTE=1` / `OWNSCRIBE_TEST_REAL_MIC=1` — they will
change your machine's mute state, so don't run them during a call.

### Test-first, and mutation-check what you write

A red→green transition proves a test *ran*; it does not prove the test *guards* anything. Before
calling a test done, break the thing it defends in the **production** function and confirm it goes
red. Tests here have passed against the code they claimed to cover — a bare `XCTAssert(true)`, a spy
asserted instead of the real child process, and six tests that re-implemented the reader they were
testing, so stubbing that reader to `return nil` left all six green.

Report the kill **rate**, not "killed": a mutation that turns 7 of 8 tests red looks identical to
one that turns 1 red, and the difference tells you how much of the suite actually depends on the
behaviour. And measure it rather than predicting it — a mutation claim written from reasoning
landed in a commit message here on 2026-07-31 with the wrong arithmetic.

Two guards that are NOT reachable by a unit test, and the technique that reaches them anyway:
a SwiftUI render (instantiating a `View` deadlocks this project) and a declaration's POSITION in a
file. Both are readable from the **source** — `GlassPlacementTests`, `LibrarySidebarTests` and
`SearchPlacementDecisionTests` open the `.swift` file and assert on what it contains. "Only a
view-host test could catch this, so it is untestable" is how a live bug shipped: the banner rendered
`headline ?? message`, which orphaned the recovery instruction, while the data-level test stayed
green because the string was present in the struct.

## Verifying HF-gated / real-audio behavior

The regular test suite mocks everything gated behind a HuggingFace token (pyannote diarization/embedding models) or real hardware (MPS). `scripts/verify_with_token.py` consolidates every one of those checks into a single script, so they can all be closed in one pass instead of separately:

```bash
HF_TOKEN=hf_... uv run python scripts/verify_with_token.py
HF_TOKEN=hf_... uv run python scripts/verify_with_token.py --clip real_meeting.wav
HF_TOKEN=hf_... uv run python scripts/verify_with_token.py --clip-a alice.wav --clip-b bob.wav
```

Run `--help` to see every supported clip flag. Each check is independent and prints PASS/FAIL/SKIP with a detail line; the script exits non-zero only if a check that actually ran failed.

## Code style

This project uses [ruff](https://docs.astral.sh/ruff/) for linting. Run `uv run ruff check src/ tests/ scripts/` before submitting a PR — or just `bash scripts/check.sh`, which includes it along with `ruff format --check`. Nothing checks this automatically on `main` yet (see "Running tests" above), so an unlinted PR stays unlinted until someone runs it locally or the `ci-resurrection` workflow lands.

## Open contribution areas

Here are some areas where contributions would be especially welcome:

### Linux/Windows audio capture backends

Currently, system audio capture only works on macOS via Core Audio Taps. Adding support for PulseAudio/PipeWire (Linux) or WASAPI (Windows) would make the tool cross-platform. See `src/ownscribe/audio/base.py` for the recorder interface. A two-device mode for SoundDeviceRecorder (separate system audio + mic streams) would also bring mic mute toggle support to non-macOS platforms.

### GUI frontend

**Partly built — check before starting.** A native SwiftUI menu-bar app now exists
(`swift/Sources/OwnscribeMenuBar`, see "The macOS app" in the README): recording indicator, a
three-column library window with the transcript and an inspector, claim anchoring with clickable
timestamps, an RMS envelope strip, and a system-wide mic mute. It shells out to this repo's
`ownscribe`, so it is a front end rather than a reimplementation.

Still open, and worth doing: **live transcript preview during recording** (nothing streams yet — the
transcript appears after the pipeline finishes), live vumeters in the menu bar
(`AudioLevels.computePeakLevel` already computes the level and only writes it to `stderr`, so this is
a display to wire up rather than a computation to write), per-speaker envelope lanes, and a
non-macOS GUI, which depends on the capture backends above.

### Integration with meeting tools

A big difference to cloud-based apps is that those usually connect to meetings directly and capture the audio through that. This way, if your microphone is muted, it's not recorded. With the mic mute toggle (press `m` during recording), you can now mute/unmute the mic stream without stopping the recording. Further integration ideas include detecting the meeting app's mute state automatically.

### Speaker name assignment

Currently, diarization produces anonymous labels (`SPEAKER_00`, `SPEAKER_01`). Allow users to map these to real names, either interactively after transcription or via a pre-configured mapping.

### Additional LLM backends

Add support for more summarization backends beyond the built-in local model, Ollama, and OpenAI-compatible servers — for example, Anthropic or Google. See `src/ownscribe/summarization/base.py` for the summarizer interface.

### Improved diarization

The current diarization works well for 2-3 speakers but can struggle with larger meetings. Investigate better models or post-processing to improve accuracy for many-participant calls.

## Contribution licensing

This fork's own additions are licensed under the PolyForm Noncommercial
License 1.0.0 (see [LICENSE.md](LICENSE.md)); the code inherited from
upstream stays MIT (see [LICENSE-MIT](LICENSE-MIT)).

By submitting a contribution, you agree that it is licensed to the project
under the MIT license, the text in [LICENSE-MIT](LICENSE-MIT), regardless of
the PolyForm Noncommercial terms that apply to the project's own code. This
keeps every contribution as reusable as the upstream project it builds on,
and lets the project relicense the combined work later without needing to
track down every contributor individually.

## Submitting changes

1. Fork the repo and create a feature branch
2. Make your changes
3. Ensure tests pass (`uv run pytest`) and linting is clean (`uv run ruff check src/ tests/ scripts/`)
4. Submit a pull request with a clear description of the change
