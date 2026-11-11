# Protocols: the shape of a story

English · [简体中文](protocols.zh-CN.md)

A protocol is the answer to one question: how does a run move from one moment to
the next? The engine implements protocols; a package picks one in its manifest
and the engine plays the story with that shape.

Two protocols ship today. A package names one in `protocol`, and `V-06` refuses
an install when the name is not in the table below.

<!-- generated:protocols -->

| Protocol | Implemented by | What the story has to look like | What to declare |
| --- | --- | --- | --- |
| `linear@1` | `app/protocols/linear_v1.gd` | one node at a time, choices lead to other nodes; a node without choices ends the run | `data/nodes.json` with `entry`, every choice naming a `next` node |
| `turn_based@1` | `app/protocols/turn_based_v1.gd` | the same walk, plus a round counter that advances when a node is left | `data/nodes.json`; `data/phases.json` if the run should have a limit |

<!-- /generated:protocols -->

## Choosing one

- A story where every moment is a decision and the last moment has no choices
  left is `linear@1`. This is the shape of the smoke story and of most short
  things.
- The same story with a round counter, a limit and ranks that change as the
  rounds pass is `turn_based@1`. The counter advances when a node is left, so a
  run of twelve turns is a run that visits twelve nodes.

The difference is the counter, not the depth. Neither protocol knows about
combat, initiative or hidden information; if a story wants those, they have to
be expressed as resources, rules and choices inside one of the two shapes.

## The third way to play is not a protocol

The engine also ships a capability called `cards.hand@1`. It is not a protocol:
it rides on either one and adds a hand of cards to the session, with a deck, a
cost per card and an optional picture. A package that declares it needs a
`data/hand.json`; `V-36` refuses a hand without a deck, `V-37` a card naming a
resource that does not exist, and `V-39` a card pointing at a picture the
package never declares.

So there are two protocols and one capability. If you were looking for a third
protocol: there is none, and adding one means writing code in the engine, not
data in a package.

## What a protocol never does

It never reads your text and it never decides anything about your story. It
decides when a turn passes, what a view looks like, and what a snapshot has to
carry so that a save can resume mid-run. Everything a player is told comes from
`data/nodes.json`, `data/actions.json` and their translated copies.
