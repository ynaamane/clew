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

## Master mute (built-in mic)

- [ ] With the built-in mic as the active input, click the menu-bar mute
      button (or press ⌘⇧M). The icon switches to `mic.slash` and the
      button label changes to "Unmute".
- [ ] Play audio in another app while muted, then check System Settings →
      Sound → Input — the input level meter should show no activity.
- [ ] If a call app (Zoom/Meet/Teams) is open, confirm ITS mic level also
      shows silent — this is the "one mute, not two" requirement.
- [ ] Unmute (⌘⇧M or the button again). The icon returns to `waveform`/
      `mic.fill`, and the input level meter shows activity again.
- [ ] No warning banner appears in the dropdown — a warning means the
      verify-after-set check failed even on the built-in mic, which would
      be unexpected and worth reporting.

## Master mute (AirPods Max / Pro)

- [ ] Connect the AirPods, wait for them to become the active input
      (System Settings → Sound → Input, or just start using them), then
      repeat the built-in-mic checklist above.
- [ ] Specifically watch for: does the mute reach the call app (Zoom etc.),
      or only the recording? If a warning banner appears in the dropdown
      ("Couldn't mute the microphone system-wide...Bluetooth..."), that
      means the verify-after-set check caught a failure — the recording
      should still be protected (confirm via the level meter / a test
      recording), but the call itself may not be muted. This is the
      known, documented AirPods failure mode (Apple Developer Forums
      thread 693516) the fail-loud path exists for — expected to
      _sometimes_ happen on AirPods, never expected to happen silently.
- [ ] Try muting right after AirPods connect (before other apps have used
      the mic) vs. mid-call — the HFP/A2DP profile-switch timing differs
      and this is the scenario most likely to expose a settling issue.
- [ ] Quit the app while muted (via AirPods or built-in). Reopen it and
      check System Settings → Sound → Input is NOT still muted — the app
      should have restored the unmuted state on quit.
- [ ] Mute via the hotkey or menu button, then quit with **⌘Q** (NOT the
      "Quit ownscribe" menu button). Check System Settings → Sound → Input
      — the mic should be unmuted, same as the button-quit case above. This
      is the path that was silently broken before the quit-path fix: ⌘Q
      bypasses the button's click handler entirely, so this only proves
      anything if you genuinely use ⌘Q, not the menu.
- [ ] Repeat with `killall OwnscribeMenuBar` (the app's actual process
      name, not the `MeetingScribe.app` bundle name) from a terminal instead
      of ⌘Q. This sends a raw SIGTERM directly to the process, bypassing
      the normal Quit Apple-Event entirely — it exercises the secondary
      signal-handler path, not just the notification path above. Same
      expectation: mic unmuted afterward.

## Global hotkey while unfocused

- [ ] With the app running and a DIFFERENT app focused (a browser, Zoom,
      a text editor — not the menu-bar dropdown), press ⌘⇧M. The mute
      state should toggle exactly as if you'd clicked the menu-bar button,
      confirmed via the icon changing next time you open the dropdown.
- [ ] This was verified once end-to-end during development (real keystroke
      while a different real app had focus, callback fired) — this is
      the first real confirmation on your actual machine/hardware.

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
