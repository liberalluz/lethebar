### Fixed

- `pr_merge.py --body-only --out <file>` writes the merge body to a file itself, so the text never passes through a shell pipe that decodes UTF-8 as the local code page; `#46` lost an em dash to that step and was amended.

### Changed

- `CONTRIBUTING.md`, `CONTRIBUTING.zh-CN.md` and `docs/specs/git-conventions.md` now name `--out` as the way to produce the `--body-file` argument, and record both ways it has gone wrong: the subject repeated in the body (`#38` to `#45`) and U+FFFD from a redirect (`#46`).
