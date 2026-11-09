### Added

- `pack.py badge <repo-root>` writes a repository's pack table from every
  `packs/*/manifest.json`: a `packs-N` badge, `spec` and `engine` badges only
  when every pack agrees (otherwise `mixed`), and one table row per pack with
  `Kind`, `Pack`, `Version`, `Spec` and `Engine`. `--write` replaces only the
  marked block and `--check` names the pack and the field when a row drifts
  (B88).
- The gate runs `pack.py self-test` as the `badges` step, taking the check count
  from twelve to thirteen. A stale table now turns the gate red.

### Changed

- `docs/guide/publishing.md` pins the current release instead of `v0.6.0`, and
  documents `badge` as the command that writes the README block, including that
  `packs-N` counts layers and `Kind` explains which rows are playable.
