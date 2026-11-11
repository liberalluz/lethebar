### Fixed

- `publish.py` refuses a tag that is not the engine version. Its note and
  evidence paths are keyed by version alone, so a `pack/<id>/v<version>` tag
  would publish a pack under the engine's note and evidence; a pack keeps those
  in its own repository.
