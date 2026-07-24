# TODO — meeting-scribe

## Status: CLI working end-to-end (real solo test passed, BUG3 fixed). Menu-bar app in final packaging. No open bugs.

CLI proven on a real solo test 2026-07-24: system audio (YouTube) captured, mic captured, diarization split Owner vs SPEAKER_00, summary grounded (no hallucination), no Zoom-style freeze. 620 tests green (554 Python + 66 Swift), all on `main` (private repo ynaamane/meeting-scribe).

## Open bugs

None.

## Closed bugs (verified)

- **BUG0 (CRITICAL, closed)** — CoreAudio tap froze Zoom + no permission prompt. Root cause: no NSAudioCaptureUsageDescription Info.plist embedded → no prompt possible → unauthorized tap stalled CoreAudio for ~60s (froze the call). Fix: embedded Info.plist (verified in the binary via otool/strings) + a CGPreflightScreenCaptureAccess fail-loud guard before creating the tap. On macOS 26.1+/27 the tap rides the existing Screen Recording grant (so no prompt fired on this machine — expected).
- **BUG1 (closed)** — diarization produced no speaker labels on `resume`. Root cause: `resume`/`reprocess` had no `--diarize` flag → diarization stayed off by default. Fix: added `--diarize` to both. (Confirmed in the real test: Owner vs SPEAKER_00 split correctly.)
- **BUG2 (closed)** — summary invented names/action-items (John/Sarah/Mark) absent from the audio. Fix: prompt now forbids inventing names + writes "None mentioned." for empty sections, PLUS a deterministic grounding.py that flags ungrounded capitalized words (warn-only). Verified with real phi-4-mini inference (twice) + confirmed grounded in the real solo test.
- **BUG3 (closed)** — mic↔system offset (-28.3s) rendered the Owner line at a bogus timestamp ([59:51]) and scrambled transcript order. Root cause: `_merge_dual_track_results` only handled the case where mic started at/after system; when mic started first (confirmed via 3 independent measurements — acoustic cross-correlation, host-time delta, same-utterance timeline comparison, all converging on ~28.3s), shifting mic backward produced negative timestamps. Fix: the merge now anchors to whichever track started first (mirrors what the Swift audio merge already did correctly). Verified end-to-end against the real repro dir via `resume` — Owner now renders at [00:18] in correct chronological order. See LESSONS_LEARNED.md for the full mechanism.

## The final verification pass (needs YOU — HF token + real audio)

Run `scripts/verify_with_token.py` (token from env: `export HF_TOKEN=hf_xxxxx`, after accepting https://huggingface.co/pyannote/speaker-diarization-community-1). Closes in one pass:

- [ ] enrollment separation: does 0.65 cosine actually separate YOUR colleagues' voices? (tune if needed)
- [ ] MPS vs CPU end-to-end (is MPS safe on torch 2.8 → speedup unlock, or the #1886 wrong-output mode)
- [ ] the 5-source capture matrix — play audio in each, confirm non-silent system.wav:
  - [x] system-audio capture proven (real YouTube test, -21dB captured)
  - [ ] Zoom (native) / WhatsApp (native) / Meet / Teams / Discord (web in Dia) — each specifically

## Everyday usage

```
cd ~/meeting-scribe
export HF_TOKEN=hf_xxxxx
./rec.sh          # English call (Ctrl+C to stop) — output in ~/ownscribe/
./rec.sh fr       # French call  ← use this for FR audio (the real test showed --language en on FR audio still works but mislabels the header)
./rec.sh redo DIR # re-transcribe a past meeting from kept audio
./rec.sh enroll "Sam" clip.wav   # teach a colleague's voice → auto-named next time
```

- **Headphones** = cleanest separation. On speakers, call audio bleeds into your mic track; `echo_cancellation` in config mitigates.
- Audio is RETAINED → `./rec.sh redo <dir>` re-runs after a fix (used to verify the BUG3 fix against the original real repro dir).

## Menu-bar app (in progress)

SwiftUI MenuBarExtra app scaffolded + runs in dev (`swift run OwnscribeMenuBar`), drives the existing CLI venv, coexists with the CLI. Master mute (system-wide, verify-after-set + AirPods fail-loud, ⌘⇧M hotkey + menu-bar button, icon reflects verified state) + the acoustic silence gate are built and tested — see NOTES.md Task#28. Global hotkey confirmed firing once end-to-end (real keystroke, real focused app); further live re-verification blocked mid-session by the physical display going to sleep, not a code issue.

Packaging: package a real `.app` signed with a STABLE self-signed cert (so macOS permissions granted once survive rebuilds). Build/recreate steps → BUILD.md; first-launch checklist → APP_TEST.md. Remaining: create the cert (`scripts/setup-codesign-identity.sh`, needs the user to run it — writes to the login keychain), then user-side verification of the mute's built-in-vs-AirPods behavior on real hardware (fold into APP_TEST.md).

## Deferred / out of scope (by design)

- Notarization (self-signed is fine for personal use; only needed to distribute to other Macs).
- Target-speaker extraction for the conference-room simultaneous-overlap case (physical ceiling; enroll + manual cleanup instead).
- Bundling Python+models into the .app (v1 drives the existing repo venv).
- MPS as default (stays CPU until the token pass clears it; ASR is CPU-bound anyway).
