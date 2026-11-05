### Fixed

- A save now reports itself as pending until the storage layer says it has
  nothing left to flush, so the slot screen says "Saving…" before it says the
  slot is saved and a reload cannot outrun the write. Installing a package
  passes through the same gate.

### Changed

- The browser check waits for that state instead of sleeping two seconds before
  reloading, and it counts restored slots from the cross-pack list on the
  landing screen rather than from whichever pack it happened to open.