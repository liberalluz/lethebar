### Fixed

- `check_pack.py` now enforces the engine's own envelope: 500 entries and 4 MiB
  per file, not the older 512 and 8 MiB the guide had copied. A pack that
  passed the author-side check could previously fail the install with `V-28`.
- The resumed-numbers case is `TC-SAVE-005`; `TC-SAVE-003` already names the
  durability case in the controlled test plan, and two cases no longer share
  an id.
