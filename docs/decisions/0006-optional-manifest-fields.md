# ADR-0006 · Optional manifest fields do not bump `specVersion`

## Context

`B10` added three manifest fields — `defaultLocale`, `locales` and `names` — so a
package can ship translations instead of duplicating scenes. They are read only
when present, and a package that omits them behaves exactly as before: the scene
text in `nodes.json` is what the reader sees.

ADR-0005 reserved `specVersion: 2.0.0` for the batch that introduces the eight
bricks. That work has not happened. The question this record answers is whether
adding these three fields forces a format version bump, which would in turn force
every existing package to edit its manifest.

The stable-cache decision (recorded in `docs/specs/engine-bricks.md`) also matters
here: the export embeds the package format version, so a bump would invalidate
cached packages that are otherwise unchanged.

## Decision

The manifest version stays `1.0.0`. A field that satisfies all four of these is an
optional addition and does not bump the version:

1. **Absent means old behaviour.** A package without the field installs and plays
   exactly as it did before the field existed.
2. **Validation never rejects for its absence.** Only a present-but-wrong value is
   rejected, and the rejection has its own code.
3. **The engine never requires it.** No new code path makes the field mandatory
   later; a future requirement is a version bump.
4. **An older engine can still read the package.** An engine that predates the
   field ignores it and plays the package's default text.

`defaultLocale`, `locales` and `names` meet all four. `specVersion: 2.0.0` stays
reserved for changes that break one of them — a changed field meaning, a field that
becomes mandatory, or data the old engine cannot read.

## Consequences

- Existing packages keep installing with no edits, and their `specVersion` stays
  `1.0.0`.
- The test suite must prove the "absent means old behaviour" clause for every
  optional field; `TC-I18N-001` does it for these three.
- The obligation moves to future authors: if a fourth field cannot satisfy the
  four rules above, it belongs in the `2.0.0` batch, not next to these three.
- Readers of `SDD.md` §3.2 now have to check this record to know why the version
  line did not move; that is the cost of not bumping.

## Alternatives considered

- **Bump to `1.1.0`.** Rejected: the format is versioned by compatibility, not by
  feature count, and a minor bump would still invalidate the cache and still make
  authors ask whether they must edit.
- **Bump to `2.0.0` now, together with the bricks.** Rejected: it couples two
  unrelated changes and would ship a major version whose headline feature does not
  exist yet.
- **Create a separate `locales.json` file instead of manifest fields.** Rejected:
  it splits one concept across two files and makes "does this package support my
  language" a second read.
