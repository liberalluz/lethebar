### Fixed

- `pr_merge.py --verify-only` now reports a commit that sits on the default branch
  without its `(#<number>)` suffix. It used to pass any commit whose pull request
  was not named, which is how a merged subject lost `(#36)` for a few minutes.
- `pr_merge.py --show` appends the number only once. A subject that already ended
  in `(#<number>)` came out as `(#36) (#36)`.
