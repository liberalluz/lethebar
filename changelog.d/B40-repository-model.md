### Added

- `ADR-0012` gives a package an optional `collection` (`{id, names}`) and fixes the
  shelf as a world page above the pack list, skipped when only one world exists.
- `ADR-0013` gives a session an assembly: an ordered package list, three merge
  semantics, an acyclic layer chain, `V-33`–`V-35` for conflicts, and the assembly
  recorded in the save.
- `ADR-0014` records the four phases a mechanism mod passes through, from a field in
  its own package to a listed marketplace variant, and the hard line that a mod only
  changes what is declared.

### Changed

- `ADR-0010` is cut by world, not by genre: a theme repository holds packs, a genre
  repository holds material (example, template, acceptance list), and neither holds
  code. The card battle now moves into `lethebar-game-sanguo`, not into a repository
  of its own.
- `ADR-0011` records `collection` and `layer`, resolves a composition before install
  rather than one file, and reviews by `kind`.

### Fixed

- The five decision records that had lived only in a conversation now exist in the
  repository, so the model can be read instead of remembered.
