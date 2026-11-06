# ADR-0012 · A package says which world it belongs to

## Context

The shelf today is one flat list: three built-in stories, then whatever the player
imported. That works while every package belongs to a different world. It stops
working as soon as one world ships several genres — three kingdoms ships a tale, a
card battle and later a map strategy — because the list then reads
`三国 · 剧情 / 三国 · 卡牌 / 三国 · 战棋 / 修仙 · 剧情 / 修仙 · 卡牌` with nothing
tying the first three together.

The engine cannot group by anything it does not know. A package's `id` is an
identity, not a category: `liberalluz.sanguo-cards` happens to begin with a world
name, but nothing may parse it, because the next author will spell it differently.

The shape of the navigation is a product decision taken once: a world page above
the pack list, not a flat list with a prefix and not a deeper tree.

## Decision

**A package may declare the world it belongs to:**

```
collection: { "id": "sanguo", "names": { "zh-CN": "三国", "en": "Three Kingdoms" } }
```

- The field is **optional** and worth `format 2.0.0` without a version bump, like
  `names` and `defaultLocale` before it.
- `id` is what grouping reads: lowercase, `[a-z0-9-]`, stable across releases.
- `names` is a locale map, so the world's name follows the interface language the
  same way a pack's name does. A missing locale falls back to the pack's
  `defaultLocale`, then to the `id`.
- The engine keeps **no list of worlds**. The worlds on the shelf are the
  collections the installed packages declare, and nothing else.

**Validation:**

| Code | When | Severity |
| --- | --- | --- |
| `V-32` | `collection` is not an object, `id` is malformed, or `names` is not a locale map | fatal, refused at install |
| `W-04` | two installed packages share a `collection.id` but disagree on that world's `names` | warning, once per world |

For `W-04` the engine takes the names from the package whose `id` sorts first, so
the shelf is deterministic without asking the player a question. The warning names
both packages, because a world with two spellings is a packaging bug worth fixing.

**The flow, fixed:**

```
New game
  -> worlds      (only when more than one world is installed)
     sanguo  · 3 stories
     xiuxian · 2 stories
  -> packs of one world
     tale / cards / war
  -> a session   (back returns to the pack list, then to the worlds)
```

Rules that fall out of that flow:

1. A package without `collection` lands in one fallback group, named *Other* in the
   interface locale. It is a normal group: playable, grouped, not hidden.
2. A world with one pack is still a world; the pack list of a single-pack world
   shows the pack and no empty level.
3. **When exactly one world exists — including the fallback group — the world page
   is skipped.** With one world there is nothing to choose, and an extra tap is a
   tax on every session.
4. A session keeps the world it was started from, so `Back` returns to that world's
   pack list rather than to the worlds.

## Consequences

- The shelf becomes a two-level screen; `shell.gd` grows one screen state and the
  navigation between three, with `Back` walking up the same path.
- The world's name is data owned by the packages, so a translation of a world name
  is a package fix, not an engine release.
- Two packages of the same world must agree on its name, and `W-04` is the only
  thing that will tell an author they did not.
- Sorting is by world name in the interface locale, then by pack name; a stable
  order matters more than the exact collation.
- The marketplace groups by the same field (`ADR-0011`), so the shelf and the market
  cannot disagree about which world a package is in.

## Alternatives considered

- **A flat list with the world name in the pack name.** Rejected: it relies on
  every author spelling the world the same way, and it cannot skip a level when a
  world has one pack.
- **Derive the world from the package `id` prefix.** Rejected: an identity is not a
  category; the first `sanguo` and the first `three-kingdoms` would split one world
  in two.
- **A separate `worlds.json` shipped with the build.** Rejected: it puts content in
  the engine repository and makes a new world an engine release.
- **A three-level tree: world, genre, pack.** Rejected: the middle level duplicates
  what the pack's own name says (`sanguo-cards`), and it costs a tap per session for
  no decision the player wants to make.
