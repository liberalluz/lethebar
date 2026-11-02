### Added

- The web build installs a service worker that caches the whole payload on first
  load, so a reload with the network off still starts a game.
- The smoke check now drives the build with the network off: it reloads, starts a
  game, and reads back the save slot it wrote before going offline.

### Changed

- Saves and imported packs live in the engine's own storage (IndexedDB on the
  web build) instead of memory, so they survive a reload.
- A session is proven not to touch the network by counting browser requests
  during play, not by grepping the source for an HTTP client.

### Fixed

- Imported packs disappeared after a reload because the stored packages were
  never restored; they are restored at boot now.
- The screen's text column grew past the window when the text wrapped, which
  pushed every button, including "New game", below the fold.
