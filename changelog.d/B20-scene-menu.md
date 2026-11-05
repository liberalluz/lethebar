### Added

- A package that declares actions is playable: the scene draws one button per
  action, keeps an unavailable action visible and disabled with its reason, and
  shows the turn and the rank.
- `TC-SCENE-001` covers the six lines: the run opens with an empty choice list,
  every action is a button, an unavailable one is disabled, an action advances
  the turn and the rank, an ended run shows why and offers nothing, and a package
  without actions renders as before.

### Changed

- A run no longer ends merely because the node it lands on offers no choices when
  the package declares a phase machine; the phase machine's failure condition or
  turn limit ends it instead, which is what a menu-driven package needs.
