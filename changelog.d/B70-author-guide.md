### Added

- `docs/guide/pack-anatomy.md`, `docs/guide/manifest.md` and `docs/guide/publishing.md`: what a
  pack is, what every manifest field means, and the six commands that turn a directory into a
  release.
- `templates/pack-min/`: a pack small enough to read in one screen that installs, walks one choice
  and saves.
- `infra/tool/docs/gen_guide.py`: rewrites the field and vocabulary tables from the const arrays in
  `app/core/manifest_schema.gd`; `--check` reports drift instead.
- `infra/checks/check_guide.py`: checks the tables, builds the template, runs the envelope check and
  installs the zip in a headless probe. Wired into the gate as the `guide` step.
