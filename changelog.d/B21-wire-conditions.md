### Added

- An action can wait on a relation state the package declares, and on an item a
  run has already drawn; both read the same numbers the scene shows.
- An action can draw from a pool as part of itself, so the draw and the action's
  own effects commit in one step and the item unlocks whatever waited on it.
- Validation codes V-25 and V-26 refuse a condition that names a state or an item
  the package never declared, and a draw that names a pool it never declared.
- Test case TC-WIRE-001 covers the two gates, the joined draw, a save and resume,
  and both refusals.

### Changed

- The readout names the items a run has drawn, because the player can now act on
  them.
