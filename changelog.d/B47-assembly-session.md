### Added

- `PackageLoader.assemble()` resolves an ordered list of installed packages into
  the entries a session is built from, and refuses a name nothing installed
  provides with `V-33`.
- `Session` accepts `options.assembly`: the first package supplies the nodes,
  the phase machine and the entry, the rest may only add resources, actions,
  cards and pools.
- `TC-ASSEMBLY-001` opens one run from two packages and covers the merged view,
  the merged menu, the missing package and the duplicate key.

### Changed

- A key that two packages both declare keeps the earlier package's value and
  leaves one `W-05` naming the key, instead of silently overwriting.
- A save records the assembly when a run was opened from more than one package,
  so a resumed run rebuilds the same set; a single-package save keeps its old
  shape.
