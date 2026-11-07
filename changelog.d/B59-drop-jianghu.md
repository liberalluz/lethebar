### Removed

- The `jianghu` story, which demonstrated that a third pack could be written as data and then stayed as a dependency of every count in the specification documents, of every staging run, and of the release tool's own self-test.
- `TC-BUILTIN-003` and the case that opened the removed story, in both languages of the test plan and the test design.

### Changed

- `infra/tool/release/pack.py self-test` writes its own two-file fixture in a temporary directory instead of reading a shipped story, so the tool that proves the release pipeline no longer depends on content that is scheduled for removal.
- `TC-COLLECTION-001` builds its two worlds from `sanguo` and `xiuxian`, and `TC-META-001` covers the two stories that remain.
