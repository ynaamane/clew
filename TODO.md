# TODO — meeting-scribe

## Status: the app has a window that no longer hides failures. 822 tests green, HEAD `7c02399`, eight commits held for your review.

822 tests green (617 Python + 205 Swift, 4 skipped by design) plus 5 hardware tests that run on demand.

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

**⚠️ ONE THING NEEDS YOU: the window has never been seen.** It has 163 passing tests and zero visual verification — every `screencapture` came back black because the display was asleep, and the accessibility API reports no windows for one never opened. Open it with **⌘0** from the menu bar and say what you think. No audit can close this.

**The installed bundle is from before the window landed.** Re-run `bash swift/build-app.sh` to get it.

**A full code review (2026-07-27) found 14 issues; 11 were real and are now fixed.** Four independent readings ran over the same diff — an automated pass, a lead audit, an adversarial reviewer that re-executed every claim, and a late planner — and *each one found defects the other three missed*. The worst was found two hours after everyone had declared the batch done: `silence_timeout` was plumbed all the way to the tap but the callback reached nothing, so the app still never auto-stopped. See "What the review changed" below.

Everything is pushed. `design/directions.html` holds the three visual directions that were mocked up; **Glass** is the one being built.

**Proven on real audio (2026-07-27, a 17.5-min bilingual work call in Google Meet inside Dia):** the CoreAudio tap held for the whole call across app switches and network drops — RMS measured minute-by-minute, zero silent minutes. Diarization separated 3 speakers. The summary stayed factual and wrote "Action Items: None mentioned." rather than inventing commitments, so the BUG2 grounding net holds on real content.

**Transcription is 34% faster** since `c1e1f3d`: it now sizes CTranslate2 to the performance-core count instead of whisperx's `threads=4` default. Measured on a 90s slice of that call: 30.9s → 20.5s with a word-identical transcript.

## Open bugs

Three, all found on 2026-07-28 by tracing each value to its CONSUMER rather than reading diffs, and
all the same shape — a value plumbed to a consumer that is never reached (W0-7, the fourth, is closed
in `7c02399`):

- **W0-9** — you can record a whole meeting before learning nothing can transcribe it.
  `isCliAvailable` has zero consumers, so nothing checks the CLI before offering to record. The audio
  survives but the UI never says so. Costliest of the set: the unit of loss is a meeting.
- **W0-4** — the sidebar's action/anchor filters and the "non ancré" badge are dead in production (no
  writer for either count field). Scoped: cost is negligible (0.44 ms/refresh, no cache needed), but
  zero of six meetings on disk have `anchors.json`, so the counts must be `Int?` — rendering absent
  as `0` claims "all claims have evidence" for meetings never checked, which is the W0-1 failure on
  the anti-hallucination signal.
- **W0-5** — nothing in Swift reads `envelope.json`, so the timeline cannot be drawn.

W0-6 (same-minute audio overwrite) is CLOSED in `d626e72`. W0-8's wedge and tap leak were
investigated and **REFUTED** on shipped code — `b0ce8db`'s run-identity guard closed them as a side
effect; what remains is a latent note. BUG0/1/2/3/4/5 + all 11 review findings + W0-1/2/3/6 are
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
  Until now the dropdown WAS the entire interface. Standard components carry Liquid Glass
  automatically, and none of it lands on the transcript — *"Don't use Liquid Glass in the content
  layer"*, and a transcript is content made almost entirely of text.
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

## YOUR TURN — 2 steps left (step 1 is DONE)

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
8. **W0-5 — the envelope strip and per-speaker lanes.** `pipeline.py` writes `envelope.json`
   (500 buckets) and NO Swift file reads it. This is what makes an abnormal silence visible without
   opening a 400 MB wav. Zero of six meetings on disk have the file, so absent-means-unknown applies
   here too. Note `AudioLevels.computePeakLevel` is already live (called from `CoreAudioTapCapture`,
   `MicCapture` and `main.swift`) — the level exists and only goes to `stderr`, so the live vumeters
   are a display to wire up, not a computation to write.
9. **Wire the inspector's anchors to the transcript** — clicking a key point should scroll to its
   evidence. Depends on W0-4's reader.
10. **Settings.** Still a single token field. Mic on/off, silence timeout, diarization, language and
    output dir all live only in TOML.

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
