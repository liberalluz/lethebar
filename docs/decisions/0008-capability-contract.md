# ADR-0008 · A package asks for capabilities, not for engine versions

## Context

Today a package declares two things about the engine it needs: `specVersion`
(the package format) and `engine` (a version range). Both answer "can this engine
read this file". Neither answers "can this engine do what the story needs".

The eight bricks made that gap visible. `B16` through `B21` grew a ledger, a
rules table, an action menu, a phase machine, a check library, pools and a
relation graph, and every one of them is either used by a package or ignored by
it. A package that waits on a relation, or draws from a pool, is asking for a
specific piece of behaviour; the manifest cannot say so, so the failure shows up
as a rejected field, a silently ignored block, or a button that is always
disabled.

The next genres make this worse. Card battle needs a hand, a deck and a
resolution order. A map genre needs cities, adjacency and travel days. Neither is
a narration feature, and neither should be smuggled in as a variation of
`turn_based@1`.

## Decision

A **capability** is a named, versioned piece of engine behaviour. Its identifier
is `name@major` — `map@1`, `cards.hand@1`, `battle.realtime@1`.

1. **The engine provides capabilities; packages only name them.** A package
   cannot introduce a capability, and a capability never comes from a package.
2. **A package declares what it needs.** `requires.capabilities` lists the
   capabilities the package cannot run without. An empty list is the same as
   omitting the field: the package needs nothing beyond narration.
3. **A missing capability refuses the install.** The rejection names the
   capability, not the field, and it uses a stable code in the same namespace as
   the other manifest rejections. It is never a warning, and the engine never
   starts a session that will fail later.
4. **Major versions are contracts.** `map@2` is a different capability from
   `map@1`; growing a capability in a compatible way keeps its major version and
   adds to what it guarantees.
5. **Capabilities do not change the save format.** A package that needs a
   capability still saves through `saveSchema`; the capability decides what the
   engine computes, not what a slot contains.
6. **The list is finite and public.** `docs/specs/capabilities.md` names every
   capability, whether it exists, which batch intends to grow it, and what would
   prove it works.

## Consequences

- A package written for a newer engine is refused at install with a sentence a
  player can act on ("this engine does not provide `map@1`"), instead of opening
  and misbehaving.
- The engine can stay small: a genre that needs new behaviour needs a new
  capability and a batch, not a fork.
- `docs/specs/capabilities.md` becomes a document that must be maintained with
  each such batch; an undocumented capability is treated as not existing.
- The rejection code is assigned by the batch that implements this record
  (`B29`), and the code table in `SDD.md` §4.2 is where it is written down. This
  record fixes only that the code exists, is stable and names the capability.

## Alternatives considered

- **One engine fork per genre.** Rejected: the save format, the language handling
  and the export pipeline would diverge three ways, and every fix would have to
  be made three times.
- **Let a package carry the code that provides the behaviour.** Rejected here and
  deferred to `ADR-0009`: it needs a sandbox, signatures and a separate review
  lane. Until then, "a capability comes from the engine" is what keeps an
  installed package harmless.
- **Infer the requirement from the data.** Rejected: a package that names a pool
  but never draws from it should not be refused, and a package that needs travel
  days should not be guessed at from coordinates. The declaration is explicit
  because the failure needs to be explicit.
- **A single engine version constraint, refined until it means something.**
  Rejected: it would turn every behaviour change into a version bump across all
  packages, and it still could not say *which* behaviour is missing.
