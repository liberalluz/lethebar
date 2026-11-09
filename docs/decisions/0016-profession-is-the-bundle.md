# ADR-0016 · Profession is the bundle's world, and a layer cannot replace it

## Context

The six layer dimensions name what part of a target a layer replaces. `profession`
is defined as *what the world is*: its factions, its ranks, its place names
(`ADR-0010`, and the guide's table). The other five have had a consumer or a
recorded absence; `profession` has been treated as the next one to build, on the
assumption that the engine reads none of it.

That assumption is wrong. The engine already reads all three parts:

- `data/factions.json`: `package_loader.gd` loads it, `package_validator.gd`
  checks every relation, `menu.gd` lists the entities the run can talk to;
- `phases.ranks`: `session.gd` `rank()` walks them every turn, localises
  `rank.<at>` with the phase's own title as fallback, and puts the result in the
  snapshot the HUD draws;
- the resource labels: `data/state.json` carries `label` and `labels`, and the
  HUD draws them beside every resource.

So a `profession` layer has nothing to merge. It installs, it is marked pending
by `B91`, and it changes nothing — not because a reader is missing, but because
there is no data to add: the world's vocabulary is already in the bundle and
already read.

## Decision

`profession` is bundle-level. The three files above *are* the profession; the
engine introduces no `profession` block, no fourth place to put factions, and no
layer merge for it.

A `profession` layer stays in the format and stays pending. It cannot apply: a
save binds the world it was played in, and a layer that replaced the factions or
the rank ladder would change that world under the save. A different map of the
same era is a different bundle with its own id and its own save slots; two maps
of one era are two bundles side by side, not a base and a patch.

`ADR-0015` lists the applied dimensions; `profession` is not one of them, and
the reason is recorded here rather than as a missing reader. The word stays in
`LAYERS` until a format bump removes it; removing it now would be a `2.x` change
with no benefit to any author.

## Consequences

`B94` (a profession reader) is not scheduled: its premise — that the engine
reads none of the world's vocabulary — was false. The guide says profession is
bundle-level and that a `profession` layer has nothing to merge. `genre` and
`meta` remain the two dimensions with no consumer, and each still needs its own
record.

`Session.rank()` and the faction relations are the profession's readers; a
second reader would be a second source of truth for the same names, which is the
failure this record exists to prevent.

## Alternatives

**Add a `profession` block to the manifest.** Rejected: it would restate
factions, ranks and labels in a fourth place, and the engine would have to
choose which copy wins.

**Make a `profession` layer override factions or ranks.** Rejected: the save is
bound to the world, and a run whose factions changed under it is a different
run. The content and the checks assume the declared entities; a layer that
replaced them would also invalidate every relation the bundle already checked.

**Remove `profession` from `LAYERS` now.** Rejected: it is a format bump for a
word no pack uses, and the pending marker already tells a player the truth.
