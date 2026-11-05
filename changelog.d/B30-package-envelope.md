### Added

- `V-28`, `V-29` and `V-30`: a package is held to an install-time envelope before the manifest is read, and every refusal names the value it measured.
- `app/core/package_limits.gd`: the limits and the pure helpers that read a PNG or JPEG header and a WAV duration, so the numbers live in one place.
- `TC-SAFE-001`: entries, paths, per-entry bytes, the unpacked total, picture edges and audio length are all exercised, and a package inside the envelope still installs.

### Changed

- ADR-0009 now carries the numbers instead of promising them, and `SECURITY.md` says what the envelope is.
