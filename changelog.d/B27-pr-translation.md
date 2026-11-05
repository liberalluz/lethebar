### Added

- `infra/tool/merge/translate_body.py`: translate a prepared pull request body and mark the result as a machine translation; `LETHEBAR_TRANSLATION_FILE` supplies the translation where no API key is available.
- `infra/checks/check_translation.py`: refuse a batch whose prepared body has no translation, or whose translation predates the last edit.

### Changed

- `infra/tool/batch/config.json`: `translate` runs the new hook, and `translation` joins the gate as an eighth check.

### Fixed

- `infra/tool/merge/pr_merge.py`: a single-commit pull request whose subject is longer than the seventy characters GitHub keeps in `messageHeadline` began its body with the cut remainder; the message now comes from the local commit, and a payload that cannot be repaired is refused instead of used.
