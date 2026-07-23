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

## Task#4 — capture_mode=all default + retained mic/system tracks + owner auto-label

Two independent changes: (1) flipped `AudioConfig.capture_mode` default from `"picker"` to `"all"` so system-wide capture (confirmed system-wide in Task#1) happens automatically with no per-run interactive prompt; (2) retained `mic.wav`/`system.wav` as separate persistent files alongside the merged `recording.wav`, and wired the pipeline to diarize only `system.wav` while auto-labeling every `mic.wav` segment as the owner (100%-known speaker, per the task's own premise — never sent through diarization, never at risk of a wrong speaker-cluster assignment).

### capture_mode default flip

Straightforward: `AudioConfig.capture_mode` dataclass default + `DEFAULT_CONFIG_TOML` scaffold + README both changed `"picker"` → `"all"`. `tests/test_pipeline.py::TestCreateRecorder::test_capture_mode_defaults_to_all` pins the new default; `test_capture_mode_picker_override_passed_to_coreaudio` (renamed from `test_capture_mode_passed_to_coreaudio`, which used to test "all" as the override case — now it's the default, so the override case being tested is "picker") keeps override coverage. `test_default_capture_mode_all` added to `test_config.py`.

### Swift-side track retention (`swift/Sources/AudioCapture.swift::mergeAudioFiles`)

Added a copy-before-consume step at the top of `mergeAudioFiles`: before any of the existing merge/rename/delete branches run, `system.tmp.wav` → copied to `system.wav` and `mic.tmp.wav` → copied to `mic.wav` (both in the same directory as the final merged output), gated by the same `wavHeaderSize` empty-check the rest of the function already uses. Every existing branch (both-empty, mic-empty-rename-only, full-merge) runs completely unmodified afterward — this is a strictly additive change, confirmed via `git diff` showing zero deletions in the pre-existing logic.

Also added `writeTrackAlignmentSidecar(outputDir:micStartOffsetSeconds:)`, called once inside the full-merge branch (the only branch where BOTH tracks have real audio and an alignment offset is meaningful) right after the existing `offsetSeconds` calculation. Writes `track_alignment.json` with `{"mic_start_offset_seconds": <float>}` next to the retained tracks. Reuses the SAME `offsetSeconds` variable the existing merge math already computes from `mach_timebase_info` deltas between `systemStartHostTime`/`micStartHostTime` — no new alignment logic, just exposing the existing one.

**Why the sidecar is necessary, not optional**: confirmed by reading `MicCapture.start()` (sets `startHostTime` on the first `AVAudioEngine` tap callback) and `SystemAudioCapture.beginCapture()` (sets `startHostTime` via `mach_absolute_time()` on the first `SCStream` sample buffer) — the two capture engines start asynchronously (`main()` starts `MicCapture` synchronously, then kicks off `SystemAudioCapture.start()` in a `Task`), so their t=0 is NOT the same wall-clock moment. Verified empirically: an isolated harness calling `mergeAudioFiles` directly with hostTime deltas corresponding to a 300ms real skew produced `mic_start_offset_seconds: 0.29999999999999993` (float noise, harmless) with the correct sign in both directions (mic-later → positive, mic-earlier → negative, matching the pre-existing `micStartNanos - systemStartNanos` convention). Without this offset, a Python-side consumer transcribing the two retained tracks independently and merging by raw segment `.start` time would silently misalign them by however much the two engines' startup latencies differ.

**Verification method (no Swift test infra exists in this repo — confirmed by `find swift -iname "*test*"` returning nothing, and no test job in `.github/workflows/ci.yml` beyond `swift/build.sh`)**: extracted `mergeAudioFiles` + `writeTrackAlignmentSidecar` into an isolated `/tmp` Swift file (self-contained, only depends on `AVFAudio`/`Foundation`/`FileManager`/`mach_timebase_info`) alongside a tiny CLI driver, compiled with `swiftc`, and ran it against synthetic sine-wave WAVs (`ffmpeg -f lavfi -i "sine=..."`) covering all 4 branches:

- both tracks present → merged.wav + system.wav + mic.wav all correct, MD5-identical to source temp files, `.tmp.wav` correctly deleted, sidecar correctly written with the right sign both directions
- mic empty (rename-only branch) → system.wav retained (192092 bytes exact), no spurious empty mic.wav, no sidecar (no alignment target)
- both empty → no wav files at all, no sidecar
- system empty (mic-only, still reaches the full-merge branch since only `micFile` is `try`-force-unwrapped) → mic.wav retained, sidecar written with offset forced to `0.0` (no system track to align against)

This is the maximum verification tier available without either live audio hardware + TCC permissions (not available in this automated session) or adding new Swift test infrastructure (out of this task's scope — CI only ever compiles the binary, never unit-tests it; a real `XCTest` target would be a separate infra task).

### Python-side: selective diarization + merge (`src/ownscribe/pipeline.py`, `src/ownscribe/transcription/whisperx_transcriber.py`)

`WhisperXTranscriber.transcribe()` gained an optional `diarize: bool | None = None` parameter. `None` (the default, used by every existing caller) preserves the exact prior behavior (diarize iff `self._diar_config.enabled`); `diarize=False` force-skips diarization regardless of config — this is what lets the SAME transcriber instance diarize `system.wav` normally and skip diarization on `mic.wav`. Backward compatible: `pipeline.py`'s only other caller (`transcriber.transcribe(audio_path)`, single-track path) passes no `diarize` arg at all.

Reusing one `WhisperXTranscriber` instance across both tracks is not just convenient — it's strictly cheaper than two instances, confirmed by reading the caching: `self._model` (Whisper) loads once (`if self._model is None:` guard in `_prepare_transcription_models`), `self._align_models` caches per language, `self._diarize_model` loads once. Calling `.transcribe()` twice on one instance means the ~large-v3 model and the diarization pipeline are each loaded ONCE for both tracks, not twice.

New `pipeline.py` functions (all pure/small, each independently pytest-covered in `tests/test_pipeline.py`):

- `_find_dual_tracks(audio_path)` — returns `(system_path, mic_path)` if both exist next to `audio_path`, else `None`. This is the single gate everything else depends on.
- `_read_mic_start_offset(audio_path)` — reads the sidecar Swift writes; returns `0.0` on missing/malformed/missing-key (never raises).
- `_shift_result(result, offset)` — returns a new `TranscriptResult` with every segment AND word start/end shifted (uses `dataclasses.replace`, never mutates the input — verified by a dedicated `test_does_not_mutate_original`).
- `_tag_speaker(result, label)` — returns a new `TranscriptResult` with every segment's `speaker` forced to `label`, overwriting whatever whisperx/pyannote produced (irrelevant here since diarization is skipped on this track, but the function itself doesn't assume that).
- `_merge_dual_track_results(system_result, mic_result, mic_offset)` — shifts+tags the mic result, concatenates with the system result's segments, sorts by `start`, takes `max(system.duration, mic.duration + mic_offset)` as the merged duration.
- `_transcribe_dual_track(transcriber, system_path, mic_path, mic_offset)` — the orchestrator: `transcriber.transcribe(system_path)` (diarized per config) then `transcriber.transcribe(mic_path, diarize=False)` (never diarized), merged.

`_do_transcribe_and_summarize` (the shared record+transcribe+summarize core used by `run_pipeline`, `run_transcribe`, and `run_resume`) now calls `_find_dual_tracks(audio_path)` first; if both tracks exist, it goes through `_transcribe_dual_track` with the sidecar offset, otherwise it's the exact prior single-track call. This means `run_resume` on a retained dual-track directory automatically re-transcribes BOTH tracks and merges them — a free consequence of putting the detection inside the shared function, not something separately wired.

**Speaker label choice**: a fixed string constant `_OWNER_SPEAKER_LABEL = "Owner"`, not a name. Naming the owner by their real name is Task#5's job (the enrollment/naming DB) — this task only guarantees the owner's segments are correctly separated from the diarized remote speakers and never miscounted as one of pyannote's numbered clusters. Verified end-to-end at the output layer: a hand-built `TranscriptResult` with alternating `SPEAKER_00`/`Owner` segments through `format_transcript()` renders a clean alternating-speaker markdown transcript with correct per-segment timestamps.

### Gap surfaced, not silently absorbed

The planner's original brief included a "Task#8 — AUDIO RETENTION (HIGH priority)" section (retain mic.wav+system.wav+merged per recording in a stable archive dir, `retain_audio` config flag default TRUE, a retention policy, a `reprocess <recording-id>` command) that does not appear as a tracked task in this session's TaskList (P0-P10 cover capture/diarization/transcription/enrollment/correction/permissions/Canary/pilot/auto-detect/verification-matrix — no explicit retention-policy or `reprocess` command task). This task (P3) implements the CAPTURE-SIDE mechanics that retention depends on (the tracks now physically persist next to the transcript instead of being deleted), and `run_resume` already provides a form of "reprocess from retained audio" for free. But the explicit config flag (`retain_audio` default true, inverting upstream's delete-after-transcribe default), a stated retention policy (keep N days / forever / manual purge), and a dedicated `reprocess <recording-id>` command are NOT built here — they were not in my assigned task list, and building them unasked would be scope creep beyond what was delegated. Flagging this explicitly to team-lead rather than either quietly building it (scope creep) or quietly dropping it (silent gap) — see the final report.

pytest after this task: **278 passed** (deterministic across 4 consecutive full-suite runs; +21 net new tests across `TestFindDualTracks`, `TestReadMicStartOffset`, `TestShiftResult`, `TestTagSpeaker`, `TestMergeDualTrackResults`, `TestTranscribeDualTrack`, `TestDoTranscribeAndSummarizeDualTrack`, plus `TestDiarizeOverride` in `test_transcription.py`). ruff: clean. Swift: compiles clean (`swift/build.sh`), manually verified via isolated harness (see above) since no Swift test infra exists in this repo.

## Task#5 — persistent voiceprint enrollment + naming

New `src/ownscribe/speakers/` subpackage (matching the existing per-stage-subpackage convention of `audio/`, `transcription/`, `summarization/`, `output/`): `base.py` (storage), `matching.py` (cosine similarity + assignment), `embedding.py` (extraction).

### Reused the diarization embedding model directly — no extra model download

Confirmed by reading `whisperx.diarize.DiarizationPipeline.__call__` (installed 3.8.5): it already supports `return_embeddings=True`, returning `output.speaker_embeddings` — a `(num_speakers, dimension)` numpy array from pyannote's own `DiarizeOutput` dataclass (`pyannote/audio/pipelines/speaker_diarization.py:63-75`, docstring confirms "one speaker embedding per speaker... sorted in speaker_diarization.labels() order"), already a per-cluster CENTROID (`speaker_embeddings=centroids` at the two `DiarizeOutput(...)` construction sites in that file) — not something I need to average myself. `_diarize()` in `whisperx_transcriber.py` calls the raw pyannote pipeline directly (`diarize_model.model(...)`, bypassing whisperx's `DiarizationPipeline.__call__` wrapper), so the SAME `DiarizeOutput.speaker_embeddings` field is available on the object it already reads `.speaker_diarization` from — confirmed the model's `metric` property is `"cosine"` (`speaker_verification.py:685`), matching the cosine-similarity matching design directly, not an arbitrary choice.

For the standalone `enroll` command (a short reference clip, not a full meeting), the embedding model must be loaded independently — confirmed the exact right way to do this: `PretrainedSpeakerEmbedding({"checkpoint": "pyannote/speaker-diarization-community-1", "subfolder": "embedding"}, token=..., device="cpu")`, the identical dict-shaped checkpoint `SpeakerDiarization.__init__` uses internally (`speaker_diarization.py:201-204`) to construct `self._embedding`. Using a DIFFERENT default embedding model (e.g. the module-level default `hbredin/wespeaker-voxceleb-resnet34-LM` some pyannote classes default to) would have put enrollment embeddings in a different vector space than in-meeting diarization embeddings — cosine similarity between them would have been meaningless. Caught this before writing any code, by tracing `PretrainedSpeakerEmbedding`'s dispatcher (`speaker_verification.py:756-778`) and confirming it falls through to the pyannote-model path for a dict input, then confirming `get_model(self.embedding, ...)` is the same utility the segmentation model uses.

### Storage: JSON, not SQLite

The brief allowed either. Chose JSON: small N (a handful of enrolled people), no concurrent-writer requirement, and JSON is directly human-inspectable/editable — SQLite would be over-engineering at this scale. `VoiceprintDB` (`speakers/base.py`) is a plain dataclass with `load`/`save`/`upsert`/`remove`, stored at `~/.config/meeting-scribe/voiceprints/voiceprints.json` (the brief named `voiceprints/` explicitly as the directory).

**Bug caught before it could bite in production**: the first version wrote `def load(cls, path: Path = VOICEPRINT_DB_PATH) -> VoiceprintDB`, using the module constant as a signature default. Python binds a signature default ONCE at class-definition time, so `mock.patch("ownscribe.speakers.base.VOICEPRINT_DB_PATH", ...)` would silently do nothing to a call with no explicit `path=` arg — confirmed empirically with a throwaway repro before writing the fix. This would have made `VoiceprintDB.load()` (as called from `_relabel_speakers_with_voiceprints`, `run_enroll`, `run_unenroll`, `run_list_enrolled` — every real call site) permanently hard-wired to the real `~/.config/meeting-scribe` path in tests, with test isolation only accidentally working because this dev machine had no pre-existing voiceprints file. Fixed by resolving the default INSIDE the function body (`path: Path | None = None`, then `resolved_path = path if path is not None else VOICEPRINT_DB_PATH`), matching the pattern `config.py::Config.load()` already uses for `CONFIG_PATH`. Added `test_default_path_is_patchable_at_call_time` to pin this against regression. Caught the live consequence too: simulated a real on-disk voiceprints file during manual verification and watched 0 of the pre-existing `test_pipeline.py` mocked-transcriber tests fail only by accident (a bare `mock.MagicMock().last_speaker_embeddings` is truthy, not an empty dict) — hardened `_relabel_speakers_with_voiceprints` with an `isinstance(cluster_embeddings, dict)` guard so this doesn't depend on filesystem luck.

### Matching: cosine similarity, threshold-gated, never a forced wrong match

`speakers/matching.py::cosine_similarity` — plain dot-product-over-norms, `strict=True` on the `zip` (guarded by an explicit length check first, so the zip can never actually raise). `match_speaker` returns `None` below `DEFAULT_MATCH_THRESHOLD = 0.65` rather than the closest available name, satisfying the brief's explicit "NEVER force a match below threshold." `assign_speaker_names` gives unmatched clusters sequential `Unknown-1`, `Unknown-2`, ... labels (numbering only increments on actual misses, not on every cluster — verified with `test_unknown_numbering_does_not_skip_matched_clusters`).

### Pipeline wiring

`WhisperXTranscriber` gained `last_speaker_embeddings` (a `dict[str, list[float]]` property, populated by `_diarize()` via a new `_extract_cluster_embeddings` static method, empty dict when diarization didn't run or the pyannote object lacks the attribute — defensive `getattr(..., None)` check). `pipeline.py::_relabel_speakers_with_voiceprints(result, cluster_embeddings)` loads the DB, matches, and renames segment speaker labels; `_transcribe_and_identify(transcriber, audio_path)` wraps `transcriber.transcribe()` + relabeling into one call, used by BOTH the single-track path and the dual-track path's system-track leg in `_do_transcribe_and_summarize`/`_transcribe_dual_track`. The mic track (owner, `diarize=False`) is never passed through relabeling — it's already tagged `"Owner"` by the existing Task#4 logic, correctly bypassing the whole matching pipeline since the owner is a known speaker by construction, exactly as the brief specified.

### CLI: `enroll` / `unenroll` / `speakers`

`ownscribe enroll --name "Alice" clip.wav` → `run_enroll` in `pipeline.py`: checks `config.diarization.hf_token` is set (same token diarization needs — enrollment can't work without HF access to the gated embedding model, checked explicitly with a clear error rather than a stack trace on first use), computes the embedding via `SpeakerEmbedder`, upserts into the DB. `unenroll`/`speakers` are small CRUD companions (not explicitly requested in the brief, but a natural, low-cost complement — enroll without a way to fix a bad enrollment or list what's enrolled would be an obvious gap). Manually verified all three commands end-to-end with an isolated `HOME` env var (`speakers` on empty DB, seed a real voiceprint file, `speakers` finds it, `unenroll` removes it, `speakers` confirms empty again) — first attempt at manual verification used a wrong nesting level for the seed file (`voiceprints.json` instead of `voiceprints/voiceprints.json`) and correctly reported empty; this was MY test-setup mistake, not a code bug — re-verified at the correct path and confirmed working.

### Not verified — HF-gated model, no token available this session

Could not run `SpeakerEmbedder.embed_file()` or the full diarization-with-embeddings path against the REAL `pyannote/speaker-diarization-community-1` model — it's HF-gated and no `HF_TOKEN` was available in this session (same constraint noted in Task#2). Every embedding-extraction and matching code path is verified against the documented interface (read from pyannote's own source, not guessed) and unit-tested with synthetic embeddings, but the actual numerical behavior of the real WeSpeaker embedding model — whether real voices produce a clean separation at the 0.65 threshold, whether the community-1 embedding truly lives in the same space whisperx's raw `diarize_model.model(...)` call and my standalone `PretrainedSpeakerEmbedding` loader both draw from — is unverified end-to-end. This is a genuine external-credential gap, not a shortcut; flagging for team-lead/user once HF access is available for a real smoke test.

pytest after this task: **323 passed** (deterministic across 4 consecutive full-suite runs; new: `tests/test_speakers.py` 25 tests, plus new classes in `test_pipeline.py` (`TestRelabelSpeakersWithVoiceprints`, `TestTranscribeAndIdentify`, `TestRunEnroll`, `TestRunUnenroll`, `TestRunListEnrolled`) and `test_transcription.py` (`TestExtractClusterEmbeddings`, `TestLastSpeakerEmbeddings`)). ruff: clean.

## Task#6 — LLM post-correction pass for code-switch cleanup

New `src/ownscribe/correction.py` (a single top-level module, not a subpackage — matches `search.py`'s precedent: a self-contained feature with exactly one "backend" via the existing `Summarizer` interface, unlike `audio/`/`transcription/`/`summarization/`/`output/` which each have multiple concrete implementations behind an ABC). New `[correction]` config section (`enabled = false` default — opt-in per the brief; `max_length_delta_ratio = 0.4`).

### Reused ownscribe's existing LLM plumbing directly — confirmed the interface first

Every `Summarizer` implementation (`LlamaCppSummarizer`, `OllamaSummarizer`, `OpenAISummarizer`) already implements a generic `chat(system_prompt, user_prompt, json_mode, json_schema) -> str` method — an abstract method on the `Summarizer` base class, already used by `search.py` for its two-stage search pipeline. This is exactly "reuse ownscribe's existing local LLM path" — no new LLM-calling code needed, just a correction-specific prompt pair (`CORRECTION_SYSTEM`/`CORRECTION_PROMPT` in `summarization/prompts.py`, matching the existing `SEARCH_FIND_SYSTEM`/`SEARCH_FIND_PROMPT` convention) and a thin wrapper.

### Per-segment correction, never whole-transcript

`correct_transcript(summarizer, result, max_length_delta_ratio)` calls `correct_segment_text` once per `Segment`, touching ONLY `seg.text` via `dataclasses.replace` — every other field (`start`, `end`, `speaker`, `words`) is copied through untouched by construction, not by a rule I have to remember to follow. This directly satisfies the brief's "NEVER mutate timestamps/speaker tags/segment count": segment count can't drift because I map 1:1 over the existing list, and timestamps/speakers can't drift because `replace()` only overrides `text`. Rejected an alternative design (batching multiple segments into one LLM call for speed) specifically because it would let the LLM merge/split/reorder segments in its response, breaking the 1:1 mapping the safety requirement depends on — correctness over speed here, matching this profile's own reliability-over-simplicity default.

### Length-delta guard — the concrete "kill hallucinated additions" mechanism

`_is_acceptable_correction(original, corrected, max_length_delta_ratio)`: rejects an empty/whitespace-only correction, rejects any correction when the original was empty (nothing to correct), otherwise rejects if `abs(len(corrected) - len(original)) / len(original) > max_length_delta_ratio`. Verified the boundary is inclusive (`<=`, not `<`) and both directions are caught (a wild ADDITION and an unexpected TRUNCATION are both rejected) with explicit boundary-case tests. A rejected correction falls back to the untouched original segment — never partially applied, never silently corrupted.

### Pipeline wiring — one shared summarizer instance for correction AND summarization

Restructured `_do_transcribe_and_summarize`: the summarizer is now created ONCE (`needs_llm = sum_enabled or correction_enabled`) and shared between the correction pass and the summarization pass, rather than each creating (and loading a model into) its own instance — same reuse discipline already applied to `WhisperXTranscriber` in Task#4/#5. Correction runs on the transcript BEFORE it's written to `transcript.{md,json}` (so the saved file reflects corrected text) and before summarization (so the summary is generated from corrected text too). Verified backward compatibility explicitly: with `correction.enabled = False` (the default), `needs_llm` degrades to exactly `sum_enabled`, reproducing the prior code path byte-for-byte — confirmed by all 82 pre-existing `test_pipeline.py` tests passing unmodified.

**Failure handling matches the existing summarization pattern exactly**: `correction_unavailable` (backend unreachable) and `correction_failed` (exception during correction) both fall back to the uncorrected transcript and emit a `click.echo(..., err=True)` warning, mirroring `sum_unavailable`/`sum_failed`'s existing shape — a correction failure never blocks the pipeline or loses the transcript.

### Bug caught and fixed before it could slow down every future test run

The first version of `test_correction_and_summarization_share_one_summarizer_instance` set `config.summarization.enabled = True` without also mocking `llama_cpp_summarizer._ensure_model` (unlike the pre-existing `test_transcribe_and_summarize`, which does mock it) — since the default `summarization.backend` is `"local"`, this made the test attempt a REAL HuggingFace download of the Phi-4-mini GGUF on every run. Caught immediately by an anomalously slow test (50s vs the suite's normal ~5s for 350 tests) — did not brush past it as "just a slow test," investigated and found the real cause, fixed by adding the missing mock (0.18s after the fix). This is exactly the ported-code-validation "cost/rate-limit assumption baked into a test default" failure mode, caught in a test I wrote myself this session rather than in inherited code.

pytest after this task: **350 passed** (deterministic across 4 consecutive full-suite runs, ~5s total, no other network-dependent tests found; new: `tests/test_correction.py` 20 tests, plus `TestCorrectionIntegration` in `test_pipeline.py`, 7 tests). ruff: clean.

## Task#7 — capture-permission preflight + per-track RMS gate

Two independent changes, both converting a post-hoc "you already lost the recording" warning into an ahead-of-time check: (1) Swift-side TCC preflight before ANY capture engine starts, (2) Python-side per-track RMS gate that names which specific track (system vs mic) is silent, instead of one ambiguous "audio is silent" message.

### Confirmed the exact APIs against the real local SDK headers, not memory

`grep`'d the actual `MacOSX26.5.sdk` on this machine rather than trusting training-data recall: `CGPreflightScreenCaptureAccess() -> Bool` (`CoreGraphics/CGWindow.h`, "Checks whether the current process already has screen capture access" — critically, does NOT prompt, exactly what a preflight needs) and `AVCaptureDevice.authorizationStatus(for:) -> AVAuthorizationStatus` (`AVFoundation/AVCaptureDevice.h`, four states: notDetermined/restricted/denied/authorized). Compiled and ran both against this machine's REAL current TCC state before writing any pipeline code — confirmed `CGPreflightScreenCaptureAccess() == true` and `authorizationStatus(for: .audio) == .authorized` on this terminal (both already granted, since prior tasks ran real audio-adjacent tooling here).

`AVCaptureDevice` is NOT exposed via the already-imported `AVFAudio` (confirmed by grepping `AVFAudio.framework`'s headers for it — zero matches) — needed an explicit `import AVFoundation`. No new `Package.swift` linker entry required: every other framework in this file (`ScreenCaptureKit`, `CoreMedia`, `AVFAudio`, etc.) is imported the same implicit-linking way, confirmed by reading the existing `Package.swift` (only `CoreAudio`/`AudioToolbox` have explicit `.linkedFramework` entries, unrelated to this addition).

### Preflight hard-blocks, deliberately, before any capture starts

`runCapturePermissionPreflight(needsMic:)` in `AudioCapture.swift`, called in `main()` right after `--output` is validated and before `SystemAudioCapture`/`MicCapture` are constructed. On a missing permission it prints an actionable `[PERMISSION_MISSING]` message with the exact `open x-apple.systempreferences:...` fix (Screen Recording always checked; Microphone only checked when `--mic`/`--mic-device` was passed) and `exit(1)` — the SAME hard-exit pattern already used for other fatal preconditions in this function (`--output is required`, unknown option). Chose hard-block over warn-and-continue deliberately: the brief's own framing ("actionable hint BEFORE a call is lost") implies preventing a doomed recording from starting at all, not just warning partway through one that's already running and can't be fixed mid-flight.

Made the check injectable without changing production behavior: `runCapturePermissionPreflight(needsMic:hasScreenCaptureAccess:hasMicrophoneAccess:)` takes the two boolean results as parameters defaulting to the real `preflightScreenCaptureAccess()`/`preflightMicrophoneAccess()` calls — `main()`'s call site passes only `needsMic`, so production behavior is unchanged, but a test harness can inject `true`/`false` directly. Verified all 6 combinations (both granted/mic-not-needed, both granted/mic-needed, screen-denied, mic-denied-but-not-needed [must still pass — the mic check must not fire when `--mic` wasn't requested], mic-denied-and-needed, both-denied) via an isolated `swiftc`-compiled harness, matching the same verification-tier pattern used for `mergeAudioFiles` in Task#4 (no Swift test infra exists in this repo).

**Also manually verified against this machine's real, live TCC state** (not just injected fakes): ran the actual compiled binary with real permissions granted — confirmed NO `[PERMISSION_MISSING]` message fires and mic capture genuinely starts ("Recording microphone audio to..."), confirming the preflight doesn't false-positive-block a legitimately-permitted flow. The unrelated `Error: No display found` seen in both this run and a `git stash`-baseline run of the SAME command (before my change existed) confirms this session's shell has no attached interactive display for `SCShareableContent` — a pre-existing environment limitation, not a regression.

**Residual, honestly stated**: the `Privacy_Microphone` deep-link anchor name (parallel to the already-shipped, working `Privacy_ScreenCapture`) was verified only by `open`'s exit code (0, meaning macOS accepted the URL as well-formed) — visual confirmation of the exact pane it lands on was attempted (`screencapture` + AppleScript introspection) but failed because this session has no real interactive display (the screenshot came back solid black, consistent with the "No display found" limitation above). High confidence via the parallel-construction argument (same `Privacy_<Name>` pattern, same prefix, both accepted by `open`), but this specific claim is the one item in this task not independently visually confirmed.

### Per-track RMS gate (`pipeline.py`)

New `_track_rms(path) -> float | None` (RMS over the first 5s, reusing the existing `numpy`+`soundfile` deps `_check_audio_silence` already imports — no new dependency) and `_check_dual_track_silence(system_path, mic_path)`, which names the silent track specifically: system-only, mic-only, or both. Threshold `1e-5`, calibrated empirically rather than guessed: a synthetic true-zero signal (no signal ever reaching the tap — the exact permission-denied failure mode) measures RMS `0.0` exactly, while a synthetic quiet-room self-noise floor (~-60dBFS, `randn * 0.001`) measures RMS `~1e-3` — two orders of magnitude of headroom between "genuinely nothing captured" and "a real quiet room," so `1e-5` cannot mistake real ambient recording for a permission failure.

**Warns, does not hard-block** — deliberately different from `_check_audio_silence`'s existing `SystemExit(1)` for the single-track case. If the system track is silent but the mic track has real signal, the recording still has genuine value (the owner's own segments) — hard-blocking would discard a partial-but-useful recording. The existing single-track `_check_audio_silence` correctly still hard-blocks in `run_pipeline`, since a single silent file legitimately means nothing at all was captured.

Wired into `run_pipeline` right where `_check_audio_silence` already ran: `_find_dual_tracks(audio_path)` (from Task#4) gates which check runs — dual-track RMS check when both tracks are retained, the pre-existing single-track peak check otherwise. `run_resume`/`run_transcribe` are unchanged (confirmed `run_resume` never called any silence check even before this task — resuming assumes the original recording was already checked).

pytest after this task: **360 passed** (deterministic across 4 consecutive full-suite runs, ~5s total). ruff: clean. Swift: compiles clean, preflight logic verified via isolated harness (6/6 injected scenarios) plus a live run against this machine's real TCC state.
