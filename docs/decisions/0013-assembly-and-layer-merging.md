# ADR-0013 · One session may be made of several packages

## Context

A session today loads exactly one package. `Session.create(entry, options)` takes a
registry entry, reads `data/*.json` from it and runs. That was right while a world
shipped one genre: there was nothing to combine.

The moment a world ships a tale, a card battle and a mod for the card battle, three
things want to be true at once — the world's data, the genre's shape and a change to
some declared number — and none of them is a whole session on its own. The engine
has to answer, before writing code: what does a session load, how do two layers
that touch the same field combine, and what happens when they disagree.

The tempting answer — last one wins — is the one that makes a bug report
unreproducible, so it is rejected here rather than after the fact.

## Decision

**A session is created from an ordered list of packages, not from one.** The list is
called an *assembly*: the pack that defines the session, plus zero or more layers.

**Every layer declares what it changes**, through `kind` and `layer`
(`ADR-0007` already reserves both). A layer without a `layer` target is not a layer;
it is a package, and packages are played, not merged.

**Three merge semantics, and only three:**

| Semantics | Meaning | Where it is legal |
| --- | --- | --- |
| override | replace a declared scalar or object wholesale | any declared field |
| append | add entries to a declared list (choices, actions, cards, events) | declared lists only |
| disable | remove a declared entry by id, leaving the rest | declared lists and map keys |

No fourth semantic is introduced later without a new record. In particular there is
no "patch by dot path" and no expression language: a mod that needs to compute a new
value is a mod that wants to be a capability, and capabilities live in the engine
(`ADR-0008`).

**The chain is acyclic and shallow.** A layer names exactly one target; a target may
itself be a layer. The chain is resolved base first, and a cycle is refused rather
than broken. Depth is bounded by the chain length; the engine does not need a
general graph resolver, because a mod over a mod over a mod is a maintenance
problem disguised as flexibility.

**Conflicts are refused, not resolved silently.** Two layers writing the same field
is an error, not a tie to break:

| Code | When |
| --- | --- |
| `V-33` | a package named in the assembly is missing, or its version is outside the declared range |
| `V-34` | a `layer` target does not exist among the assembly, or the chain has a cycle |
| `V-35` | two layers write the same field of the same target |

`V-35` names the field and both layers. It is refused before the session starts, so
a player never plays a run whose rules they cannot predict. Explicit priority is
allowed only between layers with the same target, where both declare it; the record
of which won is written into the assembly, not left to installation order.

**The assembly is part of the save.** A snapshot carries `assembly`: the package ids,
their versions, the layer chain in resolution order, and any priority decisions. A
reload rebuilds the same assembly or refuses to load with a reason — never loads
"close enough", because a save is a claim about a specific set of rules.

## Consequences

- `Session.create` grows a package list; `view()` merges what the layers contributed,
  and the scene reads one merged view rather than three.
- A save written by an assembly becomes unreadable when a layer disappears. That is
  deliberate: the alternative is a run that silently changes rules mid-story.
- Tests must cover three cases per semantic, plus one refusal per conflict code, and
  the "remove one layer, behaviour returns to the base" comparison.
- The engine's own content is still one package per session; the assembly exists for
  authors, and the built-in stories are migrated only when a world ships two genres
  that share a session (`B44`).
- This is the largest engine increment since `v0.1.0`, so it is split into three
  batches: multi-package sessions, merge semantics, conflicts and the save block.

## Alternatives considered

- **Duplicate a package to make a variant.** Rejected: it is what the project does
  today, and it copies a hundred cards to change one cost, then the two copies drift.
- **Last layer wins on conflict.** Rejected: it makes the same installation produce
  different runs, and no bug report can say which rules were in force.
- **A patch language inside the manifest.** Rejected: it turns data into code by
  another name and breaks `ADR-0009` — a package that can compute can do anything.
- **Load a bundle package that pre-merges its world and genre.** Rejected as the only
  mechanism: it moves the composition to build time and forbids a player from
  swapping one mod, which is the whole point of a mod.

## Amendment (B86)

- A record is a layer because it says `kind: "layer"`, not because it carries a
  `target`. `InstallRegistry.entry()` copies `kind` from the manifest beside
  `layer` and `target`, and `Session.create` dispatches on it. A bundle that
  happens to name a `target` is merged as a bundle instead of being applied as a
  layer; the guess and the declaration agreed in every package the project
  shipped, which is why the mistake stayed invisible.
- The suite keeps both directions: a `kind: layer` record with a target applies
  its `disable`, and a bundle that names a target leaves the actions it names in
  place.
