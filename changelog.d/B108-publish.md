### Fixed

- `pack.py publish` reads the release before it writes: an asset that is already there with the same hash is left alone, a missing one is uploaded, and one that differs is refused unless `--force` is passed.
- The `pack.py` docstring no longer promises byte-identical builds on every platform; it promises them under the same Python and zlib, and points at the descriptor as the thing a player verifies.
- `package_loader.gd` no longer describes a fallback name that does not exist.

### Changed

- The guide states the data-id grammar (`^[a-z][a-z0-9_]*$`, `V-16`) and what a re-run of `publish` does, in both languages.
