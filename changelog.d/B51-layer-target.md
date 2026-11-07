### Added

- A layer package names the package it edits in its own manifest: `target` is
  required when `kind` is `layer`, and an assembly entry may still carry one that
  wins over the manifest.
- `V-35` refuses two layers that write the same field of the same target, naming
  both layers, the kind of field and its id.

### Changed

- A package whose `kind` is not `layer` is refused with `V-23` when it declares a
  `target`, because that reads as a layer that forgot to say so.
