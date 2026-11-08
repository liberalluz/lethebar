### Fixed

- A save that recorded a layer now replays it as a layer. `InstallRegistry.entry()`
  copies the manifest's `layer` and `target` onto the record it returns, so a run
  rebuilt from a save keeps the actions the layer disabled and the definitions it
  overrode instead of treating it as one more additive package.

### Added

- `TC-ASSEMBLY-003`: a save written in a layered run, replayed through the
  registry the way the interface does it, still refuses the disabled action and
  still reads the layer's on the ledger.
