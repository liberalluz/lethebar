# ADR-0019 · A package may remember across runs

## Context

A run is deterministic: the same save, replayed to the same turn, produces the
same state. That is what makes a save trustworthy. But some packs want the
opposite of determinism at the edge — a shop that remembers what the player
sold it, a name the player chose once, a first-run flag. Today a package can
only keep that by writing it into the save, which makes the memory part of the
run and lets a replay change the past.

The engine already has a durable key-value store for packages, the same one the
saves use. What it lacks is a declared, typed table with a rule for who may
write it and where it lives relative to a save.

## Decision

A package may declare a small `persist` table in its manifest and name the
`persist@1` capability. The table is per bundle, not per run:

- keys are lower-case ids, values are scalars or flat arrays of scalars;
- at most 32 keys and 4 KiB of JSON per table;
- the declaration carries defaults, and a key never changes type;
- it is stored under `memory:<bundle id>` in the same backend as the saves, so
  it survives a page reload and is **not** erased when the package is removed;
- it never enters `snapshot()` or a save payload.

Effects write it with `persist.<key>` (`value` or `add`); rules read it as
`persist.<key>` in the same scope as the tick. A layer's table is declared
against its target bundle: after assembly there is one table, owned by the
bundle, because merged rules carry no provenance.

## Consequences

A replay of an old save can see a different memory than the run that produced
it. That is the cost of the feature and it is deliberate: the memory is the
player's, not the run's. Anything that must replay identically belongs in the
save, not here.

The table is small on purpose. A package that needs more than 32 keys or 4 KiB
is storing a world, not a memory, and should use a save or a content layer.

`V-47` refuses a table that is too large, mistyped, or declared without the
capability. The engine does not read a package's memory when the package is not
installed; the bytes stay until something writes them again.

## Alternatives

**A per-run table in the save** — rejected: it makes memory part of the run and
breaks replay.

**Let a layer own its own table** — rejected: merged rules cannot say which
layer wrote a value, so the write would have no stable owner.

**A generic key-value API** — rejected: an undeclared table cannot be type
checked at install, and a typo becomes a silent second key.
