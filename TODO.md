# TODO — meeting-scribe

## WHAT IS ACTUALLY LEFT (2026-07-30)

Everything below this block is history and traps worth keeping. This is the open list.

### 0. THE DESIGN HAS NOW BEEN LOOKED AT (2026-07-30) — and it is wrong, as you said

First actual visual review in this project's history. `open "ownscribe://library"` +
`screencapture -l <windowid>` + reading the PNG.

**⚠️ RE-CHECKED THE SAME DAY: FOUR OF THE SEVEN FINDINGS BELOW WERE WRONG**, including the one
filed as priority 1. They were struck rather than deleted, because the failure mode is worth
more than the list: *I read a screenshot and attributed an ENVIRONMENT state, and two invisible
columns, to the code.* Looking is necessary and it is not sufficient — an observation still
needs a mechanism before it becomes a defect.

1. ~~**The window is LIGHT; the validated mockup is DARK.**~~ **MIS-DIAGNOSIS — there is nothing
   to fix, and "fixing" it would have broken light mode.** The machine is IN light mode:
   `AppleInterfaceStyle` is absent from the global domain, `System Events → dark mode` returns
   **false**, and `AppleInterfaceStyleSwitchesAutomatically` is **1** (auto day/night switching).
   The app carries no `preferredColorScheme` and no `NSRequiresAquaSystemAppearance` anywhere in
   `swift/Sources/` or either Info.plist — so it is OBEYING the system, which is correct
   behaviour. It renders dark properly when told to: proven by rendering the real view tree under
   `NSAppearance(named: .darkAqua)`. `design/direction-b-glass.png` is dark because the machine
   was dark when it was mocked up. **Do not hardcode dark** — that would override an explicit
   user setting and break the light half of an auto-switching Mac.
2. **The sidebar is visually deformed** — a huge rounded white blob, an oval wider than its
   column, bleeding past the bottom edge, with the selected row rendered as a black pill. Cause:
   `.glassEffect()` sits on the `List` (`LibraryWindow.swift:36`) rather than on a container, so
   it clips itself into a capsule instead of backing the rail. **CONFIRMED by independent
   reproduction** off-screen from the real view tree, so this one has a mechanism, not just a
   sighting. The mockup treats the rail as a container background
   (`mockup.html:95` — `background: var(--bg-sidebar); backdrop-filter: blur(28px)`).
3. ~~**Speaker avatars are absent.**~~ **WRONG — they are built and wired.**
   `MeetingDetailView.swift:129` renders an 18pt coloured disc via `SpeakerAvatarStyle`
   (`:141-150`).
4. ~~**No RMS envelope strip.**~~ **WRONG — also built and wired.**
   `MeetingDetailView.swift:15-19` draws `EnvelopeStrip` whenever `envelope.json` exists.
5. **The right column is ~60% empty** — and this is the finding that explains 3 and 4. No meeting
   is selected by default (`LibraryWindow.swift:8`), so the detail column shows
   `LibraryEmptyState` and everything in `MeetingDetailView` is off-screen. Avatars and the
   envelope strip were reported "absent" because **nothing in that column was rendering at all.**
   So selecting a meeting by default is not cosmetic: it reveals two features already paid for.
6. **Five rows read "Sans titre"** — slugless directories throw away the time they do have.
7. **The search field renders top-right, marooned from "Réunions"** — the observation stands; the
   first diagnosis and the first FIX proposal were both wrong. It is not in the detail column: it
   is attached to the list column (`LibraryWindow.swift:113`) with `placement: .toolbar`, which
   hoists it into the window toolbar. And it is **not a one-argument change** — I rendered
   `.toolbar`, `.sidebar` and `.automatic` side by side off-screen and all three produced
   **byte-identical** output (55218b ×3, `/tmp/win-spike/pl-*.png`), i.e. on macOS
   `NavigationSplitView` puts a `.searchable` field in the toolbar whatever you ask for. Putting a
   search box in the list-column header the way the mockup does (`mockup.html:112`, inside
   `.list-hdr`) therefore means **not using `.searchable`** for it — a plain `TextField` in a
   header view above the `List`. That is a real change with a real trade-off (losing the system
   search affordances, `⌘F`), so it needs a decision, not a patch.

What DOES match: the amber/green pills (`2 non ancrés`, `3 actions`) are the mockup's style,
summary excerpts render, search exists, and "non vérifiée" appears correctly on unchecked
meetings — the three things built earlier today.

**Two measurement notes.** `find ~/ownscribe -name envelope.json` now returns **2** files, not
the 1 recorded below — re-measure before quoting either. And the AX tree returned **55 lines**,
not 0: it carries every row's text with pixel frames (`@433,322 174x16`), which is enough to
measure spacing. What it lacks is `.accessibilityIdentifier` on the *interactive* views, so
elements can be read but not reliably ADDRESSED.

**⚠️ THE `screencapture` LOOP IS BLOCKED WHEN THE SCREEN IS LOCKED — and it was, minutes later.**
`ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked` → `Yes`; the library window then reports
`onscreen=no`, `AXWindow` count drops to **0**, and `screencapture -l` refuses it. So the
documented review loop silently requires the user to be sitting at an unlocked machine, which is
the opposite of reviewing autonomously. Replacement being built (task #34): an off-screen
`NSWindow` + `NSHostingView` + `cacheDisplay`, which works locked, renders both appearances via
`NSAppearance`, and reproduces the finding-2 deformation. **Dead end, measured, do not retry:**
SwiftUI's `ImageRenderer` draws `List` as a yellow no-entry placeholder and `glassEffect` as
nothing — useless for precisely the two things under review.

### 1. The design — three ABSENT elements built on 2026-07-30; the rest still needs your eyes

Rejected twice with no part named. Rather than ask a third time, the mockup was diffed against the
sources, which turns part of the question into presence/absence facts that need no judgement:

- **There was no search field at all** — `grep -rn "searchable\|Rechercher" swift/Sources/` returned
  **zero**, while the mockup puts one in the list header and the target PNG shows a "Rechercher" pill.
  The window could not search its own library. Built: filters title + date, composes with the sidebar
  filter so typing inside "Avec actions" narrows it.
- **List rows carried no summary excerpt** (mockup `.i-s`, 2-line clamp), so the middle column never
  said what a meeting was ABOUT — its whole job when scanning the next morning. Built, 0.11 ms/row
  against the 0.44 ms sidebar reference, reusing `MeetingInspectorState.loadSummary` so `output.format`
  is honoured.
- **Badges were bare coloured text, not the mockup's filled pills.** Built as one component with
  amber / green / grey variants at the mockup's padding, radius and weight.

**What this does NOT settle.** These three were absent. The window HAS now been looked at (§ 0
above), which turned the judgement checks in `APP_TEST.md` § Design pass from unanswerable into
partly answered — but **whether it reads well is still yours**, and an image cannot supply that.

Do not accept "the tests are green" as progress here, from me or anyone: 413 green tests say nothing
about how the window reads. That substitution has already been made twice.

### 2. THE NEXT DESIGN BATCH, re-ordered after the § 0 re-check

Three items are struck: two were already built (invisible behind the empty detail column) and one
was a mis-diagnosis of the machine's own setting. What is left is smaller and better grounded.

0. ~~**A review harness that works with the screen LOCKED.**~~ **DONE.**
   `bash scripts/ui-evidence/render.sh /tmp/ui-render` → `library-light.png` + `library-dark.png`,
   off-screen, works locked, renders the REAL `LibraryWindow` (it lives in the test target so it can
   `@testable import OwnscribeMenuBar` — the standalone-`swiftc` route hits a type-checker timeout and
   pushes you toward a hand-built replica, which is how a harness ends up validating a design the app
   does not have). It prints its own CANNOT-VERIFY list; read it before trusting a render.
   **It found a user-visible bug on its first correct reading** (`4b1fcfc`): the header was printing
   `^[1 voix](inflect: true)` verbatim, guarded by a test that asserted the broken string.
1. ~~**Make the window honour Dark mode.**~~ **STRUCK — it already does; the machine is in light
   mode.** See § 0 finding 1. Hardcoding dark would override the user's auto-switch setting.
2. **Fix the sidebar glass** — move `.glassEffect()` off the `List` (`LibraryWindow.swift:36`) onto a
   container so it backs the rail instead of clipping into an oval that overflows its column. Now
   the top item, and the only § 0 finding independently reproduced.
3. **Decide what to do about the search field** — NOT a placement argument. `.toolbar`, `.sidebar`
   and `.automatic` all render byte-identically on macOS `NavigationSplitView` (measured, § 0
   finding 7): the field always goes to the toolbar. Matching the mockup's in-header search box
   means replacing `.searchable` with a plain `TextField` in a header above the `List`, which
   costs the system search affordances and `⌘F`. Worth asking whether the toolbar field is
   actually WORSE before paying that — it is where macOS apps normally put search.
4. ~~**Render speaker avatars.**~~ **STRUCK — built and wired** at `MeetingDetailView.swift:129`.
5. ~~**Draw the envelope strip.**~~ **STRUCK — built and wired** at `MeetingDetailView.swift:15-19`.
   (Both were invisible only because no meeting is selected — see item 6.)
6. ~~**Select the most recent meeting by default.**~~ **DONE** (`46e1810`) via a pure
   `LibrarySelection.resolve(current:shown:)` — nil→first, filtered-out→first visible, empty→nil, and
   a **still-valid selection stays UNCHANGED** so a finishing pipeline cannot yank you out of what you
   are reading. Confirmed by render: the right column now shows résumé, points clés, actions, pistes,
   the waveform AND the speaker avatars, i.e. items 4 and 5 above were revealed rather than built.
7. **Give slugless meetings a real title** — IN PROGRESS, one round still open. `ba9e6ad` added the
   fallback chain slug → first non-backchannel transcript line (60 chars) → time, and the LLM-refusal
   guard is DONE and verified (1/14 false positives, 0/7 false negatives; `3dffe4d`). What remains is
   legibility: five of nine rows have no transcript, so they render as a bare clock time with the
   **same time repeated in the subtitle directly beneath** (`15:37` over `29 Jul · 15:37`). "Sans
   titre" was uninformative; this is redundant, which scans worse. Fix in flight: when the title IS
   the time, the subtitle shows the date alone.
8. **Add `.accessibilityIdentifier` to the interactive views.** The AX tree already yields 55 lines
   with pixel frames, so spacing CAN be measured today; what identifiers add is stable ADDRESSING of
   controls. Lower priority than previously recorded.
9. **Sidebar labels truncate at the mockup's own ideal width** — `Avec acti…`, `Non ancr…`,
   `Non index…` at `ideal: 216` (`LibraryWindow.swift:35`), which is the mockup's `--sidebar` value.
   The icon plus badge eats the room the labels need. Measure what they need rather than guessing.
10. **The CLI-missing banner is unreadable** — a 200-character message inside the 216pt sidebar
    `ZStack` wraps to ~20 lines and overlaps the sidebar items. Visible whenever the CLI is absent.
11. **The inspector shows a bare `—` under every key point** where the mockup has a timestamp chip.
    Correct per `APP_TEST.md` (`—` means "no evidence found") but a column of dashes reads as broken
    rather than as unverified. Needs a legible empty state, not a data change.

After each: render both appearances with the § 2.0 harness and **read the PNG**. The old loop
(`open "ownscribe://library"` + `bash scripts/ui-evidence/capture.sh MeetingScribe /tmp/ui-ev`) still
works when you are at an unlocked machine — activate the app first, since `screencapture -l` fails on
a window that is not frontmost — but it cannot be the harness's only path.

### 3. Needs one real recording — one item left, and it is smaller than it was

- **The clickable evidence chip → scroll**: logic is verified against the real 27-July meeting via
  `/tmp/ms-fixture`, but the window reads `~/ownscribe` and no meeting there has usable anchors, so
  a fresh recording is the only way to see it in the app.

Closed on 2026-07-30 by a real 8-second test recording, which is the argument for making them:

- ~~**Whether the mic permission prompt appears.**~~ The record button worked; audio captured at
  48 kHz, `mic.wav` written, peak −17.8 dBFS (room tone, no speech — the user did not speak, as
  intended).
- ~~**Whether `resume` writes `anchors.json` + `envelope.json`.**~~ It does. All four artifacts
  produced.
- **But the recording exposed a worse bug, now fixed** (`a455646`): the pipeline exited 1 six
  seconds after stop with `ffmpeg is not installed`. A Finder-launched app inherits launchd's
  minimal PATH, which has no `/opt/homebrew/bin`, so **transcription worked from a terminal and
  could never work from the app** — and the failure lands after the audio exists. Fixed by
  resolving the child's PATH rather than special-casing ffmpeg.
- **Cosmetic fallout, NOT fixed:** an empty transcript makes the summariser reply "I'm sorry, but I
  need the transcript…", and that reply becomes the directory name — one meeting on disk is now
  called `2026-07-30_1141_sure-please-provide-the-transcript-of-the-meeting`, and it shows in the
  window as a meeting title. Guard the slug against a refusal/apology, or fall back to the
  timestamp when the transcript is empty.

### 3. The 2026-07-29 sweep list — 6 of 8 CLOSED on 2026-07-30, 2 still open

Fixed, each mutation-verified. Five builders were killed mid-task by an API stream stall; their work
survived only because it was on disk, and **every one of the six lots needed correction before it
could be trusted**
— which is the argument for reviewing a dead agent's output rather than merging it.

- ~~**`checkHasAudio` reads only the first 48,000 frames.**~~ **CLOSED, and it was LIVE, not
  "suspected".** One second at 48 kHz. Measured through production's own `checkTracks`:
  `~/ownscribe/2026-07-27_1531/recording.wav` is a real 238.7s recording, whole-file peak 0.999,
  first audible sample at **5.33s** — it reported `hasContent=false` and wore the BUG4 ⚠ that means
  "your recording failed". `2026-07-27_1352` is silent end to end and correctly still warns. That
  pair is the discriminator. Now a chunked full scan with early exit; worst case (a silent file,
  which cannot exit early) measured **0.25s**. A bigger fixed window was rejected — same bug, longer
  fuse.
- ~~**`openAudioFileWithFrames`'s zero-frame branch is uncovered.**~~ **CLOSED** — both branches
  covered; accepting zero-frame files turns the new test red.
- ~~**`ProgressEvent.detail` is decoded then discarded.**~~ **CLOSED.** A detail now updates the
  detail alone, keeping the step and fraction it arrived under — a detail event carries no fraction,
  so overwriting would reset the bar to indeterminate. `.complete`/`.fail` stay no-ops **on purpose**,
  now pinned by a test: assigning a terminal phase from the progress stream is what once let a
  finishing pipeline clobber a live recording.
- ~~**`MeetingRow` merges two of the three anchor states.**~~ **CLOSED** — the row now says
  "non vérifiée" in secondary text, deliberately not amber: unchecked is unknown, not bad. All six
  meetings on disk are in that state, so the library used to read as fully verified.
- ~~**The sidebar badge is an unqualified lower bound.**~~ **CLOSED, with a second defect found
  underneath.** It shows "1+" when any meeting lacks the data. But zero-known-with-unknowns first
  rendered **"0+"**, which reads as "no problems, plus some unknowns" when the truth is that nothing
  was checked — and that is the only path visible on the real disk. Zero-with-unknowns now renders
  NO badge; a real zero over fully-checked meetings still renders "0", because that one is
  information.
- ~~**`WindowActivationPolicy.resetForTesting()` is test-only production code.**~~ **CLOSED** — the
  reset hook was a symptom; the disease was process-wide mutable state. Now an instance with an
  injected apply-policy closure. ~~`GlobalHotKeyRegistration.unregister()`~~ deleted (no callers,
  `deinit` does the same work).
- ~~**`_capture_prep_output` is dead and three tests patch it.**~~ **CLOSED** — wrapper deleted, the
  three tests patch `_capture_download_output` (what `prepare_models` actually reaches) and each
  asserts the call happened, so the inertness cannot return silently. Renaming the target kills all
  three by name; against the old version the same mutation left them green.

**Still open, deliberately — the two the stalled agent never reached:**

- **`PipelineRunner.cancel()` still has no caller**, so a multi-minute transcription cannot be
  stopped. Decide: wire it to a control, or delete it. If wired, it must not leave `phase` stuck on
  `.processing` and must not clobber a phase that has already moved on.
- **`registerTerminationSignalHandlers` still has zero test references** (`AppState.swift:108`) —
  the SIGTERM/SIGINT path to `restoreUnmutedOnQuit`, the highest-blast function in the app. Needs a
  seam so registration and the handler body are testable without raising a real signal, and without
  adding a test-only method to production.

**Two traps this batch produced, both worth keeping:**

- **A test can pass while the production function it names is fully sabotaged.** Four badge tests
  computed `count` and `hasUnknowns` themselves and fed them to `badgeText`, never calling
  `LibrarySidebar.sections`. Proof: sabotaging `sections()` to always claim complete data left **all
  21 tests green**. Rewritten through `sections()`, the same sabotage kills 2.
- **A new function with tests and no callers is not a fix.** `UnanchoredClaimBadge` shipped with 4
  green tests, zero production callers, and logic that returned nil for BOTH `nil` and `0` — it
  relocated the merge it was meant to remove. Same shape as `silence_timeout`. Trace a feature to its
  consumer.

### 4. Deferred by earlier decision, unchanged

Per-speaker envelope lanes · live transcript preview while recording · live vumeters in the menu bar
(`AudioLevels.computePeakLevel` already computes the value and only writes it to `stderr`) ·
diarization/language/output-dir in Settings (still TOML-only) · `AppState` re-reading config after
Apply (it reads once at launch, so the pane says restart) · the `.badge()` render site, which needs a
view-host test — the thing that deadlocked this project twice for 29 minutes holding the SwiftPM
lock · the AirPods mute case, irreducibly manual · MPS diarization until the token pass clears it.

---

## Status: 636 Python + 413 Swift green, all 10 gates green (`git log --oneline origin/main..main | wc -l` for what is held back).

Measured 2026-07-30 on the merged tree after eight lots landed: `bash scripts/check.sh` → **`CHECK=0`
read from a captured variable, 0 failed gates**, including the release build. Swift → **367 XCTest
(`Executed 371 tests, with 4 tests skipped and 0 failures`) + 46 swift-testing = 413**. Python
**inside check.sh** → **636 passed, 7 deselected** (`check.sh:23` runs `-m "not hardware"`).
`/usr/bin/log show --last 10m | grep -cE 'PauseIO|ResumeIO'` → **0** after the full run, so nothing
reached the real input device.

The BUG5 staleness gate fired on the first attempt of two separate runs — correctly, since the lots
edited Swift sources —
and the harness reported **exit code 0 while a gate had FAILED inside**, which is exactly why the exit
status must be captured into a variable and read from the log rather than taken from the runner. Fixed
with `bash swift/build.sh`.

Measured 2026-07-29 on the merged tree, not quoted — and I first typed 355 here before running the
command, which is the fourth time today that writing a number failed as a separate step from
measuring it. `bash scripts/check.sh` → **`CHECK=0`, 0 gates failed**, including the release build;
Python **inside it** → **636 passed**, because `check.sh:23` runs `-m "not hardware"`. A Python count
without its invocation is meaningless — an independent reviewer and I once reported 635 and 629 for
the same tree before reconciling them. Swift → **330 XCTest
(`Executed 334 tests, with 4 tests skipped and 0 failures`) + 23 swift-testing = 353**. The 4 skips
are the hardware-gated tests, by design. `/usr/bin/log show --last 5m | grep -cE 'PauseIO|ResumeIO'`
→ **0** after that full run, so nothing in the suite reached the real input device.

Read the exit status from a captured variable, never off a pipeline: on the first run of this batch
the harness reported "exit code 0" while `CHECK=1` sat in the output, and the real failure was the
BUG5 staleness gate (`bin/ownscribe-audio` older than `SettingsView.swift`). Fixed with
`bash swift/build.sh` — that gate firing is it working, and it fires on ANY Swift edit, including
menu-bar-only ones the capture binary does not contain.

Both frameworks must be counted: `swift test` prints an XCTest total AND a separate
`Test run with N tests` line for swift-testing, so every "276 Swift" in this file's history was
XCTest-only. And do not pipe the run through `tail` to read a total — it truncates the summary away,
and inside a `> file` redirect it destroys the number on disk.

**⚠️ THE DESIGN IS NOT GOOD. Rejected on 2026-07-28, and rejected AGAIN on 2026-07-29** after a
rebuild that shipped 11 changed files. Nothing was done to the design between those two rejections —
the second one confirms it, it does not add information. Still nobody has named a part.

**And the 2026-07-29 rejection came with a defect that made the app unusable, which is the more
useful signal:** clicking Record reported missing permissions and refused to start. Root cause, found
in the log rather than guessed: `AVCaptureDevice.authorizationStatus` returns `.notDetermined` until
something asks, `preflightMicrophoneAccess` required `== .authorized`, and **no code in the app ever
called `requestAccess`** — `grep -rn requestAccess swift/Sources/` returned nothing. Since a missing
`[audio]` section means `mic ?? true`, the mic was always required, so the record button could never
work on a machine that had never answered a prompt it was never shown. The preflight's detail text
goes to `stderr`, which a Finder-launched app has nowhere to display, so the banner said "System
Audio Recording **or** Microphone" without naming either. Fixed: the app now requests when the answer
is unanswered, fails closed on a real denial, and names the missing permission with its exact Settings
path. Mutation-verified four ways.

And read how this line got here, because the mistake is worse than the design: earlier
on 2026-07-28 this file claimed the Glass direction was delivered, on the reasoning that
raising the deployment target to macOS 26 made standard components adopt Liquid Glass
automatically. The user opened the app, saw stock SwiftUI, and said so. That was corrected,
`glassEffect()` was applied to the sidebar and inspector, avatars and an envelope strip were
built — and then **the exact same error was repeated**: this line was rewritten to say the
window "now looks like the design you validated", again with **zero visual verification**.
262 tests green is not a design check. It never was.

**The rule, and it has now been broken twice in one day:** a claim about APPEARANCE requires
LOOKING. Not a passing suite, not 3 `glassEffect` call sites, not a symbol present in the
binary. Those prove the code runs; they say nothing about whether it reads well. If nobody
has looked, the honest status line is "unverified", never "matches the design".

**What is NOT yet known:** which part of the design is wrong. "Pas bon du tout" is a verdict
on the whole, so the next step is to look at the window WITH the user rather than guess at
spacing or colour and iterate blind against a target nobody has seen.

**⚠️ BUG5 WAS STILL LIVE UNTIL TODAY, in the binary the pipeline actually runs.** The July fix landed in Swift and never reached production: `coreaudio.py` prefers `bin/ownscribe-audio` over anything in `.build`, `bin/` is gitignored, and only `swift/build.sh` copies into it — so the shipped binary sat three days older than the fix and still halved playback speed. Measured on one real dual-track capture: `bin/` gave `recording.wav` **12.81s @24000Hz** from 48 kHz sources; `.build/` gave **5.52s @48000Hz**. The signature is in your retained meetings — the two from July 24 are 24000Hz.

Fixed in `4be4e08`: `bin/` rebuilt, the e2e test now resolves the binary through production's own `_BINARY_CANDIDATES` and asserts the merged sample rate **equals** its sources', and `check.sh` gained a staleness gate that names the newer Swift file. **Any recording made before today from the CLI plays back at half speed — `./rec.sh redo <dir>` re-merges it correctly from the retained tracks.**

**The window now surfaces `.failed` and the unverified-mute warning** (`7c02399`, W0-7). A banner in the glass rail — never the content layer — with the decision in a pure `bannerState()`: an error outranks the mute warning, and the mute banner is deliberately **not dismissible**, because a warning that the call can still hear you must not be silenceable while it is true. `dismissFailure()` is what makes the error surface usable at all: `.failed` previously had no exit but a retry, and when the cause persists the retry re-fails. `scripts/check.sh` is the CI replacement — 9 checks, including the release build.

**THE TWO MUTE CHECKS THAT GATED EVERYTHING ARE DONE — automated, not deferred to you.** With the AirPods disconnected the built-in mic became the default, which removed the one case the suite cannot assert against (the documented macOS Bluetooth mute bug), so both checks were written as real hardware tests and passed:

```bash
OWNSCRIBE_TEST_REAL_MUTE=1 swift test --filter RealHardwareMuteTests   # 3 tests, 0 failures
```

- A mute you made yourself in System Settings **survives quitting the app** — the app does not silently undo it.
- A mute the app made **is undone on quit** — the mic is not left muted for other apps.
- Toggling through the app takes ownership even when the mute started as pre-existing.

Verified on the real device (mic `not-muted` before, three green, `not-muted` after) and mutation-checked: removing the `appOwnsMute` guard turns the pre-existing-mute test RED against real hardware, and the mic was still restored afterwards, which proves the teardown holds on the failing path too. `setUp` records the state it found, `tearDown` restores it and ASSERTS the restore, and the suite skips itself if the default input is Bluetooth.

**Real end-to-end tests now exist, not only unit tests.** `tests/test_real_capture_e2e.py` drives the shipped `ownscribe-audio` binary (5 tests, `@pytest.mark.hardware`, so `check.sh` skips them):

```bash
uv run pytest tests/test_real_capture_e2e.py -m hardware    # 5 passed
```

Writing them corrected three assumptions about the binary, which is the argument for having them: it has no `--duration` flag (it records until SIGINT, so the tests stop it the way `rec.sh` does), it prints usage on **stderr**, and it writes **IEEE float32** — which Python's stdlib `wave` refuses outright, so the tests read via `soundfile`, the same float32 `envelope.py` depends on. They also PLAY sound while capturing, which is load-bearing: the tap records what the machine OUTPUTS, so on a muted system it correctly produces a valid 48 kHz stereo float header with **zero frames**. My first version captured that silence and blamed the binary. Mutation: replacing `afplay` with a sleep turns 2 of 5 red.

**The test suite no longer touches your microphone.** Running `swift test` used to degrade the machine's audio: 0 CoreAudio PauseIO/ResumeIO cycles before a run, **7920 after**, with the AirPods Max input dropped to 24 kHz (the HFP phone-call profile) instead of 48 kHz — which dulls playback in every app until macOS renegotiates. Three suites reached the real input device. Fixed in `e51000f`; a full run now measures **0 cycles**. If you ever see the mic sitting at 24 kHz again, that is the symptom, and `/usr/bin/log show --last 30s | grep -cE 'PauseIO|ResumeIO'` is the meter (use the absolute path — a zsh function shadows `log`).

One test is deliberately skipped: the merge-failure path only runs with a live `MicCapture`, so it needs `OWNSCRIBE_TEST_REAL_MIC=1` and built-in hardware. A hardware-free test covers the same guarantee.

**⚠️ `b0ce8db` is COMMITTED BUT NOT PUSHED, deliberately.** It changes the system-wide mute path, and its central guarantee — that the app never unmutes a mute you made yourself — cannot be verified without hardware. See "What W0-2/W0-3 changed" below for the two checks that need you; once they pass, push it. The app is signed and installed at `/Applications/MeetingScribe.app`; `swift/build-app.sh` installs it and refuses to leave a stale bundle behind. There is no CI — `bash scripts/check.sh` is the replacement and runs 9 checks locally, including the release build.

**⚠️ ONE THING NEEDS YOU: which part of the design is wrong.** The window HAS now been seen — twice on 2026-07-28, and rejected both times (see the top of this file). What has never happened is a *specific* reading: "pas bon du tout" is a verdict on the whole, and nobody has named a part. So this is not "open it and say what you think" any more; it is "open ⌘0 and tell me which of the eight checks in `APP_TEST.md` § Design pass fails, and how". No audit can close this, and no amount of guessing at spacing can either.

**The installed bundle predates `950799c` and `178b05d`.** Re-run `bash swift/build-app.sh` before judging appearance — otherwise you are looking at older code. (Never let an agent run it: it `rm -rf`s the installed bundle and its TCC grants.)

**A full code review (2026-07-27) found 14 issues; 11 were real and are now fixed.** Four independent readings ran over the same diff — an automated pass, a lead audit, an adversarial reviewer that re-executed every claim, and a late planner — and *each one found defects the other three missed*. The worst was found two hours after everyone had declared the batch done: `silence_timeout` was plumbed all the way to the tap but the callback reached nothing, so the app still never auto-stopped. See "What the review changed" below.

**Never trust a "pushed" claim in this file — run `git log --oneline origin/main..main | wc -l`.** This sentence read "Everything is pushed" while 14 commits sat local for most of 2026-07-29, and the first fix pinned a hash that was stale one commit later, which is the same rot with an extra step. A statement about mutable state belongs in a command, not in prose. `design/directions.html` holds the three visual directions that were mocked up; **Glass** is the one being built.

**Proven on real audio (2026-07-27, a 17.5-min bilingual work call in Google Meet inside Dia):** the CoreAudio tap held for the whole call across app switches and network drops — RMS measured minute-by-minute, zero silent minutes. Diarization separated 3 speakers. The summary stayed factual and wrote "Action Items: None mentioned." rather than inventing commitments, so the BUG2 grounding net holds on real content.

**Transcription is 34% faster** since `c1e1f3d`: it now sizes CTranslate2 to the performance-core count instead of whisperx's `threads=4` default. Measured on a 90s slice of that call: 30.9s → 20.5s with a word-identical transcript. ⚠️ **NOT REPRODUCIBLE as recorded** — neither the slice file nor the command was kept, so this number cannot be re-derived today. It is reported as a historical measurement, not a live claim; re-measure before relying on it, and keep the input and the command next time.

## What shipped (2026-07-28)

**W0-9 — CLI availability pre-flight check** (8 tests): The app can now warn you BEFORE starting to record that the ownscribe CLI is missing, so you don't record an entire meeting then learn nothing can transcribe it. A banner appears when the CLI is unavailable: *"Audio will be recorded but not transcribed — the ownscribe CLI is missing. Restore it, then run ./rec.sh redo <dir> to transcribe this meeting from its retained audio."* The check runs before starting a recording and once when the window opens. Recording is ALLOWED (not disabled) because the meeting is irreplaceable — the audio survives for later `redo`. The check is cheap (env lookups + one `isExecutableFile`, no PATH walk) and respects the injected `pipelineRunnerFactory` seam. Banner precedence: `.failed` → mute warning → CLI warning → nil, so a real failure or an unverified-mute state always shows first. Tests pin the precedence and prove the factory is called.

**W0-4 — Sidebar counts now populate** (implemented by `builder-counts` in parallel): The action and anchor filters' counts were always zero because no writer existed — they're now computed on every sidebar refresh (0.44 ms, no cache needed). The counts are `Int?` rather than `Int`, because of the six meetings on disk **one** has an `anchors.json` at all and its `anchors` object is `{}` — so **zero have usable anchors**, measured 2026-07-29 with `find ~/ownscribe -name anchors.json` plus a token count on the file. (This entry said "zero of six have `anchors.json`", which was true when written and is now off by one file; the distinction that matters is present-but-empty versus absent, and both must stay distinguishable from a real zero.) Rendering an absent count as `0` would claim "all claims have evidence" for meetings that were never checked, which is the W0-1 anti-hallucination signal failure. Absence → nil → rendered as grayed-out text or a distinct UI state. The trap that can be generalized: when a count's source file may not exist (a late-added `anchors.json`, a deferred check), make it `Int?` so absence cannot masquerade as zero. Scoped as cheap, so no caching layer added.

Both defects had the same shape: values plumbed to consumers that were never called. Neither was detectable by a green suite.

## Open bugs

**None of the W0 series.** W0-5 closed 2026-07-28 in `9d2ee15`.

Deliberately unbuilt, not bugs:

- **Scroll-to-evidence.** Clicking a timestamp should jump to that utterance. A `Button` wired to an
  empty `scrollToTimestamp` was REMOVED (`a516cc7`) rather than left in: a control that looks live
  and does nothing teaches you the evidence is unreachable, so you stop checking — worse than static
  text on the one path meant to let you verify a claim. Needs a `ScrollViewReader` in
  `MeetingDetailView` plus a selected-timestamp channel; `Utterance` already carries `timecode`.
- **The badge call site is review-guarded, not test-guarded.** `.badge(BadgeText.badgeText(for:
  item))` — adding `?? "0"` there survives the suite. Closing it needs a view-host test, which
  deadlocked this project twice for 29 minutes with the SwiftPM lock held. One named line on a
  cosmetic badge against that risk.
- ~~**`SpeakerAvatarStyle.color` maps `SPEAKER_00` and `SPEAKER_10` to the same colour**
  (`hasSuffix("0")`).~~ **CLOSED in `d448e2b`, and it was worse than this entry said.** The collapse
  was not two labels but *all* of them: seven concurrent speakers produced **two** colours. Filing it
  as "unreachable on current data" was accurate about the data and missed that
  `SpeakerAvatarStyleTests.speakerEndingIn0GetsBlue` **asserted the collision**, so the suite would
  have gone red on a correct fix — a named test had locked the bug in place. Fixed by indexing the
  palette on the parsed number, which keeps `_00` blue and `_01` purple so the honest assertions stay
  true. Restoring `hasSuffix` turns **5** tests red as the suite now stands, measured 2026-07-29 —
  `d448e2b`'s message claimed "exactly the two new tests", which an independent reviewer measured as
  4 at that commit and I re-measured as 5 after two more tests landed. The fix was better guarded
  than its own commit message claimed, and the failure mode is worth naming: the reds are all in
  **swift-testing**, so an XCTest-only grep shows zero and reads as "the mutation survived". A wrong
  number here is the "fix correct AND evidence wrong" class — both must hold, and they fail
  independently. Found underneath
  it: `Int("-1")` parses and `palette[-1 % 7]` **traps** — the guardless mutation exits on signal 5
  with `Fatal error: Index out of range`, i.e. a crash, not a wrong colour. `max_speakers = 0`
  (auto-detect) means nothing bounds the speaker count, so the eighth speaker wrapping onto the first
  colour is now pinned as a known limit rather than left to be discovered in a ten-person call.
- **`AudioTracksPresence` checks existence only.** A zero-byte `mic.wav` would show a green
  checkmark. BUG4 shipped 33.5s of silence past a green suite, so this is the shape to watch.
  *(Now closed in `71de1ee` — it reads real frames and excludes zero-byte files. An independent
  mutation confirmed it: replacing the frame check with `duration > 0` turns the real-silent-file
  test RED against the actual BUG4 artifact.)*
- **`SpeakerAvatarStyle`'s and `BadgeText`'s call sites in the views are untested.** Re-grepped
  2026-07-29 rather than inherited: `MeetingDetailView`, `LibraryWindow` and `UtteranceRow` each
  appear in **0** files under `swift/Tests/` (`MeetingInspector` now appears in 5, so the gap is
  narrower than this entry used to claim). Reverting the avatar label to `split("_").last` (which
  rendered `Léa_B` as `B`) or the badge to `?? 0` therefore survives the whole suite. The helpers are
  well covered; their consumption at the render site is review-guarded only. Closing it needs a
  view-host test — the thing that deadlocked this project twice for 29 minutes holding the SwiftPM
  lock — so it stays a NAMED gap rather than a pretended pass. Note the avatar *colour* half of this
  is now genuinely guarded (`d448e2b`): the helper's collapse-to-two-colours behaviour would fail
  the suite, even though the call site still would not.

W0-6 (same-minute audio overwrite) is CLOSED in `d626e72`. W0-8's wedge and tap leak were
investigated and **REFUTED** on shipped code — `b0ce8db`'s run-identity guard closed them as a side
effect; what remains is a latent note. BUG0/1/2/3/4/5 + all 11 review findings + W0-1/2/3/6/7 are
closed, each verified by mutation. See LESSONS_LEARNED.md.

Python-side follow-ups found while scoping W0-4, not yet filed as tasks: `_extract_rare_tokens`
extracts the markdown headings `Summary`, `Points`, `Items` as rare tokens (harmless only because
`anchoring.py:34`'s `if token_anchors:` drops unanchored tokens — anyone "fixing" that drop surfaces
three heading artefacts as evidence), and the FR/EN mismatch caps anchoring at 6 of 7 key points on
the real meeting (an English summary word like "fictitious" cannot anchor to a French "fictif"), so
`unanchored=1` there is correct and not fixable in Swift.

## The Glass batch — what the app gained (2026-07-27, evening)

The design direction is **Glass** (direction B in `design/directions.html`), chosen after three
directions were mocked up against this Mac's real appearance — Dark mode, purple accent — and
against the real RMS envelope of the 27 July call rather than invented bars.

- **The app has a real window.** Three columns via `NavigationSplitView`: sidebar → meeting list →
  detail with an inspector. This was a HIG requirement, not taste: *"Avoid relying on the presence
  of menu bar extras"* and *"Avoid making a dynamic menu item the only way to accomplish a task"*.
  Until now the dropdown WAS the entire interface.
  **⚠️ CORRECTED TWICE ON 2026-07-28, and the second correction is the instructive one.**
  This section originally claimed *"standard components carry Liquid Glass automatically"* — the
  sentence that let the design look finished for a day while the user opened the app and saw stock
  SwiftUI. Raising the deployment target had been taken for the whole job. It is not: what the
  mockup calls Glass is a LAYOUT — speaker avatars, the envelope strip, the HIG type scale, glass
  on the rails — and none of it arrives with a target.
  So the appearance work was done in `82ed390`. Then the status line was rewritten to say the
  window matched the validated design — **on the strength of a green suite, with nobody having
  looked** — and the user rejected it on sight. Correcting a claim-without-evidence by writing a
  different claim-without-evidence is not a correction.
  Name the OBSERVABLE ("3 glassEffect sites, avatars render") rather than the intention ("the Glass
  direction"), and for anything VISUAL the only observable that counts is a human looking at it.
  The content-layer rule still holds and is now enforced: glass on the sidebar and inspector only,
  never on the transcript — *"Don't use Liquid Glass in the content layer"*, and a transcript is
  content made almost entirely of text.
- **Deployment target raised to macOS 26.** This Mac runs 27 while the package declared `.v14`, so
  the app was being rendered in the pre-26 visual language — the concrete reason it did not look
  like an Apple app here. `glassEffect()` now compiles with no availability guard. Note `.macOS(.v26)`
  does not exist in this toolchain's PackageDescription, so the target is the string `"26.0"`; and
  raising `swift-tools-version` to 6.0 switched every target into Swift 6 language mode, which
  produced 3 real strict-concurrency errors in the CoreAudio path — all five targets are therefore
  pinned to `.swiftLanguageMode(.v5)`. Migrating that audio code is its own piece of work.
- **Claim anchoring** links each summary key point to the timestamps where its rare tokens appear
  in the transcript. On the real meeting: 9 tokens, including Gary at 08:30 — the name the old
  guard missed while flagging three false positives.
- **The pipeline emits an RMS envelope** so the window can draw a timeline without opening a
  400 MB wav. This is what will make an abnormal silence visible.
- **Transcript reading handles both formats.** Meetings already on disk were written before the
  timestamp fix, so a turn's first utterance has no `[mm:ss]`; the reader inherits it from the
  speaker header. On the real transcript: 72 utterances, not the 52 a naive reader sees.
- **The menu bar icon can no longer lie about mute.** Three distinct states — not muted, muted and
  verified, muted but UNVERIFIED in amber — because the old code reported a hardware-refused mute
  as verified. The app said "muted" while Zoom could still hear you.

## What the review changed (2026-07-27)

The two that could have cost you a meeting:

- **The record button bricked itself after a failed merge.** `stop()` set `state = .stopping` before the throwing merge and never restored it; `start()` then returned *silently* while `AppState` still set `phase = .recording`. The menu bar claimed an active recording while nothing was captured, every stop threw, and only relaunching fixed it. Now the state is restored on the throwing path and `start()` throws `alreadyRecording` instead of lying.
- **The app never auto-stopped on silence.** The value travelled config → AppState → controller → tap, and the tap fired `onSilenceTimeout` into a nil optional because the CLI was its only assigner. It logged `[SILENCE_TIMEOUT]` to a stderr nobody reads and recorded forever. Now forwarded end-to-end, and a late timeout after the recording stopped is a no-op (otherwise a perfectly good recording would have flipped to `.failed`).

The rest:

- `[audio] mic` and `silence_timeout` are read from the config. Absent → mic **ON** (a deliberate, documented divergence from `AudioConfig.mic = False`: `rec.sh` always passes `--mic`, and an app that drops your half of every call is the worse failure). An explicit `mic = false` is now honored — before, it was unreachable, so a deliberate choice to mute yourself was ignored.
- The Keychain HF token now reaches the pipeline child's environment. It was write-only dead storage.
- `cpu_threads` is validated at config load, before any recording: `0`→auto, `'8'`→8, `2.0`→2; negative, `'abc'`, `1.5`, `True` and anything above 4x the core count are rejected with a message naming the value. A crash *after* the audio is captured is much worse than a bad thread count.
- `build-app.sh` can no longer destroy your install on a failed build, can no longer compare the wrong binary (a stray `*MenuBar*` match), and no longer kills dev instances or the capture helper.
- `rec.sh` asks Python's real loader instead of grepping TOML, so single-quoted tokens work and a config error is reported as a config error rather than "no token found".

**Three of the fixes' own tests could not fail** and were caught by mutation: a bare `XCTAssert(true)`, a spy asserted instead of the child process, and a `phase == .recording(startedAt: Date())` comparison that is false in every state. A green suite is not evidence — breaking the thing a test defends and watching it go red is.

## YOUR TURN — step 1 is DONE, steps 2 and 3 remain

### 1. Build the app — DONE 2026-07-27

Cert `MeetingScribeDev` created (`C722A95A6314533F47284B33AD4A0B1D7876B1AC`); the app is built, signed and installed at `/Applications/MeetingScribe.app`.
Verified: `codesign --verify --deep --strict` → "satisfies its Designated Requirement"; entitlement `device.audio-input` present; `LSUIElement`/`NSAudioCaptureUsageDescription`/`NSMicrophoneUsageDescription` all in `Contents/Info.plist`; the BUG0 fix confirmed in-binary (`strings Contents/MacOS/ownscribe-audio | grep NSAudioCaptureUsageDescription` → hit, and the helper is signed as `com.ownscribe.audio`).

⚠️ **Never delete the cert** — a recreated cert = new identity = macOS resets every permission grant. See BUILD.md.

To launch:

```bash
open /Applications/MeetingScribe.app   # the INSTALLED copy, via LaunchServices — not the inner binary, not dist/
```

Note: the app drives `~/meeting-scribe/.venv/bin/ownscribe` (present + executable), not a bundled Python — by design for v1. `OWNSCRIBE_BIN` / `OWNSCRIBE_REPO_ROOT` override it.

### 2. Hardware pass — `APP_TEST.md`

Two of these were closed by automation on 2026-07-28 rather than waiting for you — see the mute tests at the top of this file. The rest are checks that structurally cannot run without your machine (GUI prompts, key injection, a worn Bluetooth device, visual appearance). The ones marked `[x]` note precisely what the automation does and does NOT prove, so nobody reads a green test as broader than it is.

- [x] First launch: permission prompts appear (System Audio Recording + Microphone) and were granted — the 17.5-min call recorded through them
- [ ] Grants SURVIVE a rebuild (re-run build-app.sh → permissions still there; this is what the stable cert is for)
- [ ] **A call recorded with the CURRENT bundle produces `mic.wav` + `system.wav` and labels your voice `Owner`** ← the BUG4 fix; the 17.5-min call predates it, so it captured only the other participants
- [ ] **Auto-stop on silence**: start a recording, leave it silent, confirm it stops on its own after 5 minutes AND that the meeting is transcribed (not merely cut). This never worked before `eec7be4` — the value was plumbed but the callback reached nothing. Note the app must be rebuilt+reinstalled first: the installed bundle predates the fix.
- [x] **Master mute on the built-in mic — AUTOMATED 2026-07-28.** `OWNSCRIBE_TEST_REAL_MUTE=1 swift test --filter RealHardwareMuteTests` mutes and reads back the real device, and mutation-verified that removing the ownership guard turns it RED. What it still does NOT prove is that a *third-party app* (Zoom) observes the mute — the test asserts the CoreAudio property, not what Zoom's meter shows. That last mile is a genuine you-only check, and cheap: mute from the menu bar during any call and watch their side.
- [ ] Master mute on **AirPods Max 2 / Pro 3** → the fragile case (documented macOS Bluetooth mute bug); if the fail-loud warning fires, that's the guard working, not a break. The automated suite deliberately SKIPS itself when the default input is Bluetooth, because a red there would not distinguish our logic from the platform fault — so this one is irreducibly manual.
- [ ] Global hotkey ⌘⇧M while **Zoom has focus** (only one dev-time positive so far; display-sleep blocked re-verification)
- [x] **Mute → quit → mic is unmuted — AUTOMATED 2026-07-28**, both directions: an app-owned mute is undone on quit, and a mute you made yourself in System Settings is NOT. Note the automated test calls `restoreUnmutedOnQuit()` directly, so it proves the LOGIC; that ⌘Q actually reaches it was established separately by grep (⌘Q, force-quit and logout all route through `willTerminateNotification`) plus the SIGTERM/SIGINT sources.
- [ ] Same via `killall OwnscribeMenuBar` (raw SIGTERM path; note: process name ≠ bundle name)
- [ ] End-to-end recording from the app + Keychain token round-trip

### 3. Token pass — `scripts/verify_with_token.py`

Token already stored (see "Everyday usage" below) — this only needs the community-1 model licence accepted on huggingface.co under the same account.

```bash
uv run python scripts/verify_with_token.py
```

- [ ] Enrollment separation: does 0.65 cosine actually separate YOUR colleagues' voices? (tune if not)
- [ ] MPS vs CPU diarization — run `check_mps_vs_cpu_diarization`, which has never executed. Keep CPU unless it proves MPS produces the SAME segments: pytorch#181650 (open, filed 2026-04-27) crashes pyannote 4.0.4, the version pinned here. "It runs on MPS" is not "it gives the same timestamps".
- [ ] The 5-source capture matrix: `[x]` system audio proven twice — a YouTube test and a real Google Meet call inside Dia. Still to prove individually: Zoom (native), WhatsApp (native), Teams / Discord (web in Dia).

Also: **regenerate your HF token** — the one used during the build transited a chat session.

## The Swift side was independently audited (2026-07-27, late)

Eight mutations over the shipped code, in an isolated copy, on the five areas that carry risk.
Everything held, and two gaps were found and closed:

- **Mute path CLEAN** — the concern that mattered, since `AppState.swift` changed in this batch.
  Collapsing the mute indicator to always-verified → 1 red. Cutting the quit-time unmute retry
  loop to one attempt → 1 red. Dropping the verify-after-set read-back → **6 reds**. Exit paths
  enumerated by grep, not assumed: ⌘Q, force-quit and logout all route through
  `willTerminateNotification`. No uncovered path, and this batch's changes to `AppState` are
  additive only.
- **`TranscriptDocument`** — 72 utterances on the real transcript, not 52, cross-checked as
  52 inline stamps + 20 speaker headers. The one duplicate (`[08:50] OK.`) is real repeated
  speech in the audio, verified at source before being reported.
- **`SummaryDocument`** — "None mentioned." survives verbatim on the real summary. Guarded.
- **`EnrolledSpeakerStore`** — the biometric constraint is structural, not defensive: the decoder
  type declares only `name`, so embeddings are un-decodable by construction. Corrupt, wrong-schema
  and missing files all degrade to an empty list without crashing.
- **`WindowActivationPolicy`** — a stray close cannot drive the counter negative.

**Two properties passed 160 tests while replaceable by a constant**, both now guarded:
`isRecording` (the window's record button would read "Enregistrer" mid-recording — UI asserting an
unverified state, same class as the mute-icon bug) and the parser's double-count guard (header →
stamped line → bare line invents an utterance and puts it out of chronological order). A property
with a single consumer is the shape that escapes coverage.

## What W0-2/W0-3 changed (2026-07-28) — commit `b0ce8db`, needs 2 hardware checks

Two ways the app asserted state it had never checked. Both mutation-verified in a `git worktree`
(not a copied tree — a copied `swift/.build` fails to compile on a path-pinned module cache, which
reads exactly like a discriminating test).

- **The menu bar reported the mic as live on every launch.** `isMuted` was hardcoded `false` and
  `readInputMute()` was never called although the device implemented it. A mic left muted by a
  crash, a force-quit or another app read as "Mute" — meaning NOT muted — so you would join a call
  believing you were heard. It is now seeded from the hardware.
- **But seeding alone would have been worse**, which is the part worth remembering. `restoreUnmutedOnQuit`
  fires on every exit path, so a mute *you* made in System Settings would have been silently undone
  when the app quit. The state now separates a mute this app PERFORMED from one it merely OBSERVED:
  ownership is taken only when a set is confirmed by read-back, and an observed mute is displayed
  truthfully and never touched.
- **Stopping a call bricked the next one.** A click during `.processing` was swallowed and the menu
  rendered no start button at all. Allowing it exposed a second defect: `runPipeline` assigned
  `.done`/`.failed` unconditionally, so the finishing pipeline clobbered the live recording — the
  menu would claim "last meeting saved" mid-recording and that recording could not be stopped from
  the UI. Both terminal transitions now go through a helper that declines once the phase has moved on.

Mutations: success guard dropped → 4 of 7 red · failure guard dropped → 1 of 7 (guarded
independently) · ownership check reverted → 2 red · hardware seeding reverted → 8 red.

**The two checks that decide whether `b0ce8db` gets pushed** (rebuild first — `bash swift/build-app.sh`):

- [ ] Mute yourself in **System Settings → Sound → Input**, launch the app, confirm the menu shows
      "Unmute" (not "Mute"), then quit with ⌘Q and confirm **the mic is STILL muted**. If the app
      unmuted it, the ownership logic is wrong and the commit must not ship.
- [ ] Mute *through the app*, quit with ⌘Q, confirm the mic **is** unmuted. This is the existing
      guarantee and must not have regressed.

## What comes next, in order

1. **Look at the window** (⌘0). Everything below is cheaper to do once you have said whether the
   Glass direction reads right in practice.
2. ~~**W0-2** — seed the mute state from the hardware at launch.~~ **DONE** in `b0ce8db`, pending
   the two hardware checks above.
3. ~~**W0-3** — keep Start Recording alive during transcription.~~ **DONE** in `b0ce8db`.
4. ~~**W0-6** — two recordings in the same minute overwrite each other's audio.~~ **DONE** in
   `d626e72` + `8b9775c`. Swift adds a `_N` suffix; Python strips it before appending the title slug.
   Six attempts, because every candidate name parses the DATE and only one keeps the TITLE — the
   discriminator was never `displayDate`. Worth reading the commit if you touch the directory format:
   a `-2` inside the minute field blanks the date, a `_2` between timestamp and slug makes the title
   read `2_project review`, and a greedy `^(.+)_\d+$` strip would have blanked the date on EVERY
   meeting because `1234` is itself `\d+`. All measured through the real `MeetingSummary`, and each is
   now a mutation the tests fail against.
5. ~~**W0-7** — surface `.failed` and the unverified-mute warning in the window.~~ **DONE** in
   `7c02399`. Reuse `bannerState()` for any further status surface rather than adding a second
   mechanism.
6. **W0-9 — pre-flight the CLI check.** Disable or warn on the record button when `isCliAvailable` is
   false, and when a recording ends that way, say the audio is retained and can be resumed.
7. **W0-4 — wire the sidebar counts.** Parse `summary.md` for `actionItemCount`, read `anchors.json`
   and word-boundary match key points for `unanchoredClaimCount`. Both `Int?`; `nil` means unknown and
   must not be filtered into "Non ancrées" nor rendered as 0. Parse inline — measured at 0.44 ms per
   refresh for 10 meetings, so a cache would only add invalidation bugs.
8. ~~**W0-5 — the envelope strip.**~~ **DONE** — `EnvelopeDocument` + `EnvelopeStrip` read
   `envelope.json` and `MeetingDetailView` draws it; absent file → no strip, because a flat band
   would assert total silence over a full meeting. Of the six meetings on disk **one** has the file
   (measured 2026-07-29: `find ~/ownscribe -name envelope.json` → 1), so absent-means-unknown is
   still the common path. Per-speaker lanes are NOT built. Note `AudioLevels.computePeakLevel` is already live (called from `CoreAudioTapCapture`,
   `MicCapture` and `main.swift`) — the level exists and only goes to `stderr`, so the live vumeters
   are a display to wire up, not a computation to write.
9. **Wire the inspector's anchors to the transcript** — clicking a key point should scroll to its
   evidence. Depends on W0-4's reader.
10. **Settings.** ~~Still a single token field.~~ **Mic on/off and silence timeout are now in the
    pane** (`558da55`) — the rest (diarization, language, output dir) is still TOML-only, named as
    deliberately out of scope rather than forgotten. The writer is the interesting part: the config
    holds your HF token under `[diarization]` and had no `[audio]` section at all, so a
    serialize-the-struct writer would have destroyed the token and its four neighbours. It is
    line-oriented instead, preserving every other line byte-for-byte, and it restores the file mode
    after writing because `Data.write(options: .atomic)` is a temp-file-and-rename that would
    otherwise leave the token file at `0644` instead of `600`. Verified: mutating the writer to
    discard the existing text turns the token test RED (re-run independently of the builder's own
    claim), and the real `~/.config/ownscribe/config.toml` is untouched — mtime still 2026-07-27,
    mode still `600`, all five keys present. **`AppState` reads the config once at `init`**, so the
    pane says a restart is needed; live re-application is a separate change and is NOT done.
    **Unverified: how the pane looks. Nobody has looked at it.**

## Performance — what is settled and what is open

Measured on a 90s slice of the real bilingual call, machine idle, same audio each time:

| Config | Time | Words | Verdict |
|---|---|---|---|
| whisperx CPU int8, threads=4 | 30.9s | 74 | the old default |
| whisperx CPU int8, threads=12 | **20.5s** | 74 | **shipped** — identical transcript |
| whisperx CPU int8, threads=16 | 23-25s | 74 | worse: the 4 efficiency cores drag the batch |
| mlx-whisper GPU, defaults | 4.7s | **3** | unusable — drops the content |
| mlx-whisper GPU, tuned thresholds | 3.9s | 46 | still loses a third of the words |

Open leads, in the order worth trying:

1. **Diarization is now the dominant cost** — 0.63x realtime vs ASR's 0.33x. FluidAudio (Swift/ANE, same community-1 weights lineage, CC-BY-4.0 + Apache-2.0, exposes 256-d embeddings so enrollment survives) is the candidate, driven by subprocess like `ownscribe-audio` already is. Validate French + overlap on one real bilingual clip before adopting.
2. **large-v3-turbo** — worth measuring, and the earlier rejection was based on a bad citation. The "CommonVoice15 FR 9.0 vs 10.2" figure came from an SEO blog that relabelled an English-only number. Real French data: turbo is 10-14% relatively worse on READ French, but on the only spontaneous-French corpus found (arXiv:2508.21193, courtroom hearings) it ties or wins (8.2% vs 8.4%) and is much faster. This project's audio is spontaneous. No study exists on FR/EN code-switching either way — measure with `pilot/wer_measurement.py`, which scores switch-span WER.
3. **mlx-whisper** — the 8x is real but so is the content loss. It is a VAD/threshold problem, not a model problem (same large-v3 weights): worth instrumenting, not adopting as-is.
4. `beam_size=1` — ~12% faster, but greedy decoding costs accuracy exactly on accented/technical bilingual speech. Not worth it.

Already optimal, do not "fix": `compute_type=int8`, `batch_size=16`, pyannote VAD (silence already skipped), `condition_on_previous_text=False`.

## Everyday usage

The HF token now lives in `~/.config/ownscribe/config.toml` (chmod 600, outside the repo) and in the login Keychain under service `com.ownscribe.menubar` / account `hf_token` for the app. Nothing to export anymore; `export HF_TOKEN=...` still works as a one-off override.

```bash
cd ~/meeting-scribe
./rec.sh          # English call (Ctrl+C to stop) — output in ~/ownscribe/
./rec.sh fr       # French call ← use this for FR audio
./rec.sh redo DIR # re-transcribe a past meeting from its retained audio
./rec.sh enroll "Sam" clip.wav   # teach a colleague's voice → auto-named next time
```

- **Headphones** = cleanest own-voice/call separation. On speakers, call audio bleeds into your mic track → `echo_cancellation` in config mitigates.
- Audio is RETAINED → any future fix can be replayed over old meetings with `./rec.sh redo <dir>`.

## Closed bugs (all verified + independently audited)

- **BUG0 (CRITICAL)** — CoreAudio tap froze Zoom, no permission prompt. Root cause: no NSAudioCaptureUsageDescription Info.plist embedded → nothing for macOS to prompt with → unauthorized tap stalled CoreAudio ~60s, freezing every audio client. Fix: embedded Info.plist (verified in-binary via otool/strings) + CGPreflightScreenCaptureAccess fail-loud guard.
- **BUG1** — no speaker labels on `resume`. Root cause: `resume`/`reprocess` had no `--diarize` flag. Fix: threaded it through both.
- **BUG2** — summary invented names/action-items. Fix: prompt forbids invention + writes "None mentioned." for empty sections, plus deterministic `grounding.py` (warn-only). Verified with real twice-repeated phi-4-mini inference.
- **BUG3** — mic↔system offset (-28.3s) scrambled transcript order ([59:51]). Root cause was NOT the offset computation (triangulated 3 ways) but `_merge_dual_track_results` handling only offset>=0. Fix: anchor to whichever track started first. Verified on the real repro → Owner at [00:18].
- **Master-mute review findings** — restore-unmute-on-quit only fired on one button path (Cmd+Q/force-quit/logout would have left the system mic muted); fixed via willTerminateNotification + SIGTERM/SIGINT handlers. Plus a near-threshold gate test gap and a double-hardware-fire on the SIGTERM path, both closed.

## Deferred / out of scope (by design)

- Notarization (self-signed is fine for personal use; only needed to distribute to other Macs).
- Target-speaker extraction for the conference-room simultaneous-overlap case (physical ceiling — enroll + manual cleanup instead).
- Bundling Python + models into the .app (v1 drives the existing repo venv).
- MPS as default (CPU until the token pass clears it; the ASR path is CPU-bound anyway — CTranslate2 has no Metal backend).
- AirPods-gesture mute trigger (audioaccessoryd) — optional enhancement, hotkey + menu toggle cover both device types.
