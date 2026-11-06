# ADR-0010 · The engine repository is not the game repository

Amended: 2026-11-06 — repositories are cut by world, not by genre; a genre
repository holds material, never a runtime.

## Context

This repository contains the engine (`app/`), the contracts (`docs/specs/`), the
tooling (`infra/`, `tools/`), the decisions, and three built-in stories under
`content/builtin/`. The stories are convenient: they give the test suite
something real to load, and they are what a first player picks from.

They are also the thing that will not scale. A card battle needs new engine
behaviour and a hundred cards of content. A map-based strategy game needs a
runtime that does not exist yet and art that has nothing to do with narration.
Keeping those in the engine repository would mean: a format change re-runs every
game's tests; a content fix bumps the engine version; and a contributor who wants
to write a story must read the engine first.

## Decision

**The engine repository carries the engine, the contracts, the tooling and at
most two smoke packages.** It carries no world's content and no world's art.

**A game repository carries content only.** `content/`, assets, translations,
the world's own release notes. It does not carry engine code and cannot modify
the engine.

**A repository is not a package.** One game repository may ship several packages.

```
lethebar-game-sanguo/
  shared/                 officer tables, place names, portraits, glossary
  packs/sanguo-tale/      manifest + data             -> build/sanguo-tale.zip
  packs/sanguo-cards/     manifest + data + card art  -> build/sanguo-cards.zip
  packs/sanguo-war/       manifest + data + map art   -> build/sanguo-war.zip
```

The packages share the tables, so a corrected officer number is corrected once.
One CI builds all three. Three packages, one repository, one version number.

### Two kinds of author repository

A genre is a **capability**, and a capability lives in the engine (`ADR-0008`).
What a genre needs in a repository is not a runtime but the material that teaches
someone to write a package of that genre.

| Repository | Holds | Who it serves | Installable |
| --- | --- | --- | --- |
| `lethebar-game-<world>` | `shared/` and `packs/*`: worlds, art, translations | players | yes, each pack |
| `lethebar-genre-<genre>` | `example/`, `template/`, `acceptance/`, `notes.md` | authors | the example only |
| `lethebar-mod-<family>` | `mods/*`, each with `kind: mod` and a `layer` target | players, after `ADR-0013` | yes, as a variant |

A world repository may also carry built-in packs of several genres — that is the
normal case, not an exception. A genre repository is opened when a **second
author** wants to write in that genre, or when two worlds both need the same
template; opening it earlier means maintaining a tutorial nobody reads.

### Three hard lines

1. **No code in either repository.** `app/core` and `app/render` are the engine
   (`ADR-0009`). A repository that grows a `.gd` file has started a second engine.
2. **The capability comes first.** A genre repository can only teach what the
   engine already provides; a package that names a capability the engine lacks is
   refused at install (`V-27`).
3. **Material is copied, assets are depended on.** A world copies a genre's
   template once and owns the result, so a template change never forces a world to
   release. Shared art is the opposite: it is published once and depended on by
   range, because two copies of the same portrait drift.

### How the three layers compose

A session is one engine plus up to three layers of package:

| Layer | Provides | May it add something new |
| --- | --- | --- |
| theme pack | world data: names, places, art, glossary | no, it fills declared fields |
| genre pack | the shape of play, through the capability it names | no, the shape is the engine's |
| mechanism mod | changes to fields another layer already declared | **no** — it changes, it never adds |

Composition is only real once the assembly layer exists (`ADR-0013`); until then
a device installs several packages and plays them one at a time. The mod phases
are recorded in `ADR-0014`.

**Names, and what each one is for:**

| Repository | What it is |
| --- | --- |
| `lethebar` | the engine, the contracts, the tooling |
| `lethebar-docs` | design, plan, records — the material that is worth more than the code |
| `lethebar-game-<world>` | a world: shared tables and one pack per genre it ships |
| `lethebar-genre-<genre>` | material for one genre: example, template, acceptance list |
| `lethebar-mod-<family>` | a family of mods over the same targets (after `ADR-0013`) |
| `lethebar-marketplace` | the index a player or author can browse (later) |

A repository name is for people; a package id is for the engine. `lethebar-game-sanguo`
may ship `liberalluz.sanguo-cards`; the two are deliberately unrelated, so a package can
move between repositories without renaming anything.

**How a game repository consumes the engine:** the engine publishes a build
artifact; the world's manifest states an engine range and the capabilities it
needs (`ADR-0008`). During development the world runs against a local engine
checkout by path override, and the range is what a release is verified against.
Without that split between "develop" and "release", the first day of the split is
the day someone wants to merge it back.

**The split happens when all four of these hold, not on a date:**

1. The capability contract and the trust envelope are implemented and the
   capability list has not changed for two consecutive batches.
2. A non-narration genre (card battle) runs inside the engine repository, proving
   that a world repository can hold more than one genre.
3. The engine produces a reusable artifact and a world can state a version range
   against it.
4. The engine's own assertions no longer depend on every built-in story: one smoke
   package is enough to prove the pipeline.

**Order:** the world repository first — `lethebar-game-sanguo`, because it has the
most content and therefore proves the multi-genre layout. `lethebar-game-xiuxian`
follows. Genre material repositories open only when a second author appears; mod
repositories only after the assembly layer lands.

## Consequences

- The reading order is `0008` (what a capability is), `0009` (what a package may
  trust), this record (where repositories sit), `0013` (how several packages become
  one session), `0014` (when a mod may stand alone) and `0011` (what the market
  records). Each links to the next; a newcomer who reads them in order ends up with
  the model the project runs on.
- The engine's test suite shrinks to one smoke package, and genre behaviour is
  proved in the world's repository. That is a real loss of coverage in the engine
  repository and must be paid for by a smoke test that still exercises every
  pipeline stage.- A change that touches both engine and content becomes two pull requests in two
  repositories, in a fixed order (engine first, released, then the game).
- A world repository has to run its own gates per pack: one pack failing must not
  hide another, and a version bump is shared even when only one pack changed.
- `docs/specs/git-conventions.md` and `check_tree.py` will need to know about the
  new arrangement when the split happens; doing it early is what this record
  postpones.
- The built-in stories stay in this repository until the split, and then move in
  one commit each, with a pointer left behind.

## Alternatives considered

- **One repository per package.** Rejected: shared officer tables and portraits
  would be copied three times and drift, and three CIs would be maintained to ship
  what is one product.
- **One repository per genre.** Rejected as the default: it splits one world's art
  across several repositories, so a three-kingdoms portrait ends up in the card
  repository while the map that uses it ends up in the strategy one. The genre axis
  survives as material, not as the place worlds live.
- **One monorepo forever.** Rejected: it ties the engine release cadence to content
  work, and makes "contribute a story" require the engine's build tooling.
- **Git submodules for the engine.** Rejected as the primary mechanism: submodules
  pin a commit, not a range, so a game would be stuck at whatever engine commit
  someone last updated, and an engine fix would require touching every game.
