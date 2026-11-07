### Added

- `infra/tool/release/preflight.py`: six numbered items that say what a pack
  repository is missing before it publishes — manifest, version and contract,
  artifact, descriptor, release, and whether a browser can actually fetch the
  asset. Each failure names the command that fixes it, and the last item fetches
  the published zip over the network instead of assuming it is reachable.
- `pack.py publish --apply` creates the release when the tag has none. `gh release
  upload` only attaches files to a release that already exists, so the first
  publication of every pack used to fail with `release not found`.
- `pack.py` validates a pack before it builds any command: a descriptor with no id
  or version is refused, and nothing reaches `gh`.

### Changed

- `pack.py` reads the GitHub client from `LETHEBAR_GH` (default `gh`), which is
  what lets a test prove that the create runs before the upload.
- The docstring example tags a pack as `pack/<id>/vX.Y.Z`, matching the release
  section of `docs/specs/git-conventions.md`.
- `preflight.py` and `pack.py` share the reachability rule: an asset that answers
  without `Access-Control-Allow-Origin` is reported, because a browser install
  depends on that header and a terminal does not.
