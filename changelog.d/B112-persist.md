### Added

- `persist@1`: a package may declare a small table that survives across runs
  (`manifest.persist`), write it with `persist.<key>` effects and read it from
  rules. It lives outside the save snapshot, so a replay does not change it.
- `V-47` refuses a table that is over 32 keys or 4 KiB, mistyped, or declared
  without the `persist@1` capability.
