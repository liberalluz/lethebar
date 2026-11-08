# One repository, several packs

A world usually grows more than one pack: the main story, a rules variant, a
content layer someone else wrote. They live side by side in the same repository,
and each one is released on its own.

```
your-world-repository/
├── packs/
│   ├── sanguo/          the main story: manifest.json, data/
│   ├── sanguo-cards/    a layer that adds a card table
│   └── sanguo-notes/    a content layer: cast, view, arc
├── infra/               the two tools, and whatever else you want
└── .github/workflows/   one gate, three steps
```

Nothing above `packs/` is part of a pack. The archive a player downloads holds
`manifest.json` and `data/`, `assets/`, `i18n/` — never the repository around it.

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

## Packs that build on each other

A layer says which pack it belongs to:

```json
{ "kind": "layer", "layer": "mod", "target": "sanguo", "requires": ["sanguo"] }
```

`target` names the pack the layer is written for; the assembler refuses a layer
whose target is not installed (`V-34`). `layer` says what kind it is: `mod`
changes rules, `content` adds cast, view and arc, `genre` brings a whole shape.
Two layers writing the same field of the same pack is a conflict reported by
name (`V-35`), never silently resolved.

## The repository is not part of the contract

Its folders, README, tests and `infra/` are yours; the engine never looks at
them. The shape is enforced in exactly two places — the archive you publish and
the install a player runs — and both read the same rules. That is why one
repository can hold one pack or ten, and why the only thing to plan in advance
is the list of ids.
