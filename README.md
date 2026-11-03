# Lethebar

English · [简体中文](README.zh-CN.md)

> An engine that ships no gameplay, plus a set of plugins that carry both the story and the rules for playing it.
> Change the story without rebuilding the engine; change the rules without rebuilding the story.

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE) [![Engine](https://img.shields.io/badge/engine-Godot%204-478cbf.svg)](https://godotengine.org)

## Status

**v0.0.1 is out and playable in a browser.**

- Two built-in stories ship with it: `sanguo` (three decision rounds, `turn_based@1`) and `xiuxian` (a five-scene segment, `linear@1`)
- It also installs a `.zip` pack from your own disk, keeps three save slots per pack, and reopens offline
- The interface speaks English and Chinese; a pack can carry its own text tables, so `sanguo` reads in either language
- A pack can declare pictures and sound, and a scene draws them; `sanguo` ships a painted scene and a short theme
- Verified on desktop Chrome and on iOS Safari, online and with the network off
- Known gaps: only PNG, JPEG and WAV; one picture band and one portrait column; `xiuxian` still carries Chinese text only
- Next: `v0.1.0` opens the pack format to the eight content bricks

This repository is public now because the plugin spec should be seen and challenged early.

## What it does

- **Four layers, one dependency direction** — engine (rules runtime + render runtime), plugin layer (career packs, category packs, mechanics mods), asset layer, meta config. The engine never knows a specific gameplay.
- **A pack is data, never code** — a pack is a plain zip with a `manifest.json`; the engine interprets the protocol the pack declares and refuses to execute code shipped inside it.
- **One engine, several ways to play** — the protocol registry ships `linear@1` and `turn_based@1`; switching packs never touches the engine.
- **Reproducible sessions** — same choices, same result; the seed is derived from the pack id and the starting counter, never from the wall clock.
- **Offline, with saves** — once loaded, a reload still opens new sessions and existing saves; three save slots per pack.

## Quick start

```bash
git clone https://github.com/liberalluz/lethebar.git
cd lethebar
python infra/stage_builtin.py                  # stage built-in packs into app/
godot --path app --headless --quit              # import assets; creates app/.godot/ (git-ignored)
godot --path app --headless -s res://tests/run_tests.gd   # rule-layer assertions
```

All three commands only check things. To play it, open the exported build or
`https://liberalluz.github.io/lethebar/`.

## Commands

| Command | What it does |
|---|---|
| `python infra/checks/check_changelog.py` | Fail when a branch has a `feat` or `fix` commit without a new `changelog.d/` fragment |
| `python infra/checks/check_tree.py` | Verify the repository layout: root entries, and no tracked generated files |
| `python infra/stage_builtin.py` | Pack `content/builtin/*` into `app/builtin/*.zip` before tests or export |
| `python infra/export_web.py` | Export the web build to `build/web/`; needs `GODOT_BIN` and `GODOT_TEMPLATE_APPDATA` |
| `python infra/verify_web.py` | Load that build in headless Chrome and report console output; needs `node` |
| `godot --path app --headless --quit` | Import assets, rebuild `app/.godot/` |
| `godot --path app --headless -s res://tests/run_tests.gd` | Rule-layer assertions (protocol, assembly, save encoding) |
| `python infra/tool/batch/batch.py` | Create the branch and checklist from a batch card |

There is **no CI yet**. The table above is the current gate: a local pass is the only pass. Once CI exists, this table must change in the same PR as the workflow.

## Project structure

| Directory | Responsibility |
|---|---|
| `app/` | The Godot project root (`project.godot`) and the engine: `core/` (rules runtime), `protocols/` (protocol registry), `render/` (render runtime), `ui/`, `tests/` (headless assertions) |
| `content/` | Built-in plugin packs and their data, one directory per pack |
| `infra/` | Build, export and deployment scripts, including `stage_builtin.py` |
| `infra/tool/` | Vendored Nebula tooling: batch execution, repository policy, release |
| `docs/` | Specs, decisions, intent ([docs/README.md](docs/README.md)) |

## Architecture

The engine has two layers: the **rules runtime** decides how a session advances, the **render runtime** decides how it is presented. The plugin layer sits above both and joins by declaring which capabilities it uses (`dimension`, `requires`) instead of shipping its own renderer. Dependencies flow one way only: `render → session → protocol → data`.

See [SDD](docs/specs/controlled/SDD.md) for detail and [ADR-0001](docs/decisions/0001-engine-and-language.md) for why it is built this way.

## Plugin format

A pack is a plain zip with a `manifest.json` at its root: `id`, `version`, `specVersion`, `engine`, `protocol`, `capabilities`, `mechanics`, `entry`, `saveSchema`, `assets`.

The engine validates a pack against `V-01`…`V-09` on load: missing assets warn without crashing, an invalid pack is rejected while the game stays usable. See [SDD §3](docs/specs/controlled/SDD.md), [ADR-0002](docs/decisions/0002-plugin-package-zip.md) and [ADR-0003](docs/decisions/0003-plugins-carry-data.md).

## Documentation

| Looking for | Where |
|---|---|
| Why this exists | [docs/intent/](docs/intent/) |
| How it should be | [docs/specs/](docs/specs/) |
| What was decided and rejected | [docs/decisions/](docs/decisions/) |

Where a document goes: how it should be → `specs/`; decided or not → `decisions/`; why → `intent/`; how to operate → `runbooks/`.

## Contributing

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a PR
- Changing code with AI? Read [CONTRIBUTING.ai.md](CONTRIBUTING.ai.md) too: AI changes need a human reviewer plus tests or evidence, and the author cannot self-approve
- For plugin-spec feedback, paste a draft `manifest.json` into an issue — it beats abstract discussion

## Security

See [SECURITY.md](SECURITY.md). Plugin packages are treated as untrusted input.

## License

The engine is licensed under the [Apache License 2.0](LICENSE): commercial use and redistribution are allowed, provided copyright notices and [NOTICE](NOTICE) are kept.

Third-party dependencies and assets are credited in [NOTICE](NOTICE). Plugin packs are licensed by their own authors and are not covered by this repository's license.
