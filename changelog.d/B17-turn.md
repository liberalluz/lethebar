### Added

- A package can declare an action menu in `data/actions.json`: costs, effects and
  `requires` are applied together, and an action whose requirement fails is listed
  as unavailable with the failing condition instead of vanishing.
- `data/phases.json` gives a run a length, ranks read from the turn number, and
  failure conditions whose reason is shown when they end the run.
- `data/checks.json` resolves dice checks from the session RNG and records the
  numbers that decided them under `state.checks.<id>`.
- `V-16`, `V-17` and `V-18` refuse a malformed menu, phase machine or check at
  install time.

### Changed

- A save now carries the turn number and the per-action counters, so a restored
  run keeps its rank and its used-up actions.
