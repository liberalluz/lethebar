### Changed

- The batch runner is the installed skeleton again: `pause`, `resume`, `exit`,
  `budget_override`, `pr_title` and `release_checks` all exist, and the twelve
  gate commands still run in the order they ran before.
- `release-tool`, `pack-envelope` and `guide` moved to `release_checks`, so an
  ordinary batch runs nine commands instead of twelve. A card marked
  `release: true` still runs all of them.
- `config.json` gained the blocks the skeleton expects: `commit`,
  `release_checks`, `pr_create`, `merge` and `docs_root`.
- The `commit` block carries the `team` convention this repository already
  follows by hand: seven types, seven scopes and the two body lines. A card
  now has to name its `git_scope`, and a commit whose scope is outside the
  list fails the gate.
