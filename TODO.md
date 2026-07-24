# TODO — meeting-scribe

## Status: code-complete, awaiting the final token/real-audio verification pass

17/18 build tasks done, 504 tests green, working tree clean at `de4d7df`. Everything below is what CANNOT be closed without Yanis's HuggingFace token + his real machine/apps/audio — it was deferred by design to a single end-of-build pass, not skipped.

## The final verification pass (needs YOU — ~10 min)

Run `scripts/verify_with_token.py` after:

1. **Create a HuggingFace token + accept model licenses**
   - Sign up at huggingface.co (free)
   - Accept conditions on https://huggingface.co/pyannote/speaker-diarization-community-1
   - (optional, only to re-test the pilot) accept https://huggingface.co/nvidia/canary-1b-v2
   - Generate a token at https://huggingface.co/settings/tokens
   - `export HF_TOKEN=hf_xxxxx`

2. **What the script closes in one pass** (7 checks, PASS/FAIL/SKIP):
   - [ ] community-1 loads + diarizes a real WAV end-to-end (proves the whole gated path)
   - [ ] enrollment separation: does the 0.65 cosine threshold actually separate YOUR colleagues' voices? (measure intra vs inter-speaker distance, tune if needed)
   - [ ] standalone-enroll embedding space == in-meeting embedding space (same vectors, same audio)
   - [ ] owner mic-track labeling on a real dual-track capture
   - [ ] MPS vs CPU end-to-end diff — does community-1 on MPS produce the #1886 wrong-output/all-speaker-0 mode, or is MPS safe on torch 2.8? (op-level already passes; only the full pipeline is unverified). If MPS is clean → big speedup unlock.
   - [ ] Canary A/B re-run on YOUR real code-switched audio (the FEBLOC fallback said Canary loses by 66pts on switch spans; confirm on your own audio)

3. **The 5-source capture matrix (Task#11, needs your live apps)** — play audio in each, confirm non-silent system.wav:
   - [ ] Zoom (native app)
   - [ ] WhatsApp (native app)
   - [ ] Google Meet (web tab in Dia)
   - [ ] Microsoft Teams (web tab in Dia)
   - [ ] Discord (web tab in Dia)
   - Note: the CoreAudio global tap SHOULD get all 5 at once (proven headless with a synthetic tone + FFT), but the archcheck flagged that some apps don't always land in a stereo-mix tap — this is the one thing to prove empirically before trusting it.

4. **AEC on real human speech** — the `--echo-cancellation` path is verified against a synthetic tone (~800x suppression, but that was Apple's audio-ducking on a tone, not validated on a real voice). Test on speakers with a real call: does it clean the bleed WITHOUT degrading your own-voice transcript? Default stays `off`; `auto` enables it only on built-in speakers.

## Known minor issue (non-blocking)

- `verdict.md` prints `mean_rtf=nan` (run_pilot.py:246 reads `mean_rtf` as a dict key, but it's a computed @property on ThermalTestResult — never serialized). The real per-iteration RTF values ARE in `results.json`'s `iterations[]`. Cosmetic report-writer gap; fix whenever pilot/ is next touched.

## Recommended usage (documented, no code needed)

- **Wear headphones** for cleanest own-voice/call separation (physically perfect by construction). Speaker mode works but see `--echo-cancellation`.
- Enroll recurring colleagues once (`ownscribe enroll --name "X" clip.wav`) → auto-named in every future meeting.
- Buggy transcript? `ownscribe reprocess <recording-dir>` re-runs from retained audio, no re-recording.

## Deferred / out of scope (by design)

- Target-speaker extraction for the conference-room simultaneous-overlap case — rejected (wrong direction, no Mac/FR artifact, degrades ASR). The N-people-one-channel overlap is an accepted physical ceiling; enroll room participants for solo-turn naming + manual cleanup on true overlaps.
- MPS as default — stays CPU until the token pass confirms MPS is clean end-to-end (the whole pipeline is CPU-bound anyway: CTranslate2 has no Metal backend).
- Retention consent/legal note — recording other call participants; add a "call is transcribed" notice per your context.
