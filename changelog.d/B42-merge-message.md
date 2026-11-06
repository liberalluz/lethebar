### Changed

- `infra/tool/merge/pr_merge.py` now flattens the body it writes: inline code and bold lose their
  markers and every paragraph is filled at 72 columns, so a rendered pull-request body no longer
  becomes a commit message full of backticks and one 880-character line.
- `--verify-only` applies the same rules, so the top commit of `origin/main` can be judged after a
  merge, which is the only moment a squashed message can first be read.

### Added

- `infra/checks/check_commit_body.py --ref <commit>` judges a single commit. The range mode cannot
  see a squash merge: the commit lands on the default branch and no branch is ahead of it.
- `docs/specs/git-conventions.md` §2 states both rules: plain text wrapped at 72 columns, and the
  check that runs against `main` after a merge.
