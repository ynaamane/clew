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
