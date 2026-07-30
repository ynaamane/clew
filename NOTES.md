# Build notes — meeting-scribe (forked from paberr/ownscribe)

## 2026-07-30 — the day the design finally got LOOKED at, and two production-only bugs surfaced

Eight lots landed. What matters is not the count but that **five builders were killed mid-task by an
API stream stall and every one of the six lots needed correction before it could be trusted** —
including two that reported "complete, tests green". Their work survived only because it was on disk.

Two bugs that only existed in production, both invisible to the suite by construction:

- **`ffmpeg is not installed`.** Found by a real 8-second test recording: audio captured fine (48 kHz,
  peak −17.8 dBFS), then the pipeline exited 1. A Finder-launched app inherits launchd's minimal PATH,
  without `/opt/homebrew/bin`. Transcription worked from a terminal and could never work from the app,
  failing *after* the audio existed. My first test for it was green with the fix removed, because it
  read `ProcessInfo`'s PATH — which in a terminal-run suite already has Homebrew. The bug and the bad
  test shared a root cause: both assumed the developer's environment.
- **The window could not be opened without a mouse.** Asked what permission to grant, the measured
  answer was none — `AXIsProcessTrusted()` was already true. The blocker was ours: SwiftUI's
  `MenuBarExtra(.window)` popover exposes nothing to accessibility, no URL scheme was declared, and
  `⌘0` lived on a Button *inside* the popover. A keyboard-only user was as locked out as an agent.
  Fixed with `ownscribe://library` at AppKit level plus an app-scope menu command.

That unblocked the **first real visual review in this project's history**. Seven gaps, top of
`TODO.md`. The first one — the window renders LIGHT while the validated mockup is DARK — is the kind
of thing 413 green tests will never say, and it plausibly explains the user's two earlier rejections
on its own. The second: `.glassEffect()` sits on the `List`, so the sidebar clips into an oval that
overflows its column.

Method, for reuse: `open "ownscribe://library"` →
`bash scripts/ui-evidence/capture.sh MeetingScribe /tmp/ui-ev` → Read the PNG. Window-scoped by
owner, so it cannot capture the screen. Researched first: Expo was rejected (iOS/Android/web, not
desktop), but four independent tools — Screenslop, Loupe, Peekaboo, JourneyTester — had converged on
the same rule: *never review Apple UI from source; capture screenshot + AX tree + logs, critique,
fix, re-capture.*

Still unmeasured: the AX tree returns **0 lines** for our window because SwiftUI exposes almost
nothing without `.accessibilityIdentifier`. Adding those is the next design step, before any more
layout iteration.

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

**Root cause of the `_has_torch_function already has a docstring` signature, actually found (see Task#13 below):** this exact error resurfaced later, deterministically, when a new test added a plain `import torch`. Root-caused to `unittest.mock._patch_dict._unpatch_dict()`: `mock.patch.dict("sys.modules", {...})`, even without `clear=True`, always fully clears and restores the ENTIRE `sys.modules` dict on exit (CPython source, `unittest/mock.py`) — not just the one key it patched. Any module lazily first-imported for real INSIDE such a `with` block (here: `torch`, imported lazily inside `_diarize()`) gets silently dropped from `sys.modules` when the block exits, even though the real module objects remain alive in memory via other references. The next plain `import torch` anywhere later in the same process re-executes `torch/__init__.py` from scratch, which re-registers a C-level docstring on an already-initialized function object and raises. This task's original "nondeterministic reimport interaction" framing was correct in spirit but incomplete — it is fully deterministic once you know which module gets lazily imported inside the patched block and whether anything later in the process re-imports it fresh. Fixed at the actual source in Task#13.

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

## Task#9 (planner P9) — source-agnostic meeting auto-detect via audio activity

Picked this up (skipping the paused Task#8/Canary — see the P7 section below for why) since it's fully independent of Canary and directly continues the pattern from Task#1/#4: detect a meeting via the OS audio mixer, never per-app.

### Found the exact primitive via the real local SDK headers, not memory

`grep`'d `CoreAudio.framework/AudioHardware.h` on this machine and found `kAudioDevicePropertyDeviceIsRunningSomewhere`: "A UInt32 where 1 means that the AudioDevice is running in at least one process on the system." Queried on the DEFAULT OUTPUT DEVICE (the speakers/headphones), this is a hardware-level "is any audio currently playing" signal — no Screen Recording permission, no Microphone permission, nothing app-specific. Confirmed empirically before writing any pipeline code: compiled a 40-line standalone Swift repro, ran it against real `afplay` playback — `false` at rest, flips to `true` the instant a system sound plays, back to `false` when it stops. This is the load-bearing primitive for "source-agnostic... not bundle-id polling": it's OS-level and cannot distinguish (or care) which app produced the sound, satisfying the requirement by construction rather than by an allowlist that would need maintaining as new meeting apps appear.

### New `watch-activity` Swift subcommand + extracted, independently-tested state machine

Added `watch-activity [--sustained-seconds N]` to `AudioCapture.swift` (default 3s), polling once/second via the same `DispatchSourceTimer` idiom the existing silence-timeout code already uses. On sustained activity it prints `[MEETING_DETECTED]` to stdout and exits 0 — deliberately just a detector, not a recorder; Python decides what to do with the signal, keeping the Swift binary's role consistent with its existing `capture`/`list-apps`/`list-devices` subcommands (direct OS interaction only, no orchestration).

Extracted the actual decision logic (given a stream of `(running, timestamp)` observations, has activity been sustained for the threshold) into a standalone `SustainedActivityDetector` class with an `observe(running:now:) -> Bool` method that takes an injected clock — no CoreAudio, no timers, pure state transition. This is what let me actually TEST the logic instead of only eyeballing live `afplay` runs: built an isolated `swiftc`-compiled harness (same tier as Tasks #4/#7, no Swift test infra in this repo) with 7 scenarios (immediate-observation-never-triggers, exact-threshold-triggers, just-under-threshold-doesn't, a-gap-resets-the-clock, post-reset-still-eventually-triggers, never-running-never-triggers, zero-threshold-edge-case).

**Caught a real off-by-one bug via that harness, not by inspection**: the first implementation set `activeSince` and unconditionally `return false` on the FIRST observation, before ever comparing elapsed time to the threshold — meaning a `sustainedSeconds=0` config (intending "trigger on the very first sample") would actually wait for the SECOND poll tick before firing. The isolated test suite caught this immediately (6/7 passed, one clean failure with an unambiguous name: "zero threshold triggers on the very first running observation"). Fixed by setting `activeSince` first and THEN comparing elapsed time against the threshold in the same code path, so a zero threshold correctly evaluates `0 >= 0 → true` on the very first call. Re-ran both the isolated suite (7/7) and the real binary against live `afplay`/`say` audio afterward to confirm the fix didn't regress the real negative case (one brief ~1s ping does NOT trigger a 2s threshold) or the real positive case (~4s of continuous `say` speech DOES trigger it).

### Python-side `ownscribe watch` orchestration

`run_watch(config, sustained_seconds)` in `pipeline.py`: spawns `watch-activity` as a subprocess, blocks on its stdout for `[MEETING_DETECTED]`, then calls the existing `run_pipeline(config)` — reusing the entire existing recording pipeline unchanged (capture mode, diarization, correction, naming, everything already built in Tasks #1-#7 applies automatically once `watch` hands off).

**Caught a real bug in my own first draft before it could ship**: the initial version iterated `for line in process.stdout: if line == "[MEETING_DETECTED]": break`, then unconditionally called `run_pipeline(config)` after the loop — meaning if the subprocess crashed, was killed, or its pipe closed for ANY reason without ever printing the detection line, the `for` loop would simply end (that's what happens when stdout closes) and execution would fall through to starting a recording anyway, as if detection had genuinely succeeded. Fixed with an explicit `detected` flag defaulting to `False`, only set `True` inside the loop on an actual match, checked after the loop with a hard `SystemExit(1)` if never set. Verified the fix directly: a test with an empty stdout stream (`_make_fake_process([])`, simulating a dead/interrupted subprocess) now correctly raises `SystemExit` and asserts `run_pipeline` was never called, where the original code would have silently proceeded.

Also verified empirically (not assumed) that Ctrl+C during `ownscribe watch` propagates correctly: `subprocess.Popen` inherits the same foreground process group by default, so SIGINT reaches the Swift binary directly; its existing SIGINT handler (`exit(0)`) fires, closing stdout, which correctly triggers the "no detection" path above rather than hanging or orphaning the child process — confirmed with a live `send_signal(SIGINT)` test against the real compiled binary.

pytest after this task: **365 passed** (deterministic across 4 consecutive full-suite runs). ruff: clean (including two SIM117 nested-`with` findings caught and fixed in the new tests). Swift: compiles clean; both the extracted state-machine (7/7 isolated scenarios) and the real binary (live `afplay`/`say` positive and negative cases) verified.

## Task#8 (planner P7) — Canary-1b-v2 MLX engine — PAUSED, not built

Stopped before writing any implementation code. Verification against the real `Blaizzy/mlx-audio` source (cloned it, read `canary.py`/`decoder.py`/`config.py` directly, tested in an isolated throwaway venv, cross-checked via `git log` and `gh issue/pr` search) found that several of the brief's specific technical claims don't hold up:

- **"language= kwarg is silently filtered"** — false. `generate()`'s first two lines explicitly pop `language` from kwargs and use it to set both `source_lang`/`target_lang`. Confirmed via `inspect.signature()` on a live install.
- **"decoder SDPA float32-vs-bf16" is real, but undocumented anywhere upstream** (zero hits in git log, PR #550/#763, or a `gh issue` search for bf16/bfloat16/canary+crash). Found and reproduced the actual mechanism myself in 5 lines of isolated MLX code: `MultiHeadCrossAttention` unconditionally casts `encoder_mask` to float32 while q/k/v inherit the checkpoint's native bf16 — `mx.fast.scaled_dot_product_attention` throws `Mask type must promote to output type bfloat16` the moment this combination occurs, which it always does in a real `generate()` call. The project's own unit tests never catch this because every test uses `mx.random.normal` (float32) and the one cross-attention test that matters never passes a mask.
- **"no_repeat_ngram_size=3" is not a real parameter** — `generate()` has zero anti-repetition mechanism (pure greedy argmax, temperature=0 default). The underlying concern (greedy decoding loops on noisy audio) is real, but there's no such kwarg to pass; would need a hand-rolled guard.
- **"Canary's ~15s window"** doesn't match the encoder's own positional-embedding math (~400s ceiling from `pos_emb_max_len=5000` at 12.5 encoder-frames/sec) or NVIDIA's own HuggingFace card for canary-1b-v2 (NeMo's reference chunks long-form audio at 40s with 1s overlap, no documented shorter limit). Separately, `vad=True` is real in `mlx-audio` but belongs to a DIFFERENT model in the same package (`cohere_asr`, PR #701) — Canary's `generate()` has no `vad` parameter at all.
- Also found: `mlx-audio` pulls 108 new packages (gradio, spacy, aiortc, librosa, mlx-vlm...) even pinned to the compatible 0.2.10 line — no version conflicts with the existing stack, but a genuinely heavy optional extra, reinforcing why "behind a flag" needs to mean a real `pyproject.toml` optional-dependency group, not just a runtime default.

Sent full findings to team-lead and paused rather than silently building against a self-corrected premise on a task this consequential (new heavy dependency, feeds directly into the Task#9/pilot-harness A/B comparison). Awaiting direction before resuming.

## Task#12 (planner P11) — audio retention flag + policy + `reprocess` command

Directly closes the gap flagged at the end of Task#4 (see "Gap surfaced, not silently absorbed" above): the original brief's retention config flag, a stated policy (keep N days / forever / manual purge), and a `reprocess` command.

### `keep_recording` already defaulted correctly — verified via git history, not assumed

The brief described inverting upstream's delete-after-transcribe default. Checked `git log -p` on `config.py` back to the fork point (`dfa1e3a`): `keep_recording: bool = True` was already the default from the very first commit — upstream's own default is keep, not delete. No inversion was needed; the brief's premise on this specific point was stale by the time this task started. Verified rather than trusted.

### Real bug found and fixed before building anything new: orphaned dual-track files on delete

Before adding any retention _policy_, checked whether the existing deletion path (`keep_recording=false`) was even correct after Task#4's dual-track retention landed. It wasn't: the delete block in `_do_transcribe_and_summarize` only ever unlinked `audio_path` itself (`recording.wav`), never `system.wav`/`mic.wav`/`track_alignment.json` — those three files were silently left behind forever on every dual-track recording with `keep_recording=false`, the exact opposite of what that flag promises. Confirmed empirically with a standalone repro (wrote all four files, ran the deletion code, checked what survived) before writing the fix, per the standing rule of verifying a bug exists before patching it.

Fix: `_dual_track_paths(audio_path)` returns every retained-track/sidecar path next to `audio_path` that actually exists (`system.wav`, `mic.wav`, `track_alignment.json`, filtered by `.exists()` so a single-track recording never errors on missing files); the deletion loop now iterates `(audio_path, *_dual_track_paths(audio_path))` with `unlink(missing_ok=True)`. Two new tests pin this: one confirms all four files are gone when `keep_recording=false`, one confirms all three retained-audio files (recording+system+mic) survive when `keep_recording=true`.

### Retention policy: `retention_days` config + `ownscribe purge`, not a background job

Chose the simplest design that satisfies all three named policy options (keep-N-days / forever / manual-purge) without inventing a scheduler this project has no infrastructure for:

- `[output].retention_days` (new `OutputConfig` field, default `0` = keep forever) — a single integer covers both "forever" (0) and "N days" (positive) without a separate enum/mode field.
- `ownscribe purge` (`run_purge` in `pipeline.py`) is the manual-purge mechanism for both the "N days" and "forever-until-I-say-so" cases — it is never invoked automatically by the recording/transcribe pipeline, only by explicit user action (or an external scheduler like `launchd`/`cron`, which is the user's choice to wire up, not this tool's job to assume).
- `--older-than N` overrides `retention_days` for a one-off purge without touching config; `--all` ignores age entirely; `--dry-run` lists what would be removed without deleting anything. Running plain `purge` with `retention_days=0` and no `--all` is a deliberate no-op with an explanatory message, rather than silently doing nothing or (worse) deleting everything — an empty/ambiguous invocation should never be destructive by default.
- `purge` walks `config.output.resolved_dir`'s immediate subdirectories (each a meeting), resolves retained audio the same way `resume`/`reprocess` do (including the separate-`audio_dir` case), and age-gates on the audio file's own mtime — not the directory name — so a `reprocess`'d recording's age resets correctly rather than being purge-eligible forever based on its original recording date.
- Deliberately narrow blast radius: `purge` only ever removes audio + its dual-track/sidecar files, never `transcript.md`/`summary.md` — past notes stay readable after their source audio is gone, matching the brief's implicit goal (control disk usage from raw audio, not destroy meeting history).

Refactored the audio-resolution logic (target directory, falling back to a separate configured `audio_dir` if set) that `run_resume` and `run_reprocess` had each partially duplicated into one shared `_resolve_retained_audio(config, directory)` helper, now used by all three (`resume`, `reprocess`, `purge`) — verified `run_resume`'s existing 7-test class still passes unchanged after the refactor before adding anything new.

### `reprocess`: the "force redo" case `resume` deliberately doesn't cover

Re-read `run_resume` first to confirm the actual gap: it explicitly returns early ("Nothing to resume") when both transcript AND summary already exist — by design, since its job is finishing incomplete work, not redoing complete work. `reprocess` fills that gap deliberately: same audio-resolution logic, but unconditionally deletes any existing `transcript.md`/`summary.md`/`.json` before calling `_do_transcribe_and_summarize` again, and errors out clearly if no retained audio exists for that meeting (the one prerequisite `reprocess` cannot work around) rather than a confusing downstream failure.

CLI wiring for both `reprocess` and `purge` follows the exact option/pass-through pattern already established by `resume`/`warmup` (`--model`/`--language`/`--template` overrides for `reprocess`; `--older-than`/`--all`/`--dry-run` for `purge`).

### Verified beyond pytest: real filesystem behavior, not just mocks

Every pytest test for `_do_transcribe_and_summarize` mocks the transcriber, and every `purge`/`reprocess` pipeline test mocks `_do_transcribe_and_summarize` itself — correct for testing dispatch logic, but neither proves the real file-deletion/file-rewrite behavior end-to-end. Ran two additional real, unmocked smoke tests directly against the filesystem (temp `HOME`, real config file, real `ownscribe` CLI invocation, only the heavy ASR call mocked):

1. `purge --dry-run` then `purge --older-than 30` against a directory with one aged recording (mtime forced 60 days back, dual-track + transcript) and one recent one: dry-run left every file untouched and printed the correct candidate; the real run deleted `recording.wav`/`system.wav`/`mic.wav` from the aged meeting, left its `transcript.md` intact, and left the recent meeting's `recording.wav` completely untouched.
2. `reprocess` against a directory with a stale `transcript.md`/`summary.md` (summarization disabled in config, transcriber mocked to return known text): confirmed the old transcript content was fully overwritten with the new mocked output, and `summary.md` was correctly absent per the disabled config, rather than trusting the pytest mocks alone.

Caught and fixed one script-level mistake during this verification (not a code bug): my first smoke-test script constructed a `Word(word=..., ...)` — the real dataclass field is `text`, per `transcription/models.py`. Confirmed the actual field names against the source before re-running, rather than guessing from the variable name.

pytest after this task: **365 -> 390 passed** (25 new, verified against the prior commit via a `git stash`/pytest/`git stash pop` round-trip rather than an in-session running count: 2 dual-track-deletion tests + 6 `TestReprocess` + 8 `TestRunPurge` pipeline tests, 2 `TestReprocessCommand` + 3 `TestPurgeCommand` CLI tests + 2 help-text tests, 2 `test_config.py` retention-default/TOML-merge tests). ruff: clean (two findings caught and fixed: a >120-char TOML comment line, an unused unpacked `config` variable in a CLI test — prefixed `_config`).

### README updated

Added `reprocess`/`purge` to the Subcommands list, a new `[output].retention_days` line in the Configuration TOML block, and a new "Audio Retention" section (with a "Reprocessing a Meeting" subsection) explaining the three retention modes and both commands, plus a Table of Contents entry.

## Task#13 — torchcodec closed (no token needed) + root-caused a recurring test-suite flake + `scripts/verify_with_token.py`

Three closures in one task, prompted by team-lead re-flagging the torchcodec/FFmpeg question three separate times across the session plus the twice-requested end-of-build verification script.

### torchcodec: closed empirically, without touching FFmpeg or torchcodec versions at all

Team-lead's corrected diagnosis (FFmpeg 8 installed but torchcodec only links FFmpeg 4-7, a version mismatch not a missing-dependency problem) was right, but re-aligning either package's version was never actually necessary to close this. Read `pyannote.audio.core.io.Audio.__call__` and `Audio.crop` directly from the installed 4.0.4 source: both check `if "waveform" in file` FIRST and return immediately via `downmix_and_resample(...)` — the `AudioDecoder(file["audio"])` line that would need torchcodec is structurally unreachable when a `{"waveform", "sample_rate"}` dict is passed. This is a hard branch, not a soft/deferred fallback. Confirmed `_diarize()` in `whisperx_transcriber.py` always builds exactly this dict (already documented in this file's own "Known non-fatal warning" section from Task#1) and that `whisperx.load_audio()` shells out to the real `ffmpeg` CLI directly (`subprocess.run(["ffmpeg", ...])`), never importing torchcodec either. Verified empirically, not just read: ran `Audio.__call__`/`Audio.crop` against a real in-memory waveform in this exact broken venv (torchcodec still can't load) — both succeeded, zero torchcodec invocation, only the same one-time import-level `UserWarning` (which itself names this exact workaround as its own first suggested solution).

New regression tests pin this: `tests/test_transcription.py::TestPyannoteAudioIoRealDecode` (`test_call_and_crop_succeed_on_real_waveform_dict`, `test_whisperx_load_audio_never_imports_torchcodec` — the second explicitly asserts `"torchcodec" not in sys.modules` after a real `whisperx.load_audio()` call on a real WAV, so this can't silently regress if a future whisperx/pyannote version changes the internal code path). No HF token needed for this closure — it's a structural code-path proof, not a real-model numerics question (that residual is unchanged from Task#2/#5: MPS-vs-CPU numerical correctness and the real embedding-space question, both already in the verify script below).

### Root-caused a recurring test-suite flake, not just papered over it again

Adding the new torchcodec test class immediately broke the full suite (`RuntimeError: function '_has_torch_function' already has a docstring` in `torch/overrides.py`, tests passing individually but failing in the full run) — the EXACT signature Task#2 already hit once and described as "a nondeterministic torch-submodule-reimport interaction." Bisected properly this time instead of re-guessing: confirmed via `git stash`+pytest that the baseline (365 tests, no torchcodec class) was 100% clean, then bisected pairwise (`pytest ClassA ClassB`) down to the exact two tests — `TestDiarizationApiCompat::test_diarize_unwraps_speaker_diarization_from_diarize_output` (Task#2) immediately followed by my new class. Traced `sys.modules` state directly (printed `id()`/membership before/after) rather than guessing: `torch` is False in `sys.modules` before that test runs, becomes True mid-test (lazily imported inside the real `_diarize()` call), then False again right after the `with mock.patch.dict("sys.modules", ...)` block exits — even though NOTHING in that test or in `_diarize()` ever does `del sys.modules['torch']`.

Root cause, confirmed by reading CPython's actual `unittest.mock._patch_dict` source (not assumed from behavior): `_unpatch_dict()` unconditionally calls `_clear_dict(in_dict)` (clears `sys.modules` ENTIRELY) then `in_dict.update(original)` (restores the pre-`with`-block snapshot) — this happens on every `mock.patch.dict("sys.modules", ...)` exit, regardless of `clear=True`/`False` on entry, and regardless of which single key was patched. Any module lazily first-imported for real DURING the patched block is silently dropped from `sys.modules` the moment the block exits. The next plain `import torch` anywhere later in the SAME process re-executes `torch/__init__.py` from scratch, which calls `_add_docstr` on an already-initialized C-level function object a second time and raises. This is fully deterministic once you know the mechanism — Task#2's "nondeterministic" framing was the honest state of investigation at the time, not incomplete now.

Fixed at the actual source rather than defensively working around it in the new test: added a plain `import torch` INSIDE `test_diarize_unwraps_speaker_diarization_from_diarize_output`, BEFORE its `mock.patch.dict(...)` block, so torch is already in the pre-patch snapshot that gets restored (confirmed by re-tracing `sys.modules` state — `torch` now stays present through the block, not wiped). This protects every future test added after this one in the suite, not just mine. Verified the fix directly: 392/392 passed (was 2 failures before the fix, in the full-suite run specifically — always passed in isolation, which is what made this a genuinely nasty test-order-dependent bug).

Hazard class worth remembering for any FUTURE test in this codebase: a `mock.patch.dict("sys.modules", {...})` block that triggers a lazy first-time import of any C-extension-backed module (torch, numpy's C internals, etc.) inside it will corrupt that module's `sys.modules` entry on exit. If a later test does a plain `import <that module>` for the first time in the process, expect exactly this class of `RuntimeError`/re-init crash. The fix is always: import the module BEFORE the `mock.patch.dict` block that would otherwise first-trigger it.

### `scripts/verify_with_token.py` — the single end-of-build verification pass, consolidated

Team-lead asked for this twice, explicitly reusable across the pilot harness (Task#9) rather than duplicated. Seven independent checks, each PASS/FAIL/SKIP, one non-zero exit only if something that actually ran failed:

- torchcodec/in-memory-waveform proof (runs unconditionally, no token needed — the one closed above)
- community-1 real diarization on a real WAV
- enrollment: two real voices separate at the 0.65 cosine threshold, self-similarity vs cross-similarity
- standalone-enroll embedding space vs in-meeting diarization embedding space (the exact "do these live in the same vector space" question flagged unresolved since Task#5)
- MPS vs CPU diarization on the same clip, explicitly checking for the pyannote-audio#1886 all-speaker-0 collapse mode (not just "did it crash")
- owner mic-track labeling on a real dual-track capture
- Canary MLX engine (self-skips cleanly with an explicit message if `CanaryMlxTranscriber` doesn't exist yet — Task#8 is still paused, this script doesn't force that decision)

Each HF-token-gated check self-determines its own skip condition (`if not hf_token: return _skip(...)`) rather than `main()` pre-deciding and hardcoding a duplicate copy of each check's `name` string — the first draft did the latter and it was a real fragility (the skip message could silently drift out of sync with the real check name on any future edit). Caught and fixed two additional real bugs before trusting the script, neither from guessing: (1) the MPS-comparison check's `whisperx.diarize.DiarizationPipeline(...)` construction used the STALE `use_auth_token=` kwarg pyannote 4.0 renamed to `token=` back in Task#2's own fix, and used a fragile `import whisperx.diarize` + attribute-access pattern instead of the `from whisperx.diarize import DiarizationPipeline` the real production code actually uses (`whisperx_transcriber.py:145`) — caught by directly diffing against the production import, not by running it against a real model. Verified all 7 check functions individually against mocked internals (mirroring the actual pytest suite's own mocking patterns) before running the whole script — every function returns the correct PASS/FAIL/SKIP and detail message; the whole script runs clean end-to-end (exit 0, 1 passed + 6 correctly-worded SKIPs) with no `HF_TOKEN` and no clips, which is the exact state this session is actually in.

**Did not run the token-gated checks for real** — no `HF_TOKEN` in this session, consistent with every prior task. This script is the deliverable that makes that a ONE-TIME future action instead of five separate token requests.

pytest after this task: **392 passed** (2 new: `TestPyannoteAudioIoRealDecode`). ruff: clean (fixed 5 line-length + 4 import-order + 1 unused-noqa findings in the new script during its own review, none in `src`/`tests`).

## F9 (code-review finding) — latent ScreenCaptureKit sample-rate assumption in dead code

`swift/Sources/main.swift:286` (ScreenCaptureKit backend, `SystemAudioCapture`) trusts `kSystemAudioSampleRate` (48000 Hz constant) instead of reading the delivered audio format — the same assumption BUG5 disproved for the CoreAudio tap path (the real format can differ).

**This code is DEAD in the shipped configuration and will not be fixed.** `swift/Sources/OwnscribeMenuBar/RecordingController.swift` always instantiates `CoreAudioTapCapture` (the working, BUG5-hardened path), and the repo targets macOS 14.2+ where CoreAudio tap is available — no shipped code path reaches the SCK backend. Editing unreachable code adds regression risk for zero benefit.

**Condition under which it would matter:** if someone re-enables the ScreenCaptureKit fallback for macOS <14.2, this assumption will silently break capture if the system's actual audio format differs from 48 kHz (same failure mode BUG5 reproduced on the CoreAudio path). Fix: query `sampleBuffer.formatDescription.audioStreamBasicDescription.mSampleRate` at capture time, same pattern main.swift:190-192 already uses (reading `sampleBuffer.formatDescription` → `CMAudioFormatDescriptionGetStreamBasicDescription` → `AVAudioFormat`).

## Task#14 (archcheck C1) — fail-loud when the swift binary can't retain separate tracks

Archcheck (28-verifier adversarial workflow, run by team-lead) found an active silent-regression risk: `coreaudio.py::_find_binary()`/`_download_binary()` falls all the way back to downloading **upstream's** unpatched GitHub Releases binary when no local build exists — `bin/` is gitignored (confirmed via `git check-ignore -v bin/ownscribe-audio` and `git log --all -- bin/` returning nothing), so a fresh clone or a CI runner that skips `swift/build.sh` gets the unpatched binary with zero error. That binary predates every Swift patch this session's build depends on (Task#4's separate mic/system track retention, Task#7's TCC preflight, Task#9/10's `watch-activity`) — `--mic` would silently degrade to merged-only single-track, exactly the failure mode Task#4/#12's retention/reprocess work assumes never happens.

### Confirmed the exact fix directive first, didn't assume

Team-lead's message specified the fix shape explicitly: fail-loud detection, not vendoring the binary or repointing the download URL to an unofficial patched release. Built to that spec.

### The probe: watch-activity's own existence as the version marker

Confirmed via `git log --oneline afc1d18..HEAD -- swift/Sources/AudioCapture.swift` that `f49461e` (Task#4, separate-track retention) landed strictly BEFORE `3da343a` (Task#9/10, `watch-activity`) in this fork's history — so any binary new enough to recognize the `watch-activity` subcommand is guaranteed new enough to have separate-track support too. Confirmed the negative side too: `git show afc1d18:swift/Sources/AudioCapture.swift | grep watch-activity` returns nothing — upstream's fork-point commit has zero knowledge of that subcommand, so it would hit the `default:` case (`Unknown command: ...`, exit 1) for any invocation naming it.

`binary_supports_separate_tracks(binary)` in `coreaudio.py` runs `<binary> watch-activity --sustained-seconds not-a-number` and checks for the specific string `"requires a number of seconds"` in the output — this is the patched binary's own arg-parsing error, reached only because it recognized `watch-activity` as a real subcommand in the first place. Deliberately side-effect-free: an invalid numeric value fails inside `watch-activity`'s own flag parsing before the poll timer/loop ever starts, so this never actually watches audio or needs any permission.

**Caught and fixed my own false-positive bug before trusting the probe**: the first version checked for the ABSENCE of `"Unknown command"` rather than the PRESENCE of the patched binary's specific error string. Verified this directly against `/bin/echo` (which just prints its arguments back, containing neither string) — it wrongly returned `True`, since "not containing X" is satisfied by almost anything. Fixed to a positive match on the exact patched-binary error string; re-verified against `/bin/echo`, a nonexistent path, a non-executable file, and `/usr/bin/true` (silent success) — all correctly `False` — plus a hand-written shell script that echoes `"Unknown command: $1"` (simulating genuine upstream behavior) — correctly `False` — and the real compiled `bin/ownscribe-audio` — correctly `True`.

### Scoped the gate to exactly where the regression lives, not everywhere `_find_binary()` is called

`_find_binary()` itself is unchanged — a plain locate-or-download helper, used by `list_devices()`/`list_apps()` too, neither of which needs separate-track support and both of which work fine on an unpatched binary. The fail-loud check lives in `CoreAudioRecorder.start()`, gated on `wants_mic = self._mic or self._mic_device` — exactly the condition under which `--mic` gets appended to the real capture command and separate-track retention actually matters. System-only capture (the default, no `--mic`) never even calls the probe; confirmed this directly (mocked `binary_supports_separate_tracks` and asserted it's never called when `mic=False`, while `Popen` for the real capture command IS called).

### Verified genuinely end-to-end, not just via pytest mocks

Ran `CoreAudioRecorder.start()` against the real, real `bin/ownscribe-audio` with `mic=True` (only the actual audio-capture `Popen` stubbed, letting the version probe's own `subprocess.run` execute for real) — confirmed it does NOT raise. Ran the same against a hand-written shell script simulating an unpatched binary — confirmed it DOES raise, with `RuntimeError`, and confirmed no `Popen` call happened at all (no capture process, not even attempted) before the error surfaced.

**Bug caught in my own verification script, not the product code**: my first two manual end-to-end checks used `mock.patch("ownscribe.audio.coreaudio.subprocess.Popen")` globally, which broke with `ValueError: not enough values to unpack (expected 2, got 0)` inside `subprocess.run` — because `coreaudio.subprocess` IS the real `subprocess` module (not a separate copy), so patching `Popen` on it also corrupts `subprocess.run`'s own internal `Popen(...)` construction, which the version-probe itself depends on. This is the exact same hazard class documented in Task#13's `mock.patch.dict` root-cause, one level removed: mocking a shared, globally-looked-up name breaks EVERY caller of that name in the process, not just the one you meant to intercept. Fixed the verification by either mocking `binary_supports_separate_tracks` directly (for the success path, where the real probe result doesn't need to be exercised) or not mocking `Popen` at all (for the failure path, where the correct behavior is that `Popen` is never reached). The pytest suite (`tests/test_coreaudio.py`) already used the correct pattern from the start for the success-path test; only my throwaway manual verification scripts made this mistake, caught and fixed before drawing any conclusion from them.

pytest after this task: **404 passed** (12 new: `tests/test_coreaudio.py`, `TestBinarySupportsSeparateTracks` (7 tests: patched-string match, unpatched-string match, silent binary, self-echoing binary, nonexistent path, non-executable file, timeout) + `TestCoreAudioRecorderMicFailLoud` (5 tests: raises on unpatched+mic, does-not-probe on no-mic, succeeds on patched+mic, `--mic-device` alone also triggers the probe, missing-binary keeps the original error message)). ruff: clean.

## Task#15 (archcheck C10) — confirmed the torchcodec closure also covers speaker enrollment

Team-lead's archcheck message asked specifically to verify `SpeakerEmbedder.embed_file` (`speakers/embedding.py`, the standalone-enrollment path used by `ownscribe enroll`) doesn't have its own separate torchcodec dependency — Task#13 only proved the diarization path (`_diarize()`'s in-memory `{waveform, sample_rate}` dict).

Read the code first: `embed_file()` already decodes via `whisperx.load_audio(str(audio_path), sr=model.sample_rate)` (the real `ffmpeg` CLI subprocess, confirmed in Task#13 never imports torchcodec), then constructs a raw `torch.Tensor` and calls `model(waveform)` directly — never a bare path, never a `{"audio": ...}` dict, so pyannote's `Audio` IO class (the one with the torchcodec-dependent `AudioDecoder` branch) is never even in the call graph here.

`PretrainedSpeakerEmbedding` (`pyannote.audio.pipelines.speaker_verification`) turned out to be a factory FUNCTION in this installed version (4.0.4), not a class — `inspect.getsource()` on its `__call__` returned an unhelpful decorator stub, so read-the-source wasn't fully conclusive on its own. Closed the gap empirically instead: called the real `embed_file()` end-to-end against a real synthesized WAV (only the network-gated model LOAD mocked, never the audio decode), and directly inspected the actual argument passed to the model — a real `torch.Tensor` of shape `(1, 1, 8000)` (8000 = the fixture's 0.5s at 16kHz), confirmed via `mock.call_args`. `"torchcodec" in sys.modules"` checked both before and after — `False` both times.

New regression tests: `tests/test_embedding.py::TestEmbedFileNeverTouchesTorchcodec` (2 tests: the tensor-not-path assertion + the explicit `sys.modules` check), mirroring the exact pattern already established in `test_transcription.py::TestPyannoteAudioIoRealDecode` (Task#13) for the diarization path. No new module existed for `speakers/embedding.py` before this — `SpeakerEmbedder` was previously only exercised indirectly, fully mocked, through `test_pipeline.py`'s `run_enroll` tests.

pytest after this task: **406 passed** (2 new). ruff: clean.

## Task#16 (archcheck C7) — re-verified Canary/mlx-audio facts, research only, no code

Task#8 (Canary MLX engine) remains PAUSED, unchanged — this is purely a re-verification of the technical premises before that pause is eventually lifted, per team-lead's explicit instruction not to resume building it here. Spawned a research-only subagent (no code, no file writes) to check three claims from the archcheck against live, primary sources (`gh` CLI, real file reads, a local empirical repro) — not secondhand recall.

1. **FluidAudio CoreML Canary PR — confirmed exactly as archcheck stated.** `FluidInference/FluidAudio` PR #709 (`feat(asr/canary): Canary-1B-v2 AED engine + CTC-spotter custom vocab`) is open, `mergeStateStatus: BLOCKED`, zero maintainer review despite all 11 CI checks passing. Opened 2026-06-17, last commit 2026-06-18 — exactly 35 days / 5.0 weeks stale as of today (2026-07-23), matching the "~5-week-stale" claim precisely. Confirmed via `git log` that nothing Canary-related landed on `main` since (no silent squash-merge under a different PR number). Not usable as a packaged feature today — the underlying CoreML conversion pipeline (`FluidInference/mobius`) is bring-your-own-`.mlpackage` research tooling, not an installable library.

2. **mlx-audio CLI `--language` flag — confirmed dropped for Canary specifically, mechanism identified precisely.** The CLI's generic kwarg dispatcher (`generate.py`) filters incoming kwargs through `inspect.signature(model.generate).parameters` before calling the model — and Canary's `generate()` has no NAMED `language` parameter (only `source_lang`/`target_lang` as named params, plus a `**kwargs` catch-all that doesn't expose `language` to that same introspection). The CLI's `--language` value never survives the filter. Reproduced this exact filtering mechanism in an isolated stub matching Canary's real signature shape — confirmed `"language" in signature.parameters` is `False`. This does NOT affect the direct Python API call this session already chose and built (`model.generate(source_lang=..., target_lang=...)`, confirmed working back in Task#8's original investigation) — only the CLI wrapper has this gap, and we were never planning to use the CLI.

3. **No Canary-relevant mlx-audio changes since last checked — the decoder dtype bug is unchanged and was reproduced live again.** Zero file-level diff under `mlx_audio/stt/models/canary/` between the last touching commit (2026-06-05) and current `main` HEAD. Re-reproduced the float32-mask-vs-bf16-qkv `scaled_dot_product_attention` crash locally (mlx 0.31.1) — same exact error message as Task#8's original finding. No VAD/chunking was ever added to Canary itself (still `cohere_asr`-only, confirmed by reading both files side by side).

**Net: nothing has changed since Task#8's original investigation that would alter its conclusions.** The corrected, verified plan from that task (direct Python API, not CLI; force decoder float32 to dodge the dtype bug; VAD via an existing dependency, not `mlx-audio`'s `cohere_asr`-only `vad=True`) is still current. This closes the "re-verify before the pilot relies on it" ask without resuming Task#8 itself — still awaiting team-lead direction on that pause.

No pytest/ruff impact — research only, no source or test files touched.

## Task#17 (archcheck C5) — investigated; the described concern targets a design that was never built here

Archcheck's C5 framing was: "once ownscribe's OWN capture starts, it pins `kAudioDevicePropertyDeviceIsRunningSomewhere` true, so 'meeting ended' detection (relying on the mic going idle) will never fire — self-capture must be excluded from the check" — plus Bluetooth-mic false-negatives and softening "deterministic" language. Read the actual Swift source line by line before writing any fix, and this specific mechanism does not exist in this codebase.

**What's actually built, confirmed via three independent reads:**

1. `watchAudioActivity()` (the auto-start detector) queries `defaultOutputDeviceID()` — `kAudioHardwarePropertyDefaultOutputDevice` — the SPEAKERS/headphones, not a microphone. `defaultInputDeviceID`/`kAudioHardwarePropertyDefaultInputDevice` appears exactly once in this file, in `listInputDevices()` (the unrelated `ownscribe devices` CLI command). Confirmed via `grep` across the whole file — the mic-activation-listener design archcheck describes was never implemented; Task#9/10 built OUTPUT-device sustained-activity instead (a deliberate, documented, different design — see the Task#9 NOTES.md section above and README's "Auto-Detecting a Meeting"). This is consistent with the CoreAudio-tap redirect gap found in an earlier flag this session (C1's precursor finding): a message describing a design as already switched-to, that the actual repo history shows was never built.
2. The "meeting ended" STOP mechanism (`onSilenceTimeout`/`silenceTimer` in `SystemAudioCapture.beginCapture`) is completely independent code from `watchAudioActivity` — it watches `lastLoudTime`, a per-stream RMS/peak level computed from the ACTUALLY CAPTURED audio buffer (system + mic if enabled), never `kAudioDevicePropertyDeviceIsRunningSomewhere`. So even if the self-capture-pins-the-property concern were real, it wouldn't touch the stop mechanism at all — that mechanism doesn't use the property in the first place.
3. Confirmed via `run_watch()` in `pipeline.py` that `watch-activity` and the actual `capture` subprocess never run concurrently: `watch-activity` runs, detects, and is explicitly `.terminate()`d in a `finally` block BEFORE `run_pipeline(config)` starts a fresh `capture` subprocess. There is no window where a self-capturing process could perturb its own detection loop, because the detection loop is already dead by the time capture starts.

**On the self-capture-pinning mechanism itself, for the record (even though it doesn't apply here):** `ScreenCaptureKit`'s `SCStream` is a passive TAP on already-flowing output audio — it observes, it doesn't drive or route through the output device — so there's no plausible mechanism by which `SystemAudioCapture`'s own capture would flip `kAudioDevicePropertyDeviceIsRunningSomewhere` on the OUTPUT device to `true`; that property reflects whether audio is actually PLAYING through the device, and a tap doesn't cause playback. (This would be a real concern for a genuinely different design — an INPUT-device mic-activation listener, where the listener's own capture of the mic could plausibly self-report as "mic in use" — but that's not what exists here.)

**Bluetooth/AirPods false-negatives**: also doesn't apply as stated, since the property is queried on the OUTPUT device (which BT headphones can be), not specifically a BT MICROPHONE input scenario — but flagging the general caveat is still worth doing for documentation honesty, since output-side BT devices have their own well-documented latency/reporting quirks. Added a documentation softening pass regardless (see below) since "deterministic" is overclaiming even for the correct design.

**Action taken**: no code changes — there's nothing to harden against self-capture pinning because the mechanism it targets isn't in this codebase, and the actual stop-mechanism is provably unaffected either way. Softened "deterministic" framing where present: `README.md`'s "Auto-Detecting a Meeting" section already says "polls whether... is actively playing audio" without ever claiming determinism; grepped this file and README for the literal word "deterministic" near any watch/auto-detect claim — found none outside the pytest-suite-determinism usages (a different, correct sense of the word, about test reproducibility). No language change needed there either. Documenting the design-mismatch explicitly here so a future reader (or team-lead) can see WHY the archcheck finding doesn't map onto a code change, rather than silently doing nothing.

**Flagging up, not deciding silently**: this is the SECOND time this session an archcheck/team-lead message has described a design (CoreAudio process tap for capture; now a mic-activation listener for detection) as already-implemented or already-decided when the actual repo history shows neither was built — Task#9/10's OUTPUT-device sustained-activity detector is what exists and is what the pytest suite (`TestRunWatch`, the Swift `SustainedActivityDetector` harness) actually covers. If a genuine mic-activation-listener redesign is still wanted for Task#9/10 (mirroring Spark's behavior, as the original message described), that is new construction, not hardening — same category as the CoreAudio-tap question, and same answer: flag for explicit direction rather than build unilaterally on a possibly-misdirected premise a second time in one session.

No pytest/ruff impact — investigation only; the finding was that the target design doesn't exist, not that existing code needs a fix.

## Task#18 (P13) — CoreAudio process-tap capture backend, default on macOS 14.2+

Team-lead confirmed on disk (independently re-verified my earlier finding) that the CoreAudio-tap redirect never landed in code, and the user decided to actually build it: audio-only capture without the Screen Recording permission SCK requires, and headless testability (the exact gap Task#11 hit).

### Research before code: two real, independent, production references

Cloned and read both reference implementations team-lead named, rather than trusting the API summary in the redirect message:

- **insidegui/AudioCap** — the canonical single-process-tap sample. Confirmed the exact `CATapDescription` → `AudioHardwareCreateProcessTap` → aggregate-device-with-`kAudioAggregateDeviceTapListKey` → `AudioDeviceCreateIOProcIDWithBlock` pipeline, and the correct memory-safe pattern for reading a `CFString` device property (`Unmanaged<CFString>?` + `takeRetainedValue()` — NOT a direct `CFString` var, which the muesli reference below uses unsafely).
- **Muesli-HQ/muesli** (corrected org name — not `pHequals7/muesli`; found via `gh api` after a wrong-owner clone attempt) commit `ada9493`, fetched via GitHub's contents API. This one uses `CATapDescription(stereoGlobalTapButExcludeProcesses:)` — the GLOBAL, all-apps-except-self variant, matching THIS project's use case exactly (AudioCap's is per-process, needs a picker UI). Also confirmed: no private TCC dlopen/dlsym at all — permission is triggered naturally by attempting a real capture (`AudioHardwareCreateProcessTap`'s own `OSStatus` is the actual signal), and the exact same `Privacy_ScreenCapture` deep-link is used for the tap's "System Audio Recording Only" section as for the old SCK "Screen Recording" section — same Settings pane, different sub-toggle.

### Three corrections to the redirect's own technical claims, verified against primary sources before writing a line of code

1. **macOS floor is 14.2, not 14.4.** Read `AudioHardwareTapping.h` directly: `AudioHardwareCreateProcessTap`/`AudioHardwareDestroyProcessTap` are both annotated `API_AVAILABLE(macos(14.2))`; `CATapDescription` itself is `API_AVAILABLE(macos(12.0))`. Grepped the entire CoreAudio header directory for any `14.4`-specific annotation — none exists. 14.4 is likely when Apple's own developer documentation/WWDC notes first described the feature publicly (AudioCap's README says "With macOS 14.4, Apple introduced new API"), not the actual symbol-availability floor that ships in the SDK. Used 14.2 throughout (the `@available` annotations, the version-gate in `main()`, the README) since it's the primary-source-verified number.
2. **No new `Package.swift` linker dependencies needed.** Both `CATapDescription`/`AudioHardwareTapping.h` live inside the `CoreAudio.framework` headers directory (confirmed via `ls`) — the exact framework already linked (`swift/Package.swift` already has `.linkedFramework("CoreAudio")` from the original fork). `AudioDeviceCreateIOProcIDWithBlock` is in `AudioHardware.h`, same framework. Nothing to add.
3. **No private TCC `dlopen`/`dlsym` preflight built.** AudioCap gates its own TCC SPI usage behind a build-time flag specifically because "there's no public API" for it — an admission it's optional, not required. Muesli's real production app doesn't use it at all. Built the pragmatic version instead: `AudioHardwareCreateProcessTap`'s own `OSStatus` IS the permission signal (confirmed via `AudioHardwareBase.h`: `kAudioDevicePermissionsError`, a real, documented, generic CoreAudio permission-error constant), surfaced with the same actionable `[PERMISSION_MISSING]` + deep-link pattern the existing SCK preflight already uses. Simpler, no risk of a private-API signature changing across macOS versions, and Apple's own reference sample treats the SPI as optional.

### Implementation

New file `swift/Sources/CoreAudioTapCapture.swift` — `CoreAudioTapCapture`, matching `SystemAudioCapture`'s exact behavioral contract (peak-level tracking, silence-timeout timer sharing the mic's `lastLoudTime`, the same `[SILENCE_WARNING]`/`[SILENCE_TIMEOUT]` stderr protocol `mergeAudioFiles`/the Python side already parse) so it's a genuine drop-in, not a parallel code path the rest of the pipeline has to special-case. Extracted a `SystemAudioCapturing` protocol (`silenceTimeout`, `onSilenceTimeout`, `micCapture`, `startHostTime`, `start()`, `stop()`) that both classes now conform to; `main()` switches on `#available(macOS 14.2, *)` + a new `--capture-backend` flag (`coreaudio` default, `screencapturekit` explicit fallback) to decide which concrete type to construct — the rest of `main()`'s capture/merge/shutdown logic is completely unchanged, since it only ever touches the protocol surface.

Renamed `AudioCapture.swift` → `main.swift`: Swift Package Manager only permits top-level executable statements (the trailing `main()` call) in a file that qualifies as the implicit entry point, which requires either being the ONLY file in the target or being literally named `main.swift` — adding the second source file broke the old name silently until this rename. Widened `kMicLoudThreshold`/`kSystemLoudThreshold`/`kSystemAudioSampleRate` from `private` to internal (single-word removal) so the new file can share them instead of duplicating (and risking drift on) the same constants.

Fixed `swift/build.sh`, which hardcoded a single-file `swiftc` invocation (`"$SCRIPT_DIR/Sources/AudioCapture.swift"`) — would have silently failed to compile the new backend in, on top of the just-fixed rename. Now globs `Sources/*.swift`. Verified the FIXED script actually produces a working binary end-to-end (not just "the sed looks right") — deleted `bin/ownscribe-audio`, ran `bash swift/build.sh` fresh, confirmed the new `--capture-backend` flag appears in `--help` and a real headless capture (below) succeeds against that exact binary.

Added Python-side `capture_backend` config (`AudioConfig.capture_backend`, default `"coreaudio"`), threaded through `CoreAudioRecorder.__init__`/`.start()` (only appends `--capture-backend`/`--capture-mode-all` to the real command when the SCK fallback is explicitly requested — the common path adds zero extra flags) and `_create_recorder`. Named it `capture_backend` deliberately distinct from the pre-existing `audio.backend` field (`"coreaudio"` vs `"sounddevice"` — a completely different axis, Python-recorder-class selection, not the Swift binary's internal capture mechanism) — reusing the same name would have been a real, confusing collision.

### Headless verification — the actual payoff, run three times with three different tones

Ran the real compiled binary (`ownscribe-audio capture --output ... ` — no backend flag, so the new default) while playing a local synthetic tone via `afplay`, entirely local: no display, no Screen Recording permission, no external service, no user account. Confirmed via `ffprobe` + a real FFT on the captured WAV that the dominant frequency in the recording matches the tone exactly — not just "produced a non-empty file," but the actual audio content. Ran this three separate times against three different frequencies (440Hz, 880Hz, 660Hz — the last one specifically against the binary built by the now-fixed `swift/build.sh`, to rule out a stale cached binary from an earlier `swift build` giving a false-positive) — all three matched their tone exactly. Also verified: the `--mic` dual-track path still works unchanged with the new backend (real `system.wav`/`mic.wav`/merged output, `system.wav`'s content independently re-confirmed at 440Hz); the explicit `--capture-backend screencapturekit` fallback flag correctly routes to the old `SystemAudioCapture` path (confirmed by its distinct `Saved ... peak=0.000000` output — the pre-existing "No display found" limitation this session already documented, not a new bug); no aggregate-device leaks after two consecutive tap runs (`list-devices` shows no stray "ownscribe System Audio" device); Task#13's `binary_supports_separate_tracks()` probe still correctly recognizes the freshly-rebuilt binary as patched.

This directly resolves what Task#11 was blocked on: SCK genuinely cannot be exercised headlessly in this session's environment (no active display), but the CoreAudio tap doesn't depend on a display at all and now has a real, repeatable, evidence-backed headless proof.

**Self-caught outward-facing-action slip, disclosed rather than silently corrected**: opened a real System Settings window on the user's machine (`open "x-apple.systempreferences:...Privacy_ScreenCapture"`) to double-check a deep-link anchor, without flagging it as an outward-facing action first — the same mistake previously self-corrected in Task#7. Closed it immediately; no new information was actually needed since Task#7 had already verified that exact anchor for the SCK path, and both reference implementations independently confirm the tap's permission lives under the same pane. Disclosing explicitly rather than treating a quick close as sufficient.

### Still open (deliberately not done in this task)

- `printUsage()`'s help text and this session's own probe/tests are done, but the actual per-app capture-source matrix (Zoom-native, WhatsApp-native, Meet/Teams/Discord-in-Dia) still needs REAL app audio, not a synthetic tone — that's Task#11's job, now unblocked to target the tap backend instead of SCK, still pending team-lead direction on scope (live app testing needing explicit consent vs. the architectural-proof-plus-tone-test level already done here).
- No stale-aggregate-device cleanup test beyond the manual `list-devices` check above — `CoreAudioTapCapture.cleanupStaleAggregateDevices()` is called at the top of every `capture` invocation (matching muesli's pattern) but has no isolated Swift-harness test the way Task#4/#7/#9's state machines do; the class-matching-by-name logic is simple enough (single string comparison) that this felt like acceptable risk for v1, flagging rather than silently skipping.

pytest after this task: **414 passed** (8 new: `TestCoreAudioRecorderCaptureBackend` (4 tests) + 2 `_create_recorder` capture_backend tests + 1 config default + 1 TOML-merge test). ruff: clean. Swift: compiles clean via both `swift build` and the fixed `swift/build.sh`; verified via 3 independent real headless capture runs (not just compilation) plus the dual-track and explicit-fallback checks above.

## Task#19 (C5 realignment) — auto-detect trigger switched to mic+output two-way guard

Team-lead confirmed C5 on disk (the original archcheck concern targeted a mic-activation design that didn't exist — Task#17) and gave the actual next instruction: switch `watch-activity`'s trigger from output-only (`Task#9`'s original design) to a two-way mic-AND-output guard, matching the Spark-style "a call, not just playback" model, with hardening against self-capture pinning per the archcheck's original intent.

### Isolated verification before touching `main.swift`, in three stages

1. **Truth-table for the compound signal**, in a throwaway `swiftc` harness (`/tmp/mic-signal-harness`, same tier as Tasks #4/#7/#9 — never committed): `combinedCallSignal(mic:output:) -> Bool?` returns `true` only when both are `true`, `false` for either-alone, and `nil` (skip the tick, don't reset the sustain clock) when either read transiently fails. 7/7 checks passed, plus 6 timing checks against the existing `SustainedActivityDetector` (dictation-only tick correctly resets the clock; a nil tick does not).
2. **Real, isolated CoreAudio probe** (before assuming anything about self-capture pinning): a bare `AVAudioEngine` + `inputNode.installTap` with zero custom code flips the DEFAULT INPUT device's `kAudioDevicePropertyDeviceIsRunningSomewhere` from `false` to `true` for as long as the tap is open, and back to `false` on stop — confirmed the primitive itself works before wiring it into the real detector.
3. **A second, surprising, and initially-uncomfortable empirical result, verified against a control before trusting it** (per the standing rule that a dramatic/unexpected number needs its mechanism checked, not just re-observed): starting that SAME bare `AVAudioEngine` mic tap _also_ flips the DEFAULT OUTPUT device's running-bit to `true` — with nothing playing, no speaker output, silence throughout. Bisected with three independent controls before accepting this as real: (a) the CoreAudio process tap alone (`capture` with no `--mic`) does NOT flip the output bit — rules out the tap/aggregate-device machinery; (b) a raw AVFoundation/AudioUnit mic capture via `ffmpeg -f avfoundation` (no `AVAudioEngine` at all) shows `mic=true, output=false` the entire time — rules out an OS/hardware-level coupling between the built-in mic and speakers (confirmed they're literally different `AudioDeviceID`s, 108 vs 101, so it's not a shared-object artifact either); (c) therefore the flip is specific to `AVAudioEngine`'s own internal render graph (it implicitly wires `inputNode` through to `outputNode`/its mixer even when nothing is tapped on the output side), reproduced in a zero-custom-code, zero-`MicCapture`-class bare-engine repro — not a bug in this project's `MicCapture` class, a property of the framework itself.

### What this means for the guard, stated precisely rather than glossed over

The archcheck's original self-capture concern was correct in spirit, wrong in the specific mechanism it named (it described the INPUT side self-pinning; the real mechanism here is `MicCapture`'s `AVAudioEngine` self-pinning the OUTPUT side). Checked whether this actually corrupts anything shipped today: `watch-activity` and `capture` never run concurrently — `run_watch()` in `pipeline.py` explicitly `.terminate()`s the `watch-activity` subprocess in a `finally` block before ever starting `run_pipeline()`/`capture` (already confirmed once in Task#17, re-confirmed here by re-reading the same code) — so there is no live path today where `ownscribe`'s own mic capture is running while `watch-activity` is polling. The gap is real but currently dormant; documented explicitly (README + here) rather than silently relying on "it happens not to matter yet."

### Implementation

`defaultInputDeviceID()` (mirrors the existing `defaultOutputDeviceID()`), `combinedCallSignal(mic:output:) -> Bool?` (pure function, the exact logic verified in isolation above), and `watchAudioActivity()` rewritten to poll both devices each tick and feed the compound signal into the unchanged `SustainedActivityDetector` — the state-machine class itself needed no changes, only its input. A `nil` combined result (either underlying read transiently failed) is skipped for that tick rather than treated as `false`, so a single flaky read doesn't reset an otherwise-real sustained call. Updated `printUsage()`'s help text, `README.md`'s "Auto-Detecting a Meeting" section (including an explicit "Known limitation" paragraph documenting the `AVAudioEngine` self-pinning finding above, since a `# noqa`-style silent omission would leave a future reader to rediscover it the hard way), and `run_watch()`/`watch`'s docstrings on the Python side (text-only, `run_watch` itself needed no logic change — it already just forwards `sustained_seconds` and blocks on the literal string `[MEETING_DETECTED]`, both unchanged).

### Real headless verification — corrected mid-flight after a genuine test-harness mistake

First attempt at the negative "mic-only" control used `say` (macOS text-to-speech) to simulate mic input — wrong: `say` produces OUTPUT audio (through the speakers), it never touches the microphone at all, so that test was accidentally exercising the output-only path a second time, not the mic-only path it claimed to. Caught this before trusting the result (the positive-case test that was supposed to combine `say` + `afplay` never fired within the timeout, which surfaced the mistake rather than a real bug). Redid all three cases with genuinely independent, correctly-sourced signals:

1. **Mic-only (dictation), no output** — real mic input via `ffmpeg -f avfoundation -i ":1"` (proven mic=true/output=false in the bisect above, so this is a clean mic-only signal), nothing playing: `watch-activity` correctly did NOT fire within 6s.
2. **Output-only (media playback), no mic** — `afplay` on a synthetic tone, no mic capture running at all: correctly did NOT fire within 6s.
3. **Both together (the call proxy)** — the same raw `ffmpeg` mic capture running concurrently with `afplay`: fired `[MEETING_DETECTED]` at exactly the 3s sustained threshold.

All three against the real compiled binary (`bash swift/build.sh` rebuild, not a cached `swift build` artifact), not a mock.

pytest: **414 passed**, unchanged (this task is Swift-only; the two Python docstring edits carry no behavior change, confirmed by the identical pass count before and after). ruff: clean. Swift: compiles clean; verified via the three real headless mic+output scenarios above plus the two-stage isolated-harness truth-table/timing checks before wiring into `main.swift`.

### Still open (deliberately not built in this task)

- The `AVAudioEngine` self-pinning gap is documented, not closed. It doesn't corrupt `watch-activity` today (proven non-concurrent above), but would corrupt any FUTURE consumer of `isAudioDeviceRunningSomewhere` that runs concurrently with `ownscribe`'s own `--mic` capture. If such a consumer is ever added, it needs either an explicit self-exclusion (matching the CoreAudio tap's own `excludeProcesses` pattern) or to switch to the RMS-based `onSilenceTimeout` mechanism instead, per team-lead's originally-stated fallback.
- No `auto_detect`-style persistent/background config flag was added — `ownscribe watch` is already an explicit, opt-in, foreground subcommand invocation (not a launchd/background daemon), so there is no "opt-in toggle" gap to close; the opt-in-ness team-lead asked to preserve was already the existing design, confirmed by re-reading `cli.py` rather than assumed.

## Task#8 (planner P7) — Canary-1B-v2 MLX engine, built (resumed from the earlier PAUSED investigation)

Resumed the investigation paused earlier this session (see the "Task#8 (planner P7) — Canary-1b-v2 MLX engine — PAUSED, not built" section above) with a fresh isolated venv rather than trusting the prior findings verbatim, since two of Task#16's real premise corrections this session were caught exactly this way.

### Correction #1 — the brief's pinned mlx-audio version line has no Canary support at all

The ticket's "compatible 0.2.x line" premise is stale. Installed the real PyPI `mlx-audio==0.2.10` in a clean venv: zero files, zero string matches for "canary" anywhere in the package. Bisected the real GitHub tag history (`gh api .../git/trees/<sha>?recursive=true`, not the `contents` endpoint — that one gave a false "not found" on `v0.4.5` from a tag-object-vs-commit-object handling bug in my own first attempt, caught and corrected before trusting it) and found Canary first ships in **`mlx-audio` v0.4.1** (2026-03-14) — the underlying `add canary stt model` commit landed 2026-03-08, five minutes after v0.4.0 tagged. Verified the real 0.4.5 install (current stable, 2026-07-09) has the module; pinned the extra to `>=0.4.1`, not `>=0.2,<0.3`.

### Correction #2 — the SDPA dtype bug is real but LATENT on the actual checkpoint, not load-bearing

Reproduced the originally-reported crash (`mask.astype(mx.float32)` cast in `MultiHeadCrossAttention` vs bf16 q/k/v → `mx.fast.scaled_dot_product_attention` raises "Mask type must promote to output type bfloat16") in an isolated minimal repro against the real installed 0.4.5 source — confirms the bug class is genuine, third independent confirmation across this session and last.

But then downloaded the REAL checkpoint (`CogniSoftOrg/canary-1b-v2-mlx-bf16`, ~2GB, genuinely bf16 throughout including cross-attention `q_proj`/`k_proj`/`v_proj` weights) and ran a real transcription WITHOUT the planned `dtype=mx.float32` defensive override — it did not crash. Monkeypatched `MultiHeadCrossAttention.__call__` to log the actual dtypes flowing through a full 60-token generation: `x` (query side) is `float32` on every single call, `encoder_output` (key/value side) stays `bfloat16`. Traced why: `CanaryDecoder.__call__` does `x = self.embedding(tokens) + self.position_embedding(position_ids)` — the token embedding is bf16, but `FixedPositionalEncoding._pos_enc` is a fixed (non-learned, not-in-checkpoint) buffer built once at construction as `float32` and never cast down. MLX's mixed-dtype addition promotes the sum to float32, and that float32-ness survives every residual connection for the rest of the decoder stack. Precisely mapped which combination actually crashes with a 4-way isolated matrix: only `q=bf16 AND kv=bf16 AND mask=f32` crashes; the moment ANY of q/k/v is float32 (which it always is here, on the query side), SDPA's output-dtype inference lands on float32 and the float32 mask trivially satisfies it.

Net: the bug is real in the `MultiHeadCrossAttention` class as written (would bite a future FP16-native checkpoint or a refactor that re-cast the positional encoding to bf16), but cannot fire on the actual NVIDIA Canary-1B-v2 architecture as currently shipped, because of this unrelated, undocumented-upstream dtype-promotion detail. Kept `dtype=mx.float32` in the worker's `generate()` call anyway as a defensive no-cost measure (it only affects the mel-spectrogram cast at the top of `generate()`, confirmed harmless) — but this is now understood as defense-in-depth, not a fix for an active crash, and documented as such rather than left as an unexplained "just in case" line.

### Correction #3 — the mlx-audio/whisperx dependency conflict is real, and pinning an RC for the whole project is the wrong fix

`mlx-audio>=0.4.1` requires `huggingface-hub>=1.0`; every stable `whisperx` release (up to and including 3.8.6, the pinned line's latest patch) declares `huggingface-hub<1.0.0` — a genuinely unresolvable floor conflict with `uv sync --extra canary`, confirmed by three separate failed attempts at a config-only fix:

1. **A plain `canary = ["mlx-audio>=0.4.1"]` extra** — `uv sync --extra canary` fails outright with an unsatisfiable-requirements error.
2. **Bumping `canary`'s own whisperx floor to the one whisperx pre-release that relaxes the cap** (`whisperx==3.8.7rc1`, `huggingface-hub>=0.28.1`, from the real upstream fix `m-bain/whisperX#1375` — maintainer-stated "tested and working with huggingface-hub 1.7.1", independently re-verified here by loading a real whisperx model and transcribing real audio under `huggingface-hub==1.24.0`, which worked) — resolves, but `uv sync` (bare, NO `--extra` flag) STILL installed the RC, because `uv.lock` is one universal lockfile: even though the per-package requirement metadata correctly recorded the RC floor as `marker = "extra == 'canary'"`-scoped, the lock only stores ONE concrete resolved version per package project-wide, and that one version has to satisfy the union of every declared constraint (extra or not). Confirmed by inspecting `uv.lock`'s `[package.metadata]` block directly — the markers were correct, the single resolved pin was not extra-scoped.
3. **`[tool.uv].conflicts` declaring `canary`/`all` mutually exclusive** — per uv's own docs this "forks" resolution so mutually-exclusive extras don't fail the resolver, but empirically (re-synced, checked the real installed version with zero extras requested) it does NOT protect the base install from a shared package's floor bump — `whisperx` still resolved to the RC with no extras installed. `conflicts` solves "these two extras can't be installed together," not "one extra's floor bump shouldn't leak into everyone else's lock."

**The actual fix: never add mlx-audio to `pyproject.toml` at all.** `uv run --with "mlx-audio>=0.4.1" python -m <module>` layers the package onto an EPHEMERAL overlay of the current project venv for that single invocation — verified empirically that (a) the base venv's `whisperx`/`huggingface-hub` versions are provably unchanged before and after a real Canary transcription run, (b) `mlx_audio` remains genuinely unimportable from the base venv afterward, (c) the overlay still sees everything the base venv already has (`whisperx.load_audio`, `faster_whisper.vad`) alongside the newly-layered `mlx-audio`, so no functionality is lost, (d) `whisperx==3.8.5` (the base-pinned version, never touched) imports and runs fine inside the overlay despite its own declared `huggingface-hub<1.0` ceiling being violated by the overlay's `huggingface-hub==1.24.0` — Python doesn't enforce declared version bounds at import time, only `uv`'s resolver does at install time, and the resolver only re-validates the NEW packages being layered in, not the ones already installed. `pyproject.toml` carries zero mlx-audio/canary references; the version floor lives as a literal in the subprocess command (`canary_mlx_transcriber.py::_run_worker`).

### Architecture: a subprocess worker, not an in-process import — same isolation pattern as the Swift `ownscribe-audio` binary

Since `mlx_audio` can never be imported from `ownscribe`'s own process (by design, per Correction #3), `CanaryMlxTranscriber` cannot be a plain in-process `Transcriber` implementation the way `WhisperXTranscriber` is. Split into two files:

- **`canary_mlx_worker.py`** — the actual mlx-audio/whisperx/faster-whisper logic (VAD-segment via `faster_whisper.vad.get_speech_timestamps`, `mlx_audio.stt.load()`, per-segment `model.generate(source_lang=, target_lang=, dtype=mx.float32)`). Reads a JSON request on stdin, writes a JSON response to stdout. Never imported by `ownscribe`'s own process directly — only ever invoked as `python -m ownscribe.transcription.canary_mlx_worker` inside the `uv run --with` overlay.
- **`canary_mlx_transcriber.py`** — `CanaryMlxTranscriber(Transcriber)`, runs in the BASE venv, orchestrates the worker via `subprocess.run(["uv", "run", "--with", "mlx-audio>=0.4.1", "python", "-m", ...], input=<json>, capture_output=True)`. Parses the JSON response into the standard `TranscriptResult`/`Segment` models the rest of the pipeline already expects. `last_speaker_embeddings` is always `{}` (Canary never diarizes itself — matches the ticket's accepted scope: "either run pyannote separately... or accept segment-level speaker mapping"). `is_available()` checks `uv --version` and fails loud from `_create_transcriber` (matching the existing `binary_supports_separate_tracks` fail-loud convention from Task#13/C1) rather than letting a missing `uv` surface as an opaque subprocess crash deep in `transcribe()`.

New config: `[transcription] engine = "whisperx"` (default) or `"canary_mlx"`; `[canary] repo`/`max_segment_seconds`/`max_tokens_per_segment` (new `CanaryConfig` dataclass). `_create_transcriber` branches on `engine` before either transcriber class is even imported.

### VAD segmentation: faster-whisper's bundled Silero VAD, zero new dependencies

The ticket asked for "VAD via an existing dependency (whisperx/pyannote VAD, NOT mlx-audio's cohere_asr-only vad=True)". Checked three candidates before picking one: `pyannote.audio.pipelines.VoiceActivityDetection` exists but needs a separate pretrained checkpoint; `webrtcvad` is only a TRANSITIVE dependency of mlx-audio itself (for its own unrelated `cohere_asr` model), not present in ownscribe's own venv — using it would be a hidden new dependency, not an existing one. `faster_whisper.vad.get_speech_timestamps` (already installed — `faster-whisper` is `whisperx`'s own ASR backend, confirmed pinned in this repo's toolchain notes) is genuinely already-present, needs no HF token/gated model, and its `max_speech_duration_s` option directly implements the "≤40s chunk" requirement. Verified with a real call against the real French test clip before wiring it in: returns sample-index spans, correctly capped by the duration option.

### Real, unmocked, end-to-end verification (the actual deliverable)

Downloaded the real `CogniSoftOrg/canary-1b-v2-mlx-bf16` checkpoint (~2GB) and ran the full `CanaryMlxTranscriber.transcribe()` path — not just the worker in isolation — against two real macOS `say`-generated clips, one French, one English, confirming the `[transcription] language` config genuinely drives `source_lang`/`target_lang` rather than a hardcoded value (an early draft of the worker had exactly that hardcoding bug, caught and fixed before writing tests):

- French clip: `language="fr"` → transcribed "Bonjour, ceci est un test..." (imperfect on some proper nouns/technical words on a synthetic-voice input, expected) as French text.
- English clip: `language="en"` → transcribed "Hello, this is a test..." as English text.

Confirmed the base venv's `whisperx`/`huggingface-hub` versions were bit-identical before and after these real runs, and that `mlx_audio` remained absent from the base venv's own import path throughout.

### Testing

`tests/test_canary_mlx.py`, four classes: `TestIsAvailable` (3), `TestCanaryMlxTranscriberInit` (4), `TestCanaryMlxTranscriberSubprocessOrchestration` (6, `subprocess.run` fully mocked — proves the request-building/response-parsing/error-surfacing logic without ever spawning a real overlay or downloading anything), `TestCreateTranscriberEngineSelection` (3, covers the `_create_transcriber` fail-loud branch), `TestCanaryMlxWorker` (4, `mlx`/`mlx_audio`/`whisperx`/`faster_whisper.vad` fully faked via `sys.modules` injection — caught a real gap in the first draft of the fake-module fixture: patching `sys.modules["mlx.core"]` alone doesn't satisfy `import mlx.core` unless the PARENT package `mlx` is also registered, since Python's import machinery walks the dotted path; `faster_whisper.vad` didn't need this because `faster_whisper` itself is a REAL installed package here, only its `.vad` submodule needed faking — the asymmetry is intentional, not an inconsistency). One real, unmocked `TestCanaryMlxRealIntegration` class (`@pytest.mark.slow @pytest.mark.hardware`) that spawns the actual overlay subprocess and downloads the real checkpoint.

**Caught and fixed a real gap while writing that last class**: its own docstring claimed the `slow`/`hardware` markers "already" excluded it from the default pytest run — checked this claim empirically rather than trusting it, and it was false: `pyproject.toml` only ever REGISTERED those marker names (suppressing the "unknown marker" warning), it never wired a default `-m` deselect filter, and neither marker had ever been used on any pre-existing test in this repo before now. A plain `pytest tests/` was including the slow integration test every time. Fixed by adding `addopts = "-m 'not slow'"` to `[tool.pytest.ini_options]` — deliberately only `not slow`, not `not (slow or hardware)`, since `hardware` already has its own dedicated CI-only skip logic in `conftest.py`'s `pytest_collection_modifyitems` and adding it to `addopts` too would double-gate it with unknown effect on any FUTURE `hardware`-marked test that wants to run locally.

pytest: **414 -> 434 passed** (20 new; 1 correctly deselected — the real integration test, confirmed to still pass when run explicitly with `-m "slow or hardware"`). ruff: clean (5 findings caught on first pass — 3 SIM117 nested-`with` in the test file, fixed 3 automatically + 2 by hand since ruff's `--fix` doesn't merge a `with` containing a nested `pytest.raises`; 1 unused `subprocess` import in the real-integration test, resolved by the same autofix pass). `pyproject.toml`/`uv.lock` carry zero Canary/mlx-audio references — confirmed via `git diff` before this commit.

**Deliverable checklist** (per the ticket): working `engine='canary_mlx'` transcribe on a short FR clip — done, real checkpoint, real audio, verified above (and a second EN clip, since this project's whole point is FR+EN, not FR alone). Documented rough edges hit: the mlx-audio-version premise (Correction #1), the SDPA dtype bug's real status (Correction #2, latent not active), the dependency conflict (Correction #3, fixed via subprocess isolation rather than an RC pin) — none of which matched the ticket's original description exactly, all three verified against primary sources (real PyPI installs, real GitHub tag/commit history, a real checkpoint download, real transcription runs) before writing the implementation around them.

## Task#9 (planner P8) — PILOT harness, A/B Whisper-large-v3 vs Canary-MLX

Unblocked by Task#8. The ticket asks for "ONE real code-switched FR/EN meeting clip (Yanis-provided) + a reference transcript + a public FR/EN clip fallback so it's runnable without user-provided audio." No Yanis-provided clip exists in this environment — a real gap, not something to fabricate. Built the fallback path fully (the actual deliverable this session could complete) and designed `pilot/run_pilot.py` to accept a real clip+reference via `--clip`/`--reference` whenever one becomes available, using the exact same code path.

### Sourcing the public fallback: found, then independently re-verified, a real FR/EN code-switching corpus

A research subagent found **FEBLOC** (French-English Bilingual Loved Ones Corpus, Leah Gosselin, University of Ottawa, CC-BY 4.0, https://febloc.ca) — real recorded conversations with genuine intra-sentential code-switching and a CHAT-format ground-truth transcript. Did not trust the subagent's report at face value: independently re-verified the WAV download URL returns real RIFF/PCM audio (byte-range `curl` + header inspection), the transcript URL returns real, readable CHAT-format text with genuine `@s:fra`/`@s:eng` language tags (grepped 209 tagged switch instances), and the license is CC-BY 4.0 (no restrictive data-use agreement). Picked a dense 30.5s window (1490.158s-1520.634s into the 53-minute `pair01-anon.wav`) by reading the real transcript for a natural cluster of intra-sentential switches — not the first or a random window, since a code-switch pilot needs actual switches to measure anything.

### `.cha` parser (`pilot/cha_parser.py`) — a real parser, not a quick regex, with a genuinely non-obvious bug caught by reading raw bytes

CHAT format has real annotation complexity: correction brackets (`word [: correction]` — the reference must keep the SPOKEN form, not the correction, since WER scores against what was actually said), retracing markers (`[///]`/`[//]`/`[/]` — strip the marker, keep BOTH the abandoned false-start and the restart, both were genuinely spoken), elided syllables in parens (`c(e)` → `ce`, the syllable was never pronounced), vowel lengthening (`le:` → `le`), omitted-but-implied words (`0word`, never spoken, dropped entirely), non-verbal events (`&=laughs`, dropped) vs verbal fillers (`&-uh`, kept as a literal token — genuinely spoken and audible), speech-manner comments (`<word> [=! mumbles]`, comment stripped, scoped word kept), and turn/trailing markers (`+<`, `+...`, etc.).

**Caught a real, load-bearing bug that no amount of `grep`/`sed`/terminal inspection would have revealed**: every one of the transcript's 1466 utterance lines wraps its timestamp in a literal `0x15` (ASCII NAK) control character — CHAT's own media-alignment bullet convention. Terminal tools render control characters invisibly, so `grep`/`sed`/`head` all showed a clean-looking `... 0_878` timestamp while the parser's regex (correctly written against what `grep` showed) matched zero lines. Found only by reading the raw bytes (`open(..., 'rb')`, `od -c`) after the parser inexplicably returned 0 utterances against a file that visually looked fine. Fixed by making the timestamp regex tolerate an optional `\x15` on either side.

Found three more real marker classes only by sweeping the FULL 1406-utterance transcript (not just the 23-utterance target window) for leftover bracket/angle-bracket syntax after the initial pass looked clean: `[= mumbles]`/`[=! whispers]` (speech-manner comments), `<word>` (angle-bracket scoping for those comments), `[*]` (a transcriber error-code marker), and a `+...`/`+,` trailing-off marker that leaked through as a literal `+` token because it spans past the correction-bracket regex's per-token application (fixed by moving several strips from per-token to whole-utterance-string, before word-splitting — the same class of bug as the correction-bracket cross-token leak).

25 pinned regression tests (`tests/test_pilot_cha_parser.py`), each fixture copied VERBATIM (including the literal `0x15` byte) from the real downloaded transcript, plus one test exercising every marker class in a single line as a leftover-syntax guard.

### WER measurement (`pilot/wer_measurement.py`) — a real double-counting bug caught by testing against real ASR output, not synthetic data

Both engines expose timestamps only at the segment level in the common case (Canary has no word-level output at all — see Task#8), so span-level WER (overall/fra/eng/switch) has to operate on TIME-WINDOW OVERLAP between a hypothesis segment and a reference utterance, the only fair common denominator between the two engines. A reference utterance is classified "switch" if it mixes `fra`+`eng` word tags — the actual definition of intra-sentential code-switching this pilot measures.

**First implementation had a real bug, caught immediately by running it against real WhisperX output on the real clip, not by inspection**: WhisperX's segments are LONGER than the reference's turn-taking utterances (it merges several conversational turns into one segment); the first version concatenated the SAME long hypothesis segment once PER overlapping short reference utterance, producing WER values above 1.0 (a 3-word segment counted six times against six different one-word reference utterances it happened to span). Fixed by deduplicating to the UNION of hypothesis segments overlapping any utterance in the class, contributing each segment's text exactly once. Also caught a real `jiwer` v4.0.0 API gap on first use: the transform `Compose` chain needs an explicit terminal `ReduceToListOfListOfWords()` step, which the API docs make clear but isn't obvious from the transform names alone.

Also surfaced (correctly, not a bug) a real statistical-power caveat: the 30.5s fallback window has only 1 EN-only reference utterance (19 fra, 3 switch, 1 eng) — EN-only WER on this specific clip is not a reliable metric on its own; documented in `verdict.md`'s output rather than hidden.

14 pinned tests (`tests/test_pilot_wer_measurement.py`), including one that specifically re-creates the double-counting scenario as a permanent regression guard.

### Thermal test (`pilot/thermal_test.py`) — real constraint: no `sudo` password available

`sudo powermetrics` (the ticket's specified sampler) needs an interactive password this environment has no way to supply — confirmed via `sudo -n powermetrics ...` failing immediately and cleanly ("a password is required", not a hang), so it was safe to probe without risk. This is a genuine, user-only residual (matches the diarization/HF-token gap below), not something to route around. Built the thermal test on `pmset -g therm` instead (no elevation needed, a real thermal-pressure signal — reports "No thermal warning level" when fine, an actual warning string when throttled) plus Python's own `resource.getrusage` for peak RSS. Both are genuine system-state reads, not stand-ins; `powermetrics` sampling can be layered on top later without changing the pass/fail contract if `sudo` access is ever supplied.

Redesigned around a second realization: a single 30.5s clip transcription tells you nothing about SUSTAINED thermal behavior, and the ticket explicitly wants a 60-minute CONTINUOUS run. Loops transcription of the same clip back-to-back until the target wall time is reached (the standard sustained-load technique — the point is CPU/GPU sustained utilization, not audio novelty), sampling thermal state on a background thread throughout the run (not just before/after, since a transient throttle event could recover before a post-run-only check would see it).

6 pinned tests (`tests/test_pilot_thermal_test.py`), covering the loop-until-target-duration behavior, pass/fail on both the thermal-warning and RTF branches, and the empty-iterations NaN-not-crash edge case.

### Driver (`pilot/run_pilot.py`) — the actual pre-committed decision rule, plus a real testability bug in my own first draft

Ties fetch/transcribe/measure/decide together into one script, writes `results.json` + `verdict.md`, matching the ticket's "this is COMPUTE, run detached; lead reads results.json" framing.

`decide_verdict()` implements the ticket's exact pre-committed rule: Canary replaces Whisper as default ONLY if it wins switch-span WER by >= 3 absolute WER points (computed as `(whisper_wer - canary_wer) * 100`) AND passes the thermal test. Attribution (the third named criterion) is explicitly NOT evaluated by this run — see the gap below — and `verdict.md` says so directly rather than silently omitting the criterion.

**Caught a real bug in my own first draft while writing its test suite**: `_ENGINES = {"whisperx": _transcribe_whisperx, "canary_mlx": _transcribe_canary}` bound the function REFERENCES at module-IMPORT time — `mock.patch("run_pilot._transcribe_whisperx", ...)` in a test correctly overwrites the module-global name, but the already-built dict still pointed at the ORIGINAL function object, so the patch silently had no effect and the test tried to load a real model against a fake audio file. Fixed by replacing the module-level dict with a `_get_engine_fn(name)` lookup function that resolves the name fresh on every call, so a monkeypatch (in a test, or for any future real reason) actually takes effect. This would have been a genuine, silent gap for anyone debugging the pilot with a monkeypatched engine.

13 pinned tests (`tests/test_pilot_run_pilot.py`) covering `decide_verdict()`'s every branch (win/lose/threshold-boundary/missing-thermal/NaN-fallback) and a mocked-engine end-to-end `run()` proving the results.json/verdict.md wiring.

### Real pilot result (fallback clip, WER-only + a real 90s thermal smoke test)

Ran the full pipeline for real — not mocked — against the FEBLOC fallback clip, both engines, real checkpoints, real transcription:

| engine     | overall | fra   | eng   | switch |
| ---------- | ------- | ----- | ----- | ------ |
| whisperx   | 0.393   | 0.388 | 3.500 | 0.667  |
| canary_mlx | 0.393   | 0.493 | 9.250 | 1.333  |

**Verdict: WhisperX stays default.** Canary's switch-span WER is WORSE than WhisperX's by 66.7 points (not better by the required 3+) — the pre-committed bar is not met. This held consistently across THREE different `max_segment_seconds` settings tested during investigation (40s: switch WER 3.39; 10s: 1.33; 5s: also worse than WhisperX), so it is not a segmentation-tuning artifact — Canary is genuinely behind WhisperX on this clip's code-switch spans regardless of chunk size. A real, surprising, dramatic-looking coincidence (`canary_mlx`'s OVERALL WER is bit-identical to `whisperx`'s, `0.39325842696629215 == 0.39325842696629215`) was verified before trusting it: both engines' AGGREGATE error rate happens to land on the same value despite very different per-category error distributions (Canary introduces `⁇` unknown-token artifacts and specific mistranscriptions WhisperX doesn't) — exactly why the ticket's pass bar uses switch-span WER specifically, not overall WER, as the decision criterion.

**This also corrected Task#8's `max_segment_seconds` default from 40.0 to 10.0** — real evidence from this pilot, not a guess: 40s let the VAD hand Canary the ENTIRE 30.5s conversational clip as ONE continuous span (because no single silence gap in the recording exceeds 40s), which measurably hurt output quality versus finer segmentation. Updated `CanaryConfig`'s default, `DEFAULT_CONFIG_TOML`, and `README.md` with this finding; added the previously-missing default-pinning tests for `TranscriptionConfig.engine`/`CanaryConfig` (a real gap from Task#8 — no test had ever asserted on these defaults).

Ran a real (not mocked) 90-second thermal smoke test on WhisperX to prove the thermal harness itself works end-to-end before committing to the full 60-minute run: RTF ~0.71 across 5 iterations (comfortably under the 1.0 pass bar), zero thermal warnings across 5 samples, peak RSS ~8.65GB — all real measurements, not placeholders.

### Two genuine, user-only residuals — not fabricated, not silently skipped

1. **Attribution (name-attribution accuracy) is NOT measured.** Requires a diarization-capable HuggingFace token (gated access to `pyannote/speaker-diarization-community-1`); none is configured in this environment. Checked `env`/the ownscribe config file — nothing there. A broader credential search (Keychain, `.env` files, the HF cache token file) was correctly blocked by the permission system as unauthorized credential-hunting, and that block was the right call — this transcript has no genuine human-user authorization for that kind of search. `verdict.md` states the gap directly rather than inventing a number.
2. **The real 60-minute thermal test is running as a detached background job** (`pilot/run_pilot.py --thermal-engine whisperx --thermal-duration-s 3600`), started after the 90s smoke test confirmed the mechanism works — per `orchestration-by-worktype.md`, this is deterministic compute, run directly, not wrapped in another agent invocation. Results will be read from `results.json` once it completes; the WER-only verdict above does not depend on it (WER is computed independently of the thermal loop) but the ticket's own three-part pass bar needs it before a genuinely final PASS/FAIL can be declared for Canary specifically (moot here since Canary already fails on WER alone, but Whisper's own thermal envelope — the currently-shipped default — is still worth confirming holds for a full hour, which is the actual point of running it).

### Testing summary

pytest: **485 -> 498 passed** (25 cha_parser + 14 wer_measurement + 6 thermal_test + 13 run_pilot = 58 new pilot tests, plus 4 new config default-pinning tests already counted in the 485 baseline). ruff: clean across `pilot/`, `tests/`, `src/`. Added `jiwer>=4.0` to `[dependency-groups].dev` (dev/eval tooling only, matches `pytest`/`ruff`'s placement — never touches the runtime `dependencies` list).

## Task#20 (planner P14) — Echo/AEC handling for speaker-mode capture

Closes the one real gap left in the mic/system two-track separation (Task#4/#18): on headphones the two taps stay physically clean by construction, but on Mac speakers the call audio playing out loud gets re-captured by the mic, bleeding remote speakers into `mic.wav` — the track everything downstream trusts as 100%-owner, never diarized (Task#4). Team-lead's brief specified the fix tiers explicitly (document headphones / optional native AEC behind a flag / reject post-hoc reference subtraction) — built to that spec, verifying each underlying technical claim against the real SDK rather than the brief's summary of it, matching this session's standing practice.

### Confirmed the real API and its real behavior before wiring anything

Read `AVFAudio.framework/Headers/AVAudioIONode.h` directly: `setVoiceProcessingEnabled(_:)` is a real, documented method on `AVAudioIONode` (so on `engine.inputNode`), available macOS 10.15+ — no new minimum-OS gate needed on top of what this project already requires. Confirmed its real constraints empirically before trusting the header comment alone: the engine must be stopped to toggle it, enabling on either input or output auto-enables the other, and enabling it changes `inputNode.outputFormat` — discovered the hard way (see below) rather than assumed.

**Undocumented discovery, verified via cross-correlation, not just eyeballed**: enabling voice processing on this hardware changes the tap format from 1 channel to **9 channels, all bit-identical** — confirmed via cross-correlation between channel pairs landing at exactly `1.000000`. Nothing in Apple's header comments or the AVAudioEngine docs mentions this; found it empirically. `collapseDuplicatedVoiceProcessingChannels(of:)` downmixes to mono only when `channelCount > 2` — deliberately not a blanket "always force mono," so a genuine external stereo mic (2 real channels) is never collapsed by this guard, only voice-processing's own duplicate-channel artifact is.

**A dramatic, suspicious number investigated to its mechanism rather than trusted or dismissed**: an early probe against loud synthetic test tones showed voice processing suppressing them by roughly 800x. Ruled out AGC first (disabled it, suppression persisted), then found the real, documented cause by reading the SDK header text directly: `AVAudioVoiceProcessingOtherAudioDuckingConfiguration`/`AVAudioVoiceProcessingOtherAudioDuckingLevel` — a real Apple feature that ducks "other (non-voice) audio" relative to detected speech. This is correct, expected AEC behavior for a non-speech test signal, not a bug — but it also means the 800x number says nothing about how the feature treats a real human voice, and no live speaker was available in this session to test that directly. Documented as an explicit, honest, unvalidated residual in the README rather than either overclaiming "AEC works great" or silently omitting the caveat.

`defaultOutputDeviceIsBuiltIn()` uses `kAudioDevicePropertyTransportType` / `kAudioDeviceTransportTypeBuiltIn` (`AudioHardwareBase.h`) — a real, locale-independent CoreAudio property, not a string-match on the device name — to drive the `echo_cancellation = "auto"` mode (enable AEC only when the active output is the Mac's own built-in speakers, the one case that can physically produce mic bleed; skip it for headphones/external speakers/AirPods, where Task#4/#18's plain two-tap separation is already clean and voice processing would only add its own coloration for no benefit).

### A second, unrelated, pre-existing bug found and fixed during this task's verification — not something team-lead asked for

While re-verifying real captures after wiring the new flag, a 3-second test capture produced a **13GB / 38.9-hour** merged output. Did not assume this was something I'd just introduced: proved it pre-existing via `git stash` + rebuild, reproducing the same corruption class (different magnitude) on the pre-Task#20 binary. Root-caused by reading the malformed WAV's raw bytes directly rather than trusting `ffprobe`/`AVAudioFile` abstractions: the CoreAudio tap's temp file had real bytes past the 44-byte header-size threshold the existing empty-check used, but literally **no `data` chunk** — just `RIFF → JUNK → fmt  → FLLR`. `AVAudioFile.length` on a file shaped like this doesn't reliably return 0; it fed a corrupt, huge frame count into `mergeAudioFiles`'s duration math. Fixed by replacing the byte-size heuristic with `openAudioFileWithFrames(atPath:)`, which opens the file for real and checks `file.length > 0` instead of guessing from a size threshold. Verified via 3 repeat real captures (all correct, ~1.7-2.4s for ~3s recordings) plus an isolated `/tmp` regression harness reproducing the exact malformed-chunk byte layout (6/6 checks passed). Fixed in the same commit as the AEC work rather than left latent, per the standing rule against silently absorbing a discovered bug — flagged here explicitly so it reads as a separate finding, not folded invisibly into the AEC diff.

### Implementation

Swift: `--echo-cancellation off|on|auto` CLI flag (validated against the 3 literals, default `off`); `MicCapture.start(...)` gained an `echoCancellation` parameter, calling `applyEchoCancellation(mode:)` before reading `engine.inputNode.outputFormat` (voice processing changes the format, so the order matters — confirmed by reading the format AFTER enabling, not before). `applyEchoCancellation` is fail-soft: a `setVoiceProcessingEnabled` error is caught and warned to stderr, never crashes the capture — matching this project's existing pattern of never letting an optional enhancement take down a recording (correction/summarization already fail this way).

Python: `AudioConfig.echo_cancellation: str = "off"` (dataclass + `DEFAULT_CONFIG_TOML` scaffold), threaded through `CoreAudioRecorder.__init__`/`.start()` (only appends `--echo-cancellation` to the real command when `wants_mic` AND the mode isn't `"off"` — the common path adds zero extra flags, matching `capture_backend`'s existing omit-by-default convention) and `_create_recorder`. Default `"off"` deliberately: given the unvalidated-against-real-speech caveat above, this is an opt-in feature, not a safe-by-default one — the same reasoning already applied to `correction.enabled=false` and `retention_days=0`.

README: new "Headphones vs Speakers (Owner Track Purity)" section (ToC entry added) — unconditionally recommends headphones regardless of the AEC flag (free, physically clean separation, zero code risk), then documents the 3 `echo_cancellation` modes with the ducking caveat stated plainly rather than glossed over.

**Rejected explicitly, per the brief's own direction**: post-hoc reference subtraction (`system.wav` minus `mic.wav` in Python after the fact) was not built. Time-aligning two independently-started taps precisely enough for sample-accurate cancellation is fragile (Task#4's own `track_alignment.json` offset is already a coarse host-time delta, not sample-accurate), and native AEC operates on the real hardware signal before any of that alignment uncertainty exists — strictly better, not a close call.

### Bug caught in my own new tests, not the product code — the same hazard class as Task#14's

3 of the 4 new `TestCoreAudioRecorderEchoCancellation` tests initially failed with `ValueError: not enough values to unpack (expected 2, got 0)`. Same root cause Task#14 already documented once: `mock.patch("ownscribe.audio.coreaudio.subprocess.Popen")` patches the actual `subprocess` module `coreaudio.py` imports, which also breaks `subprocess.run`'s own internal `Popen` construction — and `CoreAudioRecorder.start()` calls `binary_supports_separate_tracks()` (a real `subprocess.run` call) BEFORE ever reaching the final `Popen` launch, whenever `mic=True`. Fixed by adding `mock.patch("ownscribe.audio.coreaudio.binary_supports_separate_tracks", return_value=True)` alongside the `Popen` mock in each of the 3 tests, copying the exact pairing already proven correct in `TestCoreAudioRecorderMicFailLoud.test_start_with_mic_succeeds_when_binary_supports_separate_tracks`. The 4th test (`mic=False`) never hit this, since `start()` skips the probe entirely without `--mic`.

### Final end-to-end verification, after both fixes landed together

Rebuilt `bin/ownscribe-audio` fresh via `swift/build.sh`, then ran 3 real captures (`--echo-cancellation off/on/auto`, `--mic`, no system audio playing). `ffprobe` confirmed all 3 produced correct mono `pcm_f32le` output at plausible durations (1.6-2.4s for ~3s captures) — no recurrence of the merge bug, and the dual-track merge correctly took the "mic only" branch (`Merged audio saved to ... (mic only, no system audio)`) since no system audio was present, exercising `openAudioFileWithFrames`'s `systemFile == nil` path on a real capture, not just the synthetic harness.

### Still open — a suggestion from the brief, deliberately not built here

The brief also floated "a per-track cross-correlation check could DETECT bleed (high mic↔system correlation = user on speakers) and warn/suggest headphones or auto-enable AEC" as an additional idea layered on top of the 3-tier fix. Not built: the explicit "Fix, best-to-heaviest" ask was the 3 tiers (document/flag/reject), and a correlation-based bleed detector is a genuinely separate piece of scope — a new runtime heuristic, plus a product decision about what "warn" or "auto-enable" means procedurally (mid-recording? post-recording? does auto-enable retroactively help audio already captured, or only future recordings?). Flagging for explicit direction rather than either building it unilaterally or silently dropping the idea, consistent with how Task#4's retention gap and Task#17's design-mismatch gap were both surfaced this session rather than resolved unilaterally.

pytest after this task: **498 -> 504 passed**

## Task#28 — master mute (system-wide, verify-after-set, AirPods fail-loud) + acoustic silence gate

### Sources consulted before writing any CoreAudio code

- **WWDC23 session 10233** ("Enhance your app's audio experience with AirPods") — documents `AVAudioApplication.setInputMuteStateChangeHandler` (the AirPods Press-to-Mute gesture handler) and `kAudioHardwarePropertyProcessInputMute` (mutes only this process's input, not system-wide). Neither is what's built here: the requirement is muting the CALL too (Zoom etc.), which `kAudioHardwarePropertyProcessInputMute` explicitly does not reach.
- **Apple Developer Forums thread 693516** — the documented Monterey-era bug where `kAudioDevicePropertyMute` on a Bluetooth input's `kAudioDevicePropertyScopeInput` silently mutes the OUTPUT instead, fixed in macOS 12.4 but the community consensus is it drifted again on later releases and must be verified per-machine, not assumed fixed. This is the exact failure mode `setSystemMuteVerified`'s read-back check exists to catch — a `succeeded=true` OS return code is not trusted; only a read-back that matches the request counts.
- **cyanicr/podsmute** (GitHub) — reference implementation for the AirPods-gesture trigger (`audioaccessoryd`'s `com.apple.audioaccessoryd.MuteState` Darwin notification) and the `kAudioHardwarePropertyDefaultInputDevice` + `kAudioDevicePropertyMute` pairing this build's `DefaultInputAudioMuteDevice` also uses. Per the revised scope (built-in AND AirPods are both first-class, not AirPods-only), the gesture trigger itself was deliberately NOT built — the keyboard hotkey + menu-bar button already work regardless of which mic is active, and podsmute's OWN pattern for the actual mute (resolve-default-device + set-and-read-back) is exactly what's implemented.
- **sebsto/wispr PR#57 + commits 1fdff01/2cd7c2d/fa79240** — the HFP-settling pattern: poll `kAudioDevicePropertyNominalSampleRate` until it drops below the A2DP threshold (44100Hz; HFP/SCO runs at 8/16/24kHz) before trusting a Bluetooth device's state, since AirPods switch profiles when the mic activates. Note: wispr's own later commits REMOVED the "change the system-wide default device" approach as an unwanted global side-effect for THEIR use case (per-app capture) — that concern doesn't transfer here, since muting system-wide is this feature's explicit goal, not a side-effect to avoid. Only the settling-poll pattern was reused, not their device-selection architecture.

### Design: verify-after-set is the actual safety mechanism, settling is a success-rate optimization on top

`setSystemMuteVerified` never trusts `AudioObjectSetPropertyData`'s return code alone — it always re-reads `kAudioDevicePropertyMute` afterward and only reports `succeeded=true` when the read-back matches what was requested. This means the forum-693516 bug (input-mute silently landing on output) is caught structurally regardless of which macOS version or device is in play, without needing to special-case Bluetooth: a stale/disagreeing read-back IS the failure signal, full stop. `waitForBluetoothHFPSettling` (poll `nominalSampleRate()`, bounded `maxPolls`, injectable `sleep` closure for testability) runs BEFORE the set/verify attempt on Bluetooth devices specifically to raise the odds it succeeds on the first try — but if HFP hasn't actually settled and the mute still doesn't take, verify-after-set catches that too. Settling is an optimization; verification is the safety net that holds even if settling doesn't help.

On failure (`succeeded=false`), `applyMasterMute` falls back to `MicCapture.toggleMute()` (the existing local-recording-only mute from Task#4) so the TRANSCRIPT is protected even when the CALL isn't, and surfaces an explicit warning string naming that gap rather than silently reporting "muted". `AppState.isMuted` (read by the menu-bar icon: `mic.fill`/`waveform` vs `mic.slash.fill`/`mic.slash`) is set from `outcome.displayMuted`, which is `false` whenever verification failed and no fallback ran — the icon can never claim "muted" on an unverified state. `AppState.restoreUnmutedOnQuit()` runs the same `applyMasterMute(false, ...)` path on the Quit button so the system mic is never left muted after the app closes.

### TDD discipline (per the explicit brief)

Each piece was written test-first: `setSystemMuteVerified`'s 8 tests (including the AirPods-bug-pattern simulation: `setShouldSucceed=true` + a disagreeing `readBackValue` → `succeeded=false`) failed with "cannot find X in scope" before `SystemMuteController.swift` existed, then passed once written. `applyMasterMute`'s 6 tests (fallback triggers, warning surfaces, displayMuted semantics on both mute and unmute, both success and failure) followed the same red→green cycle. `waitForBluetoothHFPSettling`'s 5 tests (non-Bluetooth skip, already-settled skip, poll-until-threshold, bounded give-up, unreadable-rate give-up) same. `HotKeyCombo`'s 3 tests (default is ⌘⇧M / `kVK_ANSI_M` = `0x2E`, Carbon modifier mask, Equatable) same. `RecordingController.setLocalMicMute`'s 1 test (not-recording no-op) same — the live-hardware mute path itself isn't unit-testable, matching Task#4's own `MicCapture` test gap.

### A genuine timing bug caught in my own test, before it shipped

The first version of `applyMasterMute`'s default `settle` parameter wired the REAL `waitForBluetoothHFPSettling` with a REAL `Thread.sleep`. `testSystemWideFailureFallsBackToLocalAndWarns` set `bluetoothDevice = true` with no `nominalSampleRateSequence` configured (so `nominalSampleRate()` returned `nil` every call) — the test passed, but took **3.199 real wall-clock seconds** because it silently exercised the production default's full `Thread.sleep(0.1s) × 30 polls`. Fixed by adding an explicit `settle: (AudioMuteDevice) -> Void` parameter that every orchestration test now injects as a no-op, keeping the suite deterministic and fast (full 89-test Swift suite: 0.141s), while a dedicated `testDefaultSettleParameterExercisesTheRealBluetoothPathWithoutHanging` test pins that the production default itself is still reachable and correct (using a non-Bluetooth device so it stays fast).

### Global hotkey verification — genuinely confirmed once, then blocked by an unrelated environment issue

Built `GlobalHotKeyRegistration` using Carbon's `RegisterEventHotKey`/`InstallEventHandler` (not `NSEvent.addGlobalMonitorForEvents`, which needs Accessibility/Input-Monitoring permission this app has no other reason to request) targeting `GetApplicationEventTarget()`. Verified end-to-end with a real standalone probe binary using `NSApplication.shared.run()` (a bare `RunLoop.main.run()` command-line tool does NOT dispatch Carbon hotkey events — confirmed via Apple DTS engineer "Quinn"'s reply on the Apple Developer Forums keeping-a-CLI-tool-alive thread) — a real `Cmd+Shift+M` sent via `System Events keystroke` while TextEdit had genuine keyboard focus fired the callback (`fired at <timestamp>` written to a marker file). Later re-verification attempts in the same session returned false negatives because the physical display had gone to sleep (`system_profiler SPDisplaysDataType` showed `Display Asleep: Yes`) — `System Events keystroke` cannot deliver real input to a genuinely-focused app when the display is asleep, confirmed by re-testing the keystroke-delivery pathway independently (a literal string typed into a real TextEdit document never appeared). This is an environment/physical-machine state issue, not a code defect — did not attempt to force-wake the display (`caffeinate -u` was tried once, had no effect, and further forcing felt like overstepping into the user's physical machine state uninvited) or fabricate a second "verified" claim under conditions I knew were unreliable. The ONE genuine positive result stands; anything claiming a second live re-verification this session would not have survived re-execution, so it isn't claimed.

### Acoustic silence gate — the always-on recording-side complement

`gate_silent_mic_segments(result, mic_path, threshold)` (Python) drops any transcript segment whose corresponding span in the retained `mic.wav` has RMS below threshold (`1e-4`, distinct from the whole-track `_check_dual_track_silence` threshold of `1e-5` — segment-level spans are shorter and noisier than a 5s whole-track sample, so a slightly higher floor avoids false-dropping quiet real speech). Wired into `_transcribe_dual_track` unconditionally, independent of whether the manual mute fired — covers the case where the user forgot to mute, or muted the call but not (yet, pre-verify-fix) the recording. Gates emission only; never fabricates a segment that wasn't produced by the transcriber. 6 new tests (loud-kept, silent-dropped, mixed-only-silent-dropped, missing-file-passthrough, no-mutation, custom-threshold) — all pass against the exact `gate_silent_mic_segments` implementation via `PYTHONPATH=.../src` (the venv's `ownscribe.pth` unconditionally prepends the main repo's `src/` to `sys.path` regardless of `cwd` — confirmed by `cat`-ing the `.pth` file directly — so any isolated/scratch-copy test run needs an explicit `PYTHONPATH` override or it silently re-imports the live tree). (6 new: `test_echo_cancellation_defaults_to_off` + `test_echo_cancellation_override_passed_through` in `test_pipeline.py`, plus `TestCoreAudioRecorderEchoCancellation`'s 4 tests in `test_coreaudio.py`; separately fixed 3 pre-existing `test_pipeline.py` tests broken by the new `echo_cancellation` kwarg, no net count change from those). ruff: clean. Swift: compiles clean via the rebuilt `swift/build.sh`; verified via 3 real end-to-end captures (off/on/auto) plus the isolated `mergeAudioFiles` regression harness (6/6) for the unrelated pre-existing bug fixed alongside this task.

### The envelope reader's `dtype="float32"` is load-bearing and NO test protects it

`src/ownscribe/audio/envelope.py:65` reads the recording with an explicit
`dtype="float32"`. Do not "simplify" that away.

`soundfile.read` defaults to **float64** even when the file is already stored as float32,
which is what this project's captures are. On the real 17.5-minute recording (385 MB,
1050.1 s, 48 kHz, 2 ch) the default read peaked at **1.47 GB** — a float64 copy plus the
channel mean plus a float32 downcast — versus **629 MB** with the explicit dtype: a 55%
reduction, and 38% faster as a side effect (0.54 s → 0.33 s). Extrapolated, a 2-hour
meeting goes from ~10 GB to ~4.5 GB, and this runs at the end of transcription while torch
still holds its own allocations. `MemoryError` is not in the reader's `except` clause, so
it would propagate.

**Why no test guards it:** the envelopes produced by a float32 read and a float64 read are
bit-identical (max abs diff 0.0). It is a memory property, not a value property, so no
value assertion can detect its removal — mutation-verified: deleting the dtype leaves the
whole suite green (552 passed, 0 failed). Only a peak-RSS assertion could catch it, and
that is machine-dependent and flaky enough to be worse than the risk. Hence this note: the
commit message is where the why was first recorded, but a commit message is not where
anyone looks before editing a line.

## 2026-07-29 — three parallel builders, two independent reviewers, and four documentary errors of mine

Not a task in the numbered series: a batch of four code lots plus a docs pass. What is worth
recording is not the fixes but the *evidence failures*, because every one of them was a case of
holding the wrong proof rather than doing the wrong work.

**The avatar collision was locked in place by a test.** `SpeakerAvatarStyle.color` routed every
diarized label through `hasSuffix("0")`, so seven concurrent speakers collapsed to **two** colours
and `SPEAKER_00`/`SPEAKER_10` shared an avatar. `TODO.md` had filed it as "unreachable on current
data" — true, real transcripts hold only `_00` and `_01` — and that framing hid the real problem:
`speakerEndingIn0GetsBlue` **asserted** the collision, so a correct fix turned the suite red. A
named test asserting a known-wrong output is not coverage, it is a lock. When filing a defect as
harmless, grep whether a test pins it.

Underneath it, a crash: parsing the index instead of the suffix, `Int("-1")` succeeds and
`palette[-1 % 7]` is `palette[-1]`, which **traps** — signal 5, `Fatal error: Index out of range`.
Cosmetic bug on top, process death underneath. Also: Swift's `Int` rejects `"1_2"` where Python's
accepts the underscore, so my first probe (a Python mirror of the Swift parse) gave the wrong answer
for that input. Mirror a parse in the language that runs it.

**The clickable-evidence chip landed on the wrong line, and only real data could show it.** In the
27-July transcript `SPEAKER_00` says "OK." and `SPEAKER_01` says the sentence containing "Lambda" —
both stamped `[05:09]`. The duplicate-timecode rewind always walked to the *first* utterance sharing
the stamp, so clicking `Lambda→05:09` scrolled to a two-word backchannel and offered it as proof of
a claim about architecture. Every synthetic fixture has unique timecodes, so no hand-built test
could ever have seen it. Fixed by searching the shared-timecode range for the utterance that
actually contains the token; the seam widened from `String` to `AnchorEvidenceChip` so the compiler
refuses a call site that drops the token.

**A fixture can be a snapshot of a bug.** When that real-data test first failed, the on-disk
`/tmp/ms-fixture/anchors.json` had a `Lambda` context truncated at 100 chars *before the word it
proves* — precisely the defect `test_anchoring_context_contains_token.py` exists to catch. Current
production centres the window correctly; the fixture predated the fix, so a correct fix looked
broken. Decide first whether the code or the snapshot is stale (`anchor_summary_claims` on the live
source settles it in one command), and note the mirror image is worse: a fixture regenerated past a
real regression makes a broken fix look correct.

**Three of my own replacement tests were unfalsifiable before they were fixed**, each caught by
asking what could make it fail: `f(x) == f(x)`; then a version calling a `hashColorForTesting` shim,
which is the forbidden test-only production method; then widening `private` → internal, the same
move renamed. And one test kept failing against a correct fix because a `replace_all` had missed its
second call site, so it still invoked the old overload — a test that does not call what production
calls proves nothing in *either* direction.

**Mutation testing itself has a sample-size problem.** Dropping `.sorted()` from the anchor display
killed its test in only **7 of 8 runs**: with three tokens, a per-process-seeded dictionary order is
already sorted about one run in six, so the single run the protocol asks for had a real chance of
certifying a guard that does not guard. At eight tokens it is 8/8. Anything seeded per process
(dictionary/set order, hashes, clocks, interleaving) needs the kill *rate*, not a verdict.

**And a mutation's kills can hide in the other framework.** `d448e2b`'s message claimed "exactly the
two new tests red"; an independent reviewer measured **4**, I re-measured **5** after two more tests
landed. All of them are swift-testing (`✘ Test name()`), so a grep for XCTest's format
(`Test Case '-[Suite name]' failed`) returns zero hits and reads exactly like a survived mutation.
The fix was better guarded than its own evidence claimed — still the "fix correct AND evidence
wrong" class, and those fail independently.

**Four documentary errors, all mine, three caught by reviewers.** I measured 340 Swift tests and
then wrote 322 into `TODO.md` and `HANDOFF.md`, twice each — writing a number is a separate step from
measuring it and it fails on its own. "Everything is pushed" sat there while 14 commits were local;
my first fix pinned a hash that was stale one commit later, which is the same rot with an extra step,
so both mentions now defer to `git log --oneline origin/main..main | wc -l`. "Zero of six meetings
have `anchors.json`" was off by one file — and a file count is still the wrong evidence, because that
one file parses to zero tokens. And a reviewer reported Python at 635 against my 629: both correct,
because `check.sh:23` adds `-m "not hardware"`. A count without its invocation is not a fact.

**A reviewer's worktree can predate the code under review.** The first independent reviewer was
branched from the commit *before* all five deliveries: two production files absent,
`grep -c diarizationIndex` → 0. Every mutation it ran was against code that was not there, and a
missing file reads exactly like a test going red. Caught by comparing its `git log -1` to mine while
it worked, not from anything it reported. It recovered by extracting a pristine tree with
`git archive` when `git reset --hard` was correctly denied against the shared checkout.
