# Building Clew.app

The app ships as a self-signed `.app` bundle for personal/solo use: no Apple
Developer account, no notarization. This is a deliberate tradeoff: a stable
self-signed identity keeps TCC permission grants (Screen & System Audio
Recording, Microphone) across rebuilds, at the cost of the "unidentified
developer" Gatekeeper warning on first launch (right-click → Open once).

## 1. Create the signing identity (once per machine)

```bash
bash scripts/setup-codesign-identity.sh
```

This creates a self-signed certificate named `MeetingScribeDev` (unchanged after
the Clew rename: it is the existing on-disk signing identity TCC grants are
anchored to on a machine that already ran this once, see "Do not delete this
certificate" below), imports it into your login keychain, and trusts it for
code signing. It is idempotent: running it again when the identity already
exists is a no-op.

Verify it exists:

```bash
security find-identity -v -p codesigning | grep MeetingScribeDev
```

**Do not delete this certificate.** macOS TCC (the permission system behind
Screen & System Audio Recording and Microphone) keys its grants to the
signing identity, not the binary path or contents. Every subsequent build
signed with the same `MeetingScribeDev` certificate is treated as "the same
app" by TCC, so a permission you grant once survives every future rebuild.
Delete and recreate the certificate and you get a new certificate hash — TCC
treats that as a brand new app, and every permission has to be re-granted.

If you ever need to start over anyway (e.g. debugging a corrupted keychain
entry), delete the identity from Keychain Access, re-run the setup script,
and expect one round of permission prompts on the next launch.

## 2. Build and sign the app

```bash
bash swift/build-app.sh
```

This builds `ownscribe-audio` and `OwnscribeMenuBar` in release mode,
assembles `dist/Clew.app`, signs both binaries plus the bundle
itself with the `MeetingScribeDev` identity, then **installs it to
`/Applications/Clew.app`**, quitting a running instance first, and
failing if the installed binary ends up differing from the one just built.
Pass `SKIP_INSTALL=1` to stop at `dist/`. Installing is part of the build on
purpose: a real 17-minute call was once recorded against a stale bundle
because building and installing were separate manual steps.

The two binaries and the bundle must all share the same identity or TCC treats
them as different apps with different grants. The script fails loudly if the
identity from step 1 isn't present.

It ends with `codesign -dvvv` / `--entitlements -` output so you can confirm:

- signature is present and cert-anchored (not `adhoc`)
- Hardened Runtime is on (`flags=... runtime` and a real `Runtime Version`)
- `com.apple.security.device.audio-input` entitlement is embedded
- `NSAudioCaptureUsageDescription` / `NSMicrophoneUsageDescription` /
  `LSUIElement` are present in the bundle's `Info.plist`

## 3. Launch it

```bash
open /Applications/Clew.app
```

Launch the INSTALLED copy, not the one in `dist/`: otherwise you can be
testing a different build than the one you think is current. Always launch via
`open` (or double-click in Finder): this goes through LaunchServices, which is
what actually triggers the TCC permission prompts on first launch. Running the
inner binary directly from a shell
(`/Applications/Clew.app/Contents/MacOS/OwnscribeMenuBar`) skips
LaunchServices and the permission prompts may not fire correctly.

The app is `LSUIElement`, so it has no Dock icon — look for it in the menu bar.

See `APP_TEST.md` for the first-launch checklist — some of the permission
behavior can only be verified interactively, not from a build script.

## Design decisions (v1)

- **Self-signed, not Apple Developer**: personal solo use, no Mac App Store
  target, no distribution to other machines. A Developer ID certificate
  ($99/yr) would remove the Gatekeeper warning and enable notarization, but
  isn't needed here.
- **No notarization**: out of scope for a self-signed personal build —
  notarization requires an Apple Developer account.
- **Hardened Runtime ON**: this is what makes `com.apple.security.device.audio-input`
  meaningful — Apple's own docs describe enabling Hardened Runtime as the
  first step before adding that entitlement. Without Hardened Runtime the
  entitlement is simply ignored.
- **App Sandbox OFF**: `AudioHardwareCreateProcessTap` (the CoreAudio system
  audio capture path) is fragile under the sandbox, and there is no Mac App
  Store target planned. Revisit only if that changes.
- **CLI stays independent**: `swift/build.sh` (builds just `ownscribe-audio`
  into `bin/`, used by the Python CLI) is unaffected by this app-packaging
  flow. Both binaries are signed with the same identity by `build-app.sh` so
  TCC treats them consistently when run from the app bundle, but the CLI's
  own standalone binary at `bin/ownscribe-audio` keeps working exactly as
  before, unsigned or ad-hoc-signed by SPM, for terminal use.
