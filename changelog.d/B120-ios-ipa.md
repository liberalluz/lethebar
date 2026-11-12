### Fixed

- The iOS exporter prints the ipa path from one module constant, so
  `main()` no longer references a local that `build_commands()` owns.
- `--self-test` checks the constant's name and parent.

### Changed

- The gate runs `python infra/export_ios.py --dry-run`, so a dangling
  name in the exporter's entry point fails on Windows before macOS.
