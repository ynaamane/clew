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
