### Added

- `docs/guide/repositories.md` says what a package is: the two `kind` values,
  why every run needs exactly one bundle, the six dimensions a layer can fill,
  the three refusals the assembler makes, and the naming rule that puts the world
  first and the form nowhere.
- `docs/guide/repositories.md` shows one repository holding two bundles and two
  layers, and says which row of the interface each one appears on.

### Changed

- `docs/guide/pack-anatomy.md` sets the minimal manifest of a bundle beside the
  minimal manifest of a layer, and adds the three questions that tell them apart.
- `docs/guide/manifest.md` explains how `kind`, `layer` and `target` depend on
  each other, including the asymmetry that a `layer` on a bundle is ignored while
  a `target` on a bundle is refused, and closes with what this build does not
  honour yet.
