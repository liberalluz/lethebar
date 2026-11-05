# Capabilities

A capability is a named, versioned piece of engine behaviour that a package can
require. The contract is in `docs/decisions/0008-capability-contract.md`; this
file is the list it points at.

A capability identifier is `name@major`. The engine provides it; a package names
it in the `capabilities` field of its manifest; an engine that cannot provide it refuses the
install and names what is missing. Growing a capability compatibly keeps its
major version; changing what it guarantees starts a new one (`map@2`).

A package is checked when it is installed, not when it is played: an unknown
capability is `V-27`, and a format 1.0.0 package that still names a capability
without its major version installs with `W-03` so that nothing published earlier
stops working (ADR-0006). The ids below are the ones this build accepts.

Nothing here describes content. Officers, cards, cities and scenes are data a
package carries; a capability is what the engine knows how to do with them.

## Implemented

| Capability | What the engine provides | Grown in | Proven by |
| --- | --- | --- | --- |
| `narrative@1` | scenes, choices, the linear traversal | `B2` | `TC-PROTO-001`, `TC-BUILTIN-001` |
| `rounds@1` | turn counter over a scene run, round readout | `B3` | `TC-PROTO-002` |
| `ledger@1` | named state values with bounds, clamped writes | `B16` | `TC-LEDGER-001` |
| `rules@1` | `{when, set}` tables applied after every step | `B16` | `TC-LEDGER-001` |
| `menu@1` | per-turn action list, availability reasons, end conditions | `B17` | `TC-TURN-001` |
| `phases@1` | turn budget, ranked bands, failure conditions | `B17` | `TC-TURN-001` |
| `pools@1` | declared item pools, one draw per item per run | `B18` | `TC-POOL-001` |
| `relations@1` | entity pairs, thresholds, relation state | `B18` | `TC-REL-001` |
| `conditions@1` | `when` clauses that read a relation or a drawn item | `B21` | `TC-WIRE-001` |
| `draws@1` | an action that draws from a pool in the same step | `B21` | `TC-WIRE-001` |
| `clock@1` | a tick per turn or per scene, readable by rules | `B19` | `TC-CLOCK-001` |
| `actions@1` | action buttons rendered from package data, disabled with a reason | `B20` | `TC-SCENE-001` |
| `assets@1` | declared textures, audio and text bound to a scene | `B9` | `TC-ASSET-001` |
| `locale@1` | interface language, package translations, per-locale fallback | `B8`, `B10` | `TC-I18N-001` |
| `save@2` | three slots, previews, resume, durable write | `B4`, `B23` | `TC-SAVE-001`…`TC-SAVE-003` |
| `offline@1` | installable web build, package and save survival without a network | `B6`, `B12` | `TC-OFF-001`…`TC-OFF-004` |
| `format@2` | package format `2.0.0`: `kind`, `layer`, `requires` | `B15` | `TC-FMT-001` |

A package needs none of these by name today: an empty `requires.capabilities`
means "narration only", which is what every existing package declares. The list
exists so that the next genre can ask for something specific.

## Planned

| Capability | What it would provide | Batch | What would prove it |
| --- | --- | --- | --- |
| `cards.hand@1` | a hand, a deck, a draw and a discard, a resolution order | not scheduled | a card battle package plays a full hand with no engine change per card |
| `map@1` | cities with coordinates, adjacency with travel days, a travel action | not scheduled | a package moves between two cities and arrives after the declared days |
| `units@1` | officer and troop instances with stats, loyalty and assignment | not scheduled | a package assigns an officer to a city and reads their stats back |
| `battle.turnbased@1` | a resolution of two stacks with per-unit strength and modifiers | not scheduled | two stacks fight to a declared outcome that a test can reproduce |
| `battle.realtime@1` | a ticked battle runtime with player intervention points | not scheduled | a battle runs, the player intervenes once, and the report explains the outcome |

"Not scheduled" is deliberate: these are the capabilities the two known genres
would need, and writing a batch for them before the genre is designed would fix
behaviour we cannot yet justify. The card battle branch comes first.

## Adding a capability

A capability is added by the batch that implements it, in the same pull request
that changes `SDD.md` §4.2 (or the equivalent section) and this table. If the
addition changes what an existing capability guarantees, it is a new major
version and an ADR, not an edit here.

Two rules keep the list honest:

- **One capability serves more than one package, or it is content.** If only one
  story could ever use it, it is a table in that story's data, not engine code.
- **A capability the engine does not provide does not appear as implemented.**
  A package that needs it is refused by name; a package that omits it keeps
  working.
