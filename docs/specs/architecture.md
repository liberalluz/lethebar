# Architecture

This page is for the people who change the engine. An author needs
[the guide](../guide/what-is-this.md) instead; a pack's contract with the engine
is in [`docs/specs/controlled/`](controlled/), and the capability list is
[`capabilities.md`](capabilities.md). This page explains how those pieces fit and
where a change belongs.

## 1. The thesis and what it refuses to be

The engine carries **play shapes as data**: a package says what a run is made of,
the engine supplies the way a step is taken, the numbers, the storage, and the
drawing. It is not a game, not a scripting host, and not a plugin runtime —
packages are data, and the only code is the engine's.

That gives two non-goals:

- **No gameplay in the engine.** If a behaviour can be a table, it is a table.
- **No code in a package.** Not a sandbox with rules, a refusal: a package that
  carries an executable is rejected by `check_pack` and again at install.

## 2. Five invariants

1. A package is data. The trust boundary is the zip envelope, not a sandbox.
2. A run is one bundle plus zero or more layers; a layer supplies one declared
   part and nothing else.
3. A capability is a promise (`name@major`): the engine provides it, a package
   names it, and a missing one refuses the install (`V-27`).
4. A run is deterministic: the same packages, the same assembly and the same save
   rebuild the same run.
5. Four seams each have a check: format, assembly, capability, release.

## 3. Words

| Word | What it is | What it is not |
|---|---|---|
| pack | a zip of data with a manifest | a plugin, a script bundle |
| bundle | a pack that is a whole run | the only kind of pack |
| layer | a pack that patches a declared part of a bundle | a second story |
| dimension | the part a layer declares it patches (`content`, `mod`, …) | a package type |
| protocol | the code that takes one step | a genre |
| brick | one data file a run reads (`ledger.json`, `phases.json`, …) | a capability |
| capability | a named promise (`cards.hand@1`) | a field or a permission |
| service | the engine code behind a capability | something a package names |
| genre | a way to take part (a run shape) | a protocol |
| run | one session from start to save | a package |
| assembly | the ordered list of packs a run is built from | a save file |

## 4. Four views

Each view answers one question. Do not mix arrow kinds in one figure: dependency,
sequence and data flow read differently, and a figure that draws all three is
unreadable.

### 4.1 Structure — what depends on what

```text
shell ──► session ──► protocols
  │          │
  │          ├──► bricks (nodes, ledger, rules, actions, phases, …)
  │          └──► save_store
  └──► loader ──► validator ──► schema
            │
            └──► registry ──► assemble
```

Rules: an arrow is an import; `session` never imports `shell` or `loader`;
`protocols` import nothing from the shell; `schema` depends on nothing.
The four extension points are marked with a star: protocols, bricks,
capabilities (validator), layers (assemble).

### 4.2 Runtime — how one run happens

```text
install → pick layers → assemble → start
   → [ show a scene → player chooses → advance → apply effects ]
   → at a boundary: phases and rules
   → save → resume
```

Three lanes: the author's pack, the engine, the player. The figure is a sequence,
not a module map.

### 4.3 Contract — who promises what

| Capability | Reads these bricks | Needs this protocol | State |
|---|---|---|---|
| `text@1` | nodes, i18n | any | provided |
| `ledger@1` | ledger | any | provided |
| `phases@1` | phases | `turn_based@1` | provided |
| `cards.hand@1` | hand, pools | `linear@1` | provided |
| `cards@1` | hand, node fields | `cards@1` | planned |
| `map@1` | space | `turn_based@1` | planned |

The full list, with services and proofs, is [`capabilities.md`](capabilities.md).

### 4.4 Change — where a new thing belongs

| You want to add | It lands in | Cost |
|---|---|---|
| a number, a cost, an action | data (`mod`) | no code |
| another way to tell it | data (`content`) | no code |
| the same story, read differently | a layer plus protocol merging | about 150 lines, not built |
| a new step (cards) | a new protocol and its node contract | one design |
| a map, a battle, entities | a new service | a major version |

## 5. The inventory

### 5.1 Dimensions

| Dimension | Owner | Carries | Today |
|---|---|---|---|
| `profession` | bundle | the world: factions, ranks, place names | read, never a separate pack |
| `genre` | bundle | how the player takes part | two protocols; a `genre` layer does nothing |
| `mod` | layer | numbers and costs another pack declared | applied |
| `content` | layer | view, density, cast, arc | applied |
| `meta` | bundle | audience, minutes, pitch, icon | read, not patchable |
| `assets` | layer and bundle | pictures, sound, text files | applied (`V-45`) |

### 5.2 Protocols

| Id | One step | Node contract | State |
|---|---|---|---|
| `linear@1` | pick a choice, go to the next node | `choices`, `effects`, `next` | provided |
| `turn_based@1` | one action is one round | the same nodes plus a round count | provided |
| `cards@1` | draw, play, discard, resolve | needs enemy, deck, cost and win fields | planned |

Registered in `app/core/protocol_registry.gd`; an unknown id is `V-06`. A protocol
must implement `start/advance/evaluate/snapshot`, hold no private state, be
deterministic, be data-agnostic, and declare its node contract.

### 5.3 Bricks

| File | Holds | Capability |
|---|---|---|
| `nodes.json` | scenes, choices, jumps | `narrative@1` |
| `ledger.json` | named values, bounds | `ledger@1` |
| `rules.json` | `{when, set}` tables | `rules@1` |
| `actions.json` | actions, costs, effects | `actions@1`, `menu@1` |
| `phases.json` | turn budget, ranks, failure | `phases@1` |
| `pools.json` | pools, one draw per item per run | `pools@1` |
| `relations.json` | entity pairs, thresholds | `relations@1` |
| `hand.json` | deck, hand, draw, discard | `cards.hand@1` |
| manifest `clock` | a tick per turn or per scene (`clock@1` has no file) | `clock@1` |

`content`, `meta` and `assets` are manifest blocks, not files.

### 5.4 Services

| Group | Service | Used by |
|---|---|---|
| package | import, envelope, uninstall | loader, registry |
| validation | manifest and `V-*` codes | validator |
| assembly | layer merge, conflict refusal | assemble |
| run | state and advance | session |
| play | ledger, rules, menu, phases, pools, relations, clock, hand | bricks |
| view | drawing, assets, i18n, input | view, shell |
| storage | snapshot, slots, rebuild | save_store |
| release | build, hash, release, site | release tools |
| offline | service worker, pck cache | web build |

## 6. Genres against services

`●` needed, `○` optional, `×` missing.

| Genre | narrative | numbers | rules | actions | phases | random | relations | clock | space |
|---|---|---|---|---|---|---|---|---|---|
| linear reading | ● | ○ | – | – | – | – | – | – | – |
| turn-based strategy | ● | ● | ● | ● | ● | – | ○ | – | – |
| roguelike | ● | ● | ● | ● | ● | ● | – | ○ | × |
| puzzle | ● | ● | ● | ● | – | – | ○ | – | – |
| management | ● | ● | ● | ● | ● | – | ● | ● | – |
| card collection | ● | ● | ● | ● | ● | ● | – | – | – |
| idle | ● | ● | ● | ● | ● | – | – | ● | – |
| relationship | ● | ● | ● | ● | – | – | ● | – | – |
| live viewing | carrier, not a genre | | | | | | | | |
| interactive branching | carrier, not a genre | | | | | | | | |
| stacking | the union of two rows | | | | | | | | |

Reading: narrative is universal; random, relations and clock split the genres
apart; space is an empty column today, which is why a map is a new service and not
a new brick.

## 7. Gaps, and how to change it

Two columns, because they fail differently:

| Missing capability | Blocks |
|---|---|
| `cards@1` | a real card game, deck building |
| `map@1` | sandbox, a true grid roguelike |
| `units@1` | officers with stats, NPCs |
| `battle.turnbased@1` | tactical battles |
| `battle.realtime@1` | action, ARPG |

| Implementation debt | Consequence |
|---|---|
| `genre` layers do nothing | a genre-shaped pack must be a bundle |
| `mechanics` is declared but never read | an author can set it and change nothing |
| no offline clock | idle runs stop when the tab closes |
| no entity layer | no NPC, no units, no map |

How to change it:

1. Does the new behaviour fit a brick? If yes, it is data and no code changes.
2. If it needs a new step, it is a protocol: `protocols/`, the registry, and the
   node contract in the design.
3. If it needs something the engine cannot do (space, ticks, entities), it is a
   service, and a capability is its name.
4. Every new capability lands in `package_validator.gd` and `capabilities.md` in
   the same pull request; `check_capabilities.py` refuses a one-sided change.
