### Fixed

- A run resumed from a save slot reads in the locale of the interface instead of
  falling back to the package's own text, so an English interface no longer opens a
  Chinese scene after `Continue`.

### Changed

- `SaveStore.resume()` takes the locale as an option. The save keeps the run, not the
  preference, so a payload written before this change still resumes — in the
  package's text.
