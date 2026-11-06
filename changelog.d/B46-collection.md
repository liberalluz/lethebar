### Added

- A package may declare `collection: {id, names}`, the world it belongs to,
  and the landing screen offers worlds before packs (PR 85).
- A world title comes from the package that declares it and follows the
  interface locale; a world two packs word differently keeps one title, taken
  from the pack whose id sorts first.

### Changed

- `start_game()` opens the world screen only when more than one world holds
  packs, so a repository with a single theme keeps its click count.

### Fixed

- A pack that names a world with a malformed id or no titles is refused at
  install with `V-32` instead of showing up in a world nobody can name.
