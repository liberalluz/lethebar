# changelog.d

One fragment per `feat` or `fix` pull request. It is written in the same pull
request as the change, not at release time.

- Name it after the batch or the change: `b3-turn-based.md`,
  `web-build-verification.md`.
- Use one Keep a Changelog heading per section, then one `- ` bullet per
  user-visible change: `### Added`, `### Changed`, `### Fixed`, `### Removed`.
- Write what a reader of the release notes needs, not which files moved.
- `python infra/checks/check_changelog.py` fails when a branch carries a `feat`
  or `fix` commit without a new fragment.
- At a release the fragments are folded into `CHANGELOG.md` under the version
  heading, and the fragment files are deleted in the pull request that tags it.
