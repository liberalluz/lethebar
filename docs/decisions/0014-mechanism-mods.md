# ADR-0014 · A mechanism mod changes what is declared, and only that

## Context

The project calls one of its seven cells a *mechanism mod*: a change to how a run
behaves inside a genre — a tighter economy, a harsher winter, a different cost
curve — without writing a new genre.

Today that cell has no independent form. A mod is data inside the package that needs
it: `data/mechanics.json`, the thresholds in `data/phases.json`, the numbers in
`data/actions.json`. Two variants of one story are two packages, and changing one
cost means copying a hundred cards.

The engine is about to grow an assembly layer (`ADR-0013`), which makes a mod a
package with `kind: mod` and a `layer` target. That is a change of form every few
versions, and without a record of *why* each step waits for the previous one, the
next person reads "mods cannot be installed separately" as an oversight.

## Decision

**A mod is a package that changes fields another layer already declared.** It adds
no capability, no field, no file type and no code. If a change needs a new field to
exist, the field belongs in a capability, and capabilities live in the engine
(`ADR-0008`).

**Four phases, each with its precondition:**

| Phase | When | Form | Allowed | Precondition |
| --- | --- | --- | --- | --- |
| 0 | now, through `v0.3.0` | fields inside the package that needs them | tuning numbers, adding rules | none |
| 1 | after the assembly layer (`v0.4.0`) | `packs/<pack>/mods/<slug>/`, `kind: mod`, `layer` set | override, append, disable declared fields | merge semantics, an acyclic chain, a conflict code |
| 2 | after phase 1 is in use | its own repository, `lethebar-mod-<family>` | the same, shared across worlds | at least three mods over one target, and a second world wanting one |
| 3 | after the marketplace (`v1.0.0`) | a listed variant on its target's page | install and uninstall, reversibly | composition preflight, review by `kind` |

Phase 1 without phase 2 is the normal state for a long time: the mod lives next to
the pack it changes, in the same repository and the same version number, so the two
cannot drift. Moving it out is a distribution decision, not a correctness one.

**The hard line.** A mod changes; it never adds. Concretely, a mod may set a number,
replace a table entry, append to a declared list or disable a declared entry. It may
not introduce a resource, an action, a card, a rule shape, or a field the base
package does not have. A change that wants to add is either content (a new package)
or capability (engine work), and both have their own path.

**Uninstall returns to the base, byte for byte.** The acceptance for every phase is
the same comparison: run the base, run base plus mod, remove the mod, run again, and
the first and third runs produce identical views and identical saves.

## Consequences

- Until phase 1, "two variants of a story" stays two packages; that duplication is
  the honest cost of not having merge semantics, and it is recorded rather than
  hidden.
- A mod repository cannot exist before the assembly layer without becoming a folder
  of files that nothing applies — which is why phase 2 is gated on use, not on
  enthusiasm.
- The marketplace cannot list a mod before phase 3, because a mod without a resolved
  `layer` is an install that does nothing.
- Every phase keeps the same acceptance comparison, so the meaning of "the mod works"
  does not change as the distribution form does.

## Alternatives considered

- **Ship independent mods now, with `layer` declared but unused.** Rejected: it
  creates a class of packages that install successfully and change nothing, and the
  first bug report about it will be unanswerable.
- **Let a mod add fields, and let the engine ignore unknown ones.** Rejected: that is
  how a data format becomes a programming language by accident.
- **Skip to a mod repository, keep merge semantics for later.** Rejected: the
  repository is the easy part; without merging it is an empty promise with a CI.
- **Make every change a capability instead of a mod.** Rejected: "the economy is
  harsher" is not a new way to play, and turning every tuning knob into an engine
  capability would bloat the engine with one-off switches.

## Amendment (B86)

- A player can remove an installed package from the pack page: the first press
  asks, the second erases the registry record and the stored bytes, so `V-03`
  no longer makes a wrong version permanent. A bundle that still owns a layer is
  refused, and the refusal names the layers, because removing the base first
  would leave records whose `target` names nothing.
- Removal is the phase-1 form of the reversibility this ADR asks for, and it does
  not wait for the marketplace. The acceptance is unchanged: run the base, run
  the base plus the layer, remove the layer, run again — the first and third runs
  show the same view and write the same save.
- A save that needed the removed layer refuses to open with `E-02`; it is not
  deleted.
