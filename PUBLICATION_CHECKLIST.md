# Publication checklist

Single gate before any repo visibility flip (`gh repo edit --visibility public`). Consolidates
steps A1 through A7 of the Track A plan (`/Users/yanisnaamane/taff/docs/plans/2026-08-04-usine-signal-portfolio.md`,
item 8) plus the license and CONTRIBUTING checks. No box below is checked without a proof
location (file path, command, or commit hash). Statuses are honest, not aspirational: PENDING
means PENDING, not "almost done."

**Caveat on every SHA and run URL cited below**: A3 (git history treatment) is still an open
decision. If Yanis chooses the excision path, the rewrite changes every commit hash after the
first touched commit (measured: 302 of 317 commits shift). Any proof here that cites a SHA or a
CI run URL, including `285a5c6`, `879cea5`, `4eab296` and `007832f` below, was captured before
that rewrite and is provisional: it will need to be re-captured against the post-rewrite history
before the actual visibility flip. The plan's own ordering rule: no proof citing a SHA or run URL
is trustworthy until it is captured after the rewrite (if the rewrite happens).

**On the two patterns referenced below.** The *narrow purge pattern* (A1) and the *widened NDA
pattern* (A2 and the final sweep) are both recorded verbatim in the Track A plan linked above,
and are referred to here by name rather than inlined. Naming them instead of quoting them keeps
this file from reproducing the very tokens the sweep exists to remove, which is also why the
employer name and the client project codename appear below as descriptions rather than literals.

## Checklist

- [x] **A1: Purge of the 3 identified docs (screenshot-incident narrative)**
  Done. Evidence: commit `285a5c6` ("docs: genericize the screenshot-incident narrative across
  all docs (A1+A2)"), touching `HANDOFF.md`, `LESSONS_LEARNED.md`, `TODO.md` (plus `APP_TEST.md`,
  `CLAUDE.md`, `design/mockup.html`, folded in under A2 below). Done criterion from the plan: the
  narrow purge pattern returns zero matches across those three docs. Re-verified fresh this
  session (2026-08-06) against current HEAD
  (`879cea5`): still zero matches, and the technical lesson (never `screencapture` the full
  screen, target the window via `-l <windowid>` or `-R`) reads intact in all three docs.

- [x] **A2: Widened-pattern NDA sweep at HEAD**
  Done at HEAD `879cea5` (same content as `285a5c6`, no NDA-relevant edits since, other than the
  two items below closing). Pattern: the widened NDA pattern described at the top of this file,
  all tracked files, `.git` excluded. Full occurrence table with a verdict per line is in
  `/Users/yanisnaamane/taff/docs/handoffs/reports/2026-08-04-meeting-scribe.md`. Re-run that
  session: 28 occurrences (excluding the `MeetingsLack`/`ClaimsLacking` substring false
  positives, consistent with the report's count), all in the ACCEPTABLE class per the plan's
  criteria (generic colleague-voice examples, internal project-ticket references with no
  employer identified, the employer name used alone as a nameable career fact per the project's
  own NDA read). Zero occurrences of the codename. Two items the report flagged as needing a
  human decision: **both RESOLVED**, commit `d154869` ("docs: reframe pilot as global-recorder,
  not client-fed (pre-publication)"), landed the same day, before either reached Yanis as an
  open question. Stale citation refreshed this session (2026-08-07), re-checked directly rather
  than trusted:
  - `NOTES.md:629`, `pilot/run_pilot.py`, `pilot/fetch_fallback_clip.py` used to name the
    employer in the phrase describing the fallback clip; reworded to generic terms ("without any
    user-provided audio", "a real, Yanis-provided meeting clip"). Re-verified this session: a
    grep for the employer name across `NOTES.md`, `pilot/run_pilot.py` and
    `pilot/fetch_fallback_clip.py` returns zero matches (this checklist
    previously cited that old wording as still current, which by the time it was written was
    already a session behind).
  - `.claude/skills/ownscribe-pipeline-traps/SKILL.md:56` used to claim "the repo is private
    because it holds biometric voiceprints"; reworded to the accurate claim. Re-read this
    session: the line now says "Voiceprint embeddings are biometric data (GDPR Art. 9, cleared
    for this use) and live outside the tracked tree, under `~/.config` and `~/ownscribe`: never
    commit them into the repo", no false claim about repo contents.
  Also DONE (same anonymization pass, commit `e5b2202`; the follow-up commit that carried it into
  `HANDOFF.md` and `LESSONS_LEARNED.md` no longer exists as a separate commit, because the history
  rewrite applied that same rename to every version of those files and left it empty): the
  remaining 3 of the 5 tracked micro-validations from the morning-review queue (colleague first
  names anonymized project-wide across `TODO.md`, `rec.sh`,
  `HANDOFF.md`, `LESSONS_LEARNED.md`; the forced-purple-selection question decided in place, kept
  the macOS system selection color). All 5 micro-validations from `pending-decisions.jsonl` are
  DONE.
  **Final re-run of this sweep, post-A3 history rewrite (if any), is still PENDING**, see the
  note below; this refresh checks current HEAD content only, not history.

- [ ] **A3: Git history treatment**
  PENDING, Yanis decision. Tradeoff document with a real trial run already done:
  `/Users/yanisnaamane/taff/docs/handoffs/2026-08-04-a3-history-tradeoff.md`. The trial (on a
  separate mirror clone, real repo untouched) found: paragraph-excision by `git filter-repo`
  callback produces a genuinely clean history covering both blobs and commit messages (a
  token-only `--replace-text` pass would NOT: 19 blobs tell the whole leak narrative without
  containing the employer name or the codename as tokens); the hash churn is unavoidable in any
  rewrite (comes
  from GPG-signature stripping, not from the excision itself); 42 of 43 commit-hash citations
  across the docs go stale under a rewrite. Three options are on the table (surgical excision,
  HEAD-only purge with documented residual risk, fresh-start public history), see the tradeoff
  doc for the full comparison. **The real deadline for this decision is the public flip (target
  September 1, 2026), not any earlier internal date**, per the plan's own note in the tradeoff
  doc.

- [ ] **A4: `scripts/check.sh` green + real visual verification**
  Partially done. `check.sh` evidence: `CHECK_EXIT=0` read from a captured variable (not off a
  pipe), 10/10 gates, at commit `285a5c6`, Python 676 passed / 1 skipped / 7 deselected
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
  `ci-resurrection`, remote SHA `007832f`, `.github/workflows/ci.yml`, two jobs as specced
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
  **Root cause CONFIRMED 2026-08-10, post-flip** (superseding "could not be confirmed
  programmatically" above; `ci.yml` has also since merged to `main`): a `workflow_dispatch` run
  on the now-public repo (`31394710701`) failed in 5 seconds with zero steps started, and its
  check-run annotation reads "The job was not started because your account is locked due to a
  billing issue." The lock is at the ACCOUNT level; public-repo free minutes do not bypass it.
  Billable timing for that run is 0 ms (public repos bill nothing), so unlocking cannot create
  CI spend here. Unlock is Yanis-only: GitHub Settings, Billing and plans. Re-dispatch
  afterwards with `gh workflow run ci.yml -R ynaamane/clew`; the `ubuntu` job re-runs on the
  next push. Meanwhile the CI badge was removed from the README until runs resume (`a5c1581`,
  on Yanis's request; restoration note tracked in the taff ledger).

- [x] **A7: README attribution section + CI badge fix**
  Done. Local commit `4eab296` on `main`, verified: `README.md` only, 13 insertions. Section
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
  `test_cli.py`, 678 passed project-wide, `scripts/check.sh` 10/10 (`EXIT=0`). Commit `30c87ea`.

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

- [x] **License structure decision (PolyForm-NC vs MIT vs AGPL)**
  DONE. Decision: PolyForm Noncommercial 1.0.0 on Yanis's own additions, decided by Yanis
  2026-08-07 (`/Users/yanisnaamane/taff/pipeline/queue/pending-decisions.jsonl`, id
  `license-choice`; also recorded in `/Users/yanisnaamane/taff/pipeline/queue/morning-review.md`).
  Full tradeoff doc: `/Users/yanisnaamane/taff/pipeline/research/license-structure.md` (Variant
  A). Applied this session:
  - `LICENSE` moved to `LICENSE-MIT` (`git mv`), a short scope paragraph added above the
    unmodified MIT text (fork point commit `fc8198ea18abe63b8fe450b128d244fcd57f0abb`, verified
    against `git log` on `main`, not the dossier's stale `afc1d18...`, see note below), copyright
    line updated to "Copyright (c) 2026 Pascal Berrang and the ownscribe contributors". Rest of
    the 21-line MIT block confirmed byte-identical by diff.
  - `LICENSE.md` created: delimitation top-matter (fork point, inherited-MIT permanence,
    Copyright (c) 2026 Yanis Naamane, the `Required Notice:` line, commercial contact
    yanis@nymedia.io) followed by the full PolyForm Noncommercial 1.0.0 text, fetched verbatim
    from `https://polyformproject.org/licenses/noncommercial/1.0.0` (via its linked official
    plain-text download) and confirmed byte-identical to the fetched source by `diff` (exit 0)
    and matching MD5.
  - `README.md`: License section replaced, MIT badge (was line 5) replaced with a shields.io
    PolyForm badge pointing at `LICENSE.md`.
  - `CONTRIBUTING.md`: new "Contribution licensing" section added before "Submitting changes"
    (umbrel-pattern inbound-MIT clause: contributions licensed to the project under MIT
    regardless of the project's own PolyForm-NC terms).
  - `pyproject.toml`: `License :: OSI Approved :: MIT License` classifier removed (now false);
    `license` field changed to `{ text = "PolyForm-Noncommercial-1.0.0 AND MIT" }` (PolyForm-NC
    has no registered SPDX identifier, so the free-text form is used rather than a bare string
    that would misrepresent itself as a valid SPDX expression); `maintainers = [{ name = "Yanis
    Naamane", email = "yanis@nymedia.io" }]` added, `authors` (Pascal Berrang) unchanged. Verified
    parseable (`tomllib.load`) and resolvable (`uv run` builds the package without new warnings
    beyond the pre-existing uv-version one).
  Proof: this session's commits on `main` (see git log for SHAs) touching `LICENSE-MIT`,
  `LICENSE.md`, `README.md`, `CONTRIBUTING.md`, `pyproject.toml`.
  **Fork-point hash correction, worth a human eye**: the dossier's Variant A text names commit
  `afc1d18268f67e6c5a097a4e7bd8850138ffc5e2` as the fork point. That commit exists only on the
  `a10-pr01`/`a10-pr03` worktree branches, not on `main`; `main`'s own history was rewritten at
  some point (same tree, same message and timestamp, different parent, consistent with the A3
  tradeoff doc's note that GPG-signature stripping churns hashes). `main`'s current fork-point
  commit is `fc8198ea18abe63b8fe450b128d244fcd57f0abb` (`fc8198e`), matching what
  `README.md`'s existing "What I Inherited vs What I Built" section already cites. The license
  files use the verified `main` hash, not the dossier's stale one.
  **Sequencing note**: `pending-decisions.jsonl`'s `license-choice` entry says "Application des
  fichiers : apres la fin de l'excision A3" (apply the files after A3 excision finishes), and A3
  is still PENDING below. Applied now anyway, on explicit instruction, on `main` of the still
  PRIVATE repo (verified via `gh repo view`), so this does not touch the public-visibility gate;
  flagging the sequencing conflict for the record rather than silently overriding it.
  **SUPERSEDED (single-file merge)**: the two-file layout described above (`LICENSE-MIT` +
  `LICENSE.md`) is gone. `LICENSE-MIT`'s content is now merged verbatim into `LICENSE.md` under
  a new `## Inherited work (MIT)` section (the 21-line MIT block, scope paragraph and the Pascal
  Berrang copyright line all byte-preserved), with the PolyForm terms under
  `## Work added in this fork (PolyForm Noncommercial 1.0.0)`; `LICENSE-MIT` was `git rm`'d and
  every reference to it in `README.md` and `CONTRIBUTING.md` now points at the corresponding
  `LICENSE.md` section anchor. The `LICENSE-MIT` mentions in this entry and the ones above
  describe the file layout that was true at the time and are left as historical record, not
  live pointers.

- [x] **`pyproject.toml` URLs fixed**
  Done. `[project.urls]` Homepage/Repository/Issues point to
  `https://github.com/ynaamane/meeting-scribe` instead of upstream's `paberr/ownscribe`.
  `license`, `authors`, `classifiers` and `maintainers` were later touched by the license
  structure item above (license classifier removed, `license` field set, `maintainers` added);
  `authors` (Pascal Berrang) and `name` (`ownscribe`) remain untouched, `name` on purpose per the
  new pre-release item below.
  **SUPERSEDED 2026-08-07 by the Clew rename below**: `name` is no longer untouched, and the
  URLs above point at `ynaamane/clew` now, not `ynaamane/meeting-scribe`.

- [x] **CONTRIBUTING.md up to date**
  Done. Clone URL fixed (`git clone https://github.com/ynaamane/meeting-scribe.git` / `cd
  meeting-scribe`, was still `paberr/ownscribe`). The "Running tests" section's **"There is no
  CI"** paragraph (`CONTRIBUTING.md:27` before that session) is rewritten: CI exists on branch
  `ci-resurrection` (`.github/workflows/ci.yml`, matches A6's evidence above) and will start
  running once the repo goes public and the workflow merges to `main`; the macOS job stays manual
  (`workflow_dispatch`) since a hosted macOS runner is not something to burn on every push. The
  matching "there is no CI" line in the "Code style" section was updated too, for internal
  consistency. The license-structure item above closed the remaining gap: a "Contribution
  licensing" section is now in `CONTRIBUTING.md`, before "Submitting changes".

- [ ] **Final NDA sweep (widened pattern, blobs AND commit messages)**
  PENDING, to run after the A3 decision is executed (if a rewrite happens) or explicitly
  confirmed as HEAD-only (if not). Must cover both surfaces per the report's Decouverte 4: a
  blob-only sweep already missed a commit message once (`7a95e66`'s message quoted the old
  CLAUDE.md leak narrative verbatim, found only by `git log --all -p`, not by an
  enumerate-blobs approach). Command for the re-run: pipe `git log --all -p` through a
  case-insensitive grep for the widened NDA pattern described at the top of this file, against
  whatever history state is live at flip time, plus a human read of every remaining occurrence.

- [x] **Rename the package off the `ownscribe` PyPI namespace**
  Done 2026-08-07, superseded and folded into the full Clew rename below: `pyproject.toml`'s
  `name` is now `"clew"`, no longer the upstream `ownscribe` PyPI namespace.

- [x] **Full product rename: ownscribe / MeetingScribe -> Clew (decision Yanis 2026-08-07)**
  Done. Naming dossier: `/Users/yanisnaamane/taff/pipeline/research/naming-dossier.md`. Scope
  and proof, this session:
  - GitHub remote renamed to `ynaamane/clew` (repo itself already renamed on GitHub before this
    session; `git remote set-url` + `git fetch` verified against the new URL). The local checkout
    directory intentionally STAYS `/Users/yanisnaamane/meeting-scribe` (other sessions' docs
    reference that path).
  - Python package: `src/ownscribe/` -> `src/clew/` (`git mv`), every `from ownscribe` / `import
    ownscribe` rewritten to `clew` across `src/`, `tests/`, `pilot/`, `scripts/`.
    `pyproject.toml`: `name = "clew"`, `[project.scripts]` now `clew = "clew.cli:main"` primary
    plus `ownscribe = "clew.cli:main"` kept as a muscle-memory alias (same entry point).
    `uv lock` / `uv sync` regenerated cleanly (`Added clew v0.13.1`, `Removed ownscribe v0.13.1`).
  - Config/data paths, safe migration: new canonical `~/.config/clew` (config + `voiceprints`
    subdir) and `~/clew` (output), legacy `~/.config/ownscribe`, `~/.config/meeting-scribe/voiceprints`
    and `~/ownscribe` migrated automatically, once, on real CLI startup only (`clew.cli.main()`,
    never `clew.cli.cli()`, so the CliRunner-driven test suite can never trigger a real move --
    see `main()`'s docstring in `src/clew/cli.py`). `CLEW_PROGRESS` env var replaces
    `OWNSCRIBE_PROGRESS`, which still works as a fallback. Migration ran for real on this machine
    during verification (see caveat below) and moved Yanis's actual config and 12 real meeting
    directories intact, then `tests/test_envelope.py`'s real-file reference test found the
    migrated recording at its new path and passed.
  - macOS app, display-level: `CFBundleName` -> `Clew` (both plists), `NSAudioCaptureUsageDescription`
    / `NSMicrophoneUsageDescription` reworded, `CFBundleURLSchemes` -> `clew` (was `ownscribe`,
    matching `WindowOpenRoute.scheme`), every `Button`/`MenuBarExtra`/alert/settings string that
    said "MeetingScribe" or "ownscribe" (found via a second, lowercase-inclusive sweep after the
    first pass missed several: the "Quit ownscribe" menu button, the `MenuBarExtra` title, two
    `PipelineRunner` error strings, a Settings save message, a French CLI-absent banner). Build
    script `swift/build-app.sh`: `APP_NAME="Clew.app"`. Internal Swift module/type names
    (`OwnscribeMenuBar`, `OwnscribeCapture`, `OwnscribeConfigReader`, etc.), the `ownscribe-audio`
    binary name, and `CFBundleIdentifier` (`com.ownscribe.*`) all deliberately UNCHANGED this
    pass (see follow-ups). `swift build` (debug + release) and `swift test` both green: 492
    XCTest (9 skipped, 0 failures) + 48 swift-testing, after fixing one test that hardcoded the
    old scheme in uppercase (`OWNSCRIBE://LIBRARY`, missed by a case-sensitive sed).
  - Docs: `README.md` (title, the dossier's one-liner, install instructions rewritten to
    `git+https://github.com/ynaamane/clew` since this fork isn't published to PyPI, every CLI
    example, a new "Migrating from ownscribe / MeetingScribe" subsection; PyPI badge REMOVED
    rather than left pointing at the wrong/unrelated `ownscribe` PyPI page), `LICENSE.md` /
    `LICENSE-MIT` (checked, no repo URLs needed changing, upstream attribution untouched),
    `CONTRIBUTING.md`, this file, `APP_TEST.md`, `.claude/skills/ownscribe-pipeline-traps/SKILL.md`.
    The upstream fork attribution ("a fork of paberr/ownscribe at commit fc8198e") is unchanged
    everywhere, as required: that fact never changes regardless of this fork's own name.
  - Demo GIFs (`docs/demo-pipeline.gif`, `docs/demo-ask.gif`): see the dedicated GIF item below
    for the regeneration decision and evidence.
  - Gate: `bash scripts/check.sh` exit 0 (all 9 checks: ruff check, ruff format --check, pytest,
    swift build debug, swift build release, swift test, `bin/ownscribe-audio` staleness --
    rebuilt via `bash swift/build.sh` after the Swift edits, 3x shellcheck).
  **Caveat, stated plainly**: verifying `clew --help` for real (`uv run clew --help`) triggered
  the real migration against this actual machine's real `~/.config/ownscribe`, real
  `~/.config/meeting-scribe`, and real `~/ownscribe` (12 meeting directories, ~2.3GB), outside
  any test isolation. Verified lossless afterward (directory listing diffed, config.toml content
  read back, no error), but it was a real mutation of real user data during a verification pass,
  not inside a sandboxed test. Documented here rather than left silent.
  Proof: this session's commits on `main` (see git log for SHAs).

- [x] **Regenerate demo GIFs with Clew branding**
  DONE after all (2026-08-10, superseding the infeasibility finding below): commits `f99d3bd`
  ("docs: regenerate demo GIFs with Clew branding, commit the tooling") and `332269e` (library
  window tour GIF) landed the regenerated assets plus the capture tooling; the post-flip check
  verified all three GIFs decode on the public README. The 2026-08-07 analysis below is kept as
  the historical record of why it initially looked infeasible.
  ~~PENDING, investigated and found infeasible with existing tooling this session (2026-08-07).~~
  `docs/demo-pipeline.gif` and `docs/demo-ask.gif` were added upstream by Pascal Berrang
  (`e1f106e` / `a272390`, Feb 2026, both pre-fork) as "README simulations": the only trace of
  how they were built is a `.gitignore` comment, `# asciinema recordings (regenerated from
  scripts/)` / `*.cast`, but no such script, `.tape` file, or Makefile target exists anywhere in
  this repo's git history (`git log --all --name-only` searched for `.cast`, `demo`, `record`,
  every commit, nothing). This machine has none of asciinema, `agg`, `gifski`, or `ttygif`
  installed (`which` checked all four, all absent), and no Makefile exists to define a target
  either. Regenerating would mean building a brand-new capture pipeline from scratch, not
  reusing existing tooling, which is out of scope for a rename pass and risks producing a lower
  quality artifact than the original without Yanis's input on what the demo should show. The
  GIFs also predate the entire fork (claim anchoring, voiceprints, the macOS app all came after
  Feb 2026), so they already showed upstream's original CLI before this rename, not just the old
  product name. Left untouched per instruction: do not fake anything. `pilot/fetch_fallback_clip.py`
  does fetch a bundled public clip that could feed a REAL `clew` pipeline run once a capture
  pipeline exists (asciinema + agg is the standard combination for this kind of demo).

- [ ] **PEP 541 claim of PyPI `clew`, post-flip**
  PENDING, pre-release item, not flip-blocking. Per the naming dossier, `clew` on PyPI is a dead
  squat (a single `0.0.1` release, no author, no summary): file a PEP 541 name-claim request
  after the repo goes public, citing the dead release as justification. Do this instead of
  publishing under `clew-cli` or a similar workaround; the dossier's fallback name is `clew-cli`
  only if the PEP 541 claim is rejected. Not started this session (this session only renamed the
  local package; nothing was published or submitted to PyPI, per this repo's standing rule to
  never publish).

## Post-flip status (2026-08-10)

The final gate below was satisfied: Yanis gave the explicit go and executed the flip himself
on 2026-08-10; `gh repo view ynaamane/clew` confirms `private: false`. Post-flip hygiene, each
point verified against the PUBLIC rendering, not the local tree:

- README renders with all three GIFs decoded in a real browser (Playwright `img.decode()`:
  demo-pipeline 1200x760, demo-ask 1200x620, demo-app 1080x660); each asset also serves 200
  `image/gif` from `raw.githubusercontent.com/ynaamane/clew/main/docs/`.
- Release v0.13.2 is public (not draft, not prerelease); `Clew.app.zip` (582,208 bytes)
  downloads anonymously (ranged GET returns 206).
- Leak scan of the rendered surfaces (repo home, releases page, license page, Actions tab,
  rendered README HTML): zero matches for the employer name, the client codename, and the
  colleague first names (patterns kept out of this file per the convention at the top).
- Repo description set from the README tagline, plus 8 topics (transcription, whisper,
  meeting-notes, macos, local-first, privacy, diarization, speech-to-text) via `gh repo edit`,
  re-read after the edit. Previous description ("... Personal tool.") is recorded in the
  session log if a rollback is ever wanted.
- Profile pin: not possible via API (GraphQL schema introspected: no profile-pin mutation
  exists, only `pinIssue` and friends). One manual click left for Yanis: profile, Customize
  your pins, check `clew`.
- First upstream PR opened with Yanis's explicit go: `paberr/ownscribe#41`, head
  `ynaamane:fix-output-dir-rename-collision` (local branch `a10-pr01`, tip `5e51f39`, on the
  true upstream base `afc1d18`). Rendered PR page checked: zero em/en-dashes, zero internal
  tokens.
- CI: still blocked; root cause now confirmed at the account level, see A6 above.

## Final gate

**Yanis reads this checklist end to end and gives an explicit go before any
`gh repo edit --visibility public` is run. This checklist, and the agents that produced it,
never execute that command themselves: visibility changes are a human-only action, always.**
