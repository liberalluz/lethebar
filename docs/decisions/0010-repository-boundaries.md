# ADR-0010 · The engine repository is not the game repository

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
most two smoke packages.** It carries no genre's content and no genre's art.

**A game repository carries content only.** `content/`, assets, translations,
the genre's own release notes. It does not carry engine code and cannot modify
the engine.

**A repository is not a package.** One game repository may ship several packages.

```
lethebar-game-sanguo/
  shared/            officer tables, place names, portraits
  packs/sanguo/      manifest + data + its own art   -> build/sanguo.zip
  packs/chibi/       manifest + data + its own art   -> build/chibi.zip
  packs/guandu/      manifest + data + its own art   -> build/guandu.zip
```

The packages share the tables, so a corrected officer number is corrected once.
One CI builds all three. Three packages, one repository.

**Names, and what each one is for:**

| Repository | What it is |
| --- | --- |
| `lethebar` | the engine, the contracts, the tooling |
| `lethebar-docs` | design, plan, records — the material that is worth more than the code |
| `lethebar-game-<slug>` | a built-in genre game, one or more packages |
| `lethebar-template-<slug>` | a starting point for authors, not a game |
| `lethebar-marketplace` | the index a player or author can browse (later) |

A repository name is for people; a package id is for the engine. `lethebar-game-sanguo`
may ship `liberalluz.sanguo`; the two are deliberately unrelated, so a package can
move between repositories without renaming anything.

**How a game repository consumes the engine:** the engine publishes a build
artifact; the game's manifest states an engine range and the capabilities it
needs (`ADR-0008`). During development the game runs against a local engine
checkout by path override, and the range is what a release is verified against.
Without that split between "develop" and "release", the first day of the split is
the day someone wants to merge it back.

**The split happens when all four of these hold, not on a date:**

1. The capability contract and the trust envelope are implemented and the
   capability list has not changed for two consecutive batches.
2. A non-narration genre (card battle) runs inside the engine repository, proving
   that "one genre, one repository" is workable.
3. The engine produces a reusable artifact and a game can state a version range
   against it.
4. The engine's own assertions no longer depend on every built-in story: one smoke
   package is enough to prove the pipeline.

**Order:** the card battle repository first, because it is data-only and cheap.
The strategy branch waits until it is actually scheduled.

## Consequences

- The engine's test suite shrinks to one smoke package, and genre behaviour is
  proved in the genre's repository. That is a real loss of coverage in the engine
  repository and must be paid for by a smoke test that still exercises every
  pipeline stage.
- A change that touches both engine and content becomes two pull requests in two
  repositories, in a fixed order (engine first, released, then the game).
- `docs/specs/git-conventions.md` and `check_tree.py` will need to know about the
  new arrangement when the split happens; doing it early is what this record
  postpones.
- The built-in stories stay in this repository until the split, and then move in
  one commit each, with a pointer left behind.

## Alternatives considered

- **One repository per package.** Rejected: shared officer tables and portraits
  would be copied three times and drift, and three CIs would be maintained to ship
  what is one product.
- **One monorepo forever.** Rejected: it ties the engine release cadence to content
  work, and makes "contribute a story" require the engine's build tooling.
- **Git submodules for the engine.** Rejected as the primary mechanism: submodules
  pin a commit, not a range, so a game would be stuck at whatever engine commit
  someone last updated, and an engine fix would require touching every game.
