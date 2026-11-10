### Added

- `check_pack.py` warns when a layer names a dimension this engine build does not apply, instead of staying silent until the author reads the guide.
- `check_commit_body.py` enforces the 72-column rule the conventions already state; a line whose longest token is a path or a URL is allowed to run long.
- `batch.py exit` writes a `Checks` section with the last gate result for every step and a `sha256` for each skill evidence file.
