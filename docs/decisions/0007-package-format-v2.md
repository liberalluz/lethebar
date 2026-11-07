# ADR-0007: package format v2

**Status**: accepted (2026-11-04)

## Context

`specVersion` is `1.0.0` and has been since the first package was written. It
describes four things: a zip with `manifest.json`, `data/nodes.json`,
`data/mechanics.json` and assets. That is enough for two stories and two
protocols, and it is not enough for anything else the project intends to ship.

The v0.1.0 work adds eight engine bricks (`docs/specs/engine-bricks.md`) and a
package that plays a different genre. The bricks need somewhere to be declared,
and a genre that plays differently needs a way to say which pieces it is built
from. Neither fits in `1.0.0` without guessing at field names three times over,
which is exactly what the bricks spec was written to avoid.

The seven-layer design (`lethebar-docs/design/02`) splits a game into an engine,
a profession pack, a genre pack, mechanic mods, a content layer, meta and an
asset pack. Today's package is the last mile of that: one zip that carries
story, mechanics and assets together, with no way to say "this story needs the
Three Kingdoms profession pack". Adding that in the middle of a release would
mean two ways to describe the same package at once.

## Decision

**A package declares `specVersion: "2.0.0"`, and with it `kind`, `layer` and
`requires`.**

1. `kind` is `bundle` or `layer`.
   - `bundle` is playable on its own. It is what `sanguo` and `cultivation` are
     today.
   - `layer` is a piece that only means something when a bundle requires it.
2. `layer` is required when `kind` is `layer`, and names one of
   `profession | genre | mod | content | meta | assets`. It is ignored when
   `kind` is `bundle`.
3. `requires` is an array of `{id, version}` pairs, using the same version
   constraint syntax as `engine` (`>=4.7.0 <5.0.0`). A bundle may require any
   number of layers; a layer may require other layers.
4. Resolution looks in the installed catalog first, then the built-in catalog
   shipped inside the build. A missing requirement is a validation error
   (`V-24`), not a runtime failure halfway into a scene.
5. The bricks are switched on by the presence of their data file, not by a
   manifest list. A package with `data/nodes.json` alone behaves exactly like a
   `1.0.0` package, which is what makes the migration cheap.
6. `1.0.0` packages stay readable through v0.1.x and are refused from v0.2.0.
   Reading one produces a warning (`W-01`) that names the missing
   `specVersion`, so an author sees it before it becomes an error.

## Alternatives considered

- **Leave `specVersion` at `1.0.0` and add fields as optional.** This is what
  ADR-0006 did for `defaultLocale`/`locales`/`names`, and it was right there:
  an old engine reads the package the same way, because the fields only change
  presentation. It is wrong here: `requires` can make a package unplayable
  without another package, so an engine that ignores it would start a game it
  cannot finish. A missing requirement has to be an error in engines that
  understand it and must not be a silent no-op in engines that do not.
- **Keep one format and express layers as a `kind` field without versioning.**
  Then a `1.0.0` engine that meets a `kind: layer` package has no rule to
  follow. Versioning the format is the rule.
- **Stop accepting `1.0.0` at v0.1.0.** Cleaner to implement, but it strands
  every package written before today, including the two built-ins, at the exact
  moment the project starts asking for third-party packages (`TC-PKG-005`).
  One release of overlap costs a warning line.
- **Assemble layers at build time into one bundle.** That would keep the
  runtime simple but moves composition into a build step, and the design wants
  composition at install time so a player can mix a story with a different
  mechanic mod.

## Consequences

- `app/core/manifest_schema.gd` gains three fields and their shape checks
  (`V-23`); `app/core/package_validator.gd` gains `V-24` and `W-01`.
- The two built-in packages are migrated to `2.0.0` in the same batch that
  teaches the schema, so there is never a build that reads a format it cannot
  produce.
- `docs/specs/controlled/SDD.md` §3.2 is normative for `1.0.0` and must be
  updated when the batch lands, with `BL-1` re-registered (the baseline records
  the document hashes). This ADR records the decision; the SDD change belongs to
  the format batch, not to this one.
- The engine keeps refusing unknown protocols (`V-06`) and now also refuses a
  bundle whose requirements cannot be resolved. Both are the same principle:
  a package that cannot be played is rejected at install time, not at the scene
  where it runs out.
- A layer that nothing requires is not an error. It is installed and does
  nothing, which is what a player sees after installing a mod for a story they
  have not installed.
