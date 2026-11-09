### Added

- an `assets` layer now reaches the run: its declared pictures, sounds and text
  are merged into the bundle's lookup at assembly time (`B92`).

### Fixed

- two applied layers carrying the same asset path are refused with `V-45` before
  the run starts, instead of one silently winning;
- the guide no longer says a non-bundle target is accepted, and names the three
  dimensions that still do nothing.
