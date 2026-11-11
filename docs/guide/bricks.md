# The eight bricks

English · [简体中文](bricks.zh-CN.md)

A package does not describe a game. It declares data files, and each file turns
on one part of the engine. Eight parts exist. Nothing else does: a package that
wants a ninth kind of rule is asking for a new engine capability, not a clever
data file.

| What a player experiences | Which brick |
| --- | --- |
| numbers that go up and down and stop at a floor | state ledger |
| a choice that changes two numbers by different amounts | settlement rules + action menu |
| a run that ends after twelve turns | phase machine |
| a choice that only appears once you have the sword | pools + checks |
| a world that remembers who stands where | relations |
| a limit that is not a turn, such as a cooldown | clock |

## The table

Every row names the data file that turns the brick on and the engine file that
reads it. The table is generated from the source, so a reader file that moves or
disappears breaks the generator before it can mislead a reader.

<!-- generated:bricks -->

| Brick | Turned on by | Read by | What it owns |
| --- | --- | --- | --- |
| 1. State ledger | `data/ledger.json` | `app/core/ledger.gd` | the resources a run keeps, each with a start, a floor and a ceiling |
| 2. Settlement rules | `data/rules.json` | `app/core/mechanics.gd` | when a state looks like this, change that state by this much |
| 3. Action menu | `data/actions.json` | `app/core/menu.gd` | what a player can do, what it costs, what it changes, how often |
| 4. Phase machine | `data/phases.json` | `app/core/phases.gd` | the turns a run has, the ranks it passes through, the ways it ends |
| 5. Checks | `data/checks.json` | `app/core/checks.gd` | a named test on the state that a choice or a card can ask for |
| 6. Pools | `data/pools.json` | `app/core/pools.gd` | a set of items drawn without repeats, or dealt as a hand |
| 7. Relations | `data/relations.json` | `app/core/relations.gd` | who stands where with whom, and what a change of standing moves |
| 8. Clock | `manifest.json `clock`` | `app/core/session.gd` | when a turn passes: every choice, every node, or every n of them |

<!-- /generated:bricks -->

## How a brick is turned on

By declaring the file. A package with `data/ledger.json` and `data/actions.json`
has a ledger and a menu; a package with neither still installs and plays a
linear story, because those two bricks are the only ones a run insists on.

Leaving a file out is not an error. Declaring it badly is: the validator reads
every data file the manifest implies, and refuses the install when one of them
names something that does not exist. Three examples of that shape:

- an action costs `gold`, and `data/ledger.json` never declares `gold` — `V-16`
- a rule sets `standing` to `allied`, and `data/relations.json` never declares
  `allied` as a state — `V-25`
- an action draws from `relics`, and `data/pools.json` never declares that pool —
  `V-26`

The full list, with the sentence each code carries, is on the
[errors page](errors.md).

## What the bricks deliberately do not do

There is no expression language. A condition is a resource compared with a
number, a relation holding, or an item that was drawn; anything more complicated
is written as several rules that fire in turn. There is no runtime scripting
either: a package that needs code is asking for `scripted@1`, which the engine
does not ship, and the answer today is no.

Two consequences: numbers are floats, so a cost of `0.5` is legal; and rules
run in the order they appear in `data/rules.json`, so a later rule sees what an
earlier one wrote.

## One name per block

A block's file is named after the block: `data/ledger.json`, `data/relations.json`, `data/hand.json`. Packages published before v0.7.5 used `state.json`, `factions.json` and `cards.json`; the engine reads only the block name now (ADR-0018).

## Ids inside a data file

Every id you write inside a data file — an action, a resource, a pool, a relation entity — matches `^[a-z][a-z0-9_]*$`: lowercase letters and digits, joined with underscores, starting with a letter. A hyphen is not part of that grammar.

| | |
| --- | --- |
| good | `send_apan_herb`, `stone`, `trust_apan` |
| bad | `send-apan-herb`, `2stone`, `trust.apan` |

The package id is the one exception: it allows hyphens (`^[a-z0-9-]+$`) because it is a URL segment and a save key, not a data id.

The rule is not cosmetic. An action id is reused as `action.<id>` in the translation file, stored in the save's `used` table, accepted by `disable.json`, and printed in the run. Changing it after a player has a save is a data migration, so pick the underscore form the first time. `V-16` refuses the archive at install when the grammar is broken.
