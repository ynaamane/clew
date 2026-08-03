---
name: swift-suite-hygiene
description: How to run, trust and mutation-check this repo's Swift suite without producing a false green, a false red, or a 23-minute deadlock that holds the SwiftPM lock. Read BEFORE running `swift test`, before writing any Swift test, and before believing any Swift test result — yours or an agent's. Every item cost a real failure on this machine.
paths:
  - "swift/**"
  - "**/*.swift"
---

# The Swift suite — how to trust a result

The suite is fast (~40s) and green. That is exactly why the failures here are all
**epistemic**: a number that was never measured, a red that isn't a defect, a green from a
command that never ran. Do not re-derive these.

## Reading the totals — the trap I fell into twice in one session

`swift test` prints **two** independent summaries, because this package uses both frameworks:

- XCTest → one `Executed N tests, with 0 failures` line **per suite**, then a bundle total.
- swift-testing → one `✔ Test run with N tests in M suites` line.

The real total is the sum of the two frameworks. Summing every `Executed N tests` line
double-counts, because per-suite and per-bundle lines both match.

```bash
cd swift && swift test > /tmp/swifttest.log 2>&1; echo "exit=$?"
python3 -c "
import re, collections
log = open('/tmp/swifttest.log').read()
cases = re.findall(r\"Test Case '-\[(\S+) (\S+)\]' (passed|failed)\", log)
print('XCTest:', len(cases), collections.Counter(c[2] for c in cases))
print('swift-testing:', re.findall(r'Test run with (\d+) tests', log))
"
```

**A `grep` for the bundle total can select a PER-SUITE line instead.** `Executed 431 tests, with
9 tests skipped` (the bundle) and `Executed 3 tests, with 3 tests skipped` (one env-gated suite)
both match the same pattern, and both appear twice. `grep -E 'Executed [0-9]+ tests' log | tail -1`
can hand you **3** as "the suite" with nothing to indicate it is wrong. Cross-check instead:
count the individual `Test Case '-[...]' passed|failed` lines, and confirm
`passed + skipped == the bundle number`. Two methods agreeing is the check; one grep is not.

**Never pipe the run through `tail -N`.** The XCTest bundle total is followed by hundreds of
lines of per-test output, so `tail -8` shows only the swift-testing block — 19 tests — and a
`tail` inside a `> file` redirect writes the *truncated* text to disk, destroying the number
permanently. I did this twice in one session and briefly believed the suite was 19 tests.
Redirect the whole run to a file, then grep the file.

## `timeout` does not exist on this machine

`timeout 300 swift test` exits **127** — the binary is absent — and the harness reports
"completed (exit code 0)". That is a green from a command that never ran, and it is the
single most dangerous line you can type here. There is no `gtimeout` either. Background the
run and poll instead.

## A run past ~90 seconds is HUNG, not slow

The whole suite is ~40s. Past 90s, attach and read the reason rather than waiting:

```bash
lldb -p <pid> --batch -o "thread backtrace all"
```

**@MainActor view-host tests deadlock this project.** `AppState`, the fake runners and the
`XCTestCase` body are all `@MainActor` while XCTest pumps a CFRunLoop on that same thread, so
a test needing a specific three-way interleaving cannot force it with `Task.yield()` — the
continuation is never resumed and the test hangs forever instead of failing. Two attempts
cost 23 minutes and 6 minutes, each holding the SwiftPM `.build` lock and blocking two other
agents.

A deadlocking test is **worse than a failing one** — it cannot report, and it blocks every
build on the machine. Delete it, do not skip it. Extract the DECISION into a pure function
(`terminalPhase(after:completedWith:)` is the precedent: same claim, 7 tests, 0.001s, and it
mutation-checks cleanly) rather than choreographing the actors.

Never instantiate a SwiftUI `View` body in a test.

## Never touch real audio hardware

A test reaching `RecordingController.start()` must inject **both** `makeSystemCapture` and
`makeMicCapture`. A start-time seam is not enough: `MicCapture` holds
`private let engine = AVAudioEngine()` as a **stored property**, so the input device is
claimed when the object is *constructed*.

Three suites hijacked the mic this way. Measured: **0** CoreAudio `PauseIO/ResumeIO` cycles in
the 20s before a run, **7920** after, with the AirPods input forced to 24 kHz (the HFP
phone-call profile) instead of 48 kHz — which dulls playback in every app until macOS
renegotiates. The user noticed the degraded audio before any of us did.

```bash
/usr/bin/log show --last 30s | grep -cE 'PauseIO|ResumeIO'   # absolute path: a zsh function shadows `log`
```

A missing config file means mic **ON** (`mic ?? true`), so pointing a test at a temp
`homeDir` is a silent opt-in. Assert the default your tests inherit.

Genuine hardware needs go behind `OWNSCRIBE_TEST_REAL_MIC=1` / `OWNSCRIBE_TEST_REAL_MUTE=1`,
and keep a hardware-free test for the same guarantee rather than losing the coverage.

## Compile traps that cost a build cycle each

- **`XCTAssertTrue(await f())` does not compile** — `'async' call in an autoclosure`. Hoist
  into a `let` first. Two separate agents lost a cycle to this.
- **Subscripting an array in a test traps instead of failing.** `doc.utterances[2]` on a short
  array kills the whole `xctest` process and takes the run's results with it — five SIGTRAPs
  in one session came from agents' throwaway tests, not from production. Assert
  `XCTAssertEqual(doc.utterances.count, n)` first, or use `.dropFirst().first`.
- `.macOS(.v26)` does not exist in this toolchain's `PackageDescription` — the target is the
  string `"26.0"`. All five targets are pinned `.swiftLanguageMode(.v5)`; raising
  `swift-tools-version` to 6.0 surfaces 3 real strict-concurrency errors in the CoreAudio path.

## Mutation-checking: how to not fool yourself

A red→green transition proves nothing. Break the thing the test names and confirm it goes
red. Three tests in one batch passed against the code they claimed to guard.

**Sabotage the production function, not the test.** The highest-yield question is *does this
test INVOKE production, or does it rebuild production's input and assert on its own local
variable?* Stubbing `loadEnvelope()` to `return nil` — the feature completely dead — left all
**six** of its tests green, because they each re-implemented
`try? EnvelopeDocument(contentsOf:)` inline. Reading the diff would never show this.

Four false-result modes, all observed here:

| Symptom | Real cause | Guard |
|---|---|---|
| Mutation survives (false green) | Another agent rewrote the file seconds earlier; the build used its version | `stat -f "%Sm %N" <file>; date`, wait for ~40s of quiet, re-verify with `sed -n` that your edit is on disk |
| Instant reds in a `git worktree` (false red) | `bin/` and `.build` are gitignored, so the built binary is absent | The tell is the clock: 0.4s where a real capture takes 16s. Run `bash swift/build.sh` |
| Reds while auditing a live tree (phantom) | You read a file another agent was mid-write | Check mtime before believing a failure. Five phantoms in one evening, incl. a whole-module error that self-resolved in 35s |
| Mutation "took" but nothing changed | Restoring with `cp` refreshed the mtime, so a staleness gate saw a fresh file | Verify the mutation landed on the property actually read — mtime, size, a symbol |

Shell cwd persists between calls. Use absolute paths — a relative `cp` after a `cd swift`
silently voided a mutation.

**Separate an assertion failure from a compile error before believing a red.** A mutation that
fails to compile produces a red that proves nothing about the guard. Grep every `error:` line on
each mutation run and check they are assertions: on one run here all 9 `error:` lines were
assertions, which is what made that kill real. And the harness will report **"exit code 0"** for
a chain whose trailing `echo` succeeded — on every run of one audit — so the mutation's true
status lives only in a captured variable (`MUT_EXIT=$?`), never in what the harness announces.

**Auditing a tree someone else is committing to means every snapshot may already be stale.** Two
readings in one session were correct when taken and wrong when reported: an `AppState` mtime, and
a "1 uncommitted / 1 unpushed" that had both landed by the time the message arrived. Before
reporting tree state as a finding, re-read it in the same breath — `git rev-parse HEAD origin/main`
and `git status --porcelain` cost nothing.

**A survived mutation, reported, is worth more than a passed one.** One agent predicted its
call-site mutation would go red, ran it, got green, and published that against its own
prediction. That honest report was worth more than two "COMPLETE" claims I had to sabotage
myself. An agent that reports only green results has not run the mutation that would
embarrass it.

## A view-host test is not the only way to reach a render

"This can only be verified by instantiating the View, and that deadlocks, so it is untestable"
is **half** right and it let a live bug through. The rendering contract is readable from the
SOURCE, which is what `GlassPlacementTests`, `LibrarySidebarTests` and
`SearchPlacementDecisionTests` already do — read the `.swift` file, assert on what it contains.

The bug it missed: `Text(state.headline ?? state.message)` renders the headline INSTEAD of the
message, so for the one banner state that sets a headline the recovery instruction became
unreachable data — the user saw "CLI absent" and nothing said `./rec.sh redo` exists. The
data-level test `banner.message.contains("./rec.sh redo")` stayed **green** the whole time: the
string was in the struct, and no view path could display it. Same shape as
`UnanchoredClaimBadge` shipping with 4 green tests and 0 callers.

So when a claim is genuinely about the view, prefer a source guard over declaring it
unverifiable — and write the mutation into the failure message, because the next person's
instinct will be to "simplify" the very line the guard exists to keep.

**A proximity assertion is not a target assertion.** `GlassPlacementTests` asserted that
`.scrollContentBackground(.hidden)` appears within 6 lines above `.glassEffect()` — which is
true whether the glass sits on the `List` or on its container. On that guard's word, the TODO
recorded "glass moved to the container" (`f0e7bd6`) as CODE DONE while `LibraryWindow.swift`
still chained the modifier on the `List` — the exact configuration the original deformed-rail
finding blamed. Found only by the 2026-08-03 audit reading the attachment point itself; third
intention-recorded-as-delivery in this repo. When a source guard exists to pin WHERE a modifier
is applied, it must name the RECEIVER (parse which declaration the modifier chain attaches to),
not assert what happens to sit nearby.

Two sequels from the same afternoon, same family:
- **The line never moved — the target did.** A rewrite dissolved the container a modifier was
  chained under, silently changing its receiver from the ZStack to the ScrollView while the
  modifier's own line stayed textually identical. The author honestly reported it "unmoved".
  A claim about a modifier is a claim about its receiver. Caught by lane cross-review, not by
  any test.
- **A guard's text pattern must match the CALL FAMILY, not one spelling.** The content-layer
  guard searched for the bare literal `.glassEffect()`, so `.glassEffect(.regular, in: .rect(...))`
  slipped past it — the guard declared "no glass" on a file gaining MORE glass. Proved live:
  an explicit-shape violation on the transcript PASSED under the old matcher, failed under
  `.contains(".glassEffect(")`. When you change a call's spelling anywhere (adding arguments,
  a label, a wrapper), grep every guard that matches it by string.

## An injected seam can end up asserting itself

When every test for a behaviour **injects** the thing it is testing, the production default is
unguarded — and the whole suite passes if that default is silently a no-op. Measured:
`TerminationSignalHandlers` had ten tests, all injecting `ignoreDefaultDisposition`, and
replacing the shipped default with `{ _ in }` turned **zero** of them red. The seam was
asserting itself.

The fix is one test that reaches past the seam to the real effect — here, reading the signal
disposition back through `sigaction(2)` (`SIG_IGN` bitcasts to **1**, `SIG_DFL` to **0**;
verified on this machine before being encoded). It kills that mutation while the other ten
stay green.

So for any injected seam, ask: **is there one test that exercises the REAL default?** If a
`?? { real thing }` can be replaced by `?? { }` with the suite still green, the answer is no.

**And the flip side, which is live here: a production default that is right for the APP can be
wrong for the TEST PROCESS.** `AppState.init` runs `signal(SIGTERM, SIG_IGN)`, correct for a
shipping app. Measured in the suite: an `AppState` built without the injected seam moves this
process's dispositions from `[0, 0]` to `[1, 1]` — SIGTERM *and* SIGINT ignored — so the xctest
runner becomes unkillable by `kill` and needs SIGKILL. **13 test files** still do it
(`TestRunnerSignalHygieneTests` pins the count and names them). Any test that mutates
process-wide state must restore what it found.

**Blast radius, measured rather than assumed:** the parent shell reads `[0, 0]` both before and
after a full suite run, so the leak is confined to the `xctest` child and does NOT escape to the
machine. Worth stating, because "the suite alters the machine" would overstate it — unlike the
mic hijack, which genuinely did reach the hardware (0 `PauseIO/ResumeIO` cycles before a run,
7920 after, with the input forced to 24 kHz).

The shared lesson is narrower and still holds: **a green suite says nothing about what the suite
did to the process it ran in.** Neither of these shows up as a failing test.

## Never `git commit --amend` in this working tree

Three lanes commit to one checkout. `--amend` acts on whatever HEAD is **now**, not on the
commit you think you are fixing: amending to correct a number in my own commit rewrote a
peer lane's commit message, because its commit had landed in the seconds between. The code
survived, the authorship did not; restored with `git reset --soft <parent>` + a fresh commit.

Same family as the `git add -A` ban — any command that acts implicitly on "current state" acts
on someone else's work here. Check `git log --oneline -1` before amending, or just don't.

## Adding a protocol requirement is a free census of your fakes

Putting `cancel()` on `PipelineRunning` broke **3** test fakes at compile time
(`FakePipelineRunner`, `StubPipelineRunner`, `EventEmittingRunner`). That is the protocol doing
its job, and it is strictly better than the alternative that was tried first: calling through
`(pipelineRunner as? PipelineRunner)?.cancel()`. The cast compiles, the seam appears to exist,
and **no test fake can ever observe the call** — a spy would prove the phase changed while the
child process kept transcribing for minutes.

When a new behaviour must be observable in tests, put it on the protocol and fix the fallout.
A conditional downcast at a seam is how a feature becomes unobservable.

## Tested helper, untested call site

`BadgeText.badgeText(for:)` is well covered, but `grep -rn "LibraryWindow" swift/Tests/` is
**empty** — so reintroducing `?? "0"` at the render site survives the entire suite. That
render-site `?? 0` is what silently defeated a deliberate `Int?` three commits after it was
chosen.

When a type encodes "unknown", **grep every render site for `??`** before believing the
guarantee holds. Closing these needs a view-host test, which is the deadlock above — so some
are accepted as review-guarded and NAMED in `TODO.md` rather than pretended closed.

## Never run `swift/build-app.sh` from an agent

It `rm -rf`s `/Applications/MeetingScribe.app`, which holds live TCC permission grants keyed
to a signing cert that **must never be recreated** (a new cert = new identity = macOS resets
every grant). Destructive and irreversible. `swift/build.sh` (builds `bin/ownscribe-audio`) is
safe.

`strings` does not surface accented or non-ASCII Swift literals — it produced a false "stale
bundle" alarm on a bundle that was current. Use `nm -a` on the symbol table.
