### Changed

- The commit types and the scope list now live in one file. `check_conventions.py`
  reads `docs/specs/git-conventions.md` and `infra/tool/batch/config.json` and
  fails when the two disagree, naming the side that is wrong. Before this batch
  the same seven scopes were written twice, and `docs(srs)` still shipped a
  commit because nothing read the list at commit time.

### Added

- `check_commit_body.py` refuses a subject that is not `type(scope): subject`.
  It imports the parser from `check_conventions.py`, so the subject is judged
  against the same list rather than a third copy of it.
- The gate runs `conventions` as its second check, before `commit-body`, so a
  drifted list is reported once instead of once per commit.
