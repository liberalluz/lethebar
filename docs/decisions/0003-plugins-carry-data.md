# ADR-0003 · Plugins carry data, never code

## Context

Plugins come from third parties and are installed by players. The engine must run
them on a web build, where there is no process sandbox to isolate untrusted code,
and the same package must later run inside a native iOS app under store review.
Sessions must also be reproducible from the same choices.

## Decision

A plugin contains **only data**: a manifest, node graphs, declarative mechanic
rule tables and assets. Gameplay is selected from a **protocol registry** the
engine provides (`linear@1`, `turn_based@1`). No scripting language is exposed to
plugins, and the engine never executes plugin-supplied code.

## Consequences

- Untrusted packages cannot execute code: the failure surface is bad data, which
  validation can reject (`V-01` … `V-09`).
- Determinism is structural: with no plugin code there is nothing that can read
  the clock or a random source outside the session seed.
- Expressiveness is bounded. A genuinely new kind of gameplay requires a new
  engine protocol, which is a product decision, not a plugin.
- Plugin authors work within declared rules; the specification must therefore be
  precise, and its gaps become engine bugs rather than author mistakes.

## Rejected alternatives

- **Ship GDScript inside the package and load it at runtime.** Untrusted code
  execution with no sandbox on the web target, and no reviewable boundary for a
  store build.
- **Evaluate JavaScript through the web bridge.** Same risk plus a second runtime
  to keep compatible across web and native.
- **A per-node expression language.** Smaller surface than a full script, but it
  still needs an evaluator whose semantics must match across platforms, and it
  reopens injection surface for a capability the SRS does not require.
