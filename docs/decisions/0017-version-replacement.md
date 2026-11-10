# ADR-0017 · A newer package keeps the one it replaced

## Context

`V-03` refused any second version of an installed id. A player who wanted an
author's fix had to remove the package first, which erased its bytes and left
the old version unreachable; an author who shipped a fix broke the only path a
player had to the version that worked. The check was protecting identity, but it
was also making every upgrade a one-way door.

## Decision

A package whose `version` is newer than the installed one installs over it. The
bytes it replaced are kept once, under `previous:<id>`, and the pack page offers
a `Restore <version>` control while that copy exists. Restoring re-imports the
kept bytes explicitly, so it is not a `V-03` refusal; the version it replaces
becomes the new previous copy, which makes the control a toggle between two
versions.

`V-03` now refuses only a lower version, and its message names both versions.
Re-importing the same version is allowed and changes nothing. Removal erases the
previous copy with the package.

Saves are untouched: a slot is keyed by package and slot, and its payload names
the version it ran under. A save made before an upgrade opens on the new version
when the node ids it names still exist; an upgrade that renames or deletes them
makes the save unreadable. `saveSchema` stays one-way, so rolling back does not
make a newer save readable.

## Consequences

A package repository grows by at most one zip per package. Two versions are
reachable from the pack page without clearing site storage. An author can ship a
fix without asking players to remove and re-install. The engine still cannot
merge two histories: there is one previous copy, not a list.

## Alternatives

- **Keep every version.** Rejected: a package repository would grow without a
  bound the engine can enforce, and the pack page would need a version picker.
- **Refuse downgrades and offer no rollback.** Rejected: it keeps the one-way
  door and gives a player no way back from a broken release.
- **Key saves by version.** Rejected: it would make every upgrade orphan the
  saves it should keep, and the payload already records its version.
