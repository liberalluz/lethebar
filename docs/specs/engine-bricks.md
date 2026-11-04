# Engine bricks

**Status**: normative from v0.1.0. These eight bricks are the engine's public
primitive surface, and package format `2.0.0` refers to them (ADR-0007). Until
v0.1.0 ships they exist so that the batches implement slices of one settled
shape instead of inventing fields three times; after that, changing a brick is a
format change and needs a new ADR.

Terms used below:

- **brick** — a primitive the engine implements. Packages declare data; they never
  implement a brick.
- **package** — a zip carrying a manifest, data files and assets. It carries data only
  (ADR-0003, ADR-0005).
- **run** — one play session, from start to end, with its own save slots.
- **tick** — an engine-internal time unit. It advances when the run advances; it is
  never read from the wall clock.

A package may use any subset of the bricks. Every brick is optional: a package that
only declares nodes behaves exactly like today's `linear@1` content.

## How a package turns a brick on

The brick is on when its data file is present. There is no manifest list of
enabled bricks, and that is deliberate: a list would have to be kept in sync with
the files, and a package that declares `ledger` but ships no `data/state.json` is
a validation error nobody asked for. Presence is the declaration, and `V-14` …
`V-21` check what the present file says.

| Brick | File | Absent means |
|-------|------|--------------|
| State ledger | `data/state.json` | no resources; a rule that writes one is `V-14` |
| Settlement rules | `data/rules.json` | effects apply, nothing settles afterwards |
| Action menu | `data/actions.json` | choices come from the node, as today |
| Phase machine | `data/phases.json` | a run ends when the story ends, as today |
| Checks | `data/checks.json` | no rolls; nothing is random except the session seed |
| Pools | `data/pools.json` | no draws |
| Relations | `data/factions.json` | no entities; a relation condition is `V-20` |
| Clock | none | `tick` still advances, nothing reads it |

The three bricks that change what a player can do — menu, phases, checks — are
what makes a genre different from a story. The other five change what the player
sees and how the numbers move.

---

## 1. State ledger

`data/state.json`

```json
{
  "resources": [
    {"id": "grain",   "label": "粮草", "init": 100, "min": 0, "max": 1000},
    {"id": "pop",     "label": "人口", "init": 50,  "min": 0, "max": 500},
    {"id": "prestige","label": "声望", "init": 10,  "min": 0, "max": 100}
  ]
}
```

- Every value is a number. There is no string or boolean state.
- `min` and `max` are inclusive; writes are clamped, not rejected.
- A rule that names an unknown resource is a validation error (`V-14`), not a
  silent zero.
- A resource that exists but was never written reads as `init`.
- The ledger is part of the save payload; a run restored from a slot reads the same
  numbers it saved.

## 2. Settlement rules

`data/rules.json`

```json
{
  "rules": [
    {
      "when": {"key": "pop", "op": "lt", "value": 10},
      "set":  {"grain": {"add": -5}, "prestige": {"add": -1}}
    },
    {
      "when": [{"key": "grain", "op": "gte", "value": 100},
               {"key": "prestige", "op": "gte", "value": 50}],
      "set":  {"pop": {"add": 5}}
    }
  ]
}
```

- `when` is one condition or an array of conditions, combined with AND.
- A condition is `{key, op, value}` with `op` in `eq | ne | gt | gte | lt | lte`.
- `set` maps a resource id to one of: a bare number (assign), `{"value": n}`,
  `{"add": n}`, `{"clamp": {"min": n, "max": n}}`.
- Rules run in file order, once per advance, after the action's own effects.
- A string in `when` is rejected (`M-02` today); there is no expression language
  and no string interpolation.

## 3. Action menu

`data/actions.json`

```json
{
  "actions": [
    {
      "id": "recruit",
      "label": "招兵",
      "costs":   {"grain": {"add": -20}},
      "requires":[{"key": "grain", "op": "gte", "value": 20}],
      "effects": [{"grain": {"add": -20}}, {"pop": {"add": 3}}],
      "limit":   {"per_turn": 1}
    }
  ]
}
```

- The engine renders the menu and **disables** an action whose `requires` fail,
  with the failing condition available to the UI. A disabled action is a state,
  not an error.
- Costs and effects apply atomically: if any part would be rejected, nothing is
  written.
- `limit` is optional and counts per turn or per run (`{"per_run": 1}`).
- When no action is available the engine still renders the turn, so a package can
  be a pure reading experience with no menu at all.

## 4. Phase machine

`data/phases.json`

```json
{
  "turns": 24,
  "ranks": [
    {"at": 1,  "title": "校尉"},
    {"at": 6,  "title": "将军"},
    {"at": 12, "title": "州牧"},
    {"at": 18, "title": "刺史"},
    {"at": 24, "title": "丞相"}
  ],
  "fail": [
    {"when": {"key": "grain", "op": "lte", "value": 0}, "reason": "粮尽"},
    {"when": {"key": "pop",   "op": "lte", "value": 0}, "reason": "无人可用"}
  ]
}
```

- `turns` is the length of one run. Reaching it ends the run as a win.
- `ranks` are read from the turn number, so a save restored at turn 13 shows the
  rank for turn 13 without extra bookkeeping.
- `fail` is evaluated after settlement. The first matching entry ends the run and
  its `reason` is shown to the player.
- A run ended by `fail` is still saveable: the player can reload before the turn
  that killed them.

## 5. Checks

`data/checks.json`

```json
{
  "checks": [
    {
      "id": "battle",
      "when": [{"key": "pop", "op": "gte", "value": 20}],
      "roll": {"dice": 1, "sides": 100},
      "target": 60,
      "bonus": {"key": "prestige", "scale": 0.5}
    }
  ]
}
```

- A check produces a boolean plus the numbers that decided it, both stored under
  `state.checks.<id>` and shown on request. The player is told why, not just yes.
- Rolls come from the session RNG, so the same seed and the same choices produce
  the same outcomes (`TC-DET-001`).
- There is no free-form probability expression: `roll`, `target` and `bonus` are
  the whole surface. A genre that needs more becomes a brick proposal.

## 6. Pools

`data/pools.json`

```json
{
  "pools": [
    {"id": "officers", "items": ["cao_cao", "liu_bei", "sun_quan"], "draw": {"n": 1, "replace": false}}
  ]
}
```

- Drawing removes items from the pool unless `replace` is true.
- The remaining pool is part of the save, so reloading cannot re-roll a draw.
- Pool order is not shuffled at load time; shuffling happens through the session
  RNG when the first draw occurs, which keeps a fresh run reproducible.

## 7. Relations

`data/factions.json`

```json
{
  "thresholds": {"ally": 60, "hostile": -60},
  "entities": [
    {"id": "wei", "label": "魏", "relations": {"shu": -40, "wu": 10}},
    {"id": "shu", "label": "蜀", "relations": {"wei": -40}},
    {"id": "wu",  "label": "吴", "relations": {"wei": 10}}
  ]
}
```

- Values are numbers with no engine-imposed range. A package that wants a bound
  declares a `clamp` in its settlement rules; the engine does not decide what
  "close" or "far" means.
- Relations are directed. `wei → shu` and `shu → wei` are two values; the engine
  never assumes symmetry, and validation (`V-20`) reports an asymmetric pair as a
  warning rather than rewriting it.
- `ally` and `hostile` are **declared by the package**, not by the engine. A
  condition may use `{"relation": "shu", "state": "ally"}` only if `thresholds`
  declares that state; using it without a declaration is a validation error, so
  there are no magic numbers in the engine to disagree with a package's intent.
- A package that uses no relations omits the file entirely.

## 8. Clock

No file. The clock lives in the engine.

- `tick` increments once per advance (a turn, or a node in a linear package).
- Idle genres read `tick` to compute growth; they never read the wall clock.
- A package may declare `{"clock": {"per": "turn"}}` to say that its growth is
  per turn rather than per node; anything else is out of scope for v2.

---

## Validation surface

Each brick gets one validation rule so an author's mistake is a data error, not a
runtime surprise:

| Rule  | Brick | Rejects |
|-------|-------|---------|
| V-14  | ledger | unknown resource in a rule or action; `min > max` |
| V-15  | rules | unknown `op`; `set` on a resource that is not declared |
| V-16  | actions | duplicate id; empty `effects`; `limit` on a missing counter |
| V-17  | phases | `turns < 1`; rank `at` outside `1 … turns`; empty `reason` |
| V-18  | checks | `sides < 2`; `target` outside the dice range |
| V-19  | pools | duplicate item; `draw.n` larger than the pool without `replace` |
| V-20  | relations | unknown entity id; `ally`/`hostile` used without a declared threshold |
| V-21  | clock | a package that declares a clock but no growth rule that reads it |
| V-22  | locales | a declared locale the engine does not support; a declared locale with no `data/i18n/<locale>.json`; a table that leaves a node, a choice label or the text empty |
| V-23  | manifest | `kind` that is not `bundle`/`layer`; `layer` missing or unknown on a `kind: layer`; `requires` that is not an array of `{id, version}` |
| V-24  | requires | a requirement that no installed or built-in package satisfies, or whose version falls outside the constraint |
| W-01  | manifest | `specVersion` still declares `1.0.0`: readable through v0.1.x, refused from v0.2.0 |

The `V-` codes are errors and refuse the package; `W-01` is a warning and the
package still installs. The split is the same one §8.2 of the SDD makes for a
missing asset: an author's typo must not strand a player mid-scene, so anything
that can be degraded is degraded and anything that cannot be judged is refused
at install time.


## Package locales

A package may carry its text in more than one language. The text in
`data/nodes.json` is written in `defaultLocale`; every other language is a
table at `data/i18n/<locale>.json`, keyed by node id:

```json
{"n1": {"text": "…", "choices": ["…", "…"]}}
```

Three optional manifest fields declare this: `defaultLocale` (a string),
`locales` (an array of the extra languages) and `names` (the pack title per
locale, so the list on the landing screen reads in the same language as the
rest of the screen).

The engine picks the table matching the locale the browser asks for and falls
back to `defaultLocale` when the package carries no table for it. `V-22`
refuses a package whose declared table leaves any node text or any choice
label empty: half a translation is worse than none, because the player would
meet a language switch in the middle of a scene.
## Minimal example

A package that uses all eight bricks but stays under 60 lines of data: three turns,
two resources, one action, one check, one pool, two factions. It exists to prove
the bricks compose before any real content is written, and it is the fixture for
the B8a/B8b/B8c acceptance lines.

## Compatibility

Format `2.0.0` is the first version that can express a package depending on
another package, so it is a major bump (ADR-0007): a `1.0.0` engine cannot judge
`requires`, and starting a story it cannot finish is worse than refusing it.

| Engine | Reads `1.0.0` | Reads `2.0.0` |
|--------|---------------|---------------|
| v0.0.x | yes | no — refused by `V-05` |
| v0.1.x | yes, with `W-01` | yes |
| v0.2.0 and later | no — refused by `V-05` | yes |

Adding an optional brick field, or an optional manifest field, is a minor bump
and needs no new ADR: the test is ADR-0006's — an older engine that ignores the
field must still read the package the same way. `requires` fails that test,
which is why this one is major.

## What is deliberately missing

- No loops, no user-defined functions, no string expressions.
- No network, no file system, no wall clock.
- No per-node scripting. A genre that cannot be expressed is a brick proposal, and
  a brick is an engine change (ADR-0005).
