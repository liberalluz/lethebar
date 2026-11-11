# What a pack is

English · [简体中文](pack-anatomy.zh-CN.md)

A pack is a zip. Inside it is data: text, numbers, and the occasional picture or sound. It holds
no program. The engine reads the data, decides what it means, and draws it.

That is the whole reason a pack can be written by someone who has never built the engine.

## The envelope, in one sentence

At the root of the archive there is exactly one file, `manifest.json`; everything else lives under
`data/`, `assets/` or `i18n/`.

Anything else — a stray `README.md`, a `dist/` folder zipped by accident, a `.DS_Store` — is
refused before upload, because a pack whose shape is guesswork is a pack whose install failures
are guesswork too.

## Four hard rules

| Rule | Why | Who refuses it |
| --- | --- | --- |
| only `manifest.json` at the root, and `data/`, `assets/`, `i18n/` below it | the engine knows where to look, so it never scans | `check_pack.py`, before you upload |
| no executables, no symlinks, no absolute paths, no `..` | a pack is data; the engine never runs anything from it | `check_pack.py` |
| the id is a lowercase slug and never changes | it is the save key, `save:<id>:<slot>` | `V-03` at install |
| `engine` names a range that contains the running build | an old engine cannot read a new format, and should say so | `V-05` at install |

The package id allows hyphens (`^[a-z0-9-]+$`). Ids you write *inside* a data file do not: an action, a resource, a pool or a relation entity matches `^[a-z][a-z0-9_]*$`, and `V-16` refuses the archive at install otherwise.

The envelope is checked twice on purpose: once by you, on the bytes you are about to publish, and
once by the engine, on the bytes a player's browser just downloaded. Only the second one protects
a player, so it exists even if you skipped the first.

Limits: 500 entries, 4 MiB per file, 32 MiB for the archive. They are generous for text and mean
for video; if a pack needs more, it needs a second pack.

## A worked tree

This is `templates/pack-min/`, the smallest pack that installs and plays:

```
templates/pack-min/
├── manifest.json
└── data/
    └── nodes.json
```

Both files are short enough to copy by hand. This is the whole manifest:

```json
{
  "id": "pack-min",
  "version": "0.1.0",
  "specVersion": "2.0.0",
  "kind": "bundle",
  "requires": [],
  "engine": ">=4.7.0 <5.0.0",
  "name": "The shortest story",
  "defaultLocale": "en",
  "protocol": "linear@1",
  "capabilities": ["text@1"],
  "mechanics": [],
  "entry": "open",
  "saveSchema": 1,
  "assets": []
}
```

Rename `id` to something of your own before you publish; everything else can stay until a pack
needs it. `manifest.json` names the entry node, the protocol and the format. `data/nodes.json`
holds three nodes: the first offers two choices, and each choice ends the story.

```text
data/nodes.json
  nodes[0] open   — text, choices: [ {label, next: "river"}, {label, next: "ridge"} ]
  nodes[1] river  — text, choices: []
  nodes[2] ridge  — text, choices: []
```

An empty `choices` list is how a story ends. The engine does not need a flag for it.

`templates/pack-turn/` is the same story with the other protocol: one node, no choices, a menu
under it, and three more data files — see [the eight bricks](bricks.md).

## A bundle and a layer, side by side

A layer is a pack of the same shape whose manifest names what it changes. The
smallest one, in full, against the bundle above:

```json
{
  "id": "sanguo-content",
  "version": "1.0.0",
  "specVersion": "2.0.0",
  "kind": "layer",
  "layer": "content",
  "target": "sanguo",
  "requires": [{ "id": "sanguo", "version": "1.0.0" }],
  "engine": ">=4.7.0 <5.0.0",
  "name": "Three Kingdoms, in the first person",
  "defaultLocale": "en",
  "protocol": "linear@1",
  "capabilities": ["text@1"],
  "mechanics": [],
  "entry": "open",
  "saveSchema": 1,
  "assets": [],
  "content": { "view": "first", "density": "sparse", "cast": [], "arc": [] }
}
```

Three questions tell the two apart, in this order:

1. **Does it start a run on its own?** Only a `bundle` does. If the answer is no,
   the pack is a layer.
2. **Which dimension of another pack does it fill?** That is `layer`:
   `profession`, `genre`, `mod`, `content`, `meta` or `assets`.
3. **Which pack is that?** That is `target`, and it is the id of a bundle the
   player has to install as well.

A layer still repeats the fields a bundle needs — `protocol`, `mechanics`,
`entry`, `saveSchema`, `assets` — even though most of them are ignored when it
is merged. That is today's shape, not the intended one; the last page of
[the guide](README.md) lists what is still rough.

## What happens when a player installs it

1. The archive is read; `check_pack`'s rules run again on the bytes.
2. `manifest.json` is validated field by field, `V-02` through `V-42`.
3. The pack is written to browser storage, so it survives a reload.
4. Starting a run creates a session at `entry` and reads `data/nodes.json`.

Nothing in that list reads the network. Installing is a local operation on a file the player chose;
that is also why a pack works offline the moment it is installed.
