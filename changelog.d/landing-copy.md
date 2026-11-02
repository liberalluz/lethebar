### Added

- `Continue` on the landing screen lists every saved run in this browser - each
  row names its story, its slot, a preview of the scene and the time it was
  written - and opens that pack exactly where the player stopped. It only
  appears when something is saved.

### Changed

- The landing screen is a way in again, not a menu: one line says what the game
  is, then `New game` leads to the stories. Listing the stories on the landing
  screen made every visit start with a choice before the player saw the game.
- The pack list shows each pack's own name and hides the protocol identifier:
  `sanguo — turn_based@1, 0.1.0` read like a turn-based strategy game.
- The save screen says what a slot holds ("Saving keeps your place in this
  story"), and an unused slot reads "nothing saved yet" instead of "empty".
