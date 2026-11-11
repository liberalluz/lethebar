# Lethebar

English · [简体中文](README.zh-CN.md)

> An engine that ships no gameplay, plus packages that carry both the story and
> the rules for playing it.
> Change the story without rebuilding the engine; change the rules without
> rebuilding the story.

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE) [![Engine](https://img.shields.io/badge/engine-Godot%204-478cbf.svg)](https://godotengine.org)

## Status

**v0.8.0 is out: a package can remember across runs, and a roll is the same in the same turn.**

The engine still ships one smoke pack, `duel`, so that its own tests have something to open. Every other pack is published from its own repository, and [the marketplace](https://liberalluz.github.io/lethebar-marketplace/) lists what is published.

## What it is

- **An engine, not a game.** It owns the rules runtime, the render runtime and the save format. Every story, every rule and every picture comes from a pack.
- **A pack is data.** A pack is a zip with a `manifest.json`; the engine reads it, checks it, and refuses to execute code shipped inside it.
- **A run is one bundle plus zero or more layers.** The bundle supplies the story and the rules; a layer changes one part of it — `content` says how the story reads, `mod` changes what the numbers do, `assets` replaces pictures and sound.
- **The same save replays the same run.** The seed comes from the package id and the starting counter, never from the wall clock, and a roll inside one turn does not reroll. It plays in the browser and keeps playing offline after the first load.

## Architecture

Three runtimes share one data layer: the **rules runtime** (`app/core/session.gd`, `protocols/`, `bricks/`) decides how a session advances, the **render runtime** (`app/render/`, `app/ui/`) decides how it is drawn, and the **data layer** (`manifest_schema`, `package_validator`, `package_loader`) decides what a pack may say.

Dependencies flow one way: `render → session → protocols/bricks`, and everything above reads the data layer rather than the reverse. There are four extension points — a protocol, a brick, a capability, a layer — and the pack format is the only contract between them.

See [the architecture page](docs/specs/architecture.md) and [ADR-0001](docs/decisions/0001-engine-and-language.md).

## Play

Open [the web build](https://liberalluz.github.io/lethebar/) or an exported build, then install a pack from the packs page: download the zip from the pack's release, pick it as a file, and play. Installing straight from a release URL is not offered, because GitHub does not send a CORS header with its release assets and the browser refuses the fetch. Each pack gets three save slots; once loaded, the build keeps playing offline.

## Quick start

```bash
git clone https://github.com/liberalluz/lethebar.git
cd lethebar
python infra/stage_builtin.py                              # stage built-in packs into app/
godot --path app --headless --quit                          # import assets; creates app/.godot/ (git-ignored)
godot --path app --headless -s res://tests/run_tests.gd     # rule-layer assertions
```

To build the browser bundle, `python infra/export_web.py` (it needs `GODOT_BIN` and `GODOT_TEMPLATE_APPDATA`).

Writing a pack? Start at the [author guide](docs/guide/README.md). The two packs in [`templates/`](templates/) are small enough to read in one screen, and [`lethebar-pack-template`](https://github.com/liberalluz/lethebar-pack-template) is a repository to start from with the gate already wired.

## Project structure

| Directory | Responsibility |
|---|---|
| `app/` | The Godot project and the engine: `core/` (rules runtime), `protocols/`, `render/`, `ui/`, `tests/` |
| `content/` | The built-in smoke packs, one directory per pack |
| `infra/` | The batch runner, checks, release and export tools, and the web stack |
| `docs/` | Intent, specs, decisions, the author guide and the runbooks |

## Documentation

| Looking for | Where |
|---|---|
| Why this exists | [docs/intent/](docs/intent/) |
| How it should be | [docs/specs/](docs/specs/) |
| What was decided and rejected | [docs/decisions/](docs/decisions/) |
| How to write a pack | [docs/guide/README.md](docs/guide/README.md) |
| How to cut a release | [docs/runbooks/release.md](docs/runbooks/release.md) |

## Contributing

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR.
- Changing code with AI? Read [CONTRIBUTING.ai.md](CONTRIBUTING.ai.md) too: AI changes need a human reviewer plus tests or evidence, and the author cannot self-approve.

## Security

See [SECURITY.md](SECURITY.md). A pack is untrusted input: the engine validates it before install and again before a run.

## License

The engine is licensed under the [Apache License 2.0](LICENSE): commercial use and redistribution are allowed, provided copyright notices and [NOTICE](NOTICE) are kept.

Third-party dependencies and assets are credited in [NOTICE](NOTICE). Packs are licensed by their own authors and are not covered by this repository's license.
