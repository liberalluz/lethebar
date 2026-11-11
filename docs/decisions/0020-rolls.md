# ADR-0020 · A roll is derived, not drawn

## Context

The engine already has a seeded generator: `Session.rng` starts from the bundle
id and a start counter, and every draw and shuffle advances it. That makes a run
reproducible — the same save, replayed, produces the same order.

The same property makes a chance event exploitable. A pack that wants "roll a
die" has no stable number it can read: the only stream advances with play, so a
player who reloads a save rolls again until the result pleases them. Closing the
save in the middle of a turn must not change what that turn's die says.

## Decision

A bundle may declare named integer ranges in `manifest.rolls` and name the
`roll@1` capability:

- a name is a lower-case id, `{from, to}` are integers, `from <= to`, the span is
  at most one million, and a manifest declares at most sixteen rolls;
- `Session.roll(name)` derives the value from `seed`, the current turn, the name
  and the bundle id, using a non-cryptographic mixer (FNV-1a then a shift-xor);
- the same turn always gives the same value, so a reload does not reroll it;
- different turns give independent values from the same range;
- the derivation does **not** advance `rng`: the hand order and pool draws of an
  existing package keep the sequence they had.

Rules read a roll as `roll.<name>`. An effect spends one with
`{"gold": {"add_roll": "loot"}}`, which the session resolves to `{"add": n}`
before the effect reaches the mechanics; a plain `add` beside it still works.

The snapshot carries `seed`, and `SaveStore.resume` restores it (a payload
written before this batch has no `seed`, so it falls back to `rng`).

## Consequences

A player who edits the save can edit the seed and therefore choose rolls. This is
not an anti-cheat mechanism and does not pretend to be one; it only guarantees
that an unedited save cannot be rerolled by reloading.

Because the value is a function rather than a stored number, the same roll can be
read any number of times in a turn and everyone agrees. A rule that wants "one
roll per turn" reads it once; a rule that reads it twice sees the same number.

Rolls are not part of the protocol or the scene graph. They do not schedule a
turn and they do not add a field to a node.

## Alternatives

**Draw from `rng` and store the result** — rejected: it advances the shared
stream, changes existing hand and pool sequences, and still needs a stored value
to survive a reload.

**A cryptographic hash** — rejected: nothing here is a security boundary, and the
dependency is not worth it.

**Let packages supply their own seed** — rejected: it would make a save's rolls
unrelated to the run it belongs to.
