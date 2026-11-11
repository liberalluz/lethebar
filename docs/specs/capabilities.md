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

The Service column names the engine code that keeps the promise; the Blocks
column names the package data it reads. A capability with no service is not
implemented, and a service with no capability is invisible to packages.

| Capability | What the engine provides | Service | Blocks | Grown in | Proven by |
| --- | --- | --- | --- | --- | --- |
| `text@1` | labels, prose and choices drawn as text | view, i18n | nodes, i18n | `B1` | `TC-PROTO-001` |
| `render.2d@1` | a 2D canvas, textures, layout | view | assets | `B1` | `TC-ASSET-001` |
| `audio@1` | declared sound and music played and stopped | audio | assets | `B9` | `TC-ASSET-002` |
| `narrative@1` | scenes, choices, the linear traversal | session | nodes | `B2` | `TC-PROTO-001`, `TC-BUILTIN-001` |
| `rounds@1` | turn counter over a scene run, round readout | phases | phases | `B3` | `TC-PROTO-002` |
| `ledger@1` | named state values with bounds, clamped writes | ledger | ledger | `B16` | `TC-LEDGER-001` |
| `rules@1` | `{when, set}` tables applied after every step | mechanics | rules | `B16` | `TC-LEDGER-001` |
| `menu@1` | per-turn action list, availability reasons, end conditions | menu | actions | `B17` | `TC-TURN-001` |
| `phases@1` | turn budget, ranked bands, failure conditions | phases | phases | `B17` | `TC-TURN-001` |
| `pools@1` | declared item pools, one draw per item per run | pools | pools | `B18` | `TC-POOL-001` |
| `relations@1` | entity pairs, thresholds, relation state | relations | relations | `B18` | `TC-REL-001` |
| `conditions@1` | `when` clauses that read a relation or a drawn item | conditions | rules, relations | `B21` | `TC-WIRE-001` |
| `draws@1` | an action that draws from a pool in the same step | draws | pools, hand | `B21` | `TC-WIRE-001` |
| `clock@1` | a tick per turn or per scene, readable by rules | clock | clock | `B19` | `TC-CLOCK-001` |
| `actions@1` | action buttons rendered from package data, disabled with a reason | menu | actions | `B20` | `TC-SCENE-001` |
| `assets@1` | declared textures, audio and text bound to a scene | assets | assets | `B9` | `TC-ASSET-001` |
| `locale@1` | interface language, package translations, per-locale fallback | i18n | i18n | `B8`, `B10` | `TC-I18N-001` |
| `save@2` | three slots, previews, resume, durable write | save_store | save file | `B4`, `B23` | `TC-SAVE-001`…`TC-SAVE-003` |
| `offline@1` | installable web build, package and save survival without a network | service worker | — | `B6`, `B12` | `TC-OFF-001`…`TC-OFF-004` |
| `format@2` | package format `2.0.0`: `kind`, `layer`, `requires` | validator | manifest | `B15` | `TC-FMT-001` |
| `persist@1` | a small per-bundle memory table outside the save, written by effects and read by rules | persist_store | persist | `B112` | `run_tests.gd` (`B112`) |
| `roll@1` | named integer ranges derived from the seed and the turn, stable within a turn | session | rolls | `B113` | `run_tests.gd` (`B113`) |
| `cards.hand@1` | a hand, a deck, a draw and a discard, a resolution order | hand | hand, pools | `B41` | `TC-CARDS-001` |

A package needs none of these by name today: an empty `requires.capabilities`
means "narration only", which is what every existing package declares. The list
exists so that the next genre can ask for something specific.

## Planned

| Capability | What it would provide | Batch | What would prove it |
| --- | --- | --- | --- |

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

Anyone can ask for one. The request is the form in
`.github/ISSUE_TEMPLATE/capability_request.yml`; it asks for six things, because a
request that cannot answer them is a wish rather than a contract:

| Field | Why it is asked |
| --- | --- |
| what you want to happen | the player-visible behaviour, not the API |
| why data cannot express it | if a table can, the answer is a table |
| the smallest engine surface | one capability, not a framework |
| who else would use it | one package is content wearing an engine costume |
| what you do if it is refused | a fallback that keeps the request honest |
| a package that would use it | a request with no package cannot be checked |

### Five tests a request has to pass

1. **Data cannot express it.** If a table, a condition or a rule can produce the
   behaviour, the answer is content, and the request is closed as content.
2. **A second consumer exists, or is named.** A capability with one package is a
   table in that package. The request names the second author, the second genre, or
   the reason the second is certain rather than hoped for.
3. **It is world-agnostic.** No officer, no realm, no named place, no story's
   vocabulary. "The three kingdoms' morale rule" is content; "a resource that
   decays each turn unless a table raises it" is a capability.
4. **It does not break what exists.** An existing package keeps installing and
   playing. Growing a capability compatibly keeps its major version; changing what
   it guarantees starts a new one and needs an ADR.
5. **The cost is paid once.** The engine gains the behaviour; every world uses it
   without a second implementation. A capability that only moves complexity from
   one package into another is not accepted.

### Three answers, each written down

- **Accepted.** The request becomes a batch: this table gains a row with the batch
  that will prove it, the batch adds the behaviour, and the acceptance case is the
  one the request named.
- **Deferred.** The request stays open with the condition that would revive it —
  a second consumer appearing, a format change landing, a world asking twice. It
  goes in `capabilities.md` under Planned with "not scheduled" and that condition,
  so nobody has to remember it.
- **Refused.** The answer says which of the five tests failed and what would change
  it. A refusal is written where the request is, not in a conversation, because the
  next person will ask the same thing.

The list stays honest by the same two rules it always had: one capability serves
more than one package, or it is content; and a capability the engine does not
provide never appears as implemented — a package that needs it is refused by name,
and a package that omits it keeps working.
