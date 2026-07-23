# Build notes — meeting-scribe (forked from paberr/ownscribe)

## Origin

Forked via `git clone https://github.com/paberr/ownscribe` (MIT), commit `afc1d18` (`Fix audio dir cleanup and rename edge cases`) on 2026-07-23. `.git` history kept. Working branch: `meeting-scribe-build`. No upstream remote push planned — this is a personal fork, diverging intentionally (privacy defaults inverted, new enrollment/naming layer, Canary A/B).

## Pinned toolchain (2026-07-23, Apple Silicon, macOS 27.0 build 26A5388g)

- Python: 3.12.5 (pyenv, `.python-version` pins `3.12`)
- uv: 0.11.30
- Swift: 6.3.3 (swiftlang-6.3.3.1.3), target arm64-apple-macosx28.0
- ffmpeg: 8.1.2 (homebrew, `/opt/homebrew/bin/ffmpeg`)

## Pinned Python deps (`uv sync --extra all`, from `uv.lock`)

- torch: 2.8.0 (MPS available + built: True)
- torchaudio: 2.8.0 (pinned `<2.9` in `pyproject.toml` — 2.9 removed `list_audio_backends()` which pyannote-audio still calls; see upstream `pyannote/pyannote-audio#1974`)
- whisperx: 3.8.5
- faster-whisper: 1.2.1 (whisperx's ASR backend)
- pyannote.audio: 4.0.4
- pyannote-core: 6.0.1, pyannote-pipeline: 4.0.0, pyannoteai-sdk: 0.4.0
- llama-cpp-python: bundled via base deps (local summarization)
- click: 8.x, sounddevice: 0.5.5, soundfile: 0.13.1

Full lockfile: `uv.lock` (144 packages resolved).

## Known non-fatal warning — torchcodec dylib load failure

`pyannote.audio.core.io` emits a `UserWarning` on import: torchcodec's bundled `libtorchcodec_core{4,5,6,7}.dylib` binaries reference `@rpath/libavutil.{56,57,58,59}.dylib` that aren't present (torchcodec ships prebuilt FFmpeg-linked binaries; none of the 4 versions it tries match what's resolvable on this machine's rpath). This affects pyannote's _file-path_ audio decoding fallback only.

**Not fatal for this project**: the diarization call path in `whisperx_transcriber.py::_diarize` always constructs an in-memory `{"waveform": tensor, "sample_rate": int}` dict (mirroring whisperx's internal helper) and never passes a bare file path to pyannote — which is exactly the workaround torchcodec's own warning suggests. Confirmed by reading `_diarize()`: it builds `audio_data` from the already-loaded `whisperx.load_audio()` numpy array, never round-trips through disk for pyannote. No action needed unless a future patch adds a direct-path pyannote call.

## Task#1 — capture-scope finding (system-wide vs per-app)

See `swift/Sources/AudioCapture.swift`, `SystemAudioCapture` class (lines 364-653) and `src/ownscribe/audio/coreaudio.py`.

**`SystemAudioCapture` capture-mode-all path (`--capture-mode-all` CLI flag, `config.audio.capture_mode = "all"`) is SYSTEM-WIDE, not scoped to a single app.**

Evidence (`AudioCapture.swift:402-409`):

```swift
if captureModeAll {
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
    guard let display = content.displays.first else { throw CaptureError.noDisplay }
    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
    try await self.beginCapture(with: filter)
}
```

This builds an `SCContentFilter` scoped to the **display** (`SCContentFilter(display:excludingApplications:exceptingWindows:)`), with an **empty** `excludingApplications` array — i.e. it excludes nothing and captures every app's audio mixed into the display's audio output. ScreenCaptureKit's per-display audio filter captures the full system audio mix at the OS level, equivalent to "Share System Audio" in the macOS screen-sharing picker. This is corroborated by `config.capturesAudio = true` + `excludesCurrentProcessAudio = true` (line 455-456) — the only exclusion is the capturing process itself (ownscribe-audio's own output, which has none), not other apps.

The **default path** (no `--capture-mode-all`, `capture_mode = "picker"`) instead shows the OS `SCContentSharingPicker` (lines 411-423), which lets the user pick `.singleWindow`, `.singleDisplay`, or `.singleApplication` — so picker mode CAN be scoped to one app/window if the user chooses that, but `.singleDisplay` in the picker is the same system-wide capture as `capture-mode-all`, just interactively selected each run.

**Conclusion — covers the multi-source requirement:** `capture_mode = "all"` captures the Mac's full audio output mix — Zoom (native app), WhatsApp (native app), and Meet/Teams/Discord running as tabs inside one Dia browser process — all simultaneously and by construction, because it taps the display's mixed audio output, not any particular process. No per-app allowlist/bundle-id patch is needed for the "capture everything" requirement. This is GOOD — matches the goal directly. Task#3 (default is currently `picker`) flips the default to `"all"` so this is automatic without an interactive picker each run — see the capture-source matrix below.

### Capture-source matrix (Task#1 deliverable)

| Source          | App type                                                       | Capture path                                                               | Status                                                      |
| --------------- | -------------------------------------------------------------- | -------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Zoom            | native macOS app                                               | `capture_mode="all"` → SCStream on display, mixes Zoom's Core Audio output | Covered — system-wide capture, no Zoom-specific code needed |
| WhatsApp        | native macOS app                                               | same as above                                                              | Covered                                                     |
| Google Meet     | web app inside Dia (single browser process)                    | same as above — Dia's audio output is part of the display mix              | Covered                                                     |
| Microsoft Teams | web app inside Dia                                             | same as above                                                              | Covered                                                     |
| Discord         | web app inside Dia (or native — either way, Core Audio output) | same as above                                                              | Covered                                                     |
| Owner's mic     | AVAudioEngine default/named input device (`MicCapture` class)  | separate tap, independent of ScreenCaptureKit                              | Covered — see Task#4 (separate track retention)             |

All 5 target sources plus mic are captured by the SAME two taps (`SystemAudioCapture` for display-mix, `MicCapture` for the input device) regardless of which app or which browser tab is active — because the capture point is the OS audio mixer output, not any per-app hook. No bundle-id polling, no per-source integration code, no Dia-specific patch required. This directly satisfies Task#9's "source-agnostic … not bundle-id polling" requirement as a side effect of how ScreenCaptureKit's display-scoped filter already works — confirmed by reading the Swift source, not assumed.

## Task#1 — pytest baseline

`uv run pytest -q` → **256 passed in 7.04s**. No `hardware`/`macos` markers skipped in this run (both apply and this machine is macOS with audio hardware present, but no live hardware-marked test ran a real capture — confirmed no failures, no skips reported in the summary line).

## Task#2 — diarization device + pyannote model

Two of the three asks in this task were already true upstream, confirmed by reading code rather than assumed:

- **pyannote model default is already `community-1`.** `whisperx.diarize.DiarizationPipeline.__init__` (installed 3.8.5) resolves `model_config = model_name or "pyannote/speaker-diarization-community-1"`, and `_load_diarization_pipeline()` in `whisperx_transcriber.py` never passes `model_name`. Upstream's own commit `26f5fc3` ("Require pyannote-audio>=4 and cover DiarizeOutput unwrap with a test") plus the existing `test_diarize_unwraps_speaker_diarization_from_diarize_output` test already pin this. No patch needed.
- **`HF_TOKEN` env var already flows into config.** `config.py::Config.load()` does `if hf_token := os.environ.get("HF_TOKEN"): config.diarization.hf_token = hf_token`. No patch needed.

What changed: **removed the `diarization.device` config knob** (`"auto"` / `"mps"` / `"cpu"`) and the `_resolve_diarization_device()` static method entirely. `_load_diarization_pipeline()` now always passes `device="cpu"` as a hardcoded literal to `DiarizationPipeline(...)`, which forwards it to pyannote's `Pipeline.from_pretrained(...).to(torch.device("cpu"))` — confirmed by reading `whisperx/diarize.py::DiarizationPipeline.__init__` directly.

**Flag on the premise, for the record — the MPS-broken claim traces to pytorch issues from 2022-2023 (`aten::_fft_r2c` not implemented on MPS: pytorch/pytorch#78044, #98272; wrong diarization timestamps on MPS: pyannote/pyannote-audio#1337), all of which were fixed by pytorch PR #119670, merged into torch 2.3 (Feb 2024).** The pinned stack here is torch 2.8.0 — five minor versions past that fix. An empirical repro on this machine confirmed `torch.stft`, `torch.fft.rfft`, and `torchaudio.functional.resample` all succeed on MPS with torch 2.8.0 (no crash, correct output shapes/dtypes). This directly contradicts the specific failure mode ("wrong timestamps, aten::_fft_r2c unimplemented") as currently described — it may have been accurate against an older torch pin ownscribe or a fork once used, but is not reproducible against what's actually installed here.

**Could not fully close this either way**: `pyannote/speaker-diarization-community-1` is HF-gated and no `HF_TOKEN` was available in this session, so the real model could not be downloaded and run end-to-end on MPS to check for correctness regressions beyond the raw FFT op (segmentation/embedding models may have their own MPS edge cases the raw op-level repro doesn't cover). Implemented the instruction as given (CPU always) since it is the safe, never-wrong choice for a feature this deliverable depends on (speaker naming), and CPU diarization on typical meeting-length audio is not the bottleneck relative to Whisper large-v3 transcription. But this is a **reversible decision made on a possibly-stale premise**, not a verified-necessary one — flagging to team-lead in case there's appetite to re-open this once HF access is available, since MPS would meaningfully speed up diarization if it's actually safe on this torch version.

**Regression test added** (`tests/test_transcription.py::TestDiarizationApiCompat::test_load_diarization_pipeline_always_forces_cpu`): asserts `DiarizationPipeline` is always called with `device="cpu"`, pinning the invariant against a future reintroduction of the device knob.

**Test-suite flake found and fixed during this task** (not a product bug): an early version of the new test mocked `torch.backends.mps.is_available` to prove the CPU-forcing behavior held even when MPS looked available — but `_load_diarization_pipeline()` no longer touches `torch` at all (the device is a hardcoded string literal now), so that mock was patching a function the code path under test never calls. Empirically, across 3 full-suite reruns with that dead mock in place, failures appeared 3 different ways (0, 1, then 3 failing tests, all inside `TestDiarizationApiCompat`, all raising `RuntimeError: function '_has_torch_function' already has a docstring` deep in `torch/overrides.py`) — a nondeterministic torch-submodule-reimport interaction, not a real regression. Confirmed via: (a) the identical failing test passed in isolation every time, (b) the unmodified baseline (via `git stash`) passed 3/3 full-suite runs, (c) after removing the dead mock, 5/5 full-suite reruns passed clean at a deterministic 252 (256 baseline − 5 removed device-knob tests + 1 new CPU-forcing test). Lesson: don't mock a dependency the code path no longer calls, even "just to be thorough" — it's not free, and with torch specifically it can introduce flake via internal docstring/override registration state that isn't idempotent across repeated mock-patch cycles in the same process.

pytest after this task: **252 passed** (deterministic across 5 consecutive full-suite runs). ruff: clean.

## Task#3 — large-v3 default + bilingual initial_prompt

Changed `TranscriptionConfig.model` default from `"base"` to `"large-v3"`, and `TranscriptionConfig.initial_prompt` default from `""` to a new `BILINGUAL_INITIAL_PROMPT` constant (a natural FR/EN code-switched sentence, not a meta-instruction — see rationale below). Both the dataclass default AND `DEFAULT_CONFIG_TOML` (the scaffold `ownscribe config` writes for a fresh install) were updated and now share the same constant via a `.replace()` substitution, so they cannot drift apart.

**Verified `initial_prompt` actually reaches every transcribed segment, not just the first.** Read `whisperx/asr.py::WhisperModel.generate_segment_batched` (the whisperx 3.8.5 batched-inference path): it builds `all_tokens` from `options.initial_prompt` once per `transcribe()` call, then does `[prompt] * batch_size` — the identical prompt is applied to every VAD-segmented batch, matching the class's own docstring ("fixed prompt for all samples in batch"). So a config-level default primes vocabulary/style consistently across an entire meeting, not just the opening seconds.

**Found and documented a real limitation while verifying this** (not something Task#3 asked to fix, but load-bearing context for anyone relying on "auto-detect" for code-switching): WhisperX's `transcribe()` calls `detect_language()` **once** on the first 30s of audio and locks a single `Tokenizer` for that language for the rest of the file (`asr.py::transcribe`, `if self.tokenizer is None: language = language or self.detect_language(audio)`). `language = ""` (auto-detect) is therefore a per-file majority-vote lock, not per-segment/per-speaker detection — confirmed by reading the call path, not assumed. This matches the community's own conclusion (`openai/whisper` discussion #49): "I don't think Whisper was designed with code-switching in mind... assumes the full audio is in a single language through the initial language detection for the first 30s." `initial_prompt` cannot override this — it primes vocabulary via token continuation (the model decides what comes next given the prompt as prior context), not instruction-following (confirmed via the OpenAI cookbook's prompting guide: "The prompt will not override the model's comprehension of the audio"). This is the concrete reason Task#6 (LLM post-correction) and Task#9 (Canary MLX, which takes explicit `source_lang`/`target_lang` per the planner's own task description) exist as separate mitigations — intra-sentence code-switching is a known Whisper architecture limit, not something a better prompt string fixes alone.

**Prompt content choice**: a natural bilingual sentence in continuation style (`"On continue le sprint review, on regarde le backend et le pipeline de deployment. Let's also check the roadmap and merge the feedback from last time."`) rather than a meta-instruction (`"You are a bilingual transcriber..."`). This follows the OpenAI cookbook's documented guidance that Whisper prompts work by example/continuation, not instruction — a prompt describing the desired style needs to be an instance of that style, not a description of it. The sentence mixes common meeting/tech vocabulary (sprint review, backend, pipeline, deployment, roadmap, merge, feedback) in both languages so both the code-switching pattern and the jargon are primed together. Fully overridable via `--initial-prompt` (CLI) or `initial_prompt` (config) — the CLI flag only overrides when explicitly passed (`cli.py`: `if initial_prompt: config.transcription.initial_prompt = initial_prompt`), so the new non-empty default doesn't block a user from setting their own.

**Bug caught during implementation**: the first attempt made `DEFAULT_CONFIG_TOML` an f-string to interpolate the prompt directly. This broke module import outright — `NameError: name 'transcript' is not defined` — because the SAME triple-quoted string already contains an unrelated example comment further down (`# prompt = "Summarize:\\n{transcript}"`, for the user-defined-templates feature), and Python's f-string parser tried to evaluate that `{transcript}` as an expression too. Caught immediately by import (any test touching `ownscribe.config` fails at collection) and confirmed fixed via an empirical `tomllib.loads()` round-trip showing the parsed `initial_prompt` matches the constant byte-for-byte and the unrelated `{transcript}` comment is untouched. Fixed by reverting to a plain (non-f) triple-quoted string with a placeholder token, substituted via `.replace()` after the literal — avoids the f-string parser touching any other `{...}` in the same text.

pytest after this task: **253 passed** (deterministic across 4 consecutive full-suite runs, +1 net test: added `test_default_transcription_initial_prompt_is_bilingual`, updated `test_default_transcription_model`, extended `test_creates_file_when_missing` to assert the scaffolded file contains the real prompt and not the placeholder token). ruff: clean.
