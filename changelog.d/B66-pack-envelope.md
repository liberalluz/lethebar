### Added

- `infra/checks/check_pack.py` reads the archive a package publishes to and
  nothing else: `manifest.json` alone at the root, every other entry under
  `data/`, `assets/` or `i18n/`, no `..`, no absolute path, no symbolic link, no
  executable suffix, and caps on entry count and bytes. Ten negative cases run
  in `--self-test`, one per rule, and the gate runs them.

### Changed

- The author gate is three steps now - `build` -> `check_pack` -> `publish` -
  and mentions no `infra/stage_packs.py`, no `--path app` and no `app/builtin`.
  A plugin repository is a project; only its archive is checked.
- `infra/checks/check_tree.py` stops having an opinion about an author's
  repository: the `world` profile is gone and `--profile` with it. The engine's
  own layout rules are unchanged.
- `ADR-0010` records the move: what may not exist is an executable entry inside
  a pack, not a build script in someone's repository.
