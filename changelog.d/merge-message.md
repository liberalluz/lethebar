### Added

- `infra/tool/merge/pr_merge.py`: builds the message for a squash merge and checks the commit one leaves behind. One commit keeps its own subject and body, so a single-commit pull request needs no arguments; more than one needs `--why` and `--batch`, because there is no single reason to take from them.
- `python infra/tool/merge/pr_merge.py --verify-only` reads the top commit of the default branch. Nothing read that commit before: the commit-body gate only looks at `origin/main..HEAD` on a branch, so a missing `Why:` on `main` stayed invisible.

### Changed

- `CONTRIBUTING.md` and `CONTRIBUTING.zh-CN.md`: the merge step says to run that check after merging, and says what a multi-commit pull request has to pass to `gh pr merge`.
