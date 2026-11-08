### Changed

- The cultivation pack is called `cultivation` everywhere. `SDD` section 10.2 lost the
  pinyin in both languages, `ADR-0007` names the pack the same way the repository does,
  and `ADR-0010` points at `lethebar-game-cultivation`.
- `ADR-0012` draws its worked example with `cultivation` instead of `xiuxian`, so the
  two-level menu example matches what a reader can install.

### Note

- The rename breaks the save key of the built-in copy that `B65` removed: those keys
  were `save:xiuxian:<slot>`. No published package ever used the pinyin.
