# Advanced usage

The full command reference, the macOS app internals, and troubleshooting notes that don't
fit the README's Quickstart. See the [README](../README.md) for the short version.

## Record, transcribe, and summarize a meeting

```bash
clew                    # records system audio, Ctrl+C to stop
```

This will:

1. Capture system audio until you press Ctrl+C (or auto-stop after 5 minutes of silence)
2. Transcribe with WhisperX
3. Summarize with your local LLM
4. Save everything to `~/clew/YYYY-MM-DD_HHMMSS/`

> **Note:** By default, Clew records all system audio directly with no picker: every
> app's output (Zoom, WhatsApp, browser tabs, etc.) is captured at once. To show a source
> picker on each launch instead, set `capture_mode = "picker"` in the `[audio]` config
> section.

On first run, WhisperX / pyannote and the summarization model may download model files.
Clew shows a `Preparing models` step and best-effort download progress in the TUI while
this happens. Use `clew warmup` to pre-download all models.

## Options

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

## Subcommands

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

## Auto-Detecting a Meeting

Instead of manually starting `clew`, run `clew watch` ahead of time: it polls whether
BOTH the default input device (mic) and the default output device (speakers/headphones)
are active at the same time (a permission-free, OS-level signal on both sides, since it
only reads a hardware property and never opens an actual audio stream), and once that
combined state holds continuously for a few seconds it starts recording automatically.
Mic activity alone (dictation, a voice memo) does not trigger it, and output activity
alone (music, a video) does not either: only mic AND output together, the pattern a live
call produces.

```bash
clew watch                          # default: 3s of sustained mic+output activity before recording starts
clew watch --sustained-seconds 5    # require a longer sustained window (fewer false starts)
```

This works identically regardless of which app produces the audio: Zoom, WhatsApp, or a
Meet/Teams/Discord tab in a browser all show up the same way at the OS device level, so
there's no per-app integration or bundle-identifier polling to maintain. A brief
notification sound does not trigger it; only activity that stays sustained on both
devices for the full `--sustained-seconds` window does. Once triggered, `watch` hands off
to the normal recording pipeline: everything else (capture mode, diarization, correction,
output format) is controlled by your regular config.

> **Known limitation**: `clew`'s own `--mic` capture (via `AVAudioEngine`) makes the OS
> report the output device as "running" even while producing silence, an artifact of
> `AVAudioEngine`'s internal render graph, not of anything actually playing. This does not
> affect `watch` today, since `watch-activity` always exits before a recording starts
> (they never run concurrently), but it means the mic+output signal is not safe to reuse
> while `clew`'s own mic capture is active.

> **Video files work too.** Anywhere Clew accepts an audio file it also accepts a video
> container (mp4, mov, mkv, m4v). It extracts the audio track via ffmpeg. To turn a
> recording into full notes, drop it in a folder and run `clew resume ./that-folder/`
> (transcript + summary); use `clew transcribe meeting.mp4` for a transcript only.

Use `warmup` ahead of time to avoid first-run model download delays while recording:

```bash
clew warmup                    # prefetch Whisper model (+ diarization if enabled in config)
clew warmup --language en      # also prefetch alignment model for English
clew warmup --with-diarization # force diarization warmup for this run
```

## Searching Meeting Notes

Use `ask` to search across all your meeting notes with natural-language questions:

```bash
clew ask "What did Anna say about the deadline?"
clew ask "budget decisions" --since 2026-01-01
clew ask "action items from last week" --limit 5
```

This runs a two-stage pipeline:

1. **Find**: sends meeting summaries to the LLM to identify which meetings are relevant
2. **Answer**: sends the full transcripts of relevant meetings to the LLM to produce an
   answer with quotes

If the LLM finds no relevant meetings, a keyword fallback searches summaries and
transcripts directly.

## Reprocessing a Meeting

If a transcript or summary came out wrong (a bad model choice, a config change, a
summarization backend swap), `reprocess` redoes the whole pipeline from the retained
audio, overwriting the existing transcript and summary:

```bash
clew reprocess ./2026-02-20_1736
clew reprocess ./2026-02-20_1736 --model large-v3 --template lecture
```

Unlike `resume` (which skips work that's already done), `reprocess` always starts over
from the audio: it errors out if no retained audio is found for that meeting (i.e.
`keep_recording` was `false` when it was recorded, or it's already been purged).

## Backfilling Older Meetings

Meetings recorded before `envelope.json` (the waveform strip) or `anchors.json`
(clickable evidence for summary claims) existed have a transcript and summary but neither
derived file. `backfill` adds whatever is missing, computed from what's already on disk:

```bash
clew backfill ./2026-02-20_1736   # backfill one meeting
clew backfill                     # scan every meeting directory, backfilling each that needs it
```

It never re-runs transcription or summarization, and it never rewrites or deletes an
existing file: a meeting that already has both `envelope.json` and `anchors.json` is left
untouched, and `envelope.json` is only added when retained audio is still present (no
audio means no waveform, not a flat one). Running it again is always safe; it reports one
line per directory and only ever adds files.

## Headphones vs Speakers (Owner Track Purity)

The mic track (`mic.wav`, labeled `Owner`) and the system track (`system.wav`, the
remote call audio) are captured from two physically separate sources, and on
**headphones** that separation is perfect: your microphone only ever picks up your own
voice, with nothing from the call bleeding in.

On **Mac speakers**, the call audio plays out loud and the microphone can pick some of it
back up (acoustic echo) before it ever reaches `clew`. That bleed lands in `mic.wav`
alongside your own voice, which can pollute the `Owner` track with fragments of the
remote speaker's audio.

**Recommended: wear headphones for meetings recorded with `--mic`.** It's free, requires
no configuration, and gives the cleanest possible separation between what you said and
what you heard. See `--mic` under [Options](#options) above and `[audio] mic` under
[Configuration](configuration.md#configuration).

If headphones aren't an option, `[audio] echo_cancellation` can enable macOS's own native
voice-processing echo canceller on the mic input:

```toml
[audio]
echo_cancellation = "off"   # "off" (default), "on", or "auto"
```

- `"off"`: never touches the mic input. The current default.
- `"on"`: always enables voice processing on the mic.
- `"auto"`: enables voice processing only when the current default output device is the
  Mac's built-in speakers (detected via CoreAudio's transport type, not by matching a
  device name), since that's the only case where mic-into-speaker acoustic echo actually
  happens. Headphones and external outputs are left untouched.

macOS's voice processing also ducks non-voice audio playing through the speakers
relative to detected speech (correct behavior for suppressing acoustic echo), but it
means the effect on your own voice specifically has not been validated against a real
recorded meeting in this fork; test it against your own voice before relying on it for
anything you need transcribed precisely.

## The macOS app

Everything above is the CLI. There is also a menu-bar app
(`swift/Sources/OwnscribeMenuBar`) that drives the same pipeline: it shells out to this
repo's `clew`, so the CLI is the engine and the app is a front end, not a
reimplementation. Build and signing steps are in [BUILD.md](../BUILD.md); the short
version:

```bash
bash swift/build-app.sh                  # build, sign AND install to /Applications
SKIP_INSTALL=1 bash swift/build-app.sh   # stop at dist/ without installing
open /Applications/Clew.app              # always launch the INSTALLED copy
```

What the app adds over the CLI:

- **A three-column library window**: filters, meeting list, transcript with an
  inspector. Meetings come from `~/clew/` (or `[output] dir` in the config). Open it
  three ways: ⌘0, the app menu, or `open "clew://library"`. The URL route exists because
  until 2026-07-30 the window could only be reached by clicking the menu bar extra, and
  SwiftUI's `MenuBarExtra(.window)` popover exposes nothing to accessibility: a
  keyboard-only user was locked out, and so was any automated visual check.
- **A search field** over the library, composing with the sidebar filter (typing inside
  "Avec actions" narrows that filter rather than replacing it), and a two-line summary
  excerpt per row so the list says what a meeting was about.
- **A record button and a global hotkey** (⌘⇧M) for the system-wide mic mute. The mute
  is verified by reading the device back, and the menu bar shows three distinct states:
  not muted, muted and verified, muted but **unverified** in amber, because a
  hardware-refused mute once displayed as successful, meaning the app said "muted" while
  the call could still hear you.
- **Claim anchoring in the inspector.** Each summary key point shows the timestamps
  where its rare tokens appear in the transcript, and clicking one scrolls to that
  utterance. Three states are kept deliberately distinct: `(pas encore vérifié)` means no
  `anchors.json` exists, an em dash means anchoring ran and found nothing, and a chip
  means real evidence. Absence must never render as a confident zero.
- **An RMS envelope strip**, so an abnormal silence is visible without opening a 400 MB
  wav.
- **Settings**: the HuggingFace token (stored in the login Keychain), plus mic on/off
  and the silence timeout. Everything else still lives in the TOML. The app reads the
  config once at launch, so changing these needs a restart.

Two caveats worth knowing before you build:

- The app requires **macOS 26+** (`swift/Package.swift`), because the design targets the
  current visual language. The CLI has no such requirement.
- macOS ties permission grants to the signing identity, so **never delete or recreate
  the signing cert**, a new cert is a new identity and every System Audio Recording /
  Microphone grant resets. See [BUILD.md](../BUILD.md).

### Looking at the window without a mouse

Two paths, and the second is the one that keeps working:

```bash
open "clew://library"                                          # then, app frontmost, screen unlocked:
bash scripts/ui-evidence/capture.sh Clew /tmp/ui-ev            # window-scoped PNG + AX tree

bash scripts/ui-evidence/render.sh /tmp/ui-render               # off-screen; works with the screen LOCKED
```

`capture.sh` resolves the window id **by owner** and passes it to `screencapture -l`, so
it cannot capture the screen, but it fails on a locked screen and on a window that is not
frontmost. `render.sh` hosts the real `LibraryWindow` in an off-screen `NSWindow` and
reads its pixels, in both light and dark appearances.

**Read its CANNOT-VERIFY output before trusting a render.** It answers layout, type
scale, text and appearance; it is blind to Liquid Glass (glass, no-glass and
glass-on-container render byte-identically) and to the selected row, which comes out
opaque black over its own label and badge. Anything about materials still needs a human
looking at a real screen. [APP_TEST.md](../APP_TEST.md) has the details.
