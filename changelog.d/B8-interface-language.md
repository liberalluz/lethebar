### Added

- `app/i18n/en.tsv` and `app/i18n/zh_CN.tsv`, the two interface catalogues.
- a language switch on the landing screen; the choice is stored and survives a
  reload.

### Changed

- every interface sentence now comes from `Locale.text()`, so `app/render`
  holds no user-visible text of its own.
