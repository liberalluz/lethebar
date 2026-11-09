# ADR-0015 · The engine names the layer dimensions it applies

## Context

A layer declares one of six dimensions: `profession`, `genre`, `mod`, `content`,
`meta`, `assets`. The manifest has accepted all six since `specVersion 2.0.0`,
but the engine has only ever read two of them (`content` and `mod`). The other
four installed cleanly and changed nothing; the pack page still offered a tick,
so a player could choose a layer, save, and get the run they would have had
without it.

`B91` made that honest in the engine: `ManifestSchema.APPLIED_LAYERS` lists the
dimensions this build applies, `layer_applied()` answers for one, the pack page
marks the rest pending without a checkbox, and a layer whose `target` is not a
bundle is refused with `V-44` before the run starts.

What the list does not say is *how* a dimension becomes applied. `content` and
`mod` merge by replacing a block or a field; `assets` is a map of path to bytes
that the shell already reads from the bundle entry. Without a record of that
rule, the next dimension is designed from scratch and the merge order is
guessed.

## Decision

`ManifestSchema.APPLIED_LAYERS` is the single source of truth for which layer
dimensions this build applies. A dimension is added to it only in the batch that
gives it a consumer; the guide's list of what does not work is written by hand
from the same set and must name the same dimensions.

`assets` becomes applied in `B92`. The merge rule:

- `package_loader.gd` already reads every path the manifest declares into the
  package's `data.assets`; assembly merges each **applied** layer's map into the
  bundle entry's map, in assembly order.
- a path the bundle also declares is overridden by the layer, like every other
  layer dimension;
- a path two applied layers both carry is refused with `V-45`, naming both
  layers and the path, before a session starts. Two layers cannot both decide
  what the run shows, and picking the later one silently would make the
  assembly order visible only to whoever reads the source;
- a `pending` layer contributes no assets: the engine does not apply it, so its
  bytes never reach the run.

The shell is not changed: `_show_assets` already reads `entry.data.assets`, and
the merge fills that map on the bundle entry.

## Consequences

`profession`, `genre` and `meta` remain pending. Each needs a consumer before it
joins the list, and each is a separate batch. `check_pack.py` still cannot warn
an author that a layer's dimension is pending: the list lives in GDScript, and a
second copy in Python is its own decision.

The `V-45` rule is about paths, not slots: two layers may declare the same slot
under different paths, and the bundle decides which path its nodes reference.

## Alternatives

**Refuse inert layers at install.** Rejected for now: a layer can be written for
a newer engine and installed on an older one, and a refusal would make the pack
uninstallable rather than inert. The pending marker says the same thing without
blocking the install.

**Merge every dimension's assets, pending or not.** Rejected: a pending dimension
must change nothing, or the marker lies and the save can change when the engine
catches up.

**Warn in `check_pack.py` first.** Deferred: the author-side warning needs the
applied set in Python, and the two copies would drift unless a generator owns
them.
