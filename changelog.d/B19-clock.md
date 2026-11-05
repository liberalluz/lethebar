### Added

- A package can declare `clock.per` and a rule can read the engine tick, so
  content that grows per turn no longer has to fake a counter with resources.
- `TC-CLOCK-001` asserts the tick, both advance modes, the save, and the two
  refusals.

### Changed

- The tick travels in the save payload, so a resumed run continues counting from
  where the player left instead of starting over.
