# Plain commit bodies

### Fixed

- `infra/checks/check_commit_body.py` refuses backticks, `**bold**` and `__bold__` in a commit body
  outside a fenced block: a commit message is never rendered, so the markers reached the reader as
  characters. `0bf59cd` carried ten backticks until it was amended.

### Changed

- `CONTRIBUTING.md` and `CONTRIBUTING.zh-CN.md` point at `docs/specs/git-conventions.md` §2 and §4
  instead of repeating the merge rules, which had already grown three paragraphs of history.
