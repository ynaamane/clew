# LESSONS_LEARNED — meeting-scribe

Bug journal + key decisions. Read before debugging. Format: what broke / root cause / fix / where.

## Architecture decisions (why the stack is what it is)

- **Fork ownscribe, don't greenfield.** It already ships the hardest part — macOS audio capture with separate mic+system taps, whisperx+pyannote pipeline, per-speaker Markdown/JSON output. Building from scratch was over-engineering.
- **Whisper large-v3, NOT turbo, NOT Parakeet, NOT Canary.** large-v3 wins on FR/EN. Turbo's pruned decoder is weaker on French. Parakeet has NO language conditioning → involuntarily TRANSLATES spontaneous French to English (silent falsification — disqualifying). Canary was a real A/B candidate (has source_lang) but the pilot on real code-switched audio showed it LOSES by 66pts on switch spans → whisperx stays default.
- **Capture = CoreAudio process tap (macOS 14.2+), NOT ScreenCaptureKit.** SCK requires Screen Recording permission even for audio-only. The CoreAudio tap uses the audio-only permission (assures the user the app can't see the screen) AND is testable headless. SCK kept as a <14.2 fallback.
- **Your voice vs the call = TWO PHYSICAL SOURCES**, not diarization: your mic (what you send) = mic.wav = "Owner", the system tap (what you receive) = system.wav = diarized. Perfect separation by construction — but only on HEADPHONES (see echo below).
- **Diarization: pyannote community-1 on CPU, never MPS.** The whole ASR path is CPU-bound anyway (CTranslate2 has no Metal backend), so forcing CPU costs nothing extra. MPS re-test deferred to the token pass.
- **Naming reuses pyannote's own per-cluster embeddings** (DiarizationPipeline return_embeddings=True) — no separate ECAPA/SpeechBrain dependency.

## Bugs caught during the build (by verification, not inspection)

- **13GB / 38.9h output from a 3s capture (pre-existing in ownscribe).** A CoreAudio tap temp file with real bytes but no `data` chunk (RIFF→JUNK→fmt→FLLR) fed a corrupt frame count into mergeAudioFiles. Fix: real frame-count check (`openAudioFileWithFrames`) instead of the byte-size heuristic. Git-stash-verified as pre-existing before fixing. Would have blown up on the first real call.
- **torchcodec fails to load (FFmpeg version mismatch).** Venv's torchcodec links FFmpeg 4-7 (libavutil.56-59); the machine has FFmpeg 8 (libavutil.60). Upgrading torchcodec needs torch≥2.9, conflicts with the torchaudio<2.9 pin → dead end. Fix: bypass torchcodec entirely — pyannote's Audio.**call** takes a preloaded `{"waveform","sample_rate"}` dict (checked FIRST, before the AudioDecoder path), which is exactly what _diarize() and whisperx.load_audio() already feed it. Pinned with a test asserting torchcodec never enters sys.modules.
- **Silent binary regression.** coreaudio.py downloaded ownscribe's UPSTREAM prebuilt binary when the local Swift build hadn't run (bin/ is gitignored) → separate-track retention silently regressed to merged-only, no error. Fix: `binary_supports_separate_tracks()` probe → fail loud instead of silently degrading.
- **mlx-audio ↔ whisperx dependency conflict (irreducible).** mlx-audio≥0.4.1 needs huggingface-hub≥1.0; whisperx caps <1.0. No config-only fix works (uv.lock pins one version project-wide regardless of extras/markers). Fix: Canary runs in a subprocess `uv run --with mlx-audio` overlay — never added to pyproject.toml. Base venv stays bit-identical.
- **AVAudioEngine self-pins the OUTPUT running-bit.** Starting a mic tap flips the default-output "running" bit true even in silence (framework render-graph artifact, not our code — bisected with 3 controls). Doesn't corrupt watch-activity today (watch + capture never run concurrently) but documented as a live constraint for any future concurrent consumer of that property.

## Process lessons

- **Empirical > recalled specs.** The Canary brief had 4/5 technical details wrong (they came from an HF model card, not the source): mlx-audio version (0.4.1 not 0.2.x), `language=` handling, `no_repeat_ngram_size` (doesn't exist), the "15s window" (conflated with a different model's VAD). All caught by reading the real source + isolated repro before writing code. Same for the "MPS broken" premise — the 2022 bug was fixed in torch 2.3; verified with a live repro on torch 2.8.
- **Disk is ground truth, not a message saying "we built X".** Two lead directives (CoreAudio tap; mic-activation trigger) were reported as decided/built but weren't in the code — caught by grepping the actual repo, not trusting the message.
- **Don't delete an artifact before independent verification.** The 60-min thermal results dir was cleaned up before the lead could verify it → had to reconstruct from the harness-persisted tool-output. Leave artifacts until signed off.
- **GDPR Art.9 (voiceprints = biometric data) is cleared for this use** (user confirmed authorized). Still: keep the repo PRIVATE, keep a "call is transcribed" notice, define a retention/purge policy.

## Thermal (verified)

large-v3 CPU on this Mac: 165 back-to-back transcriptions over a real 3605s hour, mean RTF 0.717 (well under 1.0), peak RSS 9.3GB, zero thermal warnings across 122 samples. Sustained-hour envelope holds.
