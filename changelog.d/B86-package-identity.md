### Fixed

- A package is a layer because its manifest says `kind: layer`, not because it
  carries a `target`. `Session.create` reads `kind` from the installed record, so
  a bundle that happens to name a target is merged as a bundle instead of having
  its actions disabled by the layer path (B86).

### Added

- The pack page can remove an installed package, or one of its layers, after a
  confirming second press. Before this, `V-03` refused a version that was already
  installed and offered no way back, so a pack installed once could never be
  replaced. Removing a base that still owns a layer is refused, and the refusal
  names the layers.
