# ADR-0009 · A package is data, and there are two tiers of it

## Context

`ADR-0003` decided that plugins carry data, not code. `SECURITY.md` repeats the
consequence: an installed package is treated as untrusted input. That decision
is what makes "install a zip you downloaded" acceptable in a browser game with no
server and no sandbox.

It is not a complete answer, for two reasons.

First, "data" still has ways to hurt an engine: an archive can be a bomb, a path
can climb out of the package root, an image can be enormous, a JSON file can be
deep enough to blow the parser. None of these need code.

Second, the choice was made too early to be permanent. Some genres — a scripted
encounter, a moddable card game — will eventually want logic that the eight
bricks cannot express. If the contract says "never any code", that day becomes a
rewrite of the installer, the validator and the marketplace at once.

## Decision

There are two trust tiers. Only the first one can be installed today.

**`data-only@1` — the only installable tier.** A package is JSON plus assets
(`texture`, `audio`, `text`). The engine never executes a byte of it: rules are
`{when, set}` tables, menus are data, the draw is engine code. This tier is the
default, and the only tier a marketplace may publish.

**`scripted@1` — named, not implemented.** Not accepted by the installer and not
planned for a version yet. It is written down here so the boundary is a decision
rather than an omission, and so the preconditions are explicit:

1. **An isolated runtime.** WebAssembly with a capability-based host interface, or
   a restricted expression language with a step budget. Never raw GDScript:
   loading a `.gd` file runs it with the engine's own privileges, which is the same
   as handing over the machine.
2. **Mandatory signatures.** An unsigned scripted package is not installable at
   all, not even with a warning.
3. **An explicit confirmation, off by default.** Installing a scripted package
   says what it can do and requires a deliberate action; the setting that allows
   them starts disabled.
4. **A separate review lane.** The marketplace reviews scripted packages
   separately from data-only ones, and a data-only package that later gains a
   script is a new submission, not an update.

Two further rules keep the tiers from leaking into each other:

- **The install-time envelope applies to both.** The loader checks it before the
  manifest is read, from the constants in `app/core/package_limits.gd`; every
  refusal names what was measured and uses the same stable codes as the other
  manifest rejections.

  | Limit | Value | Code |
  | --- | --- | --- |
  | The archive | 8 MB | `V-28` |
  | Entries | 500 | `V-28` |
  | One entry, unpacked | 4 MB | `V-28` |
  | Everything unpacked | 32 MB | `V-28` |
  | Path shape | relative, `[a-z0-9._/-]`, no `..`, no backslash | `V-29` |
  | Picture edge | 4096 px | `V-30` |
  | Audio | 2 MB and 60 seconds | `V-30` |

  There is no compression-ratio rule. Godot 4.7's `ZIPReader` reports files and
  bytes, not an entry's declared size, so a ratio cannot be measured here; the
  32 MB unpacked cap already bounds how far an archive can expand.
- **A capability still comes from the engine.** `ADR-0008` stands unchanged. The
  `scripted` tier, when it exists, lets a package *use* a capability the engine
  provides; it does not let a package provide one.

## Consequences

- The installer, the validator and the marketplace all test one tier today, which
  is why "no code" can be a promise instead of a policy.
- The contract does not have to be rewritten to add code later: a new tier is a
  new install path, and the data-only packages are untouched.
- The envelope limits are engine policy, not content moderation. A package that
  passes every limit can still be offensive; that is the marketplace's problem
  (`ADR-0011`), and this record keeps the engine from pretending otherwise.
- `SECURITY.md` gains one paragraph: what the engine refuses, and what it cannot
  judge.

## Alternatives considered

- **Allow code now, sandbox later.** Rejected: an unsandboxed script is total
  access, so shipping it "temporarily" would be shipping the worst version first.
- **No limits; trust the parser.** Rejected: a 4 GB zip and a 100 000-deep JSON
  document are cheap to build and do not fail politely in a browser tab.
- **Sandbox every package now.** Rejected: it costs a runtime and a signature
  pipeline to support packages that do not exist yet, and the data-only tier
  already covers every built-in story.
