# A mod layer, end to end

A `mod` layer changes numbers and costs that a bundle already declared. It does
not add a story: the nodes, the entry node and the phase machine stay the base
pack's, because a run with two beginnings is not a run. What it can do is make
the same story play differently — a tighter economy, one more action, a card
someone took out.

This page walks one from an empty folder to a published release, then shows how
to prove it took effect inside a run rather than only that it installed.

## The folder and the manifest

```
your-world-repository/
└── packs/
    └── sanguo-hard/
        ├── manifest.json
        └── data/
            ├── state.json       the resources it rewrites
            ├── actions.json     the actions it adds
            └── disable.json     the actions it removes
```

The smallest layer that installs and takes effect:

```json
{
  "id": "sanguo-hard",
  "version": "1.0.0",
  "specVersion": "2.0.0",
  "kind": "layer",
  "layer": "mod",
  "target": "sanguo",
  "requires": ["sanguo"],
  "engine": ">=4.7.0 <5.0.0",
  "name": "Three Kingdoms, harder",
  "defaultLocale": "en",
  "protocol": "turn_based@1",
  "capabilities": ["text@1", "ledger@1"],
  "mechanics": ["grain", "coin", "troops", "standing"],
  "entry": "placeholder",
  "saveSchema": 1,
  "assets": []
}
```

Three fields are what make it a layer: `kind`, `layer` and `target`. `target` is
the id of the bundle it changes; `requires` says what has to be installed for it
to be usable. `protocol` and `entry` are repeated only because the format still
asks for them; nothing reads a layer's `entry`, and it needs no node in
`data/nodes.json` (`V-07` asks only a bundle).

If the manifest declares `locales`, every node in `data/nodes.json` needs a
non-empty entry in each `data/i18n/<locale>.json`, keyed by node id. A table
shaped like `{"strings": {...}}` passes nothing; the install is refused with
`V-22: data/i18n/en.json has no entry for node <id>`. A layer that carries no
nodes needs no `locales` at all.

## What it may change

| Input file | Effect | Limits |
|---|---|---|
| `data/state.json` | the resource is **replaced wholesale**: bounds, start value, label | only a resource the base already declares; a new name is skipped |
| `data/actions.json` | actions are **added** | an id the base already uses is refused with `W-05` and the base keeps it |
| `data/pools.json` | pools are **added**, with their contents | same duplicate rule |
| `data/hand.json` | cards join the hand, and `size`, `draw_per_turn`, `reshuffle` fill gaps | same duplicate rule |
| `data/disable.json` | `{"actions": [], "pools": [], "cards": [], "resources": []}` removes those names from the run | a name that does not exist is ignored |

It may **not** change `data/nodes.json`, `data/phases.json`, the entry node or
the protocol. Those belong to the base pack, and a layer that tries is a design
question, not a configuration one.

Two layers that touch the same field are refused before a session starts
(`V-35`), and the notice names both layers and the field. Two layers that add
different actions coexist.

## Build it, check it, publish it

The four commands are the ones the other pages use, run from the repository root:

```bash
python infra/tool/release/pack.py build packs/sanguo-hard
python infra/checks/check_pack.py dist/sanguo-hard-1.0.0.zip
git tag pack/sanguo-hard/v1.0.0 && git push origin pack/sanguo-hard/v1.0.0
python infra/tool/release/pack.py publish packs/sanguo-hard --tag pack/sanguo-hard/v1.0.0 --apply
```

The tag names the pack, so one repository can publish a base pack and three
layers without their releases touching. The archive holds `manifest.json` and
`data/`, never the repository around it.

## How a player ends up using it

A layer never gets a row of its own. On the pack page it is a checkbox under the
row of the pack its `target` names, and it starts **unticked**, because a layer
changes what the player already agreed to play. Ticking it and starting builds the
run from the base plus the layers ticked.

The save records that assembly. Reload it and the same layers come back even if
something different is ticked now; if one of them has been uninstalled, the load
is refused with `E-02` and a notice naming the missing package, and nothing
half-loads.

## Proof that it took effect

Installing is not the proof; a run is. Three checks, in this order:

1. **A number only the layer can produce.** Write the base's starting grain into
   the layer's `ledger.json` as something else — `40` to `25` — then start a run
   with the layer ticked and read the line under the story. Without the tick it
   says `40`; with it, `25`.
2. **An action only the layer declares.** Put `levy` in `data/actions.json`, tick
   the layer, and the action menu has one more button. Untick and it is gone.
3. **The removal.** Put a base action in `disable.json`, tick the layer, and that
   button is missing from the menu while the rest still work.

Then save, reload the browser, and continue: the same numbers and the same menu
should come back, because the save carries the assembly and not just the base id.

Do the first check before publishing. A layer that installs, ticks and changes
nothing looks identical to a layer that works, until someone reads the number.
