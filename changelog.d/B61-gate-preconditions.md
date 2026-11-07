### Added

- `infra/ci/author-gate.yml`: the gate a pack repository copies into
  `.github/workflows/`, with its four steps in the order each one depends on.
- `infra/checks/check_author_gate.py`: the template is checked for shape, since
  the only thing that can be wrong with it here is a step that moved or vanished.

### Changed

- `infra/stage_builtin.py`: staging now removes an archive whose source
  directory is gone, names what it removed, and fails when a removal is blocked.
  `B59` shipped a deleted story for exactly one release because staging only
  wrote.
- `infra/checks/check_tree.py`: gains `--profile engine|world` and `--root`, and
  refuses an `app/builtin/*.zip` that no `content/builtin/<id>/` backs.
- `infra/checks/run_godot.py`: reads the suite's summary line and fails when more
  cases were skipped than `LETHEBAR_MAX_SKIPS` allows, so a green run has to mean
  something ran.
- `infra/tool/batch/config.json`: the tree check names the engine profile, and a
  `release-tool` step runs `pack.py self-test` before the translation check.
