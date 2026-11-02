### Fixed

- Pack text renders in the browser. The engine shipped its built-in font, which
  has Latin glyphs only, so every Chinese string in `sanguo` and `xiuxian` drew
  as a box; a player could start a game and see nothing readable.

### Added

- `app/render/fonts/NotoSansSC-Regular.woff2`: one Noto Sans SC subset
  (SIL OFL 1.1) owned by the render layer and shared by every pack, so a pack
  carries its text and never a font. Coverage is `U+4E00-9FFF` plus punctuation,
  ASCII and Latin-1; rare ideographs outside it still fall back to boxes.
- A headless check that fails when a character a shipped pack can show — or a
  character the shell puts on screen — has no glyph in the font the project
  ships. String assertions passed while every Chinese line was unreadable, so
  the coverage is now asserted on characters rather than trusted.
- `PROBE_SHOT=<path>` on the smoke probe writes the first scene as a PNG, for
  the parts of the picture a person has to read.
