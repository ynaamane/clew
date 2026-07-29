# Contributing to ownscribe

Thanks for your interest in contributing! This project is fully local meeting transcription and summarization — all processing stays on-device.

## Development setup

```bash
# Clone the repo
git clone https://github.com/paberr/ownscribe.git
cd ownscribe

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

**There is no CI.** GitHub Actions never ran on this repo — 29 consecutive `startup_failure`s with
zero jobs created. `scripts/check.sh` is the replacement, and it is the thing to run before
submitting anything non-trivial:

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

The individual suites:

```bash
uv run pytest -v                    # all tests (635 currently)
uv run pytest -v -m "not hardware"  # what check.sh runs (629) — the count differs, so quote the flag
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

## Verifying HF-gated / real-audio behavior

The regular test suite mocks everything gated behind a HuggingFace token (pyannote diarization/embedding models) or real hardware (MPS). `scripts/verify_with_token.py` consolidates every one of those checks into a single script, so they can all be closed in one pass instead of separately:

```bash
HF_TOKEN=hf_... uv run python scripts/verify_with_token.py
HF_TOKEN=hf_... uv run python scripts/verify_with_token.py --clip real_meeting.wav
HF_TOKEN=hf_... uv run python scripts/verify_with_token.py --clip-a alice.wav --clip-b bob.wav
```

Run `--help` to see every supported clip flag. Each check is independent and prints PASS/FAIL/SKIP with a detail line; the script exits non-zero only if a check that actually ran failed.

## Code style

This project uses [ruff](https://docs.astral.sh/ruff/) for linting. Run `uv run ruff check src/ tests/ scripts/` before submitting a PR — or just `bash scripts/check.sh`, which includes it along with `ruff format --check`. Nothing checks this for you: there is no CI, so an unlinted PR stays unlinted until someone runs it locally.

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

## Submitting changes

1. Fork the repo and create a feature branch
2. Make your changes
3. Ensure tests pass (`uv run pytest`) and linting is clean (`uv run ruff check src/ tests/ scripts/`)
4. Submit a pull request with a clear description of the change
