### Added

- `cards.hand@1` — a package declares a hand, a small deck and its cards, and the engine deals,
  plays, discards and draws them.
- `app/core/hand.gd` — reads the declaration (`hand.size`, `hand.draw_per_turn`,
  `hand.reshuffle`, the `cards` table, the opening `deck`), deals the opening hand and refills it.
- `Session.play_card()` — spends the cost, applies the effects through the same clamping the rules
  use, discards the card, draws a replacement and advances the turn by one.
- `V-36`, `V-37`, `V-38` — a claimed `cards.hand@1` without a deck file, a card naming a resource
  the ledger never declares, and a deck naming a card the package never declares are refused at
  install with a message that names the missing thing.

### Changed

- The scene draws the hand above the action menu, keeps a card it cannot pay for on screen with
  the reason and disables it, and the reason names the resource that is short (`S-08`).
- `snapshot()` carries `hand`, `deck` and `discard` only when the package declares a hand, and a
  resume puts all three back before the scene is drawn.
