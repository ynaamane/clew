# Clew.app: first-launch checklist

This covers the parts of the packaging that can only be verified
interactively, on your machine, with your permission prompts. Everything
else (bundle structure, signature, entitlements, plist contents, headless
launch via `open`, menu bar registration) was verified during the build —
see the `codesign -dvvv` / `--entitlements -` output printed at the end of
`swift/build-app.sh`.

## Prerequisites

1. `bash scripts/setup-codesign-identity.sh` has been run once on this
   machine (see `BUILD.md`).
2. `bash swift/build-app.sh` completed and printed `Built, signed and installed:
/Applications/Clew.app` with no errors.

## First launch

- [x] `open /Applications/Clew.app` (or double-click it in Finder; do NOT
      run the inner binary directly, see `BUILD.md` § 3).
- [x] Gatekeeper shows an "unidentified developer" warning (expected —
      self-signed, no Apple notarization). Right-click → Open, confirm once.
- [x] A waveform icon appears in the menu bar. No Dock icon (LSUIElement).
- [x] Click the menu bar icon → the dropdown opens (Start Recording /
      recent meetings / Settings… / Quit).

## Permission prompts

- [x] Click "Start Recording". macOS should show the System Audio Recording
      permission prompt (System Settings → Privacy & Security → Screen &
      System Audio Recording). Grant it.
- [x] If you enable "also capture microphone" in Settings and start a
      recording, macOS should separately prompt for Microphone access.
      Grant it.
- [x] After granting, recording actually starts — the menu shows "Stop
      Recording" and a running timer/indicator.

## Grants survive a rebuild (the whole point of the stable identity)

- [ ] With permissions already granted, run `bash swift/build-app.sh` again
      to rebuild `/Applications/Clew.app`.
- [ ] `open /Applications/Clew.app` again and start a recording.
- [ ] Confirm you are **not** re-prompted for System Audio Recording or
      Microphone — the earlier grant should still apply. If you ARE
      re-prompted, something is wrong (most likely: the app was signed with
      a different or ad-hoc identity). Check `codesign -dvvv
/Applications/Clew.app` for `Authority=MeetingScribeDev`, not
      `Signature=adhoc`.

Recording can be driven WITHOUT a human click (2026-08-24, used for the post-install e2e sound
test): the library window's toolbar record button carries `.accessibilityIdentifier`
`library.recordButton` — `open "clew://library"`, then via System Events click the button of
`toolbar 1 of window 1` whose `AXIdentifier` is `library.recordButton` (its AXTitle reads as
`missing value`, match on the identifier only). Two traps: the window can report `count of
windows = 0` for a couple of seconds after `open` (retry, don't conclude "no window" — the
MenuBarExtra popover itself remains AX-invisible, this button is the only programmatic route),
and the tap records what the machine OUTPUTS, so generate a stimulus (`say "<known sentence>"`)
during capture and grep the transcript for it afterwards.

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
- [ ] **Talk out loud during the clip, then confirm the folder contains
      `mic.wav` AND `system.wav` (not just `recording.wav`) and that your own
      words appear in the transcript labelled `Owner`.** This is the BUG4
      regression check: `enableMic` used to default to false with no way to
      turn it on, so the app recorded everyone except you. A recording with a
      single `recording.wav` and no `Owner` line means the mic path is off
      again.
- [ ] Sanity-check the duration: a 2-minute recording must produce a
      ~2-minute file, not ~4 minutes. A doubled duration (voices deep and
      slowed) is BUG5 returning — the merge falling back to a hardcoded
      sample rate instead of the captured one.

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
      "Quit Clew" menu button). Check System Settings → Sound → Input
      — the mic should be unmuted, same as the button-quit case above. This
      is the path that was silently broken before the quit-path fix: ⌘Q
      bypasses the button's click handler entirely, so this only proves
      anything if you genuinely use ⌘Q, not the menu.
- [ ] Repeat with `killall OwnscribeMenuBar` (the app's actual process
      name, not the `Clew.app` bundle name) from a terminal instead
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

## Design pass — the one no automated check can replace

This section exists because it was missing, and its absence let the same
mistake ship twice on 2026-07-28: the design was declared "matching the
validated direction" on the strength of a green test suite, twice, with
nobody having looked. Rejected on sight both times.

**No test in this repo can verify appearance.** Re-measure before quoting, but as of the end of
2026-07-31 that is **468 green Swift** (422 XCTest + 46 swift-testing) and **637 Python**;
`glassEffect` call sites; the right symbols in the binary. Every one of those proves the
code RUNS. They are all silent on whether the window reads well. The count going up changes
nothing about that — which is the whole point of this section, so do not read a bigger
number as progress on this pass.

**UPDATE 2026-07-30 — an agent CAN now look, which changes the workflow but not the rule.**

```bash
open "clew://library"                                   # opens the window, no mouse needed
bash scripts/ui-evidence/capture.sh Clew /tmp/ui-ev # window-scoped PNG + AX tree
```

The capture resolves the window id **by owner** and passes it to `screencapture -l`, so it
cannot capture the screen. Activate the app first — `screencapture -l` fails on a window that
is not frontmost ("could not create image from window"). The AX process name is
**`OwnscribeMenuBar`** (the executable), not "Clew": `System Events` lookups by the
app's display name fail with "Can't get process".

**UPDATE 2026-08-03 — an agent can also DRIVE the window, not only photograph it.** Selecting
a meeting row via `click at {x,y}` reports success but does NOT change a SwiftUI List's
selection (verified: the capture after the click was unchanged). What works is the AX
selection attribute, path taken from the capture's own `axtree.txt`:

```bash
osascript -e 'tell application "System Events" to tell process "OwnscribeMenuBar"
set selected of row 5 of outline 1 of scroll area 1 of group 2 of splitter group 1 of group 1 of window 1 to true
end tell'
```

That is how the 27-Jul meeting's detail column (real anchors, real envelope, the fold pill
with real examples) was captured and verified on 2026-08-03. Verify the selection CHANGED by
reading the next capture — never trust the click's own success report.

**⚠️ THAT PATH REQUIRES AN UNLOCKED SCREEN, so it is unavailable most of the time.** Measured
the same afternoon it was written: with the screen locked
(`ioreg -n Root -d1 -r | grep CGSSessionScreenIsLocked` → `Yes`) the library window still
exists but reports `onscreen=no`, its `AXWindow` count drops to **0**, and `screencapture -l`
refuses it. A loop that silently needs someone sitting at the machine is not an autonomous
review loop.

**The off-screen renderer is the replacement — and its BLIND SPOTS are the load-bearing part
of this section.** It builds an `NSWindow` off-screen, hosts the real `LibraryWindow`, and
reads pixels with `cacheDisplay`, so it works locked. What it can and cannot see was measured,
not assumed:

| Verifiable off-screen | NOT verifiable off-screen |
|---|---|
| Layout, spacing, column widths | **Liquid Glass / `glassEffect`** |
| Type scale, weights, truncation | Real translucency and vibrancy |
| Text content, badge values | **Selection highlights — and everything ON the selected row** |
| Light vs dark appearance | Anything the compositor draws |

**The selected row is not just mis-coloured, it is unreadable.** Sampled across a rendered
row — x=40 to x=235, y=146 to y=194 — every pixel is **(0,0,0)**: the artifact pill paints over
the icon, the label AND the badge. So a badge can be present in the app and absent from the
render. This nearly produced a false defect report ("the `9` badge is missing"), when
`LibrarySidebar.sections` passes `hasUnknowns: false` for that item so `BadgeText` provably
takes its `String(count)` path. When a string is missing from a render, first ask whether the
selection artifact ate it.

The two numbers behind the right-hand column, because "it looked fine" is exactly the trap:
`glassEffect` on the `List`, `glassEffect` on a container, and **no glass at all** render
**byte-identical** off-screen (md5 `613f4c7e77be8ae7bfb878d0b77bde8c` for all three; only
`.background(.bar)` differed). And a selected row samples **(0,0,0)** off-screen where the
real window is **(225,226,226)** — so a black pill in a render is an artifact, not a bug.

**Consequence, stated plainly: a glass change renders IDENTICALLY whether it works or not.**
Never certify glass, translucency or selection styling on an off-screen render. That would be
the same substitution this section exists to prevent — the available evidence standing in for
the required kind.

Also dead, measured, do not retry: SwiftUI's `ImageRenderer` draws `List` as a yellow
no-entry placeholder and `glassEffect` as nothing at all.

**It works — and the first reading of a correct render found a bug no test could reach.** The
meeting header was displaying `^[1 voix](inflect: true)` to the user, because SwiftUI resolves
inflection markup only in a literal or `LocalizedStringKey` and `MeetingDetailView` handed
`Text(_:)` a `String` variable. Fixed in `878de73`. The reason no suite caught it is the part
worth keeping: a test named `testTheCountKeepsItsInflectionMarkup` **asserted the broken
string**, on the reasoning that "SwiftUI does the pluralisation" — so a correct fix would have
turned it red. Same shape as the avatar test that once asserted a colour collision. A suite can
encode a bug as a requirement; a render cannot.

Run it, then **Read the PNG**:

```bash
bash scripts/ui-evidence/render.sh /tmp/ui-render    # library-light.png + library-dark.png
```

Two fixture traps that made the first renders lie, both worth knowing before trusting a new one:
`AppState.outputDir` resolves to **`homeDir/clew`**, so copying meetings into `homeDir`
itself yields an empty library with `0` badges; and injecting `pipelineRunnerFactory = { nil }`
makes `isCliAvailable` false, which fires the CLI banner. Both produced renders that looked
broken while faithfully showing the state they were given.

This closes the *absence* half of a design review: an agent can now name what is missing,
what colour the window actually is, and whether an effect renders as intended. The first such
review (2026-07-30) found seven gaps, recorded in `TODO.md § 0`, including the window being
LIGHT where the mockup is DARK — something no test would ever have said.

What it does NOT close: **whether it reads well is still yours.** An image tells an agent
what is on screen, not whether the result is good.

**UPDATE 2026-07-31 — the AX tree is now addressable.** An earlier version of this line said the
tree returns "0 lines"; that was wrong twice over. It returned **55 lines** with pixel frames
(`@433,322 174x16`), enough to measure spacing; what was missing was a stable *handle* on the
controls, because **0** `.accessibilityIdentifier` calls existed in `swift/Sources/`. Ten now do:
`library.sidebar`, `library.meetingList`, `library.search`, `library.recordButton`,
`library.cancelButton`, `meeting.transcript`, `meeting.envelope`, `meeting.backchannelToggle`,
`inspector.form`, `banner`. `scripts/ui-evidence/main.swift:66` already printed `#identifier`
when present, so they appear in the tree with no harness change.

The one that needed thought is the record button: its TITLE changes with state
(`Enregistrer` / `Arrêter`), so a script addressing it by title silently stops finding it the
moment a recording starts — exactly when you would want to press stop. The identifier is stable
while the title is not.

**UPDATE 2026-08-03 — two evidence facts from the enrollment verification.** (1) `capture.sh`
can fail the PNG ("could not create image from window") while still dumping a full `axtree.txt`
(173 lines that day) — and for a claim like "are these NAMES displayed", the AX tree is the
STRONGER evidence: `AXStaticText ="Yanis"` at real coordinates in the live app beats pixels
needing interpretation. Don't treat a failed screenshot as a failed verification before reading
the tree. (2) The off-screen render harness CANNOT verify anything that lives in the real
machine state outside the copied library — it isolates `homeDir` by design, so it never sees
`~/.config/clew/voiceprints/voiceprints.json` and the Personnes section renders empty
there regardless of what is enrolled. Live-app AX is the only channel for that class of claim.
Add it to the CANNOT-VERIFY list alongside glass/materials.

**Owner verdict 2026-08-06:** global approval by Yanis (app in daily use; recorded via
project decision log). Renderer pre-verdicts above stand; no per-item formal pass was
performed.

**Pre-capture 2026-08-04 (off-screen renderer, agent), at `285a5c6`, against
`/tmp/ui-render/library-light.png` and `library-dark.png`.** These are pre-verdicts on the
observables the renderer CAN see (layout, spacing, type hierarchy, text content, light/dark).
They are not the design verdict: no item below is globally VERIFIED, the final call on every
item is Yanis's, in the live app. Blind spots that apply to this whole block: glass and
materials render byte-identically to no glass, the selected sidebar row paints an opaque
black pill over its own label (seen again in both PNGs, known artifact, not a defect), and
real translucency, vibrancy and selection styling are invisible off-screen.

- Item 1 (one deliberate design): `Design status: UNVERIFIED`, whole-window judgment, needs Yanis.
- Item 2 (transcript legibility): observables pass in both PNGs, timestamp gutter, speaker
  avatar and utterance text render without truncation or overlap, avatar does not compete
  with the text at render size. Legibility itself: `Design status: UNVERIFIED`, needs Yanis.
- Item 3 (type scale): hierarchy reads coherent in both PNGs (detail title > section
  headers in small caps > body > badge captions), no arbitrary-size outlier observed. Exact
  pt values not measurable from pixels: final read needs Yanis.
- Item 4 (glass rails): `Design status: UNVERIFIED`, glass is in the renderer's cannot-verify
  list, needs Yanis at the screen.
- Item 5 (density and spacing vs mockup): observables pass, list rows carry the mockup's
  title/meta/summary structure with badges, compact density comparable to the mockup, no
  spacing anomaly in either theme.
- Item 6 (speaker avatars distinguishable): `Design status: UNVERIFIED` in this render, the
  selected fixture meeting has a single Unknown voice so no two-avatar comparison exists in
  the PNGs. Needs a multi-speaker meeting selected, or Yanis in the live app.
- Item 7 (envelope strip): observables pass, the strip renders with real amplitude variation
  in both themes. Informative-vs-decoration: needs Yanis.
- Item 8 (inspector states): partial pass, `(aucune correspondance)` renders on both key
  points and reads as data, not breakage, in both themes. `(pas encore vérifié)` is not
  exercised by this fixture. Whether the wording reads neutral: needs Yanis.
- Item 9 (anchor chip click): `Design status: UNVERIFIED`, interaction, off-screen renderer
  cannot click, needs the live app.
- Item 10 (settings pane): `Design status: UNVERIFIED`, the renderer draws the library
  window only, the settings pane is not in either PNG.

Open `⌘0` (or the URL above) and judge against `design/direction-b-glass.png`
and `design/mockup.html`:

- [ ] Does the whole window read as one deliberate design, or as default
      SwiftUI with effects applied on top?
- [ ] **Transcript legibility first** — this is what gets reread the next
      morning, and it is the reason the HIG forbids Liquid Glass in the
      content layer. Line length, leading, contrast, and the speaker avatar
      not competing with the text.
- [ ] Type scale: does it read as the HIG scale (title2 17 / title3 15 /
      body 13 / callout 12 / caption 10), or as arbitrary sizes?
- [ ] Sidebar and inspector rails: does the glass sit behind the content or
      fight it?
- [ ] Density and spacing versus the mockup — the mockup's `:root` block
      carries the intended values.
- [ ] Speaker avatars: legible at 18pt, and do two speakers in one meeting
      ever look alike? *(The code-level collision is fixed as of `5c49061` —
      seven speakers now get seven distinct palette colours, where every
      diarized label previously collapsed to two. So this check is now purely
      about whether the colours are DISTINGUISHABLE to your eye at 18pt,
      which no test can answer. Note the palette wraps at the eighth
      speaker.)*
- [ ] The envelope strip: is it informative, or decoration?
- [ ] Inspector states read correctly — `(pas encore vérifié)` reads as
      "not checked yet", `(aucune correspondance)` reads as "anchoring ran and
      matched nothing", and the two are not confusable. *(Changed 2026-07-31: the
      second state was a bare `—`, which was correct data that READ as broken.
      Both on-disk meetings with an `anchors.json` have **0 tokens** in it, so this
      is the common path on real data, not an edge case. The three states are now
      guarded as pairwise-distinct and non-empty; what no test can tell you is
      whether the new wording actually reads as neutral rather than as a warning —
      a key point legitimately having no anchor is normal, e.g. an English summary
      word cannot anchor to its French equivalent in the transcript.)*
- [ ] **Click an anchor timestamp chip** (`Gary→08:30`) — it should scroll the
      transcript to that utterance, and reveal it if the backchannel toggle
      was hiding it. New in `c640161`. Two things only you can judge: whether
      a `.link`-styled chip reads as clickable in the inspector, and whether
      the scroll lands somewhere legible rather than pinning the line to the
      very top or bottom.
      **The LOGIC is now verified against real data**, so this check is purely
      visual: `AnchorEvidenceRealMeetingTests` drives the 27-July meeting's 9
      real tokens / 14 occurrences through the production loader, the display
      model and the scroll targeting, and it caught a genuine defect no
      synthetic fixture could — `SPEAKER_00`'s "OK." and the sentence
      containing "Lambda" are BOTH stamped `[05:09]`, and the chip resolved to
      the two-word backchannel, offering it as proof of a claim about
      architecture (fixed in `0ae9532`).
      *(An earlier version of this line said only a fresh recording could
      exercise the path, because no meeting under `~/clew/` has populated
      anchors — one of six has the file and its `anchors` object is `{}`. That
      was wrong about the mechanism: `/tmp/ms-fixture/` is a derived copy of
      the same meeting WITH its anchors, which is exactly what the new tests
      use. A fresh recording is still the only way to see the chips **in the
      app**, since the window reads `~/clew/`, not `/tmp`.)*
- [ ] **Settings → the two new controls** (mic on/off, silence timeout) — new
      in `6c08eec`. The write path is tested and the HF token is provably
      preserved; how the pane READS is unverified, nobody has looked. Note it
      says a restart is needed, because `AppState` reads the config once at
      launch.

**Screenshots: window only, never the screen.** The one full-screen
`screencapture -x` attempt captured confidential content unrelated to this
project. Use `screencapture -l <windowid>` or `-R` on the window frame, and
only when the rest of the screen is clear.

**When the verdict is negative, get specifics before changing anything.**
"Pas bon du tout" is a verdict on the whole; guessing at spacing or colour
and iterating blind against an unseen target wastes both sides' time. Look at
the window together and name the parts.
