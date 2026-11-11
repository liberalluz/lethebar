### Fixed

- `errors.zh-CN.md` now carries the generated table's line numbers and the new file names, so it no longer points at `state.json` or `cards.json`.
- `SDD.zh-CN.md` has §11.19 and the four mapping rows it was missing, so the Chinese spec no longer stops at REQ-043.

### Changed

- `check_guide_pairs.py` compares version tokens, backticked `data/*.json` paths and REQ/TC codes between a page and its twin, not only the section count.
