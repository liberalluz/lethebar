### Added

- A package table may now carry a `strings` section that names the labels a run
  is made of: `action.<id>`, `rank.<turn>`, `resource.<id>.<value>` and
  `failure.<index>`.
- The session looks those keys up when it builds the view, so an English run
  reads English in the menu, the rank, the labelled resources and the reason a
  run ended. The render layer did not change.
- Sanguo and Jianghu ship the new section, so both English runs are complete.

### Changed

- `V-22` measures the same keys. A package that ships a table for a locale must
  translate every action, rank, labelled value and failure it declares, because a
  table that covers the scene and forgets the menu is the half-translation the
  check already refused.
