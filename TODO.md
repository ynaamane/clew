# TODO — meeting-scribe

## Status: app built, installed and proven on a real 17-minute call. No open bugs.

667 tests green (568 Python + 99 Swift), HEAD `c1e1f3d`, pushed to `main` (private repo ynaamane/meeting-scribe). The app is signed and installed at `/Applications/MeetingScribe.app`; `swift/build-app.sh` now installs it and refuses to leave a stale bundle behind.

**Proven on real audio (2026-07-27, a 17.5-min bilingual work call in Google Meet inside Dia):** the CoreAudio tap held for the whole call across app switches and network drops — RMS measured minute-by-minute, zero silent minutes. Diarization separated 3 speakers. The summary stayed factual and wrote "Action Items: None mentioned." rather than inventing commitments, so the BUG2 grounding net holds on real content.

**Transcription is 34% faster** since `c1e1f3d`: it now sizes CTranslate2 to the performance-core count instead of whisperx's `threads=4` default. Measured on a 90s slice of that call: 30.9s → 20.5s with a word-identical transcript.

## Open bugs

None. BUG0/1/2/3/4/5 + all review findings closed and independently audited. See LESSONS_LEARNED.md.

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
