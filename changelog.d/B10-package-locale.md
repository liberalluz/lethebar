### Added

- A package may declare `defaultLocale`, `locales` and `names`, and carry one
  table of text per language under `data/i18n/<locale>.json`. The Sanguo pack
  now ships English text for every node and choice.
- `V-22` refuses a package whose declared locale is unsupported, has no table,
  or leaves a node text or a choice label empty.

### Changed

- A new session plays in the language the interface is in, and falls back to the
  package's own text when the package carries no table for it.
- The pack list shows the pack's title in the current language when the manifest
  supplies one.
- The picture band now takes what the text and buttons leave over instead of a
  fixed share of the window, so a longer English scene keeps every button on
  screen.
