### Removed

- The engine no longer ships the 三国 and 修仙 stories: `content/builtin/` holds
  `duel` only, and both worlds arrive as packages from their own repositories.
  `TC-BUILTIN-001` and `TC-BUILTIN-002` left with them, and their assertions now
  live in the world repositories' gates as `TC-WORLD-001` and `TC-WORLD-002`.

### Changed

- `REQ-014` asks for one smoke story instead of a built-in 三国, `REQ-015` says
  the two worlds ship as external packages, and `REQ-034` describes the released
  package rather than one compiled into the engine.
- The shell cases that used to open 三国 now open `duel`, so the engine is still
  proven without a world: `TC-UX-001`, `TC-SAVE-002`, `TC-PKG-001`,
  `TC-INSTALL-001`, `TC-COLLECTION-001` and `TC-META-001`.

### Fixed

- Installing a world package used to fail with
  `V-03: already installed at 0.1.0; re-import that version or uninstall first`,
  because the engine shipped the same id at an older version and there is no
  uninstall control. With the built-in story gone, an external `sanguo` installs
  into a fresh engine.
