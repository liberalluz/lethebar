### Added

- A hand is laid out in rows of as many cards as the window fits, so a long hand
  wraps instead of pushing the card faces and the menu below the fold.
- The number of cards per row is measured from the window width
  (`Shell.hand_columns()`), so a resized window re-wraps the same hand.
- A card that shares a row has its label cut at `HAND_LABEL_CHARS` with an
  ellipsis; a hand that fits on one row keeps the whole label.
- `TC-HAND-001` covers the wrap: eight cards take more than one row at 600 px,
  every card is laid out once, a wider window needs fewer rows, and a short hand
  keeps its whole label.
