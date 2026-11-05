### Added

- `V-27`: a package that asks for a capability this engine does not provide is refused at install, and the refusal names the capability (ADR-0008).
- `W-03`: a format 1.0.0 package that still names a capability without its major version installs with one warning, so nothing published before this batch stops working.
- `docs/specs/capabilities.md` now lists the twenty ids this build accepts, and the table is read back by the test instead of being copied.

### Changed

- The `capabilities` field is versioned: `text` became `text@1`, `render.2d` became `render.2d@1` in the three built-in packages and in every test fixture.
