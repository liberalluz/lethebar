### Added

- `pack.py badge --fold` and `--flat` choose the table's shape once; `--write`
  keeps the shape a file already has, so a version bump cannot unfold a table
  someone folded on purpose.

### Fixed

- `publish.py` no longer falls back to a changelog section. A release body is
  the player note at `product/release-notes/<version>.en.md`, and a missing note
  stops the release instead of publishing a batch list under a player-facing
  title.

### Changed

- `author-gate.yml` pins `ENGINE_REF` at `v0.7.2` and says what that line means:
  the engine release whose tools run, not the Godot range in a manifest.
