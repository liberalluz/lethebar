# ADR-0005 · Gameplay is declared as data, composed from engine bricks

## Context

The product is an engine that ships no gameplay. Third parties publish packages;
players install them and get a different game without a different build. That is
the whole point of the plugin layer, and a marketplace of gameplay plugins is the
intended shape of the ecosystem.

Today the engine exposes two protocols baked into the source
(`linear@1`, `turn_based@1`) and the registry rejects anything else (`V-06`), so a
package can bring new *content* but not a new *kind of gameplay*. ADR-0003 accepts
that boundary and states it plainly: "a genuinely new kind of gameplay requires a
new engine protocol, which is a product decision, not a plugin."

That boundary is correct for safety and wrong for the product. Under it every
gameplay plugin has to ship as an engine release, which means there is no
marketplace for the only thing worth selling.

The web target has no process sandbox and the native build goes through store
review, so executing untrusted plugin code is not available (ADR-0003 rejected
scripting for this reason, and that reasoning still holds).

## Decision

1. **Gameplay is data.** A package declares resources, actions, phases, checks,
   pools, relations and clocks. The engine interprets the declarations; it never
   executes plugin code.
2. **The engine provides a fixed set of primitives, called bricks.** They are the
   only means a package has of expressing gameplay: a state ledger, settlement
   rules, an action menu, a phase machine, checks, pools, relations, and an engine
   clock. Their field-level definition does not live here — it lives in the engine
   specification (`docs/specs/engine-bricks.md`), so that adding a field does not
   require editing this record. What this record fixes is that such a set exists,
   that packages may only compose it, and that the set is the engine's public
   surface.
3. **A new genre is a composition of bricks.** It must not require new engine code.
   The test of the design is that a second genre reaches a playable state by adding
   data only.
4. **Adding a brick is an engine change and a product decision. Adding a genre is
   not.** That is the line between what the engine owns and what packages own.
5. **Script-based packages are not part of this decision.** They remain a possible
   later, separate channel for "advanced plugins", and would need their own record
   covering sandboxing, signing and review before anything is built.
6. **Assets stay inside the package zip.** No external URLs: in-pack assets keep
   offline play working, make the size check meaningful, and remove an availability
   dependency from the marketplace.

## Consequences

- The engine grows primitives instead of genres, so `app/core/` carries no genre
  vocabulary and stays readable.
- The package format needs `kind` and `requires`, and `specVersion` moves to
  `2.0.0`; the two built-in packages change with it.
- Expressiveness is bounded by the brick set. A genre that needs something the
  bricks cannot express becomes a brick proposal, not a plugin.
- Every brick needs a validation rule and a negative test: an author's mistake is
  now a data error rather than a code error, and data errors are cheap to catch.
- Determinism stays structural. With no plugin code there is nothing that can read
  a clock or a random source outside the session seed.
- The brick set becomes a public surface. Renaming or removing a brick is a
  breaking change for every package that uses it.

## Rejected alternatives

- **Ship a scripting language now.** No sandbox on the web target, store review on
  native, and a second set of semantics to keep identical across platforms.
- **One protocol per genre in the engine.** This is the current state; it makes the
  marketplace impossible because the valuable plugins would all be engine releases.
- **Let packages carry arbitrary expressions.** It reopens an evaluator with its own
  injection surface, and the eight bricks already cover the genres the design
  enumerates.
- **External asset URLs.** They break offline play, make the size check meaningless
  and add supply-chain risk to a marketplace.

## Revisit conditions

- A genre in the design cannot be composed from the eight bricks and its absence
  blocks a release.
- A marketplace requirement that data-only packages cannot satisfy, such as
  third-party rendering or network play.
- A sandbox that works on both web and native, which would reopen the script
  channel as a reviewed, separate path.
