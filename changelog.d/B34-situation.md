### Added

- `Session.situation()` reads how a run stands: the turns left from the declared
  budget, the entity the others lean toward and the one they push against from
  the sum of the relations each receives, and the resource closest to its
  declared floor (`REQ-033`).
- The scene prints that reading as one more segment of the readout line, through
  `ui.turns_left`, `ui.leaning`, `ui.friction` and `ui.tight`, in both languages.

### Changed

- A section whose source is not declared is left out instead of being filled with
  a zero, so a story without factions or phases reads exactly as it did before.
