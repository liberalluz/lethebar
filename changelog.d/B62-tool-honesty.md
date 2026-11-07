### Added

- `infra/checks/check_pr_body.py`: reads a pull request body by file or number and
  refuses one that lacks Summary, Impact, Verification, Risks or Self-check, that
  orders them differently, or that leaves a section empty.
- `batch.py pr <id> --translations-only`: redoes the pull request translations after
  the batch merged, for the case where only the translated body was wrong.

### Changed

- `batch.py pr --prepare` no longer invents a body when
  `.batch/<id>/pr-body.source.md` is missing. It exits 1 and names the five sections
  the template asks for, instead of shipping the stand-in body that B58 carried into
  its pull request.
- Missing pull request translations are a failure now, not a note. A batch whose
  translation hook is not configured cannot prepare a pull request.
- `CARD_TYPES` matches the seven commit types the conventions list. `process` is gone
  from the tool; it was never a type, only a branch prefix, and `B57` and `B61` both
  wrote it because the tool accepted it.
- `infra/ci/author-gate.yml` says at the top that it is a template to copy into a
  world repository's `.github/workflows/gate.yml`, and `infra/checks/check_author_gate.py`
  refuses the file if that sentence is missing.
- `infra/tool/batch/config.json` runs the author-gate check right after the tree check.
- `docs/specs/git-conventions.md` says a batch card's type uses the seven commit
  types, and replaces the `pack/<space>/vX.Y.Z` line with the rule that each pack is
  tagged on its own and a repository version is bookkeeping only.
