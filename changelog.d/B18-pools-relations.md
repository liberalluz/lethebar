### Added

- A package can declare item pools in `data/pools.json`: a draw takes the
  declared number of items and removes them unless the pool replaces them, and
  what is left travels in the save so a reload cannot re-roll it.
- `data/factions.json` declares directed relations between factions, with the
  state names supplied by the package through `thresholds`.
- `V-19` refuses a pool that lists an item twice or draws past its size without
  `replace`; `V-20` refuses a relation that points at an undeclared entity, and
  `W-02` reports a pair that disagrees in direction without rewriting it.

### Changed

- A save now carries what is left of every pool and the order the session RNG
  fixed on its first draw, so a restored run draws the same way it would have.
