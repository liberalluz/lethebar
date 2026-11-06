### Added

- An assembly entry may carry a `target` beside its id. A package that does so is a
  layer: it edits the package it names instead of adding another story, so one base
  can be played with and without the rule change it declares (REQ-042).
- `data/disable.json` lets a layer remove actions, pools, cards and resource
  definitions by id, which is the one thing a package could not say before.
- `V-34` refuses a layer whose target is not in the same assembly, a layer that sits
  on itself, a chain that returns to a package it already touched, and a package
  named twice.

### Changed

- `PackageLoader.assemble()` accepts either a package id or an `{id, target}` record
  and resolves the layer chain in list order, base first.
- A session copies the lists it is handed. It used to share the arrays held by the
  installed package, so appending an action for one run changed the package for the
  next one — the layer work would have made that visible, the fix belongs here.
