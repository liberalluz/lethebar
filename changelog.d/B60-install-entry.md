### Added

- An install entry that takes a link as well as a file. `app/render/downloader.gd`
  fetches the bytes and `PackageLoader.import_url` hashes them before anything
  is written, so a truncated download stops at `V-01` and a wrong digest at
  `V-43`, both naming what disagreed.
- Three reported outcomes for an install: `installed`, `already` and `refused`.
  A refusal leaves the installed set untouched, and a link install with no
  digest is refused rather than trusted.
- `verify_web.py --min-packs N`: the browser check fails when the build offers
  fewer stories than asked for, which is how a batch that removes a story can
  prove the stories it kept still ship.

### Changed

- The pack list draws two entries where it drew one: `Install a pack (.zip)…`
  and `Install from a link…`.
- The probe reports `stories`, the count it read on the landing screen, so the
  check above has a number to compare.
