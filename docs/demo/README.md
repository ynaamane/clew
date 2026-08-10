# Demo GIF tooling

The README demos (`docs/demo-pipeline.gif`, `docs/demo-ask.gif`) are scripted
simulations rendered by the real CLI code paths: `simulate_demo.py` imports
`PipelineProgress`, `Spinner` and the meeting-name formatter from the `clew`
package and replays scripted events through them, so the visuals stay
pixel-faithful to the product. All meeting content shown is synthetic; no real
meeting data is used.

## Regenerate

Requires [vhs](https://github.com/charmbracelet/vhs) (`brew install vhs`).
Run from the repo root:

```bash
vhs docs/demo/demo-pipeline.tape
vhs docs/demo/demo-ask.tape
```

The tapes overwrite the GIFs in `docs/` in place. Regenerate them whenever the
CLI's progress UI or user-facing strings change, and spot-check a few frames
before committing.

## Desktop app tour

`record-app-tour.sh` records a window-only tour of the library window running
on the same synthetic data, built into a throwaway home by
`make_demo_home.py`. The app instance is launched with `CLEW_HOME` pointing at
that home (exporting `HOME` is NOT enough: the app resolves the account home
and would show real meetings), from a scratch copy of `dist/Clew.app` made a
regular app with its own bundle id. It clicks through the three meetings with
guarded synthetic clicks and assembles the stills into `docs/demo-app.gif`.

```bash
SKIP_INSTALL=1 bash swift/build-app.sh    # if dist/Clew.app is stale
bash docs/demo/record-app-tour.sh
```

Run it only while nobody is using the machine (it pops a window on the active
display and borrows the cursor for a few seconds), and eyeball every frame
before committing.
