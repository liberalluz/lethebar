### Added

- A reshuffle can ask the session for an order: `Hand.draw_into()` takes an optional
  callable and keeps play order when no callable is given, so the function stays a
  pure function of what it is handed.
- The session passes `_shuffle_cards()`, a Fisher-Yates pass over the run's own
  seeded generator, so one seed deals one order and another seed does not.

### Changed

- A package that allows a reshuffle now gets a shuffled deck instead of the discard
  pile in the order the cards were played. No package format field changed, and no
  package needs to be rebuilt.
