# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development hygiene (standing rule for this project)

Default on every non-trivial change — not a per-task ask:

- **TDD, test-first.** Write the failing test first, watch it fail for the right reason (red), then the minimum code to green, then refactor. Report the red→green transition. Not test-after.
- **Independent review.** A separate reviewer (not the implementer self-reviewing) audits each delivery with empirical verification — re-run the real repro, don't just read the diff. Findings go through a DEFEND/CONCEDE/FIX pass.
- **Scrutinize high-blast-radius code hardest** — the system-wide mic mute (reaches Zoom/all apps), the CoreAudio tap, anything that can leave the system in a bad state (e.g. mic left muted after quit). The dangerous failures are silent: a false sense of mute in public, a scrambled transcript that looks fine.
- **Verify, don't assume.** Disk/`git log` is ground truth, not a message saying "it's done". Prefer a real run over reading code. State what you actually ran.
- **Mutation-check every new test.** A red→green transition is not enough: break the thing the test defends and confirm it goes red. Three tests in the 2026-07-27 review batch passed against the code they claimed to guard (a bare `XCTAssert(true)`, a spy asserted instead of the real child process, and a `phase == .recording(startedAt: Date())` comparison that is false in every state). Never add a test-only method to production to make a test possible — inject a fake at a real seam instead (`makeSystemCapture`, `mergeAudioFilesImpl`).
- **A test must INVOKE production, not merely patch the right target.** Ask: does this test call the function production calls, with the argument production passes? Four defects in one batch reduced to a test constructing production's input itself — anchoring returned empty on every real run while six tests passed on hand-built markdown; an envelope reference test re-implemented its reader inline, so a fully sabotaged reader stayed green; and two of my own replacement tests patched the correct symbol and then called it themselves, which is tautological. Parametrise over the config that changes the input (`output.format` hid a JSON-only failure).
- **Test the artifact production LOADS, not the one you just built.** `coreaudio.py:_find_binary()` prefers `bin/ownscribe-audio` over `.build`, and `bin/` is gitignored — so BUG5's fix passed every test against `.build` while the pipeline still ran a three-day-old binary that halved playback speed. Resolve binaries through production's own lookup (`_BINARY_CANDIDATES`), and note `--help` was byte-identical between the two, so a smoke test cannot tell them apart. `scripts/check.sh` now gates on `bin/` being newer than every Swift source; if it fires, run `bash swift/build.sh`. Related: pin the observable the bug CHANGES (a sample rate) rather than one it merely perturbs (a duration) — a 2x duration bug hides inside any plausible duration bound.
- **Real tests, not only unit tests.** A suite that mocks every boundary cannot see a binary that stopped working — BUG4 shipped 33.5s of silence past a green suite. Two precedents to copy: `tests/test_real_capture_e2e.py` drives the shipped `ownscribe-audio` (`@pytest.mark.hardware`, so `check.sh` skips it) and `RealHardwareMuteTests` mutes the real input device (gated on `OWNSCRIBE_TEST_REAL_MUTE=1`). **A dangerous real test must:** record the state it found in `setUp` and skip if it cannot READ it; restore in `tearDown` **and assert the restore**, so a mid-test failure cannot leave the machine altered; skip itself on the hardware class where a red would not distinguish our bug from a platform one (e.g. Bluetooth mute); and generate its own stimulus rather than depending on ambient conditions — the tap records what the machine OUTPUTS, so a silent system yields a valid header with zero frames and a test asserting duration would be measuring the room. Mutation-check these like any other, but note `git worktree` mutation runs give FALSE reds for tests needing a built binary, since `.build` is gitignored: a suspiciously fast run (0.4s where a real capture takes 16s) is the tell.
- **No test may touch real audio hardware unless it is one of the gated real tests above.** A test that reaches `RecordingController.start()` must inject BOTH `makeSystemCapture` and `makeMicCapture`. Injecting only a start-time seam is not enough: `MicCapture` holds `AVAudioEngine` as a stored property, so the input device is claimed when the object is *constructed*. Three suites hijacked the mic this way — 0 CoreAudio `PauseIO/ResumeIO` cycles before a run, 7920 after, with the AirPods input forced to 24 kHz (HFP) — and the user noticed the degraded audio before any of us. Note a missing config file means mic **ON** (`mic ?? true`), so a temp `homeDir` is a silent opt-in. If a test genuinely needs hardware, gate it behind `OWNSCRIBE_TEST_REAL_MIC=1` and keep a hardware-free test for the same guarantee. Meter: `/usr/bin/log show --last 30s | grep -cE 'PauseIO|ResumeIO'` (absolute path — a zsh function shadows `log`).
- **`XCTAssertTrue(await f())` does not compile** — `'async' call in an autoclosure`. Hoist the await into a `let` first. Two separate agents lost a build cycle to this.
- **A claim about APPEARANCE requires LOOKING — a green suite is not a design check.** This was
  violated twice on 2026-07-28, the second time hours after documenting the first. `TODO.md` claimed
  the validated Glass design was delivered because the deployment target had been raised; the user
  opened the app and saw stock SwiftUI. The appearance work was then done, and the status line was
  rewritten to "the window now looks like the design you validated" on the strength of 262 green
  tests, with nobody having looked. Rejected on sight. The error is substituting the AVAILABLE proof
  for the REQUIRED one: a passing suite, N `glassEffect` call sites and a symbol in the binary prove
  the code RUNS, never how it READS. Write "unverified" when nobody has looked. Correcting a
  claim-without-evidence with a different claim-without-evidence is not a correction.
- **Never `screencapture` the full screen on this machine.** A full-screen capture records
  everything on the display, and the one attempt captured confidential content unrelated to this
  project. Deleted immediately; the exposure was real. Target the app window alone
  (`screencapture -l <windowid>`, or `-R` on its frame), and prefer asking the user to look
  over automating a capture of a screen that holds other work.
- **Never explain the BUG5 staleness gate away — run `bash swift/build.sh` and see.** It fired on
  2026-07-30 and was dismissed as *"a false positive: that file is excluded from the audio binary
  target (`Package.swift:19`)"*. It is not scoped to a target: `scripts/check.sh:34` is
  `find swift/Sources -name '*.swift' -newer "$shipped"`, so ANY Swift edit fires it, by design. The
  run had genuinely failed. The over-broad scan is the point — one rebuild is cheaper than reasoning
  about which target holds which file and being wrong once, which is exactly how BUG5 shipped a
  three-day-old binary past a green suite. Testing the hypothesis costs one command.
- **An observation is not yet a defect — and the review loop needs an UNLOCKED screen.** Looking is
  necessary and it is not sufficient: of seven findings from the first visual review, four died on
  re-checking, including the one filed as priority 1. "The window is light, the mockup is dark" was a
  fact about the MACHINE (system in light mode, no `preferredColorScheme` anywhere, so the app was
  obeying correctly) and "fixing" it would have overridden the user's auto-switch setting. Two more
  were features already built and wired but invisible because *nothing* in that column rendered — no
  meeting is selected by default. **A screenshot shows a system state and a code state superimposed
  and says nothing about which produced what.** The one finding that survived was the one
  REPRODUCED, not merely seen. Also: `screencapture -l` cannot photograph a window on a LOCKED
  screen (the window reports `onscreen=no`, AX count drops to 0), so use
  `bash scripts/ui-evidence/render.sh /tmp/ui-render` — off-screen, works locked. Know its blind
  spots before trusting it: `glassEffect` renders **byte-identically to no glass at all** off-screen,
  and the selected row paints opaque black over its own icon, label and badge, so a badge present in
  the app is absent from the render. Never certify glass or materials on a render; see `APP_TEST.md`.
- **A test can encode a bug as a requirement.** `testTheCountKeepsItsInflectionMarkup` asserted
  `"^[1 non ancré](inflect: true)"` as correct output, reasoning that "SwiftUI does the
  pluralisation" — but SwiftUI resolves that markup only in a literal or `LocalizedStringKey`, never
  in a `String` variable handed to `Text(_:)`. So the sibling call site printed the raw markup to the
  user, and a correct fix turned the test RED. Second instance after `speakerEndingIn0GetsBlue`
  asserted a colour collision. The tell is a test whose rationale explains why the wrong output is
  right.
- **A filter needs tests in BOTH directions.** A guard meant to stop an LLM apology becoming a
  meeting title matched bare common words (`transcript`, `need`, `please`) and erased **7 of 10**
  legitimate titles — in an app whose meetings are often about transcripts. Both its tests passed:
  both asserted only that refusals are caught. What fixed it was structural rather than lexical (a
  refusal is a SENTENCE, a title is a PHRASE: first-person opening, question mark, imperative,
  sentence punctuation mid-string) — 1/14 false positives against 7/10. And put the guard where the
  signal still exists: slugification destroys the punctuation the structural test needs, so it runs
  on the RAW title.
- **You CAN look at the window yourself — do it before claiming anything about appearance.**
  `open "clew://library"` then `bash scripts/ui-evidence/capture.sh Clew /tmp/ui-ev`,
  then Read the PNG. The capture resolves the window id by OWNER and passes it to `screencapture -l`,
  so it cannot capture the screen; activate the app first, because `screencapture -l` fails on a
  window that is not frontmost. The first real review (2026-07-30) found seven gaps a green suite
  never would, starting with the window being LIGHT where the validated mockup is DARK. Two limits:
  the AX tree returns 0 lines until `.accessibilityIdentifier` is added, so findings are visual and
  not measured; and whether it READS well is still the user's call.
- **The environment a Finder-launched app inherits is not your shell's.** The app recorded a real
  meeting it could never transcribe: `ffmpeg` lives in `/opt/homebrew/bin`, launchd's PATH does not
  include it, and `PipelineRunner` passed that PATH through — so transcription worked from a terminal
  and failed from the app, *after* the audio existed. Worse, the first test for the fix asserted
  against `ProcessInfo`'s PATH, which in a terminal-run suite already has Homebrew, so it stayed
  green with the fix removed. When a defect is "works for me, not in production", the test must
  reproduce the ENVIRONMENT, not just the code path.
- **Run the full suite as the LAST action before reporting done.** Both a builder and I reported green on a red tree in the same batch: the checks were real, they just predated the final edit. And when auditing a working tree someone else is editing, check the file mtime before believing a failure — five phantom reds in one evening, including a whole-module collection error that self-resolved in 35 seconds.
- **Trace a feature to its consumer.** `silence_timeout` was correctly plumbed through four layers into a callback nobody had assigned, so the app never auto-stopped while every individual link looked right.
- **No new code comments** (self-documenting names; the "why" goes in commits / NOTES.md / LESSONS_LEARNED.md). Commit to `main`; no hardcoded secrets/tokens.

## Commands

```bash
bash scripts/check.sh                # everything at once: lint, format, both suites, release build, shell syntax
uv run pytest                        # run all tests
uv run pytest -v                     # verbose
uv run pytest -v -k test_search      # run a specific test module
uv run pytest tests/test_search.py::TestRankMeetings::test_speaker_boost   # single test (path form)
uv run pytest -v -k "TestRankMeetings and test_speaker_boost"              # or -k, which needs `and`, NOT `::`
uv run ruff check src/ tests/        # lint
uv run ruff format src/ tests/       # auto-format

cd swift && swift test               # Swift suite (capture lib + menu-bar app)
bash swift/build-app.sh              # build, sign AND install to /Applications
SKIP_INSTALL=1 bash swift/build-app.sh   # stop at dist/ without installing
```

There is no CI. GitHub Actions never ran on this repo — 29 consecutive
`startup_failure`s with zero jobs created, on a private repo where `macos-14`
minutes bill at 10x. `scripts/check.sh` is the replacement and runs the same
checks locally, plus a release build (the debug build can pass while the release
build fails on optimiser-sensitive code). Run it before pushing anything
non-trivial.

`build-app.sh` installs on purpose and fails if the installed binary differs
from the one just built — a real call was once recorded against a stale bundle
because building and installing were separate steps. Always launch the
installed copy (`open /Applications/Clew.app`), never the inner binary.

## Architecture

**clew** (formerly ownscribe; the console script is still also installed as `ownscribe` for muscle memory) is a CLI tool for local meeting recording, transcription, and summarization. The main pipeline is: Record → Transcribe → Summarize → Output.

### Plugin systems with abstract base classes

Each stage has a base class in its subpackage and one or more implementations:

- **Audio** (`audio/base.py`): `CoreAudioRecorder` (macOS, wraps a Swift binary in `swift/`) and `SoundDeviceRecorder` (cross-platform fallback). Selected in `pipeline.py:_create_recorder()`.
- **Transcription** (`transcription/base.py`): `WhisperXTranscriber` (single impl). Data models (`Segment`, `Word`, `TranscriptResult`) live in `transcription/models.py`.
- **Summarization** (`summarization/base.py`): `LlamaCppSummarizer` (default, local inference via `llama-cpp-python`), `OllamaSummarizer`, and `OpenAISummarizer`. Factory is `summarization/__init__.py:create_summarizer()` — used by both `pipeline.py` and `search.py`.
- **Output** (`output/`): `markdown.py` and `json_output.py`, selected by `config.output.format`.

### Key modules

- **`cli.py`** — Click command group. Console-script entry point: `clew.cli:main` (runs the legacy-path migration, then the `cli` group below; `ownscribe.cli:cli`'s old direct-to-group wiring is gone, tests still drive `cli` directly via `CliRunner` so migration never touches a real path). All subcommands (`ask`, `transcribe`, `summarize`, `resume`, `devices`, `apps`, `config`, `cleanup`).
- **`pipeline.py`** — Orchestrates the record → transcribe → summarize flow. Creates timestamped output dirs (`~/clew/YYYY-MM-DD_HHMM_slug/`).
- **`search.py`** — Two-stage LLM search over meeting notes. Stage 1 scores summaries for relevance, stage 2 synthesizes answers from full transcripts. Has keyword fallback and quote verification. Helper functions return data; only `ask()` calls `click.echo`.
- **`config.py`** — Dataclass hierarchy (`Config` → `AudioConfig`, `TranscriptionConfig`, `SummarizationConfig`, etc.). Loaded from `~/.config/clew/config.toml` with env var overrides (`HF_TOKEN`, `OLLAMA_HOST`).
- **`summarization/prompts.py`** — Built-in prompt templates (meeting, lecture, brief) plus search prompts. Users can define custom templates in config TOML.

### Testing conventions

- Uses `pytest` with `pytest-httpserver` for mocking HTTP APIs (Ollama, OpenAI).
- Shared fixtures in `conftest.py`: `sample_transcript`, `diarized_transcript`, `synthetic_wav`.
- Tests use `FakeSummarizer` (in `test_search.py`) or `unittest.mock` for pipeline tests.
- Markers: `@pytest.mark.hardware` (auto-skipped in CI), `@pytest.mark.macos` (auto-skipped on non-macOS).
- When mocking the shared summarizer factory in pipeline tests, patch `clew.pipeline.create_summarizer` (it's imported at module level).

### Important notes

- **`PipelineProgress`** (in `progress.py`) is the live checklist TUI that shows transcription, diarization sub-steps, and summarization with animated spinners/progress bars. It should not be replaced or simplified.
- **`README.md`** should be kept in sync when CLI commands are added or changed.
- **Four project skills hold the traps that cost real failures. Read the relevant one BEFORE working, not after a green run:**
  - `.claude/skills/swift-suite-hygiene/SKILL.md` — how to run and trust the Swift suite. Two frameworks print two separate totals; `tail` destroys the number; a run past 90s is a deadlock, not a slow build; `timeout` does not exist here and returns a green from a command that never ran.
  - `.claude/skills/ownscribe-pipeline-traps/SKILL.md` — which binary production actually loads, why absent must never render as zero, the dependency dead-ends with no config-only fix, and which fixtures are real user data.
  - `~/.claude/skills/test-sabotage-audit/SKILL.md` (user scope) — the audit that finds tests guarding nothing. Sabotage the production function, not the test.
- **Before touching anything under `swift/`, the capture backend or the mute path, read `.claude/skills/macos-audio-capture/SKILL.md`.** It holds the macOS facts that cost real failures: why the CoreAudio tap beats ScreenCaptureKit on permissions, why the embedded Info.plist is load-bearing (its absence froze Zoom), the verify-after-set mute guard for the documented AirPods bug, why restore-unmute must cover every exit path, and why the signing cert must never be recreated.
- **Transcription threads**: whisperx defaults to `threads=4`; this project sizes CTranslate2 to the performance-core count instead (`transcription.cpu_threads` to override). Do not raise it to `os.cpu_count()` — including the efficiency cores measurably slows the batch.

## Style

- Python 3.12+. Ruff with line-length 120.
- `from __future__ import annotations` in all modules.
- Lazy imports for heavy dependencies (whisperx, ollama, openai, llama_cpp) — imported inside functions, not at module level.
- Helper functions return data; orchestrator functions (`ask()`, `run_pipeline()`) handle all `click.echo` output.
