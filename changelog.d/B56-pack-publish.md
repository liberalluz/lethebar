### Added

- `infra/tool/release/pack.py` builds a pack directory into a reproducible zip, writes a descriptor with the id, version, bytes, sha256, `specVersion` and engine range, and uploads both to a release (dry by default).
- `PackageLoader.import_url(url, expected_sha256, context, fetch)` installs a downloaded pack after checking its digest, and `PackageLoader.digest_of(bytes)` is the shared hash.
- `V-43` refuses bytes whose hash differs from the expected value, naming the url and both digests.

### Changed

- Nothing in a run changes: the new path ends in the same `import_bytes` every install already used.
