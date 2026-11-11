### Added

- `roll@1`: a bundle may declare named integer ranges in `manifest.rolls`; rules
  read `roll.<name>` and effects spend one with `{"key": {"add_roll": "name"}}`.
  The value is derived from the seed and the turn, so a reload cannot reroll it,
  and it does not advance the hand or pool stream.
- `V-48` refuses a roll that is not an integer range, a range over one million,
  more than sixteen rolls, or `rolls` without the capability.
- Saves now carry `seed`; a payload from before this batch falls back to `rng`.
