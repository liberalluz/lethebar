# When the engine says no

Every refusal the engine raises carries a code. The code is the part worth
reading: it names the check, and the check names the file you have to open.

There are four families, and they arrive at different moments.

| Family | When it arrives | What it is about |
| --- | --- | --- |
| `V-xx` | installing a package, before anything is written | the package itself: the manifest, the data files, the envelope |
| `M-xx` | reading `data/rules.json` | one settlement rule that cannot be understood |
| `S-xx` | playing, when an action or a choice is taken | the run: a missing node, an action that cannot pay, a choice that is not offered |
| `SAVE-xx` | writing or reading a slot | the save: nothing to save, a full slot, a save from another schema |

`V-xx` refusals stop the install, so a package that raises one is never stored
and never appears in the list. `M-xx` refusals are raised when a rule is read,
which is during install as well. `S-xx` and `SAVE-xx` arrive in a running game;
they are shown to the player as a short sentence and they never crash the run.

## Every code, and where it is raised

The table below is generated from the source. The middle column is the file and
line that raises the code, in the engine's own tree; when the sentence in the
last column names a `data/...` file, that is the file the author has to open.

<!-- generated:errors -->

| Code | Raised at | What it says |
| --- | --- | --- |
| `M-01` | `app/core/mechanics.gd:38` | rule without a set clause |
| `M-02` | `app/core/mechanics.gd:77` | a when clause must be an object, not … |
| `M-03` | `app/core/mechanics.gd:110` | a set clause must be an object |
| `S-01` | `app/core/session.gd:143` | no implementation for protocol … |
| `S-02` | `app/core/session.gd:162` | node … does not exist |
| `S-03` | `app/core/checks.gd:38` | no check named … |
| `S-04` | `app/core/session.gd:256` | no action named … |
| `S-05` | `app/core/session.gd:260` | reason |
| `S-06` | `app/core/session.gd:468` | pool … does not exist |
| `S-07` | `app/core/session.gd:282` | pool … does not exist |
| `S-08` | `app/core/session.gd:325` | resource.….… |
| `S-09` | `app/core/session.gd:309` | no card named … in the hand |
| `SAVE-01` | `app/core/save_store.gd:14` | SAVE-01 |
| `SAVE-02` | `app/core/save_store.gd:15` | SAVE-02 |
| `SAVE-03` | `app/core/save_store.gd:16` | SAVE-03 |
| `SAVE-04` | `app/core/save_store.gd:17` | SAVE-04 |
| `SAVE-05` | `app/core/save_store.gd:18` | SAVE-05 |
| `SAVE-06` | `app/core/save_store.gd:19` | SAVE-06 |
| `SAVE-07` | `app/core/save_store.gd:20` | SAVE-07 |
| `SAVE-08` | `app/core/save_store.gd:21` | SAVE-08 |
| `V-02` | `app/core/package_validator.gd:77` | message |
| `V-03` | `app/core/package_validator.gd:84` | must match [a-z0-9-]+ |
| `V-04` | `app/core/package_validator.gd:133` | specVersion |
| `V-05` | `app/core/package_validator.gd:505` | expected a range like >=4.3.0 <5.0.0 |
| `V-06` | `app/core/package_validator.gd:516` | protocol |
| `V-07` | `app/core/package_validator.gd:521` | entry |
| `V-08` | `app/core/package_validator.gd:641` | declared asset missing from package: … |
| `V-09` | `app/core/package_validator.gd:526` | must be a positive integer |
| `V-14` | `app/core/package_validator.gd:535` | state.json |
| `V-16` | `app/core/package_validator.gd:341` | actions.json |
| `V-17` | `app/core/package_validator.gd:348` | phases.json |
| `V-18` | `app/core/package_validator.gd:352` | checks.json |
| `V-19` | `app/core/package_validator.gd:362` | pools.json |
| `V-20` | `app/core/package_validator.gd:367` | W-02 |
| `V-21` | `app/core/package_validator.gd:567` | clock |
| `V-22` | `app/core/package_validator.gd:654` | defaultLocale |
| `V-23` | `app/core/package_validator.gd:154` | message |
| `V-24` | `app/core/package_validator.gd:205` | requires |
| `V-25` | `app/core/package_validator.gd:402` | actions.json |
| `V-26` | `app/core/package_validator.gd:429` | actions.json |
| `V-27` | `app/core/package_validator.gd:178` | capabilities |
| `V-31` | `app/core/package_validator.gd:598` | a rule's relations must be an array |
| `V-32` | `app/core/package_validator.gd:101` | id must match [a-z0-9-]+ |
| `V-36` | `app/core/package_validator.gd:446` | cards.json |
| `V-37` | `app/core/package_validator.gd:496` | cards.json |
| `V-38` | `app/core/package_validator.gd:456` | cards.json |
| `V-39` | `app/core/package_validator.gd:476` | cards.json |
| `V-40` | `app/core/package_validator.gd:227` | manifest.json |
| `V-41` | `app/core/package_validator.gd:249` | manifest.json |
| `V-42` | `app/core/package_validator.gd:288` | manifest.json |

<!-- /generated:errors -->

## What to open, by code

The code tells you which file, the sentence tells you which part of it.

- `V-01` to `V-06`, `V-27`, `V-39` to `V-42`: `manifest.json`. A field is missing
  or mistyped, or it names a protocol, capability, view, density, icon or
  audience the engine does not have.
- `V-14` to `V-21`, `V-25`, `V-26`, `V-31`: a data file names a resource, action,
  entity, state or pool that is declared nowhere. The sentence says which.
- `V-22`, `V-30`, `V-43`: the package's own shape — a locale with no file, a
  format this engine does not speak, a digest that does not match.
- `V-33`: an assembly names a package that is not installed.
- `V-34`, `V-35`: a layer targets something it should not, or two layers write
  the same field.
- `V-36` to `V-38`: `data/cards.json`. A hand without a deck, an unknown
  resource, a deck that cannot be dealt.
- `S-01` to `S-09`: the run. A node or an action does not exist, cannot be paid
  for, or is not offered here.
- `SAVE-01` to `SAVE-08`: the slot. Nothing to save, a slot out of range, an
  empty slot, a save from another schema or package.

## What a player sees

`S-xx` and `SAVE-xx` sentences are composed by the engine and shown as written,
with the values filled in: `S-05` reads as "`farm` is not available: not enough
grain". `V-xx` is shown while installing, next to the field or file it is about,
so the line a player reads is the line an author needs.

Codes are stable and are never translated: a code is what an author searches for.
