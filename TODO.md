# TODO — meeting-scribe

## Status: CLI working end-to-end (real solo test passed). Menu-bar app in final packaging. One open bug (BUG3).

CLI proven on a real solo test 2026-07-24: system audio (YouTube) captured, mic captured, diarization split Owner vs SPEAKER_00, summary grounded (no hallucination), no Zoom-style freeze. 523 tests green, all on `main` (private repo ynaamane/meeting-scribe).

## Open bugs

- **BUG3 (open, being fixed)** — mic↔system track offset wrong (`mic_start_offset_seconds: -28.3`) → the Owner line renders at a bogus timestamp ([59:51]) and the transcript is out of chronological order. Fix in progress. Repro: `~/ownscribe/2026-07-24_1756_emerging-internet-force-impact/`.

## Closed bugs (verified)

- **BUG0 (CRITICAL, closed)** — CoreAudio tap froze Zoom + no permission prompt. Root cause: no NSAudioCaptureUsageDescription Info.plist embedded → no prompt possible → unauthorized tap stalled CoreAudio for ~60s (froze the call). Fix: embedded Info.plist (verified in the binary via otool/strings) + a CGPreflightScreenCaptureAccess fail-loud guard before creating the tap. On macOS 26.1+/27 the tap rides the existing Screen Recording grant (so no prompt fired on this machine — expected).
- **BUG1 (closed)** — diarization produced no speaker labels on `resume`. Root cause: `resume`/`reprocess` had no `--diarize` flag → diarization stayed off by default. Fix: added `--diarize` to both. (Confirmed in the real test: Owner vs SPEAKER_00 split correctly.)
- **BUG2 (closed)** — summary invented names/action-items (John/Sarah/Mark) absent from the audio. Fix: prompt now forbids inventing names + writes "None mentioned." for empty sections, PLUS a deterministic grounding.py that flags ungrounded capitalized words (warn-only). Verified with real phi-4-mini inference (twice) + confirmed grounded in the real solo test.

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
- Audio is RETAINED → `./rec.sh redo <dir>` re-runs after a fix (e.g. once BUG3 lands, redo this test dir to see correct ordering).

## Menu-bar app (in progress)

SwiftUI MenuBarExtra app scaffolded + runs in dev (`swift run OwnscribeMenuBar`), drives the existing CLI venv, coexists with the CLI. FINAL phase in progress: package a real `.app` signed with a STABLE self-signed cert (so macOS permissions granted once survive rebuilds). Build/recreate steps → BUILD.md; first-launch checklist → APP_TEST.md (both coming with the packaging commit).

## Deferred / out of scope (by design)

- Notarization (self-signed is fine for personal use; only needed to distribute to other Macs).
- Target-speaker extraction for the conference-room simultaneous-overlap case (physical ceiling; enroll + manual cleanup instead).
- Bundling Python+models into the .app (v1 drives the existing repo venv).
- MPS as default (stays CPU until the token pass clears it; ASR is CPU-bound anyway).
