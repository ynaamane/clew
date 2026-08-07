# Clew

[![CI](https://github.com/ynaamane/clew/actions/workflows/ci.yml/badge.svg)](https://github.com/ynaamane/clew/actions/workflows/ci.yml)
[![License: PolyForm Noncommercial](https://img.shields.io/badge/license-PolyForm%20Noncommercial-orange.svg)](LICENSE.md)
[![Python 3.12+](https://img.shields.io/badge/python-3.12+-blue.svg)](https://www.python.org/downloads/)

*Clew is the thread through every meeting you attended. Pull it, and see what connects.*

Local-first meeting transcription and summarization CLI.
Record, transcribe, and summarize meetings and system audio entirely on your machine: no cloud, no bots, no data leaving your device.

> System audio capture requires **macOS 14.2 or later**. Other platforms can use the sounddevice backend with an external audio source.

## Table of Contents

- [Privacy](#privacy)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [The macOS app](#the-macos-app)
- [Configuration](#configuration)
- [Audio Retention](#audio-retention)
- [Summarization Templates](#summarization-templates)
- [Speaker Diarization](#speaker-diarization)
- [Headphones vs Speakers (Owner Track Purity)](#headphones-vs-speakers-owner-track-purity)
- [What I Inherited vs What I Built](#what-i-inherited-vs-what-i-built)
- [Legal and privacy notice](#legal-and-privacy-notice)
- [Acknowledgments](#acknowledgments)
- [Contributing](#contributing)
- [License](#license)

## Privacy

Clew **does not**:

- send audio to external servers
- upload transcripts
- require cloud APIs
- store data outside your machine

All audio, transcripts, and summaries remain local.

<p align="center">
  <img src="docs/demo-pipeline.gif" alt="Clew demo" width="750">
</p>

## Features

- **System audio capture**: records all system audio natively via a CoreAudio process tap (macOS 14.2+), no virtual audio drivers needed, no Screen Recording permission required
- **Microphone capture**: optionally record system + mic audio simultaneously with `--mic`
- **WhisperX transcription**: fast, accurate speech-to-text with word-level timestamps
- **Speaker diarization**: optional speaker identification via pyannote (requires HuggingFace token)
- **Pipeline progress**: live checklist showing transcription, diarization sub-steps, and summarization progress
- **Local LLM summarization**: structured meeting notes with a built-in model (Phi-4-mini); also supports Ollama, LM Studio, or any OpenAI-compatible server
- **Summarization templates**: built-in presets for meetings, lectures, and quick briefs; define your own in config
- **Ask your meetings**: ask natural-language questions across all your meeting notes; uses a two-stage LLM pipeline with keyword fallback
  <br><img src="docs/demo-ask.gif" alt="Clew ask demo" width="700">
- **Silence auto-stop**: automatically stops recording after sustained silence (default: 5 minutes, configurable)
- **One command**: just run `clew`, press Ctrl+C when done, get transcript + summary

## Requirements

- macOS 14.2+ (for system audio capture)
- Python 3.12+
- [uv](https://docs.astral.sh/uv/)
- [ffmpeg](https://ffmpeg.org/): `brew install ffmpeg`
- Xcode Command Line Tools (`xcode-select --install`)

Summarization works out of the box: a local model (Phi-4-mini, ~2.4 GB) downloads automatically on first run. Optionally, you can use [Ollama](https://ollama.ai), [LM Studio](https://lmstudio.ai), or any OpenAI-compatible server instead (see [Configuration](#configuration)).

Works with any app that outputs audio through Core Audio (Zoom, Teams, Meet, etc.).

> **Tip:** The first time Clew records system audio, macOS prompts for **System Audio Recording** permission, a narrower grant than Screen Recording; it only lets Clew hear other apps' audio, not see your screen. If you use `--mic`, macOS also prompts for **Microphone** permission. Open either settings panel directly with:
>
> ```bash
> open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
> open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
> ```
>
> Enable your terminal app under "System Audio Recording Only", then restart it.
>
> Clew checks Microphone access **before** starting a recording (when `--mic` is set) and exits with the exact fix if it's missing. System Audio Recording is a private macOS permission with no public preflight API, so it's requested naturally on first capture instead. If denied, Clew reports it immediately rather than silently recording silence. With `--mic`, the system audio and mic tracks are retained separately; a post-recording RMS check on each tells you specifically which track is silent, instead of one ambiguous "audio is silent" warning.
>
> On macOS versions before 14.2, or if you pass `[audio] capture_backend = "screencapturekit"` in config, Clew falls back to ScreenCaptureKit, which does require the Screen Recording permission instead.

## Installation

This fork is not published to PyPI (the name `clew` is squatted by an unrelated
dead package; reclaiming it via PEP 541 is a future step, see
[PUBLICATION_CHECKLIST.md](PUBLICATION_CHECKLIST.md)). Every command below installs
straight from the `ynaamane/clew` repository.

### Quick start with uvx

```bash
uvx --from git+https://github.com/ynaamane/clew clew
```

On macOS, the Swift audio capture helper is downloaded automatically on first run.

### Alternative summarization backends

The built-in local model works out of the box. If you'd rather call a hosted backend,
install the matching extra as a tool:

```bash
uv tool install "clew[ollama] @ git+https://github.com/ynaamane/clew"   # use Ollama
uv tool install "clew[openai] @ git+https://github.com/ynaamane/clew"   # use any OpenAI-compatible server (LM Studio, llama-server, etc.)
uv tool install "clew[all] @ git+https://github.com/ynaamane/clew"      # install both
```

### Homebrew

There is no brew formula: Homebrew builds Python dependencies from source, which doesn't work well for the PyTorch and llama-cpp-python stack. The closest thing is installing [uv](https://docs.astral.sh/uv/) via brew and letting it manage a global `clew` command:

```bash
brew install uv
uv tool install "clew[all] @ git+https://github.com/ynaamane/clew"
```

### From source

```bash
# Clone the repo
git clone https://github.com/ynaamane/clew.git
cd clew

# Build the Swift audio capture helper (optional - auto-downloads if skipped)
bash swift/build.sh

# Install with all backends
uv sync --extra all

# Make the `clew` command available globally (editable: changes to the
# checkout take effect without reinstalling)
uv tool install --editable .
```

When installed from source, the `clew` command lives inside the project's
virtual environment, so run it with `uv run` from the repo directory:

```bash
uv run clew          # equivalent to the bare `clew` used below
```

Alternatively, activate the environment once (`source .venv/bin/activate`) and
then call `clew` directly. The examples in [Usage](#usage) use the bare
`clew` form, which works after activation, after `uv tool install`, or via
`uvx --from git+https://github.com/ynaamane/clew clew`.

## Usage

### Record, transcribe, and summarize a meeting

```bash
clew                    # records system audio, Ctrl+C to stop
```

This will:

1. Capture system audio until you press Ctrl+C (or auto-stop after 5 minutes of silence)
2. Transcribe with WhisperX
3. Summarize with your local LLM
4. Save everything to `~/clew/YYYY-MM-DD_HHMMSS/`

> **Note:** By default, Clew records all system audio directly with no picker: every app's output (Zoom, WhatsApp, browser tabs, etc.) is captured at once. To show a source picker on each launch instead, set `capture_mode = "picker"` in the `[audio]` config section.

On first run, WhisperX / pyannote and the summarization model may download model files. Clew shows a `Preparing models` step and best-effort download progress in the TUI while this happens. Use `clew warmup` to pre-download all models.

### Options

```bash
clew --mic                               # capture system audio + default mic (press 'm' to mute/unmute)
clew --mic-device "MacBook Pro Microphone" # capture system audio + specific mic
clew --device "MacBook Pro Microphone"   # use mic instead of system audio
clew --no-summarize                      # skip LLM summarization
clew --diarize                           # enable speaker identification
clew --language en                       # set transcription language (default: auto-detect)
clew --model large-v3                    # use a larger Whisper model
clew --format json                       # output as JSON instead of markdown
clew --no-keep-recording                 # auto-delete WAV files after transcription
clew --template lecture                  # use the lecture summarization template
clew --silence-timeout 600               # auto-stop after 10 minutes of silence
clew --silence-timeout 0                 # disable silence auto-stop
```

### Subcommands

```bash
clew devices                  # list audio devices (uses native CoreAudio when available)
clew apps                     # list running apps with PIDs for use with --pid
clew watch                    # wait for a meeting to start, then record it automatically
clew warmup                   # prefetch WhisperX/pyannote models before a meeting
clew transcribe recording.wav # transcribe an audio or video file: wav/mp3/mp4/mov/mkv (saved alongside)
clew summarize transcript.md  # summarize a transcript (saves alongside the input)
clew resume ./2026-02-20_1736 # resume a partial run, or process a folder's audio/video recording
clew reprocess ./2026-02-20_1736 # force a full re-transcribe+summarize, even if output already exists
clew backfill ./2026-02-20_1736 # add missing envelope.json/anchors.json without re-running ASR or the LLM
clew backfill                 # same, scanning every meeting directory
clew purge --older-than 30    # delete retained audio older than N days
clew purge --all              # delete all retained audio regardless of age
clew purge --dry-run          # preview what a purge would remove, without deleting
clew ask "question"           # search your meetings with a natural-language question
clew enroll --name "Alice" clip.wav # enroll a speaker's voiceprint from a short reference clip
clew unenroll "Alice"         # remove an enrolled speaker's voiceprint
clew speakers                 # list all enrolled speaker names
clew config                   # open config file in $EDITOR
clew cleanup                  # remove clew data from disk
```

### Auto-Detecting a Meeting

Instead of manually starting `clew`, run `clew watch` ahead of time: it polls whether BOTH the default input device (mic) and the default output device (speakers/headphones) are active at the same time (a permission-free, OS-level signal on both sides, since it only reads a hardware property and never opens an actual audio stream), and once that combined state holds continuously for a few seconds it starts recording automatically. Mic activity alone (dictation, a voice memo) does not trigger it, and output activity alone (music, a video) does not either: only mic AND output together, the pattern a live call produces.

```bash
clew watch                          # default: 3s of sustained mic+output activity before recording starts
clew watch --sustained-seconds 5    # require a longer sustained window (fewer false starts)
```

This works identically regardless of which app produces the audio: Zoom, WhatsApp, or a Meet/Teams/Discord tab in a browser all show up the same way at the OS device level, so there's no per-app integration or bundle-identifier polling to maintain. A brief notification sound does not trigger it; only activity that stays sustained on both devices for the full `--sustained-seconds` window does. Once triggered, `watch` hands off to the normal recording pipeline: everything else (capture mode, diarization, correction, output format) is controlled by your regular config.

> **Known limitation**: `clew`'s own `--mic` capture (via `AVAudioEngine`) makes the OS report the output device as "running" even while producing silence, an artifact of `AVAudioEngine`'s internal render graph, not of anything actually playing. This does not affect `watch` today, since `watch-activity` always exits before a recording starts (they never run concurrently), but it means the mic+output signal is not safe to reuse while `clew`'s own mic capture is active.

> **Video files work too.** Anywhere Clew accepts an audio file it also accepts a video container (mp4, mov, mkv, m4v). It extracts the audio track via ffmpeg. To turn a recording into full notes, drop it in a folder and run `clew resume ./that-folder/` (transcript + summary); use `clew transcribe meeting.mp4` for a transcript only.

Use `warmup` ahead of time to avoid first-run model download delays while recording:

```bash
clew warmup                    # prefetch Whisper model (+ diarization if enabled in config)
clew warmup --language en      # also prefetch alignment model for English
clew warmup --with-diarization # force diarization warmup for this run
```

### Searching Meeting Notes

Use `ask` to search across all your meeting notes with natural-language questions:

```bash
clew ask "What did Anna say about the deadline?"
clew ask "budget decisions" --since 2026-01-01
clew ask "action items from last week" --limit 5
```

This runs a two-stage pipeline:

1. **Find**: sends meeting summaries to the LLM to identify which meetings are relevant
2. **Answer**: sends the full transcripts of relevant meetings to the LLM to produce an answer with quotes

If the LLM finds no relevant meetings, a keyword fallback searches summaries and transcripts directly.

## The macOS app

Everything above is the CLI. There is also a menu-bar app (`swift/Sources/OwnscribeMenuBar`) that
drives the same pipeline: it shells out to this repo's `clew`, so the CLI is the engine and the
app is a front end, not a reimplementation.

```bash
bash swift/build-app.sh                  # build, sign AND install to /Applications
SKIP_INSTALL=1 bash swift/build-app.sh   # stop at dist/ without installing
open /Applications/Clew.app              # always launch the INSTALLED copy
```

`build-app.sh` installs on purpose and fails if the installed binary differs from the one just
built: a real call was once recorded against a stale bundle because building and installing were
separate steps.

What the app adds over the CLI:

- **A three-column library window**: filters, meeting list, transcript with an inspector.
  Meetings come from `~/clew/` (or `[output] dir` in the config). Open it three ways: ⌘0,
  the app menu, or `open "clew://library"`. The URL route exists because until 2026-07-30 the
  window could only be reached by clicking the menu bar extra, and SwiftUI's `MenuBarExtra(.window)`
  popover exposes nothing to accessibility: a keyboard-only user was locked out, and so was any
  automated visual check.
- **A search field** over the library, composing with the sidebar filter (typing inside "Avec
  actions" narrows that filter rather than replacing it), and a two-line summary excerpt per row so
  the list says what a meeting was about.
- **A record button and a global hotkey** (⌘⇧M) for the system-wide mic mute. The mute is verified
  by reading the device back, and the menu bar shows three distinct states: not muted, muted and
  verified, muted but **unverified** in amber, because a hardware-refused mute once displayed as
  successful, meaning the app said "muted" while the call could still hear you.
- **Claim anchoring in the inspector.** Each summary key point shows the timestamps where its rare
  tokens appear in the transcript, and clicking one scrolls to that utterance. Three states are kept
  deliberately distinct: `(pas encore vérifié)` means no `anchors.json` exists, an em dash means anchoring
  ran and found nothing, and a chip means real evidence. Absence must never render as a confident
  zero.
- **An RMS envelope strip**, so an abnormal silence is visible without opening a 400 MB wav.
- **Settings**: the HuggingFace token (stored in the login Keychain), plus mic on/off and the
  silence timeout. Everything else still lives in the TOML. The app reads the config once at
  launch, so changing these needs a restart.

Two caveats worth knowing before you build:

- The app requires **macOS 26+** (`swift/Package.swift`), because the design targets the current
  visual language. The CLI has no such requirement.
- macOS ties permission grants to the signing identity, so **never delete or recreate the signing
  cert**, a new cert is a new identity and every System Audio Recording / Microphone grant resets.
  See `BUILD.md`.

### Looking at the window without a mouse

Two paths, and the second is the one that keeps working:

```bash
open "clew://library"                                          # then, app frontmost, screen unlocked:
bash scripts/ui-evidence/capture.sh Clew /tmp/ui-ev            # window-scoped PNG + AX tree

bash scripts/ui-evidence/render.sh /tmp/ui-render               # off-screen; works with the screen LOCKED
```

`capture.sh` resolves the window id **by owner** and passes it to `screencapture -l`, so it cannot
capture the screen, but it fails on a locked screen and on a window that is not frontmost.
`render.sh` hosts the real `LibraryWindow` in an off-screen `NSWindow` and reads its pixels, in both
light and dark appearances.

**Read its CANNOT-VERIFY output before trusting a render.** It answers layout, type scale, text and
appearance; it is blind to Liquid Glass (glass, no-glass and glass-on-container render
byte-identically) and to the selected row, which comes out opaque black over its own label and badge.
Anything about materials still needs a human looking at a real screen. `APP_TEST.md` has the details.

## Configuration

Config is stored at `~/.config/clew/config.toml`. Run `clew config` to create and edit it.

```toml
[audio]
backend = "coreaudio"     # "coreaudio" (native macOS helper) or "sounddevice" (cross-platform)
device = ""               # empty = system audio
mic = false               # also capture microphone input
mic_device = ""           # specific mic device name (empty = default)
echo_cancellation = "off"
capture_mode = "all"      # "all" = capture all system audio directly (default); "picker" = show source picker
capture_backend = "coreaudio"  # the native helper's own mechanism: "coreaudio" (tap, macOS 14.2+) or "screencapturekit"
silence_timeout = 300     # seconds of silence before auto-stop; 0 = disabled

[transcription]
model = "large-v3"        # tiny, base, small, medium, large-v3
language = ""             # empty = auto-detect (locked per-file from the first ~30s, not per-segment)
initial_prompt = "..."    # defaults to a bilingual FR/EN sentence to prime code-switching; override freely
# hotwords = ""           # comma-separated words to boost recognition (softer hint than initial_prompt)
# cpu_threads = 0         # CTranslate2 threads; 0 = auto-detect (performance core count), or explicit positive int
engine = "whisperx"       # "whisperx" (default) or "canary_mlx" (A/B pilot, see below)

[canary]
repo = "CogniSoftOrg/canary-1b-v2-mlx-bf16"  # HF repo of the MLX-native Canary-1B-v2 checkpoint
max_segment_seconds = 10.0  # VAD-segment audio into chunks no longer than this before each pass
max_tokens_per_segment = 200

[diarization]
enabled = false
hf_token = ""             # HuggingFace token for pyannote
telemetry = false         # allow HuggingFace Hub + pyannote metrics telemetry

[summarization]
enabled = true
backend = "local"         # "local" (built-in, no server needed), "ollama", or "openai"
model = "phi-4-mini"      # local: "phi-4-mini", path to GGUF, or hf:owner/repo/file.gguf; ollama/openai: model name
# host = "http://localhost:11434"  # only for ollama/openai backends
# api_key = ""            # only for openai backend; required by servers like oMLX (or set OPENAI_API_KEY)
# template = "meeting"    # "meeting", "lecture", "brief", or a custom name
# context_size = 0        # 0 = auto-detect from model; set manually for OpenAI-compatible backends

# Custom templates (optional):
# [templates.my-standup]
# system_prompt = "You summarize daily standups."
# prompt = "List each person's update:\n{transcript}"

[output]
dir = "~/clew"
audio_dir = ""            # directory for audio recordings; empty = same as dir
format = "markdown"       # "markdown" or "json"
keep_recording = true     # false = auto-delete WAV after transcription
retention_days = 0        # days before `clew purge` may remove audio; 0 = keep forever (manual purge only)
```

**Precedence:** CLI flags > environment variables (`HF_TOKEN`, `OLLAMA_HOST`, `OPENAI_API_KEY`, `CLEW_PROGRESS`) > config file > defaults. `OWNSCRIBE_PROGRESS` still works as a legacy alias for `CLEW_PROGRESS`.

### Migrating from ownscribe / MeetingScribe

If you're upgrading from a pre-rename install, Clew moves your existing config, voiceprints, and
default output directory to their new locations automatically, once, the first time you run it:
`~/.config/ownscribe` to `~/.config/clew`, `~/.config/meeting-scribe/voiceprints` to
`~/.config/clew/voiceprints`, and `~/ownscribe` to `~/clew` (only if you never pointed `[output] dir`
somewhere else). Nothing is deleted, only moved, and only when the new location doesn't already
exist.

## Audio Retention

By default (`keep_recording = true`), every recording's WAV files (system, mic, and any sidecar files) stay on disk next to the transcript and summary. This is what makes `resume` and `reprocess` possible: both need the original audio.

There are three ways to control how long retained audio sticks around:

- **Keep forever (default)**: `retention_days = 0` and never run `purge`. Nothing is ever deleted automatically.
- **Auto-delete after each meeting**: `keep_recording = false` deletes the WAV files immediately after transcription (no retention at all, so `reprocess` won't work on that meeting later).
- **Keep for N days, then purge manually**: set `retention_days` in config, and periodically run `clew purge` to remove anything older than that. This is _not_ a background job; retention only happens when you invoke `purge`.

```bash
clew purge                    # purge using retention_days from config (no-op if retention_days = 0)
clew purge --older-than 14    # override config: purge anything older than 14 days
clew purge --all              # purge every retained recording, regardless of age
clew purge --dry-run          # preview what would be purged, without deleting anything
```

`purge` only ever removes retained audio (WAV files and sidecars): transcripts and summaries are never touched, so past notes remain readable even after their source audio is gone.

### Reprocessing a Meeting

If a transcript or summary came out wrong (a bad model choice, a config change, a summarization backend swap), `reprocess` redoes the whole pipeline from the retained audio, overwriting the existing transcript and summary:

```bash
clew reprocess ./2026-02-20_1736
clew reprocess ./2026-02-20_1736 --model large-v3 --template lecture
```

Unlike `resume` (which skips work that's already done), `reprocess` always starts over from the audio: it errors out if no retained audio is found for that meeting (i.e. `keep_recording` was `false` when it was recorded, or it's already been purged).

### Backfilling Older Meetings

Meetings recorded before `envelope.json` (the waveform strip) or `anchors.json` (clickable evidence for summary claims) existed have a transcript and summary but neither derived file. `backfill` adds whatever is missing, computed from what's already on disk:

```bash
clew backfill ./2026-02-20_1736   # backfill one meeting
clew backfill                     # scan every meeting directory, backfilling each that needs it
```

It never re-runs transcription or summarization, and it never rewrites or deletes an existing file: a meeting that already has both `envelope.json` and `anchors.json` is left untouched, and `envelope.json` is only added when retained audio is still present (no audio means no waveform, not a flat one). Running it again is always safe; it reports one line per directory and only ever adds files.

## Summarization Templates

Built-in templates control how transcripts are summarized:

| Template  | Best for                  | Output style                                 |
| --------- | ------------------------- | -------------------------------------------- |
| `meeting` | Meetings, standups, 1:1s  | Summary, Key Points, Action Items, Decisions |
| `lecture` | Lectures, seminars, talks | Summary, Key Concepts, Key Takeaways         |
| `brief`   | Quick overviews           | 3-5 bullet points                            |

Use `--template` on the CLI or set `template` in `[summarization]` config. Default is `meeting`.

Define custom templates in config:

```toml
[templates.my-standup]
system_prompt = "You summarize daily standups."
prompt = "List each person's update:\n{transcript}"
```

Then use with `--template my-standup` or `template = "my-standup"` in config.

## Speaker Diarization

Speaker identification requires a HuggingFace token with access to the pyannote diarization model:

1. Accept the terms for [pyannote/speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1) on HuggingFace
2. Create a token at https://huggingface.co/settings/tokens
3. Set `HF_TOKEN` env var or add `hf_token` to config
4. Run with `--diarize`

Diarization always runs on CPU. See `NOTES.md` for why the MPS path is disabled here rather than upstream's `device = "auto"` default.

Voiceprints created by enrollment (below) are biometric data with real legal weight: see
[Legal and privacy notice](#legal-and-privacy-notice) before enrolling anyone.

## Speaker Naming

Enroll a speaker's voice from a short reference clip (a few seconds of them speaking, isolated) to have their real name appear in transcripts instead of a generic `SPEAKER_00` label:

```bash
clew enroll --name "Alice" alice-sample.wav
```

This computes a voiceprint using the same embedding model diarization already loads (no extra download) and stores it in `~/.config/clew/voiceprints/voiceprints.json`. Enrollment requires the same HuggingFace token as diarization (§ Speaker Diarization above).

During a meeting, every diarized speaker cluster is compared against enrolled voiceprints by cosine similarity. A match above the threshold (default `0.65`) gets the enrolled name; anything below gets `Unknown-1`, `Unknown-2`, etc., never a forced wrong match. If you record with `--mic` (or `capture_mode` retains separate tracks), your own segments are always labeled `Owner` directly from the microphone track and are never sent through diarization or matching, since you're a known speaker by construction.

```bash
clew speakers            # list all enrolled names
clew unenroll "Alice"    # remove an enrolled voiceprint
```

## Headphones vs Speakers (Owner Track Purity)

The mic track (`mic.wav`, labeled `Owner`) and the system track (`system.wav`, the remote call audio) are captured from two physically separate sources, and on **headphones** that separation is perfect: your microphone only ever picks up your own voice, with nothing from the call bleeding in.

On **Mac speakers**, the call audio plays out loud and the microphone can pick some of it back up (acoustic echo) before it ever reaches `clew`. That bleed lands in `mic.wav` alongside your own voice, which can pollute the `Owner` track with fragments of the remote speaker's audio.

**Recommended: wear headphones for meetings recorded with `--mic`.** It's free, requires no configuration, and gives the cleanest possible separation between what you said and what you heard. See `--mic` under [Usage](#usage) and `[audio] mic` under [Configuration](#configuration).

If headphones aren't an option, `[audio] echo_cancellation` can enable macOS's own native voice-processing echo canceller on the mic input:

```toml
[audio]
echo_cancellation = "off"   # "off" (default), "on", or "auto"
```

- `"off"`: never touches the mic input. The current default.
- `"on"`: always enables voice processing on the mic.
- `"auto"`: enables voice processing only when the current default output device is the Mac's built-in speakers (detected via CoreAudio's transport type, not by matching a device name), since that's the only case where mic-into-speaker acoustic echo actually happens. Headphones and external outputs are left untouched.

macOS's voice processing also ducks non-voice audio playing through the speakers relative to detected speech (correct behavior for suppressing acoustic echo), but it means the effect on your own voice specifically has not been validated against a real recorded meeting in this fork; test it against your own voice before relying on it for anything you need transcribed precisely.

## Transcript Correction

Meetings with French/English code-switching (speakers alternating languages mid-sentence) can trip up Whisper's spelling and word-boundary detection. An opt-in correction pass sends each transcript segment's text through your configured LLM backend, asking it to fix spelling and misheard words only, never to paraphrase, translate, add content, or touch timestamps/speakers.

```toml
[correction]
enabled = true
max_length_delta_ratio = 0.4  # reject a fix that changes segment length by more than this fraction
```

A correction is applied only if it passes the length-delta guard; anything further outside that ratio (a sign of an added or truncated response) is rejected and the original segment text is kept unchanged. Uses your existing `[summarization]` backend: no separate model or config needed. Runs after diarization/speaker naming and before summarization, using the same summarizer instance.

## Canary Transcription Engine (A/B Pilot)

`engine = "canary_mlx"` swaps the default WhisperX/faster-whisper pipeline for [NVIDIA Canary-1B-v2](https://huggingface.co/nvidia/canary-1b-v2) via [mlx-audio](https://github.com/Blaizzy/mlx-audio) (Apple Silicon native, MLX runtime). This is a pilot A/B engine, not the default: pick it explicitly to compare against WhisperX on your own recordings.

```toml
[transcription]
engine = "canary_mlx"

[canary]
repo = "CogniSoftOrg/canary-1b-v2-mlx-bf16"
max_segment_seconds = 10.0
max_tokens_per_segment = 200
```

Requires `uv` on PATH (already required to run Clew from source). `mlx-audio` is never installed into Clew's own environment: the engine spawns `uv run --with mlx-audio ...` per transcription, layering the dependency onto an ephemeral overlay so it never touches `pyproject.toml`, `uv.lock`, or your other transcription runs. The first invocation downloads the ~2GB checkpoint from HuggingFace (cached afterward). The first `uv run --with` invocation also resolves and downloads mlx-audio itself (cached in `~/.cache/uv` afterward, so only the very first Canary transcription pays this cost).

Known scope limits for this engine, compared to the WhisperX default:

- **Segment-level only, no word-level timestamps.** Canary's decoder has no forced-alignment step; every segment's `words` list is empty.
- **No self-diarization.** Speaker labeling for Canary transcripts is whatever your existing diarization/naming pipeline produces on a segment-overlap basis. Canary itself never diarizes.
- **One language per run.** No per-segment auto-detection; `[transcription] language` (or the CLI `--language` flag) sets both source and target language for the whole file, defaulting to French if unset.
- **VAD-segmented in ≤`max_segment_seconds` chunks** (via faster-whisper's bundled Silero VAD, already installed for WhisperX, no extra dependency) rather than one continuous pass, since Canary's positional encoding has no long-form chunking of its own.
- **Pilot result: WhisperX stays the default.** On a real code-switched FR/EN clip (see `pilot/`), Canary's WER on code-switch spans was consistently worse than WhisperX's across every `max_segment_seconds` tested (5s/10s/40s): the pre-committed pass bar (Canary must win switch-span WER by ≥3 points) was not met. `max_segment_seconds` defaults to 10.0 based on this pilot, not the 40.0 first assumed: 40s let VAD hand Canary an entire 30s conversational clip in one call, which measurably hurt accuracy versus finer segmentation.

## What I Inherited vs What I Built

This project is a fork of [paberr/ownscribe](https://github.com/paberr/ownscribe) at commit `fc8198e` (2026-07-20). As of this writing, 237 of the 318 commits on this branch were made by me, all after that fork point.

Distinctive additions built in this fork, not present upstream:

- **Claim anchoring**: each summary key point links back to the transcript timestamps where its source text appears, so a claim can be checked against the recording instead of trusted on faith.
- **Voiceprint-based speaker enrollment and naming**: `clew enroll` computes a voiceprint from a reference clip and matches it against future diarized speakers by cosine similarity, replacing generic `SPEAKER_00` labels with real names. Upstream has no speaker-identity system at all.
- **Hardware-verified microphone mute**: the system-wide mute is verified by reading the device state back after setting it, instead of trusting that the set call succeeded.
- **The SwiftUI menu-bar app** (`swift/Sources/OwnscribeMenuBar/`): a three-column library window, search, claim anchoring in the inspector, an RMS envelope strip, and settings, layered on the same CLI pipeline. Upstream's `swift/` directory holds a single Swift file, `swift/Sources/AudioCapture.swift`; this fork's `swift/Sources/` now holds 65.

## Legal and privacy notice

**Recording consent is your responsibility.** The rules differ by country and by US
state: some allow one participant to record, others require every participant to agree.
In France, recording private conversations without consent is a criminal offence under
article 226-1 of the Code penal, and consent is presumed only when the recording happens
openly and participants are able to object. Saying at the start of a meeting that you are
recording is the simplest way to stay on the right side of most of these rules, and in
several jurisdictions it is what the law expects.

**Nothing leaves your machine.** Audio, transcripts, embeddings and summaries are written
to local disk only. There is no account, no telemetry, and no network call for
transcription, diarization or summarization.

**Voiceprints are biometric data.** Diarization on its own only separates speakers within
a recording (Speaker 1, Speaker 2) and enrolls nobody. Naming a speaker is an explicit,
separate step: `clew enroll --name "Alice" clip.wav` stores a voice embedding in
`~/.config/clew/voiceprints/voiceprints.json`. Under the GDPR, a voiceprint used
to recognise a specific person is special category data, and if you record work meetings
you are the controller of it. Run `clew speakers` to list what is enrolled,
`clew unenroll "Alice"` to remove one person, or delete that file to remove all of
them.

This notice is informational and is not legal advice. If you record conversations with
clients, employees or patients, check your obligations with someone qualified in your
jurisdiction.

## Acknowledgments

Clew builds on some excellent open-source projects:

- [WhisperX](https://github.com/m-bain/whisperX): fast speech recognition with word-level timestamps and speaker diarization
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper): CTranslate2-based Whisper inference
- [pyannote.audio](https://github.com/pyannote/pyannote-audio): speaker diarization
- [mlx-audio](https://github.com/Blaizzy/mlx-audio) / [NVIDIA Canary-1B-v2](https://huggingface.co/nvidia/canary-1b-v2): Apple Silicon native ASR (Canary pilot engine)
- [llama.cpp](https://github.com/ggerganov/llama.cpp) / [llama-cpp-python](https://github.com/abetlen/llama-cpp-python): local LLM inference
- [Ollama](https://ollama.ai): local LLM serving
- [Click](https://click.palletsprojects.com): CLI framework

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup, tests, and open contribution areas.

## License

This repository uses two licenses.

Code inherited from upstream, everything present at the fork point (commit
`fc8198e`, 2026-07-20), stays under the MIT License, unmodified and
permanent. See [LICENSE.md § Inherited work (MIT)](LICENSE.md#inherited-work-mit).

Everything added or changed in this fork after that commit, Copyright (c)
2026 Yanis Naamane, is licensed under [PolyForm Noncommercial
1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0): free for
personal use, research, and any other noncommercial purpose, not free for
commercial use. Full text and the delimitation between the two licenses:
[LICENSE.md](LICENSE.md).

For commercial licensing of the PolyForm-covered portions, contact
yanis@nymedia.io.
