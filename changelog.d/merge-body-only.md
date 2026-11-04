### Fixed
- `pr_merge.py --body-only` prints the body alone, so `gh pr merge --body-file` no longer puts the subject on the first body line. `#38` to `#45` were merged with the whole message and each carries that duplicate; they are left as they are, and §4 of `git-conventions.md` now says which flag feeds which argument.
