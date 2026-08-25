# Configuration

Full requirements, install options, the `config.toml` reference, and every backend Clew
supports. See the [README](../README.md) for the short version.

## Requirements

- macOS 14.2+ (for system audio capture)
- Python 3.12+
- [uv](https://docs.astral.sh/uv/)
- [ffmpeg](https://ffmpeg.org/): `brew install ffmpeg`
- Xcode Command Line Tools (`xcode-select --install`)

Summarization works out of the box: a local model (Phi-4-mini, ~2.4 GB) downloads
automatically on first run. Optionally, you can use [Ollama](https://ollama.ai),
[LM Studio](https://lmstudio.ai), or any OpenAI-compatible server instead (see
[Configuration](#configuration) below).

Works with any app that outputs audio through Core Audio (Zoom, Teams, Meet, etc.).

> **Tip:** The first time Clew records system audio, macOS prompts for **System Audio
> Recording** permission, a narrower grant than Screen Recording; it only lets Clew hear
> other apps' audio, not see your screen. If you use `--mic`, macOS also prompts for
> **Microphone** permission. Open either settings panel directly with:
>
> ```bash
> open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
> open "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
> ```
>
> Enable your terminal app under "System Audio Recording Only", then restart it.
>
> Clew checks Microphone access **before** starting a recording (when `--mic` is set) and
> exits with the exact fix if it's missing. System Audio Recording is a private macOS
> permission with no public preflight API, so it's requested naturally on first capture
> instead. If denied, Clew reports it immediately rather than silently recording silence.
> With `--mic`, the system audio and mic tracks are retained separately; a post-recording
> RMS check on each tells you specifically which track is silent, instead of one ambiguous
> "audio is silent" warning.
>
> On macOS versions before 14.2, or if you pass `[audio] capture_backend =
> "screencapturekit"` in config, Clew falls back to ScreenCaptureKit, which does require
> the Screen Recording permission instead.

## Installation details

The [README](../README.md#install) covers the quick `uvx` install. Here are the rest of
the paths.

### Alternative summarization backends

The built-in local model works out of the box. If you'd rather call a hosted backend,
install the matching extra as a tool:

```bash
uv tool install "clew[ollama] @ git+https://github.com/ynaamane/clew"   # use Ollama
uv tool install "clew[openai] @ git+https://github.com/ynaamane/clew"   # use any OpenAI-compatible server (LM Studio, llama-server, etc.)
uv tool install "clew[all] @ git+https://github.com/ynaamane/clew"      # install both
```

### Homebrew

There is no brew formula: Homebrew builds Python dependencies from source, which doesn't
work well for the PyTorch and llama-cpp-python stack. The closest thing is installing
[uv](https://docs.astral.sh/uv/) via brew and letting it manage a global `clew` command:

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

When installed from source, the `clew` command lives inside the project's virtual
environment, so run it with `uv run` from the repo directory:

```bash
uv run clew          # equivalent to the bare `clew` used elsewhere in these docs
```

Alternatively, activate the environment once (`source .venv/bin/activate`) and then call
`clew` directly. Every command shown in the README and in [docs/advanced.md](advanced.md)
uses the bare `clew` form, which works after activation, after `uv tool install`, or via
`uvx --from git+https://github.com/ynaamane/clew clew`.

Contributing, running tests, and the dev-tools install (`uv sync --dev`) are covered in
[CONTRIBUTING.md](../CONTRIBUTING.md).

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
model = "large-v3"        # tiny, base, small, medium, large-v3, turbo (large-v3-turbo: ~4x faster decode, near-parity quality on spontaneous FR/EN)
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
device = "auto"           # "auto" (MPS if available, else CPU), "cpu", or "mps"

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

**Precedence:** CLI flags > environment variables (`HF_TOKEN`, `OLLAMA_HOST`,
`OPENAI_API_KEY`, `CLEW_PROGRESS`) > config file > defaults. `OWNSCRIBE_PROGRESS` still
works as a legacy alias for `CLEW_PROGRESS`.

### Migrating from ownscribe / MeetingScribe

If you're upgrading from a pre-rename install, Clew moves your existing config,
voiceprints, and default output directory to their new locations automatically, once, the
first time you run it: `~/.config/ownscribe` to `~/.config/clew`,
`~/.config/meeting-scribe/voiceprints` to `~/.config/clew/voiceprints`, and `~/ownscribe`
to `~/clew` (only if you never pointed `[output] dir` somewhere else). Nothing is deleted,
only moved, and only when the new location doesn't already exist.

## Audio Retention

By default (`keep_recording = true`), every recording's WAV files (system, mic, and any
sidecar files) stay on disk next to the transcript and summary. This is what makes
`resume` and `reprocess` possible: both need the original audio.

There are three ways to control how long retained audio sticks around:

- **Keep forever (default)**: `retention_days = 0` and never run `purge`. Nothing is ever
  deleted automatically.
- **Auto-delete after each meeting**: `keep_recording = false` deletes the WAV files
  immediately after transcription (no retention at all, so `reprocess` won't work on that
  meeting later).
- **Keep for N days, then purge manually**: set `retention_days` in config, and
  periodically run `clew purge` to remove anything older than that. This is _not_ a
  background job; retention only happens when you invoke `purge`.

```bash
clew purge                    # purge using retention_days from config (no-op if retention_days = 0)
clew purge --older-than 14    # override config: purge anything older than 14 days
clew purge --all              # purge every retained recording, regardless of age
clew purge --dry-run          # preview what would be purged, without deleting anything
```

`purge` only ever removes retained audio (WAV files and sidecars): transcripts and
summaries are never touched, so past notes remain readable even after their source audio
is gone.

## Summarization Templates

Built-in templates control how transcripts are summarized:

| Template  | Best for                  | Output style                                 |
| --------- | ------------------------- | -------------------------------------------- |
| `meeting` | Meetings, standups, 1:1s  | Summary, Key Points, Action Items, Decisions |
| `lecture` | Lectures, seminars, talks | Summary, Key Concepts, Key Takeaways         |
| `brief`   | Quick overviews           | 3-5 bullet points                            |

Use `--template` on the CLI or set `template` in `[summarization]` config. Default is
`meeting`.

Define custom templates in config:

```toml
[templates.my-standup]
system_prompt = "You summarize daily standups."
prompt = "List each person's update:\n{transcript}"
```

Then use with `--template my-standup` or `template = "my-standup"` in config.

## Speaker Diarization

Speaker identification requires a HuggingFace token with access to the pyannote
diarization model:

1. Accept the terms for [pyannote/speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1) on HuggingFace
2. Create a token at https://huggingface.co/settings/tokens
3. Set `HF_TOKEN` env var or add `hf_token` to config
4. Run with `--diarize`

Diarization uses MPS (Apple Silicon GPU) by default when available (`device = "auto"` in
`[diarization]`, above) — CPU/MPS parity is verified bit-for-bit, and it falls back to CPU
automatically, with no crash, on a machine without MPS. Set `device = "cpu"` to force CPU.

Voiceprints created by enrollment (below) are biometric data with real legal weight: see
[Legal and privacy notice](../README.md#legal-and-privacy-notice) before enrolling anyone.

## Speaker Naming

Enroll a speaker's voice from a short reference clip (a few seconds of them speaking,
isolated) to have their real name appear in transcripts instead of a generic
`SPEAKER_00` label:

```bash
clew enroll --name "Alice" alice-sample.wav
```

This computes a voiceprint using the same embedding model diarization already loads (no
extra download) and stores it in `~/.config/clew/voiceprints/voiceprints.json`.
Enrollment requires the same HuggingFace token as diarization (§ Speaker Diarization
above).

During a meeting, every diarized speaker cluster is compared against enrolled
voiceprints by cosine similarity. A match above the threshold (default `0.65`) gets the
enrolled name; anything below gets `Unknown-1`, `Unknown-2`, etc., never a forced wrong
match. If you record with `--mic` (or `capture_mode` retains separate tracks), your own
segments are always labeled `Owner` directly from the microphone track and are never sent
through diarization or matching, since you're a known speaker by construction.

```bash
clew speakers            # list all enrolled names
clew unenroll "Alice"    # remove an enrolled voiceprint
```

## Transcript Correction

Meetings with French/English code-switching (speakers alternating languages mid-sentence)
can trip up Whisper's spelling and word-boundary detection. An opt-in correction pass
sends each transcript segment's text through your configured LLM backend, asking it to
fix spelling and misheard words only, never to paraphrase, translate, add content, or
touch timestamps/speakers.

```toml
[correction]
enabled = true
max_length_delta_ratio = 0.4  # reject a fix that changes segment length by more than this fraction
```

A correction is applied only if it passes the length-delta guard; anything further
outside that ratio (a sign of an added or truncated response) is rejected and the
original segment text is kept unchanged. Uses your existing `[summarization]` backend: no
separate model or config needed. Runs after diarization/speaker naming and before
summarization, using the same summarizer instance.

## Canary Transcription Engine (A/B Pilot)

`engine = "canary_mlx"` swaps the default WhisperX/faster-whisper pipeline for
[NVIDIA Canary-1B-v2](https://huggingface.co/nvidia/canary-1b-v2) via
[mlx-audio](https://github.com/Blaizzy/mlx-audio) (Apple Silicon native, MLX runtime).
This is a pilot A/B engine, not the default: pick it explicitly to compare against
WhisperX on your own recordings.

```toml
[transcription]
engine = "canary_mlx"

[canary]
repo = "CogniSoftOrg/canary-1b-v2-mlx-bf16"
max_segment_seconds = 10.0
max_tokens_per_segment = 200
```

Requires `uv` on PATH (already required to run Clew from source). `mlx-audio` is never
installed into Clew's own environment: the engine spawns `uv run --with mlx-audio ...`
per transcription, layering the dependency onto an ephemeral overlay so it never touches
`pyproject.toml`, `uv.lock`, or your other transcription runs. The first invocation
downloads the ~2GB checkpoint from HuggingFace (cached afterward). The first `uv run
--with` invocation also resolves and downloads mlx-audio itself (cached in
`~/.cache/uv` afterward, so only the very first Canary transcription pays this cost).

Known scope limits for this engine, compared to the WhisperX default:

- **Segment-level only, no word-level timestamps.** Canary's decoder has no
  forced-alignment step; every segment's `words` list is empty.
- **No self-diarization.** Speaker labeling for Canary transcripts is whatever your
  existing diarization/naming pipeline produces on a segment-overlap basis. Canary itself
  never diarizes.
- **One language per run.** No per-segment auto-detection; `[transcription] language`
  (or the CLI `--language` flag) sets both source and target language for the whole file,
  defaulting to French if unset.
- **VAD-segmented in ≤`max_segment_seconds` chunks** (via faster-whisper's bundled
  Silero VAD, already installed for WhisperX, no extra dependency) rather than one
  continuous pass, since Canary's positional encoding has no long-form chunking of its
  own.
- **Pilot result: WhisperX stays the default.** On a real code-switched FR/EN clip (see
  `pilot/`), Canary's WER on code-switch spans was consistently worse than WhisperX's
  across every `max_segment_seconds` tested (5s/10s/40s): the pre-committed pass bar
  (Canary must win switch-span WER by ≥3 points) was not met. `max_segment_seconds`
  defaults to 10.0 based on this pilot, not the 40.0 first assumed: 40s let VAD hand
  Canary an entire 30s conversational clip in one call, which measurably hurt accuracy
  versus finer segmentation.

## Acknowledgments

Clew builds on some excellent open-source projects:

- [WhisperX](https://github.com/m-bain/whisperX): fast speech recognition with word-level timestamps and speaker diarization
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper): CTranslate2-based Whisper inference
- [pyannote.audio](https://github.com/pyannote/pyannote-audio): speaker diarization
- [mlx-audio](https://github.com/Blaizzy/mlx-audio) / [NVIDIA Canary-1B-v2](https://huggingface.co/nvidia/canary-1b-v2): Apple Silicon native ASR (Canary pilot engine)
- [llama.cpp](https://github.com/ggerganov/llama.cpp) / [llama-cpp-python](https://github.com/abetlen/llama-cpp-python): local LLM inference
- [Ollama](https://ollama.ai): local LLM serving
- [Click](https://click.palletsprojects.com): CLI framework
