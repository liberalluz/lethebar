### Added

- A package can declare its numbers and their bounds in `data/state.json`, and a
  resource may map values to display text with `labels`.
- `data/rules.json` settles values in file order after the chosen action's own
  effects, so a rule reads what the effect just wrote.
- `V-14`: a rule that names a resource the ledger never declares is refused at
  installation, naming the resource.

### Changed

- Sanguo now keeps `power` and `standing` as numbers with labels (`兵微将寡`,
  `初露锋芒`, `名动诸侯`) instead of writing a string from a rule.
- Values are clamped into their declared `min`/`max` after both effects and
  rules; a choice that would overflow stops at the bound instead of failing.
