# B15 — package format 2.0.0

### Added

- A package says which format it speaks, whether it is playable on its own
  (`kind: bundle`) or a piece another package requires (`kind: layer` with a
  `layer` name), and what it needs (`requires`), as ADR-0007 settles.
- The installer refuses a package whose `kind`/`layer`/`requires` are malformed
  (`V-23`) or whose requirement is missing or outside its range (`V-24`), and
  says which package and which version it wanted.
- The built-in stories declare format `2.0.0` with no requirements, so what
  players install is the shape the format asks for.

### Changed

- A package that still declares `1.0.0` installs and carries one `W-01`
  warning; from v0.2.0 on it is refused.
