### Fixed

- An ideograph from CJK extension A (`U+3400-U+4DBF`) now draws as a glyph instead of a box: the
  shipped font covers that block as well as the BMP block it already covered.

### Changed

- The font subset is rebuilt from the full Noto Sans SC with `infra/build_font.py`, so the repertoire
  is reproducible instead of being whatever the last person happened to cut.
- The web payload grows from 3,473,468 to 4,142,764 bytes (`index.pck`), the only file that changes:
  the engine payload is byte-identical and keeps its cache name.
