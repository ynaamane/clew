# MeetingScribe.app — first-launch checklist

This covers the parts of the packaging that can only be verified
interactively, on your machine, with your permission prompts. Everything
else (bundle structure, signature, entitlements, plist contents, headless
launch via `open`, menu bar registration) was verified during the build —
see the `codesign -dvvv` / `--entitlements -` output printed at the end of
`swift/build-app.sh`.

## Prerequisites

1. `bash scripts/setup-codesign-identity.sh` has been run once on this
   machine (see `BUILD.md`).
2. `bash swift/build-app.sh` completed and printed `Built and signed:
dist/MeetingScribe.app` with no errors.

## First launch

- [ ] `open dist/MeetingScribe.app` (or double-click it in Finder — do NOT
      run the inner binary directly, see `BUILD.md` § 3).
- [ ] Gatekeeper shows an "unidentified developer" warning (expected —
      self-signed, no Apple notarization). Right-click → Open, confirm once.
- [ ] A waveform icon appears in the menu bar. No Dock icon (LSUIElement).
- [ ] Click the menu bar icon → the dropdown opens (Start Recording /
      recent meetings / Settings… / Quit).

## Permission prompts

- [ ] Click "Start Recording". macOS should show the System Audio Recording
      permission prompt (System Settings → Privacy & Security → Screen &
      System Audio Recording). Grant it.
- [ ] If you enable "also capture microphone" in Settings and start a
      recording, macOS should separately prompt for Microphone access.
      Grant it.
- [ ] After granting, recording actually starts — the menu shows "Stop
      Recording" and a running timer/indicator.

## Grants survive a rebuild (the whole point of the stable identity)

- [ ] With permissions already granted, run `bash swift/build-app.sh` again
      to rebuild `dist/MeetingScribe.app`.
- [ ] `open dist/MeetingScribe.app` again and start a recording.
- [ ] Confirm you are **not** re-prompted for System Audio Recording or
      Microphone — the earlier grant should still apply. If you ARE
      re-prompted, something is wrong (most likely: the app was signed with
      a different or ad-hoc identity). Check `codesign -dvvv
    dist/MeetingScribe.app` for `Authority=MeetingScribeDev`, not
      `Signature=adhoc`.

## End-to-end recording

- [ ] Play some audio (a YouTube video, a call, anything with sound) and
      record a short clip.
- [ ] Click "Stop Recording". The menu should switch to a processing state
      (transcribing/summarizing).
- [ ] Once done, the meeting appears in the recent-meetings list in the
      dropdown, and clicking it opens the meeting folder in Finder.
- [ ] Confirm a `transcript.md` (and, if summarization is enabled,
      `summary.md`) exists in that folder and its content roughly matches
      what was actually said.

## Settings / Keychain token

- [ ] Open Settings… from the menu, paste a HuggingFace token, click Save.
- [ ] Quit and reopen the app (or just reopen Settings). The token field
      should still show the saved value (loaded back from Keychain).

## If something looks wrong

- **No permission prompt ever appears, capture stays silent**: check
  System Settings → Privacy & Security → Screen & System Audio Recording —
  the app may need to be removed and re-added manually once if TCC got into
  a confused state. `tccutil reset ScreenCapture com.ownscribe.menubar` (or
  the Microphone equivalent) resets it cleanly for a fresh test.
- **Re-prompted every rebuild**: the signing identity isn't stable — see the
  "Grants survive a rebuild" check above.
- **"App is damaged and can't be opened"**: this means Gatekeeper actively
  rejected the signature (different from the normal "unidentified
  developer" warning, which just requires one confirmation). Re-run
  `swift/build-app.sh` and check the `codesign -dvvv` output for errors.
