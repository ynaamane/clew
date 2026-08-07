# Publication checklist

Single gate before any repo visibility flip (`gh repo edit --visibility public`). Consolidates
steps A1 through A7 of the Track A plan (`/Users/yanisnaamane/taff/docs/plans/2026-08-04-usine-signal-portfolio.md`,
item 8) plus the license and CONTRIBUTING checks. No box below is checked without a proof
location (file path, command, or commit hash). Statuses are honest, not aspirational: PENDING
means PENDING, not "almost done."

**Caveat on every SHA and run URL cited below**: A3 (git history treatment) is still an open
decision. If Yanis chooses the excision path, the rewrite changes every commit hash after the
first touched commit (measured: 302 of 317 commits shift). Any proof here that cites a SHA or a
CI run URL, including `3978b62`, `e96ba37`, `da97168` and `dcc91d2` below, was captured before
that rewrite and is provisional: it will need to be re-captured against the post-rewrite history
before the actual visibility flip. The plan's own ordering rule: no proof citing a SHA or run URL
is trustworthy until it is captured after the rewrite (if the rewrite happens).

## Checklist

- [ ] **A4: `scripts/check.sh` green + real visual verification**
  Partially done. `check.sh` evidence: `CHECK_EXIT=0` read from a captured variable (not off a
  pipe), 10/10 gates, at commit `3978b62`, Python 676 passed / 1 skipped / 7 deselected
  (hardware), Swift 488 XCTest (9 skipped) + 47 swift-testing, 0 failures (session report,
  Mission 3). Off-screen renderer pre-verdicts are written into
  `/Users/yanisnaamane/meeting-scribe/APP_TEST.md` (`§ Design pass`, the "Pre-capture
  2026-08-04" block, itemized 1 through 10) against `/tmp/ui-render/library-{light,dark}.png`.
  Five of ten items (2, 3, 5, 7, 8 partial) have renderer-observable PASS notes; five (1, 4, 6,
  9, 10) are explicitly `Design status: UNVERIFIED` because they need the live app or a human
  (glass/materials, selection styling, interaction, the settings pane, and the multi-speaker
  avatar comparison the current fixture can't exercise). **No item carries a human
  `Design status: VERIFIED` yet, that verdict is Yanis's, in the live app, and is PENDING.**

- [ ] **A5: Durable visual-verification protocol (Design status format)**
  PENDING. `APP_TEST.md § Design pass` currently uses a `Design status: VERIFIED` /
  `Design status: UNVERIFIED` convention informally throughout the section, but the plan's
  specific ask, a short, non-narrative rule block at the head of `§ Design pass` defining the
  exact format (`Design status: VERIFIED by <name> on <date> at <short SHA> against <artifact
  path>: <what was verified>`, otherwise only `Design status: UNVERIFIED`), is not yet written
  as a standalone rule block. Checked directly against `APP_TEST.md` this session: the section
  opens with narrative ("This section exists because...") rather than the rule. Also pending:
  `CONTRIBUTING.md`'s existing "If your change touches the window, render it and look at it"
  paragraph is not yet strengthened to reference the formal format.

- [ ] **A6: CI resurrected**
  BLOCKED at the account level, not a code problem. Workflow file is real and pushed: branch
  `ci-resurrection`, remote SHA `dcc91d2`, `.github/workflows/ci.yml`, two jobs as specced
  (`lint-and-test-python` on `ubuntu-latest`, `full-check-macos` gated to `workflow_dispatch`),
  YAML validated. Test run
  `https://github.com/ynaamane/meeting-scribe/actions/runs/31089951064` shows `startup_failure`
  at 0 seconds; the API returns path `"BuildFailed"` and an empty workflow name, meaning the run
  was never parsed into a schedulable workflow. This is not specific to this workflow file:
  GitHub's own Dependency Graph auto-runs fail identically on this repo (2026-08-04 and
  2026-08-05) and on an unrelated repo, `ynaamane/Algo`. Repo Actions settings are fully open
  (`{"enabled":true,"allowed_actions":"all"}`). Root cause needs Yanis in the GitHub web UI:
  Settings, Billing and plans, spending limit or payment method for Actions (the billing API
  endpoints 404 with the available token, so this could not be confirmed programmatically).
  `ci.yml` is deliberately NOT on `main` yet: the plan's done-criterion ("Linux job green") is
  not met. The run URL above is evidence of the diagnosis, not of completion.

- [x] **A7: README attribution section + CI badge fix**
  Done. Local commit `da97168` on `main`, verified: `README.md` only, 13 insertions. Section
  "What I Inherited vs What I Built" added around `README.md:518`, with a table-of-contents
  entry at `README.md:26`; the CI badge at `README.md:4` now points to
  `ynaamane/meeting-scribe/actions/workflows/ci.yml` instead of the upstream repo. Attribution
  count: **237 of 318 commits** by Yanis, freshly re-measured this session via `git rev-list`
  (one commit landed after the 2026-08-04 measurement of 236/317, itself a correction of the
  original plan's 235/316; use 237/318 as the current number, not the earlier two). Note: the
  section deliberately does not claim multi-sample voiceprint enrollment, since
  `VoiceprintDB.upsert` overwrites rather than accumulates and multi-sample enrollment is still
  an open item (`TODO.md:34`); it states single-clip enrollment instead, matching what the code
  actually does.

- [x] **Cleanup command purges voiceprints too (queue task 9)**
  Done this session. `cleanup` targeted `~/.config/ownscribe` only (`config.py:10`) and silently
  left voiceprint biometric data behind at `~/.config/meeting-scribe/voiceprints`
  (`speakers/base.py:9`) whenever `cleanup --all` ran, despite claiming to remove everything.
  TDD fix: failing test written first, confirmed red against the unmodified command, then green,
  mutation-checked. Independent review (`reviewer` subagent) caught a real gap the first pass
  missed: 3 pre-existing tests would have deleted a real developer's actual voiceprint store the
  moment `--all` genuinely started removing it, since they never mocked the new path; patched all
  three and added coverage for the previously-untested flagless interactive path too. Verified
  with a fake-HOME sentinel file that now survives the full `TestCleanup` suite. 48/48
  `test_cli.py`, 678 passed project-wide, `scripts/check.sh` 10/10 (`EXIT=0`). Commit `b210cc1`.

- [x] **Legal and privacy notice inserted (queue task 3, disclaimer)**
  Done this session. `README.md`, new `## Legal and privacy notice` section placed just before
  Acknowledgments (consent law by jurisdiction, local-only processing, voiceprints as GDPR
  special-category biometric data, "not legal advice"), plus a cross-reference line added to
  `## Speaker Diarization`. Inserted from
  `/Users/yanisnaamane/taff/pipeline/research/legal-privacy-notice.md` verbatim, WITHOUT the
  "cleanup does not currently touch this file" sentence the dossier's own note flagged for
  removal once the cleanup bug above is fixed, which it now is.

- [x] **MIT license intact**
  Verified this session. `/Users/yanisnaamane/meeting-scribe/LICENSE` exists, standard MIT text,
  upstream copyright notice preserved verbatim: `Copyright (c) 2026 Pascal Berrang`. No
  modification needed, MIT requires the notice survive, not the git history (also confirmed in
  the A3 tradeoff doc as the legal basis for the fresh-start option being license-safe).

- [ ] **License structure decision (PolyForm-NC vs MIT vs AGPL)**
  PENDING, Yanis decision, explicitly out of scope for this session. Full tradeoff doc:
  `/Users/yanisnaamane/taff/pipeline/research/license-structure.md` (queue item
  `license-choice`). Distinct from "MIT license intact" above: that item confirms today's
  upstream notice survives untouched; this one is whether the published repo stays plain MIT or
  re-licenses Yanis's own additions under PolyForm Noncommercial 1.0.0 (blocks commercial use,
  reads as source-available not open source on GitHub's own badge) or AGPL-3.0-only (OSI green
  badge, does not actually block commercial use). Common blockers regardless of choice, from the
  same doc: `pyproject.toml`'s `license`/`authors`/classifier/`name` fields still say upstream's
  MIT/Pascal Berrang/`ownscribe` (deliberately left untouched this session, only the
  `[project.urls]` Homepage/Repository/Issues were fixed to `ynaamane/meeting-scribe`, see below);
  the README MIT badge; a "Contribution licensing" section in `CONTRIBUTING.md` (still zero
  "licen" occurrences there). None of this is actioned until Yanis picks a variant.

- [x] **`pyproject.toml` URLs fixed**
  Done this session. `[project.urls]` Homepage/Repository/Issues now point to
  `https://github.com/ynaamane/meeting-scribe` instead of upstream's `paberr/ownscribe`.
  `license`, `authors`, `classifiers` and `name` deliberately NOT touched, they depend on the
  license structure decision above. Verified the file still parses (`tomllib.load`) and that the
  four untouched fields are byte-identical to before.

- [ ] **CONTRIBUTING.md up to date**
  Partially done this session. Clone URL fixed (`git clone
  https://github.com/ynaamane/meeting-scribe.git` / `cd meeting-scribe`, was still
  `paberr/ownscribe`). The "Running tests" section's **"There is no CI"** paragraph
  (`CONTRIBUTING.md:27` before this session) is rewritten: CI exists on branch `ci-resurrection`
  (`.github/workflows/ci.yml`, matches A6's evidence above) and will start running once the repo
  goes public and the workflow merges to `main`; the macOS job stays manual (`workflow_dispatch`)
  since a hosted macOS runner is not something to burn on every push. The matching "there is no
  CI" line in the "Code style" section was updated too, for internal consistency. Still NOT fully
  up to date: the license-structure doc's own finding stands, `CONTRIBUTING.md` has zero "licen"
  occurrences (no Contribution licensing section), which depends on the license decision above.
  Marked PENDING pending that decision.

## Final gate

**Yanis reads this checklist end to end and gives an explicit go before any
`gh repo edit --visibility public` is run. This checklist, and the agents that produced it,
never execute that command themselves: visibility changes are a human-only action, always.**
