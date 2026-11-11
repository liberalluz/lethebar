# One repository, several packs

English · [简体中文](repositories.zh-CN.md)

A world usually grows more than one pack: the main story, a second playable
variant, a content layer someone else wrote. They live side by side in the same
repository, and each one is released on its own.

```
your-world-repository/
├── packs/
│   ├── sanguo/          the base story, kind: bundle
│   ├── sanguo-cards/    another playable pack, kind: bundle
│   ├── sanguo-content/  a content layer, kind: layer
│   └── sanguo-hard/     a mod layer, kind: layer
├── infra/               the two tools, and whatever else you want
└── .github/workflows/   one gate, three steps
```

Nothing above `packs/` is part of a pack. The archive a player downloads holds
`manifest.json` and `data/`, `assets/`, `i18n/` — never the repository around it.

The folder name is not read by the engine, but keep it equal to the id: it is the
one place where a mistake is cheap to notice.

## Two kinds: one starts a run, one changes a run

Every pack declares `kind`, and there are only two values.

| `kind` | Can a player start it | What it carries | Needs `layer` and `target` |
| --- | --- | --- | --- |
| `bundle` | yes, on its own | protocol, entry node, `data/nodes.json` | no, and a `target` is refused |
| `layer` | no | one dimension of another pack | yes, both |

A run is always **one bundle plus zero or more layers**. The engine takes the
protocol, the entry node and the story from the bundle; a layer supplies one part
of that bundle and nothing else. That is why a layer on its own is not a game,
and why every set of packs you assemble needs exactly one bundle in it.

`genre` is the exception in shape: a pack that brings a whole other way to play
is a `bundle`, not a layer. Two bundles in one world are two games that sit side
by side, not a base and a patch.

## The six dimensions a layer can fill

`layer` names which part of the target the pack replaces.

| `layer` | Fills | Example |
| --- | --- | --- |
| `profession` | the world itself: factions, territory, ranks, place names | a different map of the same era is a different `bundle` |
| `genre` | how the player takes part: choices, a menu, a hand of cards | *(as a `bundle` in practice)* |
| `mod` | numbers and costs someone else already declared | harder economy, a new action |
| `content` | how the story is told: view, density, cast, arc | the same war, in first person |
| `meta` | the shop lines: audience, minutes, pitch, icon | a cut aimed at shorter sessions |
| `assets` | pictures, sound, text files | a redrawn set of card faces |

`content` replaces its block whole; `mod` merges field by field and only two
layers writing the same field collide.

## One pack, one tag, one release, two assets

| Pack | Tag | Release holds |
|---|---|---|
| `sanguo` | `pack/sanguo/v1.1.0` | `sanguo.zip`, `sanguo-1.1.0.json` |
| `sanguo-cards` | `pack/sanguo-cards/v1.0.0` | `sanguo-cards.zip`, `sanguo-cards-1.0.0.json` |

One repository can cut several releases without them touching each other, and a
player installs the one they want, because each zip carries its own id. The gate
publishes the pack the tag names, not "the pack in the repository".

## The id is the save key

The manifest names an `id`, and the engine stores a run under
`save:<id>:<slot>`. Two packs in one repository therefore must not share an id,
and a released id cannot be renamed: every save that pointed at it would be
lost. Fix the ids before the first release, then leave them alone. A
replacement pack gets a new id; the old one is not reused.

## What a layer points at

```json
{ "kind": "layer", "layer": "mod", "target": "sanguo", "requires": [{ "id": "sanguo", "version": "1.0.0" }] }
```

`target` is the id of the pack the layer changes — in practice a `bundle`, since
that is the only thing a run can start from. The assembler refuses three cases,
each with a code of its own:

- `V-33` — a name in the assembly is not installed;
- `V-34` — a target is outside the assembly, is the layer itself, or the targets
  form a cycle;
- `V-35` — two layers write the same field of the same pack.

A layer names one target. To change two packs, publish two layers.

## Naming: the world first, the purpose second, never the form

| id | kind | reads as |
| --- | --- | --- |
| `sanguo` | `bundle` | the base story |
| `sanguo-cards` | `bundle` | the same world, played with cards |
| `sanguo-content` | `layer`, `content` | the same story told another way |
| `sanguo-hard` | `layer`, `mod` | the same story, harder |

The first segment is the world, so everything about one world sorts together.
The second says what the pack does for a player, in words a player would use.
The form is **not** in the name: `sanguo-cards` is a bundle and `sanguo-content`
is a layer, and only the manifest says which. Avoid `-layer`, `-bundle`, `-v2`
and `-final`: the id is the save key, so `-v2` is a new pack wearing the name of
an old one.

## What the interface does with all this

A bundle appears as one row on the pack page, titled by its `names[locale]`. If
several packs share a `collection`, one world row leads to them. A layer never
gets a row of its own: it is a checkbox under the row of the pack its `target`
names, and it starts unticked, because a layer changes what the player already
agreed to play.

## What does not work yet

Read this before planning a family of packs:

- a layer whose `target` is not a bundle is refused with `V-44` when the
  assembly is built;
- `content`, `mod` and `assets` take effect; `genre` and `meta` install without
  changing anything; `profession` is the bundle's own data (`data/relations.json`,
  `phases.ranks`, the resource labels), so a `profession` layer has nothing to
  merge (`ADR-0016`).

## The repository is not part of the contract

Its folders, README, tests and `infra/` are yours; the engine never looks at
them. The shape is enforced in exactly two places — the archive you publish and
the install a player runs — and both read the same rules. That is why one
repository can hold one pack or ten, and why the only thing to plan in advance
is the list of ids.
