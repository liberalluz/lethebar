# What `manifest.json` means

A pack is a zip. The engine opens `manifest.json` first and decides from it alone whether the
pack can be installed. Everything else in the archive — nodes, actions, art — is only read after
this file is accepted.

## Three versions, three jobs

| Number | Lives where | Answers | Changes when |
| --- | --- | --- | --- |
| `version` | `manifest.json`, the tag, the descriptor | which build of *this pack* is this | you change the pack |
| `specVersion` | `manifest.json` | which pack *format* it is written in | the format changes, not you |
| `engine` | `manifest.json` | which engine builds can run it | the engine's major version leaves your range |

The three are independent. A pack can stay on `1.4.0` for a year while the format moves from
`2.0.0` to `2.1.0`, and an old pack that still works keeps its `engine` range untouched.

`version` is a three-part number and the tag repeats it exactly: `pack/<id>/v<version>`. The
descriptor file next to the zip is named `<id>-<version>.json` and carries the same string.

## The id is permanent

`id` matches `^[a-z0-9-]+$` and becomes the save key: `save:<id>:<slot>`. Two consequences:

- changing the id orphans every save that pointed at the old one;
- publishing `-v2` to mean a new version breaks the one rule that keeps saves readable.

If you want a clean break, publish a new id and say so; do not reuse the old one.

## Fields

<!-- generated:fields -->

| Field | Required | Type | What it means |
| --- | --- | --- | --- |
| `id` | yes | string | permanent slug, `[a-z0-9-]+`; the save key is `save:<id>:<slot>` |
| `version` | yes | string | this pack's own version; the tag carries the same string |
| `specVersion` | yes | string | the pack format this pack is written in; `2.0.0` today |
| `engine` | yes | string | `>=x.y.z <x.y.z`: the engine versions this pack runs on |
| `name` | yes | string | the title a player sees, in `defaultLocale` |
| `protocol` | yes | string | `linear@1`, `turn_based@1` or a protocol the engine implements |
| `capabilities` | yes | list | `name@version` list; each one must exist in the engine |
| `mechanics` | yes | list | resource names this pack keeps; empty is allowed |
| `entry` | yes | string | the node the session starts at |
| `saveSchema` | yes | number | integer; bump it when a save from an older build stops loading |
| `assets` | yes | list | `{type, path, slot}` list; `texture`, `audio` or `text` |
| `defaultLocale` | no | string | the language the text in `data/nodes.json` is already in |
| `locales` | no | list of strings | extra languages carried in `data/i18n/<locale>.json` |
| `names` | no | object | per-locale titles for this pack |
| `kind` | yes (2.0.0) | string | `bundle` or `layer`; format 2.0.0 and later |
| `target` | if layered | string | the package a layer changes; required when `kind` is `layer` |
| `requires` | no | list of ids | packages this layer needs before it can be played |
| `layer` | if layered | string | which of the six layers a non-playable package is |
| `collection` | no | object | the world this package belongs to: `{id, names}` |
| `clock` | no | object | `{per: turn or node, every: n}`; absent means every turn |
| `meta` | no | object | audience, minutes, pitch, icon: what a shop would show |
| `content` | no | object | view, density, cast, arc: how this pack tells its story |

<!-- /generated:fields -->

## Vocabulary

<!-- generated:vocabulary -->

| Vocabulary | Values |
| --- | --- |
| `kind` | `bundle`, `layer` |
| `layer` | `profession`, `genre`, `mod`, `content`, `meta`, `assets` |
| asset `type` | `texture`, `audio`, `text` |
| `clock.per` | `turn`, `node` |

<!-- /generated:vocabulary -->

## The smallest manifest that works

This is `templates/pack-min/manifest.json`, byte for byte:

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

`entry` names a node in `data/nodes.json`, `capabilities` says which engine features the pack uses,
and `mechanics` is empty because this story has no resources to track.

## What the engine refuses, and with which code

| You did | The engine says |
| --- | --- |
| a field is missing, or the shape is wrong | `V-02` on that field |
| the id is not a slug | `V-03` |
| `specVersion` is not a format this build knows | `V-04` |
| `engine` is missing, malformed, or excludes this build | `V-05` |
| `kind` or `layer` is not one of the values above | `V-23` |
| `requires` names a package that is not installed | `V-24` |
| a capability is not `name@version`, or the engine does not have it | `V-27` |
| `collection.id` is not a slug, or `collection.names` is not locale → title | `V-32` |

Two of these are worth failing early on purpose. `V-05` is the only code that tells a player their
engine is too old; `V-27` is the only one that tells an author they asked for a feature this build
does not have. Both are cheaper to see on your own machine than in someone's browser.
