# ADR-0018 · One block, one name

## Context

Three names described the same data. The capability is a contract
(`relations@1`), the block is the key the session reads (`factions`), and the
file is the path in the archive (`data/factions.json`). Two of the three
disagreed, and the guide printed the file name next to the capability name, so
an author could not tell which one the engine actually reads. `state.json` and
`cards.json` had the same problem: the blocks were already `ledger` and `hand`,
but the files were named after something else.

## Decision

The file is named after the block: `data/<block>.json`. The three files that
disagreed are renamed:

| block | file before | file now |
| --- | --- | --- |
| `ledger` | `data/state.json` | `data/ledger.json` |
| `relations` | `data/factions.json` | `data/relations.json` |
| `hand` | `data/cards.json` | `data/hand.json` |

The engine reads only the new names. There is no compatibility path: the engine
has no published packages to keep working, and a second spelling would recreate
the confusion this decision removes. A package that carries an old name keeps
whatever block it does not declare, exactly as if the file were absent.

Capabilities are not renamed. A capability names what the engine promises
(`relations@1`); several capabilities can read the same block, so a one-to-one
capability/file rule would be false. `phases@1` feeds both rounds and phases,
`actions@1` feeds the menu and the action list.

## Consequences

- The guide, `capabilities.md` and the SDD name files only by their block.
- The archive format stays 2.0.0: the set of file names changed, the shape did
  not.
- The three world packages that still carry `state.json` must be renamed before
  they are published again; the engine will not read the old name.
- `check_guide_examples.py` (B106) can compare a data path in the guide with the
  loader's constants, so a fourth spelling cannot appear unnoticed.

## Alternatives

- **Rename capabilities instead** (`factions@1`, `state@1`): rejected, because
  a capability is a promise about behaviour, not about a file, and renaming one
  would break every package that declares it.
- **Read the old names as a fallback**: rejected, because nothing is published
  yet; compatibility here only hides which name is real.
- **Reject the old names with a new check**: deferred; silently reading nothing
  is the same failure mode as a missing file, and an explicit refusal can be
  added when there is a reason to keep an old package alive.
