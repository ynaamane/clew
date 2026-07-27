# TODO — meeting-scribe

## Status: CODE COMPLETE. No open bugs. Everything left is a user-side hardware pass.

655 tests green (563 Python + 92 Swift), HEAD `d144b87`, all pushed to `main` (private repo ynaamane/meeting-scribe). CLI proven end-to-end on a real solo test (2026-07-24): system audio (YouTube) captured at -21dB, mic captured, diarization split Owner vs SPEAKER_00, summary grounded, no freeze. Menu-bar app scaffolded + packaged (build scripts, entitlements, stable-self-signed identity flow) but NOT yet built — that's step 1 below.

## Open bugs

None. BUG0/1/2/3 + all review findings closed and independently audited.

## YOUR TURN — 2 steps left (step 1 is DONE)

### 1. Build the app — DONE 2026-07-27

Cert `MeetingScribeDev` created (`C722A95A6314533F47284B33AD4A0B1D7876B1AC`) and `dist/MeetingScribe.app` built + signed.
Verified: `codesign --verify --deep --strict` → "satisfies its Designated Requirement"; entitlement `device.audio-input` present; `LSUIElement`/`NSAudioCaptureUsageDescription`/`NSMicrophoneUsageDescription` all in `Contents/Info.plist`; the BUG0 fix confirmed in-binary (`strings Contents/MacOS/ownscribe-audio | grep NSAudioCaptureUsageDescription` → hit, and the helper is signed as `com.ownscribe.audio`).

⚠️ **Never delete the cert** — a recreated cert = new identity = macOS resets every permission grant. See BUILD.md.

To launch:

```bash
open ~/meeting-scribe/dist/MeetingScribe.app   # via LaunchServices, NOT the inner binary
```

Note: the app drives `~/meeting-scribe/.venv/bin/ownscribe` (present + executable), not a bundled Python — by design for v1. `OWNSCRIBE_BIN` / `OWNSCRIBE_REPO_ROOT` override it.

### 2. Hardware pass — `APP_TEST.md`

The checks that structurally cannot run without your machine (GUI prompts, real devices, key injection):

- [ ] First launch: permission prompts appear (System Audio Recording + Microphone), grant both
- [ ] Grants SURVIVE a rebuild (re-run build-app.sh → permissions still there; this is what the stable cert is for)
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
- [ ] MPS vs CPU end-to-end (if MPS is clean on torch 2.8 → real speedup unlock; currently CPU by design)
- [ ] The 5-source capture matrix: `[x]` system audio proven (YouTube test) — still to prove individually: Zoom (native), WhatsApp (native), Meet / Teams / Discord (web in Dia)

Also: **regenerate your HF token** — the one used during the build transited a chat session.

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
