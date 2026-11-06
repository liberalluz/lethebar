# SRS — v0.0.0 plugin-driven narrative game

English · [简体中文](SRS.zh-CN.md)

> Software requirements for the first playable version. Scope, not design: this
> file says what must be true, not how it is built. Every row here is P1; P2/P3
> items are listed as out of scope instead of being mixed in.

## 1. Scope

A browser game whose gameplay comes from installed plugins. A player opens a
link, imports a plugin package, picks it, plays a branch segment under that
plugin's own protocol, and saves. Two built-in plugins ship, 三国 first and 修仙
second.

## 2. Requirements

| ID | Requirement | Acceptance |
|---|---|---|
| `REQ-001` | The game runs in a supported browser from a URL, with no installation and no account. | Opening the URL on a supported browser shows the first screen within 60 seconds; no sign-in prompt appears. |
| `REQ-002` | After one successful load, the game opens and plays with the network disconnected. | With the network off, reloading the page still opens a new session and an existing save, with no error screen. |
| `REQ-003` | Playing a session sends no network requests. | During one full session the browser network panel shows zero requests. |
| `REQ-004` | A plugin is installed by importing a file the player chooses. | Choosing a plugin package file in the OS file picker results in a listed, launchable plugin; no filesystem path has to be typed. |
| `REQ-005` | An invalid plugin is rejected with the specific failed check, and the game stays usable. | Importing a package with a missing required field, an unsupported spec version, or an incompatible engine range shows a message naming that check, and the game remains playable. |
| `REQ-006` | Several plugins can be installed, and one is active at a time. | With two or more plugins installed, selecting another switches the active plugin, and the first plugin's saves are unchanged. |
| `REQ-007` | A plugin authored only against the published specification runs without engine code changes. | A plugin written from the specification alone reaches its first scene with no edit to engine logic and no rebuild of engine rules. |
| `REQ-008` | Selecting a plugin starts its branch at the declared entry point and shows scene and text. | Selecting a plugin shows its entry scene text and at least one next-step control within 5 seconds of selection. |
| `REQ-009` | The engine runs at least two different play protocols declared by plugins, without engine changes. | Two plugins declaring different protocols both play to the end of their first segment, and switching between them requires no engine edit. |
| `REQ-010` | Mechanics declared by a plugin take effect during a session. | For a plugin declaring a power supply and a progress display, the session shows the declared progression values and changes them by that plugin's rules. |
| `REQ-011` | An unknown or missing asset degrades to a visible warning instead of a crash. | Loading a plugin that references an unknown asset type shows a warning naming the asset, and the session continues. |
| `REQ-012` | Each plugin keeps its own save slots, three by default, and any slot can be loaded. | With three slots filled for one plugin, loading slot two restores the state saved in slot two, and a second plugin's slots are listed separately. |
| `REQ-013` | Saves record a schema version, and incompatible saves are refused with a message. | Setting a save's schema version to an unsupported value and loading it shows a refusal message and starts no session. |
| `REQ-014` | A built-in 三国 plugin ships with at least one playable segment played by its own protocol. | From a fresh install, selecting 三国 reaches the end of its first segment, saves, and resumes from that save. |
| `REQ-015` | A built-in 修仙 plugin ships with at least one playable segment, delivered after 三国. | From a fresh install, selecting 修仙 reaches the end of its first segment, saves, and resumes from that save. |
| `REQ-016` | The same input sequence reproduces the same result. | Replaying the same choices from a fresh session yields an identical sequence of scenes and values. |
| `REQ-017` | A first-time player reaches a playable session within 10 minutes, and the author plays three sessions in a row. | In an unmoderated test, a first-time player reaches the first scene within 10 minutes of opening the link. |
| `REQ-018` | The interface speaks the language the browser asks for, and the player can switch it. | A browser set to English shows English controls; a browser set to Chinese shows Chinese controls; the switch on the landing screen survives a reload. |
| `REQ-019` | A plugin's declared pictures and sounds are drawn and played. | A plugin that declares a scene image shows it above the text at a non-zero size; a plugin that declares none shows no empty picture area. |
| `REQ-020` | A plugin carries its text in more than one language, and a partly translated package is refused. | With the browser asking for English, a plugin that ships an English table shows English text; a package whose declared table leaves a scene or a choice empty is refused at install with `V-22`. |
| `REQ-021` | A package declares which format version it speaks and what it needs. | A package that says `2.0.0` with no requirements installs and plays as before; one whose `kind`/`layer`/`requires` are malformed is refused with `V-23`; one whose requirement is missing or out of range is refused with `V-24`; a `1.0.0` package still installs and carries one `W-01` warning. |
| `REQ-022` | A package declares its numbers and their bounds; the rules that move them run after the action's own effects. | A declared resource starts at its `init` value; an effect that would push it past `max` stops at `max` instead of refusing the choice; a rule that names an undeclared resource is refused with `V-14`; a rule that reads a value the same choice just changed sees the new value; a resource with `labels` shows its label in the scene, and the number is unchanged. |
| `REQ-023` | A package can give the player a menu of actions, a run length with ranks, and dice checks. | An action whose `requires` fail is listed as unavailable with the failing condition and writes nothing when taken; a `per_run` limit refuses the second use without changing any value; an action advances the turn and the rank follows it; a failing condition ends the run and its reason is shown; a check rolls from the session RNG, compares with its target plus the declared bonus, and stores the numbers that decided it. |
| `REQ-024` | A package can draw items from a pool and record how its factions feel about each other. | A draw takes the declared number of items and removes them unless the pool replaces them; what is left travels in the save, so reloading cannot re-roll a draw; the same seed draws the same items in the same order; drawing more than a pool holds without `replace` is refused with `V-19`; a relation reads only in the direction the package wrote; a state name such as `ally` comes from the package's `thresholds`, and a relation that points at an undeclared entity is refused with `V-20`. |
| `REQ-025` | A package can count time in turns, and a rule can read the count the engine keeps. | A package that declares `clock.per` as `turn` advances the count once per action and not on a plain node advance; one that declares `node` advances it on every node advance; a rule naming `tick` in its `when` fires when the count reaches its number, and the count travels in the save so a resumed run continues from it; a rule that tries to write `tick` is refused with `V-14`, and a package that declares a clock no rule reads is refused with `V-21`. |
| `REQ-026` | A package played through actions is playable in the scene, not only in the assertions. | A package that declares actions is not finished merely because its entry node offers no choices; the scene shows one button per action; an action that cannot be taken is shown disabled with its reason and writes nothing when pressed; taking an action advances the turn and the scene shows the turn and the rank; a run that ended by a failure condition shows the reason and offers no action buttons; a package without actions renders as it did before. |
| `REQ-027` | An action can wait on a relation state or on an item already drawn, and taking an action can draw from a pool in the same step. | A package whose action declares `requires` with `{"relation": "shu", "state": "ally"}` can take it when any entity stands in that state toward `shu`, and `{"drawn": "cao_cao"}` when that item has been drawn; an action that cannot be taken is disabled with that reason; an action that declares `draw` takes one item out of the named pool as part of itself, and the drawn item then unlocks the action waiting on it; both the drawn items and the relation survive a save and a resume; an install is refused with `V-25` when a condition names a state or an item the package never declared, and with `V-26` when it draws from a pool the package never declared. |
| `REQ-028` | A save is durable before the interface says it is saved. | After the player presses Save, the slot screen says the save is being written and only then says it is saved; a reload at the moment the screen says saved finds the run; the wait is bounded and never blocks the interface; a backend that reports nothing to flush settles immediately. |
| `REQ-029` | A package names the engine capabilities it needs, with a major version. | Every entry of `capabilities` is a capability id `name@major` that `docs/specs/capabilities.md` lists as provided; anything else is refused at install and the refusal names the capability; a format 1.0.0 package that names a capability without a major version still installs, with one warning. |
| `REQ-030` | A package is held to a published install-time envelope. | The archive, its entry count, every entry path and every entry's unpacked bytes are inside the limits in `docs/decisions/0009-package-trust.md`; a picture past 4096 px on an edge and audio past 2 MB or 60 seconds are refused by name; the refusal says what was measured and what the limit was. |
| `REQ-031` | A first visit says what it is downloading and whether the browser kept it. | The landing screen names the payload size once per profile and asks the player to keep the tab open; a cache write that fails is reported with its reason instead of being silent; a reload in the same profile does not repeat the sentence. |
| `REQ-032` | A rule can move a relation, and a save keeps the result. | A rule names a pair the package declared and an `add` or `value` change; the session is the only writer of the faction map; the moved value survives a save and a resume; a rule that names an undeclared entity or a non-numeric change is refused at install with `V-31`. |
| `REQ-033` | The scene states how the run stands. | The view carries the turns left, the entity the others lean toward, the entity they push against, and the resource closest to its declared floor; each section appears only when its source is declared; the scene draws one line from the catalog. |
| `REQ-035` | An English run reads English wherever the package supplies text. | The menu labels, the rank title, the words a labelled resource reads as and the reason a run ended all come from the package table for the locale being played; a key the table leaves out falls back to the package text rather than an empty label; a package that ships a table must cover every action, rank, labelled value and failure it declares, or `V-22` refuses it. |
| `REQ-034` | The built-in Sanguo story is a full run, not a sketch. | It is budgeted at twenty-four turns over four resources, shows five ranks as the turn number passes them, can be lost three declared ways, offers a menu of five actions, and lets a rule move a relation; all of it is package data, and installing it changes nothing under `app/core`. |
| `REQ-036` | A package can deal a hand and hold a deck. | A package declares a hand, a small deck and the cards themselves; the scene shows the cards it can play and disables the ones it cannot pay for with the reason; playing a card spends what it costs, applies what it does, discards the card, draws a replacement and advances the turn by one; the hand, the deck and the discard pile survive a save and a resume; a deck that names a card the package never declares, a card that names a resource the ledger never declares, and a capability claimed without a deck file are refused at install with `V-38`, `V-37` and `V-36`. |


## 3. Out of scope for v0.0.0

- Plugin market, online plugin download, plugin updates over the network.
- Plugin editor or any authoring UI.
- 3D rendering (the specification reserves the fields; one 2D path is implemented).
- Multiplayer, accounts, cloud saves.
- iOS build, Windows build, Android.
- Automatic save migration across schema versions.
- An art or audio pipeline: a package may ship its own pictures and sounds, but
  there is no built-in art, no editing, no asset catalogue and no importing of
  formats beyond PNG, JPEG and WAV.
- Interface languages beyond English and Simplified Chinese, and right-to-left
  layout.

## 4. Cut order when the date is at risk

Scope is cut, the date is not moved. Cut in this order:

1. `REQ-015` 修仙 built-in plugin (the second plugin).
2. `REQ-010` plugin-declared mechanics (keep the protocol, drop progression).
3. `REQ-016` determinism guarantees beyond the built-in plugins.

## 5. Open questions

| ID | Question | Blocks |
|---|---|---|
| `TBD-001` | Rule for extending save slots beyond the default three: cap, how slots are added, whether old saves are affected. | `REQ-012` |
| `TBD-002` | Whether the 修仙 plugin ships inside v0.0.0 or moves to v0.1.0. | `REQ-015` |
| `TBD-003` | Backward compatibility window for the plugin specification: how many spec versions one engine version must accept. | `REQ-005`, `REQ-007` |

## 6. Reopen triggers

This SRS is abandoned and the project returns to stage 0, rather than patched,
when any of these becomes true:

1. Plugin loading and playback cannot be demonstrated within two weeks of work.
2. 2026-12-31 arrives without a playable v0.0.0.
3. The product stops being a game (for example it becomes an authoring tool).
4. A platform hard constraint appears (store rejection of the engine export, or
   the browser unable to run the render runtime).
