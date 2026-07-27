# TODO — meeting-scribe

## Status: the app has a window. 773 tests green, HEAD `e793000`, everything pushed.

773 tests green (610 Python + 163 Swift). The app is signed and installed at `/Applications/MeetingScribe.app`; `swift/build-app.sh` installs it and refuses to leave a stale bundle behind. There is no CI — `bash scripts/check.sh` is the replacement and runs 9 checks locally, including the release build.

**⚠️ ONE THING NEEDS YOU: the window has never been seen.** It has 163 passing tests and zero visual verification — every `screencapture` came back black because the display was asleep, and the accessibility API reports no windows for one never opened. Open it with **⌘0** from the menu bar and say what you think. No audit can close this.

**The installed bundle is from before the window landed.** Re-run `bash swift/build-app.sh` to get it.

**A full code review (2026-07-27) found 14 issues; 11 were real and are now fixed.** Four independent readings ran over the same diff — an automated pass, a lead audit, an adversarial reviewer that re-executed every claim, and a late planner — and *each one found defects the other three missed*. The worst was found two hours after everyone had declared the batch done: `silence_timeout` was plumbed all the way to the tap but the callback reached nothing, so the app still never auto-stopped. See "What the review changed" below.

Everything is pushed. `design/directions.html` holds the three visual directions that were mocked up; **Glass** is the one being built.

**Proven on real audio (2026-07-27, a 17.5-min bilingual work call in Google Meet inside Dia):** the CoreAudio tap held for the whole call across app switches and network drops — RMS measured minute-by-minute, zero silent minutes. Diarization separated 3 speakers. The summary stayed factual and wrote "Action Items: None mentioned." rather than inventing commitments, so the BUG2 grounding net holds on real content.

**Transcription is 34% faster** since `c1e1f3d`: it now sizes CTranslate2 to the performance-core count instead of whisperx's `threads=4` default. Measured on a 90s slice of that call: 30.9s → 20.5s with a word-identical transcript.

## Open bugs

None. BUG0/1/2/3/4/5 + all 11 review findings closed, each verified by mutation rather than by a green suite. See LESSONS_LEARNED.md.

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

The checks that structurally cannot run without your machine (GUI prompts, real devices, key injection):

- [x] First launch: permission prompts appear (System Audio Recording + Microphone) and were granted — the 17.5-min call recorded through them
- [ ] Grants SURVIVE a rebuild (re-run build-app.sh → permissions still there; this is what the stable cert is for)
- [ ] **A call recorded with the CURRENT bundle produces `mic.wav` + `system.wav` and labels your voice `Owner`** ← the BUG4 fix; the 17.5-min call predates it, so it captured only the other participants
- [ ] **Auto-stop on silence**: start a recording, leave it silent, confirm it stops on its own after 5 minutes AND that the meeting is transcribed (not merely cut). This never worked before `eec7be4` — the value was plumbed but the callback reached nothing. Note the app must be rebuilt+reinstalled first: the installed bundle predates the fix.
- [ ] Master mute on the **built-in mic** → verify Zoom/others actually stop hearing you
- [ ] Master mute on **AirPods Max 2 / Pro 3** → the fragile case (documented macOS Bluetooth mute bug); if the fail-loud warning fires, that's the guard working, not a break
- [ ] Global hotkey ⌘⇧M while **Zoom has focus** (only one dev-time positive so far; display-sleep blocked re-verification)
- [ ] **Mute → quit with Cmd+Q (NOT the menu button) → confirm mic is unmuted afterward** ← the critical fix
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

## What comes next, in order

1. **Look at the window** (⌘0). Everything below is cheaper to do once you have said whether the
   Glass direction reads right in practice.
2. **W0-2 — seed the mute state from the hardware at launch.** `AppState.swift` hardcodes
   `isMuted = false` and never calls `readInputMute()`, even though the device implements it. If the
   mic was left muted by a crash, a force-quit or another app, the menu reads "Mute" — meaning NOT
   muted — and you join a call believing you are live.
3. **W0-3 — keep Start Recording alive during transcription.** `toggleRecording` has
   `case .processing: break`, so the click is swallowed, and the dropdown renders no Start button at
   all. Stop a 17-minute call, have the next one dial in, and call two is never recorded.
4. **Swift side of the envelope strip and the per-speaker lanes.** The Python half ships the data;
   the window does not draw it yet. This is what makes a silent recording visible at a glance.
5. **Wire the inspector's anchors to the transcript** — clicking a key point should scroll to its
   evidence. The anchors exist on disk; nothing reads them in Swift yet.
6. **Settings.** Still a single token field. Mic on/off, silence timeout, diarization, language and
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
