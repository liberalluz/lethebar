### Added

- `docs/guide/bricks.md`: the eight bricks, each one named with the data file
  that turns it on and the engine file that reads it.
- `docs/guide/protocols.md`: the two protocols the engine implements, and a
  section saying that `cards.hand@1` is a capability rather than a third one.
- `docs/guide/errors.md`: every refusal code with the line that raises it and
  the sentence a player sees, generated from the source.
- `templates/pack-turn/`: a turn-based template with a menu, a limited run and
  two ranks, next to the linear one.
- `infra/checks/check_guide.py` now builds, installs and plays both templates,
  so a template that stops installing breaks the gate.

### Changed

- `infra/tool/docs/gen_guide.py` fills five tables across four pages instead of
  two tables on one page; the brick and protocol tables fail the generator when
  the source loses a file or a protocol it describes.
