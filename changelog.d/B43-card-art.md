### Added

- A card may name a picture its package declares; the hand draws it beside the
  label at `CARD_ICON_SIZE` (REQ-037).
- `V-39`: a card naming an icon that no texture asset declares is refused at
  install, and the message names the missing path.
- `Shell.card_rows()` reports what the last scene drew for the hand, so the
  headless smoke test can assert on a picture without reading pixels.
- Six faces on the shipped `duel` cards, 64x64 PNG, one per card.

### Changed

- The `card` asset slot is skipped by the scene band instead of being reported
  as an unknown slot.
