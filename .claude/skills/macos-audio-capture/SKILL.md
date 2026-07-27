---
name: macos-audio-capture
description: macOS audio-stack facts and traps for this repo — CoreAudio process tap vs ScreenCaptureKit permissions, why an embedded Info.plist is load-bearing, the system-wide mic mute + verify-after-set guard (AirPods bug), Bluetooth HFP settling, and why the signing identity must never be recreated. Read this BEFORE touching anything under swift/, the capture backend, or the mute path — these are empirically-earned, and several of them froze Zoom or silently left the mic muted when guessed at.
---

# macOS audio capture — what this repo learned the hard way

Every item below cost a real failure. Do not re-derive them from first principles or from a model's recollection of CoreAudio.

## Capture: process tap, not ScreenCaptureKit

`CATapDescription(stereoGlobalTapButExcludeProcesses:)` + `AudioHardwareCreateProcessTap` + a private aggregate device, `muteBehavior = .unmuted`. macOS **14.2+**. It needs only `kTCCServiceAudioCapture` — the audio-only permission.

ScreenCaptureKit is the fallback for <14.2 and nothing else: SCK demands **Screen Recording** permission even for audio-only capture, which contradicts the project's audio-only requirement. Never promote it to default.

## The Info.plist is load-bearing, not packaging polish

**BUG0, critical.** A capture binary with no embedded `NSAudioCaptureUsageDescription` gave macOS nothing to prompt with → the unauthorized tap stalled CoreAudio for ~60s → **every audio client froze, including Zoom** (could not even join a call). Ctrl+C released it instantly.

- Embed it in the binary (`-sectcreate __TEXT __info_plist`) and **verify in-binary** (`otool`/`strings`), not just on disk.
- Keep the fail-loud preflight before any tap creation. A missing permission must surface as an error, never as a hang.
- A synthetic-tone test cannot catch this class. Permission/TCC behavior is only real on real hardware with a real app bundle.

## System-wide mute: verify-after-set is mandatory

`kAudioDevicePropertyMute` on the **input scope** of the resolved default input device — that is what reaches Zoom and every other app.

- `kAudioHardwarePropertyProcessInputMute` (WWDC23 s10233) mutes only OUR process. It does not satisfy "mute me everywhere". Do not substitute it.
- **Always read the state back and only report muted if the readback matches.** There is a documented macOS Bluetooth bug (Apple forum 693516 / FB9778272) where the mute lands on the output instead of the input. The readback is what turns that into a visible warning instead of a user who thinks they are muted and is not. If the warning fires on AirPods, the guard is working.
- Fall back to `MicCapture.toggleMute` when the hardware path cannot be confirmed.
- Bluetooth needs HFP settling time before the mute takes — do not assert immediately after the set.
- Built-in mic and AirPods are both first-class. Never optimize the mute path for one device class.

## Restore-unmute must cover EVERY exit path

The worst near-miss in this project: restore-unmute was wired to one menu button, so **Cmd+Q, Dock-quit, force-quit and logout would leave the system mic muted, silently, after the app was gone.** Fixed with `NSApplication.willTerminateNotification` plus `SIGTERM`/`SIGINT` sources, and clearing the state flag first so the hardware does not fire twice.

Rule for any future system-state mutation: enumerate the exit paths by grepping for who calls the cleanup — do not settle for confirming the cleanup exists.

## Signing identity: create once, never delete

The self-signed `MeetingScribeDev` cert (`scripts/setup-codesign-identity.sh`) is what makes TCC grants survive rebuilds. **Deleting and recreating it = a new identity = macOS resets every permission grant**, and the user re-does the whole hardware pass. Treat the cert as durable state, not a build artifact.

Launch via LaunchServices (`open dist/MeetingScribe.app`), never the inner binary — the inner binary launches without the bundle identity and permissions behave differently.

## Two physical sources beats diarization

`mic.wav` = what you send = "Owner", never diarized. `system.wav` = what you receive = diarized. Perfect separation by construction — **but only on headphones**. On speakers the call bleeds into the mic and `echo_cancellation` (`setVoiceProcessingEnabled`) is the mitigation, not a fix.

Merging the two tracks must anchor to whichever track started **first**: handling only non-negative offsets scrambled a transcript by -28.3s (BUG3). The offset computation was correct; the merge was not.
