### Added

- A rule may carry `relations`, a list of `{from, to, add|value}` entries: the
  mechanics layer collects them and the session applies them, so the faction
  map still has one writer (`REQ-032`).
- `V-31`: a relation change that names an entity the package never declared, or
  carries something that is not a number, is refused at install.
- The save payload carries `factions`, so a moved relation survives a save and a
  resume.

### Changed

- `Mechanics.apply()` returns a `relations` list next to `state` and `warnings`;
  packages that write no relation behave exactly as before.
