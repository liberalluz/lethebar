# SDD — v0.0.0 plugin-driven narrative game

English · [简体中文](SDD.zh-CN.md)

> System design: how the game is structured, not how each line is written. Every
> P1 requirement of `SRS.md` lands in a section here (see §12). Test assertions
> are not written here; they belong to STP/STD.

## 1. Scope of this design

Covers: runtime topology, repository layout, plugin package format, load and
validation pipeline, protocol interface, session model, save model, asset and
offline strategy, and the two built-in plugins.

Defers: 3D rendering path, plugin market and network distribution, iOS build,
save migration across schema versions. Each deferral is a recorded gap, not an
empty promise.

## 2. System structure

### 2.1 Runtime topology

```text
static hosting (no application server)
  └─ app shell: html + engine code + built-in plugin packages
       └─ browser runtime
            ├─ rules runtime      (protocols, session, mechanics, saves)
            ├─ render runtime     (scene, text, 2D sprites, audio, input)
            ├─ package loader     (zip in memory, validate, install)
            └─ persistence        (IndexedDB via the JS bridge)
```

There is no server component. Nothing in the runtime requires a backend; hosting
serves static files only.

### 2.2 Repository directories

| Path | Holds |
|---|---|
| `app/core/` | engine: boot, registry, validator, session, mechanics, saves, warning channel |
| `app/protocols/` | one directory per protocol version (`linear@1`, `turn_based@1`) |
| `app/render/` | 2D scene renderer, text layout, asset binding, input mapping |
| `content/builtin/<plugin-id>/` | the two built-in plugin packages (source form) |
| `infra/` | export presets, build and check scripts |
| `docs/` | intent, SRS, SDD, ADRs, runbooks |

### 2.3 Component responsibilities

| Component | Owns | Must not own |
|---|---|---|
| `package loader` | reading bytes, unzip, manifest validation, install registry | interpreting gameplay |
| `protocol registry` | mapping `protocol@version` to an implementation, version gating | reading plugin files |
| `session` | current node, progression state, effect application, RNG state | rendering, storage |
| `save store` | slot metadata, payload round-trip, schema compatibility gate | gameplay rules |
| `render runtime` | turning session state into visible scene and input intents | deciding what happens next |
| `warning channel` | collecting non-fatal degradations | aborting a session |

The dependency direction is one way: `render → session → protocol → data`. The
render runtime never calls the package loader directly.

## 3. Plugin package format

### 3.1 Package

A plugin is a single zip file:

```text
plugin.zip
├─ manifest.json
├─ data/
│  ├─ nodes.json          branch graph: nodes, choices, effects
│  └─ mechanics.json      declarative rule tables the plugin supplies
└─ assets/
   ├─ textures/*.png
   ├─ audio/*.ogg
   └─ text/*.json
```

Unzipping happens in memory. Nothing is extracted to the filesystem, so the
format works identically in a browser and in a native build.

### 3.2 Manifest fields

| Field | Type | Meaning |
|---|---|---|
| `id` | string, `[a-z0-9-]+` | stable plugin identity |
| `version` | `X.Y.Z` | plugin version |
| `specVersion` | `X.Y.Z` | plugin specification version it was authored against |
| `engine` | range `>=X.Y.Z <Y.0.0` | engine versions it accepts |
| `name` | string | display name |
| `protocol` | `linear@1` \| `turn_based@1` | play protocol it declares |
| `capabilities` | string[] | `render.2d`, `audio`, `text` |
| `mechanics` | string[] | mechanic ids the plugin supplies |
| `entry` | string | starting node id |
| `saveSchema` | integer | save payload version this plugin produces |
| `assets` | array of `{type,path}` | declared asset inventory |
| `kind` | `bundle` \| `layer` | required by format `2.0.0`: playable on its own, or a piece another package requires (ADR-0007) |
| `layer` | `profession` \| `genre` \| `mod` \| `content` \| `meta` \| `assets` | required when `kind` is `layer`; names which piece of the seven-layer design it is |
| `requires` | array of `{id, version}` | packages that have to be installed before this one can be played; `version` uses the same range syntax as `engine` |
| `clock` | `{per: turn \| node}` | optional: which advance counts a tick. `turn` counts actions, `node` counts node advances; the engine always counts, the field only says which count a rule may read |

A package written for `1.0.0` declares none of the last three fields and still
installs (§4.2, `W-01`). `clock` is independent of the format version: a `1.0.0`
package may declare it as well.

`kind` is the identity the assembly reads, not a hint: `Session.create` applies a
record as a layer when its `kind` is `layer` and merges it as a bundle otherwise.
A `target` on a bundle is data the run ignores; it never turns the package into a
layer, and a format `1.0.0` package that declares no `kind` is a bundle.

### 3.3 Data files

- `nodes.json`: nodes with `id`, `text`, `assets`, `choices[]`; each choice has
  `label`, `next`, and `effects[]`.
- `ledger.json`: the ledger. Every resource has `id`, `init`, `min` and `max`,
  may carry a display `label`, and may map numeric values to display text with
  `labels` (for example `{"2": "名动诸侯"}`). A value is a number; a label is
  text drawn instead of the number and never changes it.
- `rules.json`: settlement rules, each `{when, set}`, evaluated in file order
  after the chosen action's own effects. A rule reads the values the effect
  just left behind, which is why a label can follow the number in the same
  step. `mechanics.json` keeps the same shape and is read when `rules.json` is
  absent, so packages written before the ledger still play.
- A rule names resources rather than free variables: every key a rule reads or
  writes must be declared in `ledger.json` (`V-14`). There is no control flow and
  no expression language beyond comparisons and arithmetic.

- `actions.json`: the menu. Each action has `id`, `label`, optional `costs`,
  `requires`, `effects` and `limit` (`per_turn` or `per_run`). Costs and effects
  are applied to a copy and committed together, so a refused action writes
  nothing; an action whose `requires` fail is listed as unavailable with the
  failing condition instead of disappearing.
- `phases.json`: `turns`, `ranks` and `fail`. The turn number is the only
  bookkeeping — a rank is read from it, so a restored save shows the rank for its
  turn. `fail` is evaluated after settlement; the first match ends the run and
  its `reason` is what the player is told.
- `checks.json`: `{id, when, roll, target, bonus}`. A check rolls from the session
  RNG, adds `bonus.scale * state[bonus.key]`, compares the total with `target`,
  and records `{roll, bonus, total, target, passed}` under `state.checks.<id>`.
### 3.4 Asset types

- `pools.json`: `{id, items, draw: {n, replace}}`. A draw takes `n` items and
  removes them unless `replace` is true; the remainder is saved, so a reload
  cannot re-roll it, and the order is fixed by the session RNG on the first
  draw rather than at load.
- `relations.json`: `thresholds` and `entities`, each entity carrying directed
  `relations`. A non-negative threshold is a floor, a negative one is a
  ceiling; the engine invents no state names and assumes no symmetry.
Registered types in v0.0.0: `texture`, `audio`, `text`. A type outside the
registry is not an error; the asset is skipped and reported (§8.2).

## 4. Load and validation pipeline

### 4.1 States

```text
idle → chosen(file) → unpacked → validated → installed
                        │            │
                        └─ rejected ─┘   (reason surfaced, install registry untouched)
```

### 4.2 Validation checks

| Code | Check | Result |
|---|---|---|
| `V-01` | zip is readable and contains `manifest.json` | reject |
| `V-02` | manifest has every required field with valid type | reject |
| `V-03` | `id` matches pattern and is not already installed with a different version | reject |
| `V-04` | `specVersion` is within the supported window | reject |
| `V-05` | `engine` range includes the current engine version | reject |
| `V-06` | `protocol` exists in the registry | reject |
| `V-07` | a bundle's `entry` node exists in its own `nodes.json`; a layer is not asked | reject |
| `V-08` | every declared asset path exists in the package | warn, skip asset |
| `V-09` | `saveSchema` is a positive integer | reject |
| `V-14` | every resource a rule reads or writes is declared in `ledger.json`, and the ledger itself is well formed | reject |
| `V-16` | actions have unique ids, at least one effect, and limits the engine counts; every resource they touch is declared | reject |
| `V-17` | `turns` is at least 1, ranks ascend inside `1..turns`, every failure carries a reason and a condition | reject |
| `V-18` | a die has at least two sides and the target lies inside the dice range; a bonus names a resource | reject |
| `V-19` | a pool lists no item twice, draws at least one, and does not draw past its size without replace | reject |
| `V-20` | every entity a relation points at is declared, every threshold is a number, and every state name comes from `thresholds` | reject |
| `W-02` | a relation pair that disagrees in direction (reported, not rewritten) | warn |
| `W-03` | a format 1.0.0 package names a capability without its major version (reported, still installs) | warn |
| `V-23` | `kind`, `layer` and `requires` have the shape §3.2 gives them, and a `2.0.0` package declares `kind` | reject |
| `V-24` | every `requires` entry is satisfied by an installed or built-in package whose version falls inside the declared range | reject |
| `W-01` | `specVersion` is below `2.0.0`: readable now, refused from v0.2.0 | warn |
| `V-21` | `clock.per` is `turn` or `node`, and a package that declares a clock also carries at least one rule whose `when` reads `tick` | reject |
| `V-25` | a condition names a relation state declared in `relations.json`, or an item some pool contains | reject |
| `V-26` | an action's `draw.pool` names a pool `pools.json` declares | reject |
| `V-27` | every entry in `capabilities` is a capability id `name@major` the engine provides (ADR-0008) | reject |
| `V-28` | the archive, its entry count, each entry's unpacked bytes and the unpacked total are inside the envelope; raised by the loader before the manifest is read | reject |
| `V-29` | every entry path is relative, lowercase and inside the charset whitelist | reject |
| `V-30` | a declared picture is at most 4096 px on an edge and a declared sound is at most 2 MB and 60 seconds | reject |
| `V-31` | a rule's relation change names entities the package declared and carries an `add` or `value` number | reject |
| `V-33` | a package named in the assembly is not installed |
| `V-34` | A layer names a target the assembly does not contain, sits on itself, closes a chain, or a package is named twice. | fatal |
| `V-35` | Two layers in one assembly write the same field of the same target. | fatal |
| `V-44` | A layer's `target` is installed but its `kind` is not `bundle`. | fatal, names the layer and the target |
| `V-45` | Two layers in one assembly declare the same asset path. | fatal, names both layers and the path |
| `V-40` | A `content` block names a view or a density the engine does not know. |
| `V-41` | The cast repeats an id or carries an empty name, or the arc's turns do not ascend and stay unique. |
| `V-42` | The `meta` block names an audience, a length, a pitch or an icon the engine cannot honour. |
| `V-43` | The bytes of a downloaded package do not hash to the value the caller expects. |
| `V-36` | a package that names `cards.hand@1` ships a `data/hand.json` with a `hand` and a `deck` | reject |
| `V-37` | every card's `cost` and `effects` name resources the ledger declares | reject |
| `V-38` | every card id in the deck is declared in the package's `cards` table | reject |
| `V-39` | A card names an icon that no texture asset declares | fatal, `data/hand.json` |

Every rejection names its code and the offending field; a rejection never
disturbs already-installed plugins or their saves. `V-24` is checked at install
time rather than when the story starts, because a bundle whose requirement is
missing cannot be finished and the player would only find out at the scene where
it runs out (ADR-0007).

### 4.3 Install registry

Installed plugins are recorded in local storage with `{id, version, manifest,
packageBytes}`. Package bytes are stored so a plugin can be launched offline and
after a reload without re-importing. Re-importing the same `id` with a new version
replaces the entry and keeps that plugin's save slots.

## 5. Protocol interface

### 5.1 Contract

A protocol implementation provides four operations over session state:

```text
start(session)          → first renderable state
advance(session, intent)→ next state after a player intent
evaluate(session)       → state after applying mechanics rules
snapshot(session)       → serialisable payload for a save slot
```

A protocol reads only the plugin's data and the session state it was given. It
may not read files, storage, or the clock.

### 5.2 Registry and versioning

Supported in v0.0.0: `linear@1` (choices advance node to node), `turn_based@1`
(a round structure with per-round intents). The registry refuses unknown
`protocol@version` at validation time, which is what makes `V-06` meaningful.

### 5.3 Adding a protocol

A new protocol means new engine code. This is the accepted limit of "the engine
does not know gameplay": the engine knows a **protocol interface**, and plugins
choose among implementations. The SRS asks for two protocols, not for arbitrary
new ones; a third protocol is a product decision, not a plugin.

## 6. Session model

### 6.1 Shape

A session holds: plugin identity, protocol instance, current node, the ledger
values, RNG state, and a warning list. Sessions are created from a plugin and are
never shared between plugins.

A run ends when the node it lands on offers no choices **and** the package does
not declare a phase machine. A package played through a menu declares phases and
its entry node usually offers no choices at all, so treating "no choices" as the
end on its own would close the run before the first action could be taken
(REQ-026). A package with a phase machine instead ends on a failure condition or
on the turn limit, both of which §6.3 describes.

Ledger values are clamped into their declared `min`/`max` after the action's
effects and after the settlement rules, so no path — not a choice effect, not a
rule, not a resumed save — can push a number outside its bounds. Clamping hides
nothing: the value simply stops at its bound.

### 6.2 Mechanics

Mechanics are declarative: the plugin names mechanic ids and supplies rule tables
in `rules.json` (`mechanics.json` before it); the session applies matching rules
after each node advance, in file order, on top of the effects the choice just
applied.
Two mechanics are part of v0.0.0: a power supply (a resource that changes on
choices) and a progress display (a derived value shown in the scene header).

### 6.5 The clock

The engine owns one counter, `tick`, starting at zero for every run. It never
reads the wall clock and no package can declare, reset or write it: a rule may
name `tick` in a `when`, and a rule whose `set` names `tick` is refused with
`V-14` (`V-21` covers the opposite mistake, a clock nobody reads).

Which advance counts is the package's choice, through `clock.per`:

- `turn` — one action advances the tick; a plain node advance does not.
- `node` — every node advance counts, including the one that lands on the entry
  node when the run starts.
- absent — the tick still advances on node advances, but no rule may read it,
  because `V-21` only asks for a reader when a clock is declared.

A package that declares a clock runs its rules after each action as well as
after each node advance; a package without one keeps the older behaviour and
runs them only after advancing. The tick travels in the save payload, so a
resumed run continues from the number the player left.

### 6.3 Determinism

Randomness comes from a session seed. The seed is derived from the plugin id and
an explicit start counter, never from the wall clock. The same choice sequence
therefore reproduces the same state sequence. No component reads the current
time for gameplay decisions.

### 6.4 Failure containment

A protocol or mechanic error aborts that session and returns to plugin selection
with the error shown. Installed plugins and other plugins' saves are untouched.

## 7. Save model

### 7.1 Slots

Three slots per plugin by default, ordered 1–3, each showing saved-at metadata
and a one-line preview taken from the session. Slots are namespaced by plugin
`id`, so two plugins never share a slot.

### 7.2 Payload

```json
{ "schema": 1, "plugin": {"id": "...", "version": "..."},
  "node": "...", "state": {...}, "rng": 123456789, "savedAt": "..." }
```

### 7.3 Compatibility

On load: `schema` must equal the plugin's declared `saveSchema` and the plugin id
must match the active plugin. Any mismatch is refused with a message naming both
values; no partial load, no automatic migration in v0.0.0.

### 7.4 Storage

Saves live in IndexedDB through the JS bridge, keyed by plugin id and slot. If a
write fails (quota, private mode), the session continues and the warning channel
reports that the slot was not written; the player is never told a save succeeded
when it did not.

### 7.5 Durability

A write is not finished when the call returns; it is finished when storage says
it has nothing left to flush. `SaveStore` carries a request and a probe: `write()`
asks for a flush and then asks whether the backend is still busy, and reports
`pending` while it is. The shell polls that flag every frame and only then says
the slot is saved.

In the browser the store is `user://`, which the engine maps onto IndexedDB and
flushes on its own schedule. The export does not expose that flush to the page,
so the shell waits a bounded amount of wall time (1.5 s) rather than calling it.
Wall time, not frames: a headless browser draws far faster than sixty frames a
second, and a frame budget would be a fraction of the window storage needs.

Installing a package writes to the same store and passes through the same gate:
`mark_writing()` exists so that a reload cannot outrun an install either.

A resumed session takes the locale of the interface, not the package default. The
save records a run, not a preference, so the locale does not travel inside the
payload: `resume()` takes it as an option and the shell passes the language it is
currently reading in. A payload that carries no such field still resumes, in the
package's own text.

## 8. Asset strategy

### 8.1 Resolution

Assets are read from the in-memory package during session start and bound to
render slots by declared type. Only referenced assets are decoded.

### 8.2 Degradation

Missing or unknown assets produce one warning each, are rendered as a placeholder
(text type renders the asset path), and never abort the session. Warnings are
aggregated per session and shown on request, not as a modal per asset.

### 8.3 Placement

A picture is drawn in a band above the scene text. The band takes the smaller of
30% of the window height and the height left over after the text and every button
have taken their share, so a wrapped line can never push a control off screen.
The band collapses to zero when a scene declares no picture. Portrait assets take
a fixed narrow column beside the text; `portrait` is supported by the layout but
no shipped package uses it yet. Audio starts when the reader enters a scene that
references it and stops when the scene is left.

### 8.4 Accepted formats

Pictures are PNG or JPEG and sounds are WAV; those are the only decoders the
engine calls. Anything else fails to decode and takes the degradation path in
§8.2 — placeholder plus one warning — rather than aborting.


## 9. Offline strategy

- The app shell (html, engine code, built-in packages) is cached by a service
  worker at first load.
- Imported plugins are stored as bytes in the install registry, so they are
  available offline without the original file.
- A cold start with no network serves the cached shell and built-in plugins; no
  runtime feature calls the network.
- A failed cache population is a warning, not a blocking error: the game works
  online-only in that case, and says so once.

## 10. Built-in plugins

Both are authored as ordinary plugin packages, with no engine-side special case.

### 10.1 三国 (`sanguo`)

Protocol `turn_based@1`. One run over twenty-four turns with four resources
(grain, troops, coin, standing), five ranks, three ways to lose and a menu of
five actions; rules move the relations between three neighbours. Save/resume at
any turn boundary (REQ-034).

### 10.2 修仙 (`cultivation`)

Protocol `linear@1`. One segment: entry scene, a fixed sequence of choices with
one mechanic (progress display). Delivered after 三国 and cut first if the date
is at risk (SRS §4).

## 11. First-run path

Landing → plugin list (built-in plugins preinstalled) → select 三国 → entry scene.
No account, no network, no dialog chain longer than one step. The path is designed
so a first-time player reaches a scene without importing anything.

The landing screen names each installed story and offers `New game` plus, when a
save exists, `Continue`, which lists every non-empty slot across plugins and
resumes it directly.

### 11.1 Interface language

The interface strings are data, not literals in the render code. `en.tsv` and
`zh_CN.tsv` under `app/i18n/` hold `key<TAB>text` rows; the render layer asks a
`Locale` helper for a key and never embeds a sentence.

Resolution order: a saved choice in `user://locale.txt`, else the browser's
`navigator.language` (`zh*` → `zh-CN`, otherwise `en`). A missing key falls back
to English, then to the key itself. The landing screen offers a switch; switching
redraws the current screen and persists the choice. A test asserts that no
Chinese literal remains in `app/render`.

### 11.2 Package language

A package may carry translations instead of duplicating scenes. The manifest
declares `defaultLocale`, the extra `locales` it ships, and `names` (display name
per locale); `data/i18n/<locale>.json` maps node id to `{text, choices}`.

Resolution order for every string: the reader's locale table → the package's
default text → the engine's English. Validation refuses a package that declares
a table it does not ship, a locale outside `en`/`zh-CN`, or a table that leaves a
scene text or a choice label empty (`V-22`), because half a translation reads
worse than none. Scenes and choices absent from a table keep the package's own
text, so a partial table is only allowed for a locale the manifest does not
declare.

### 11.3 The scene draws the menu

A package that declares actions is played through the scene, not only through
node choices. The scene draws one button per declared action; an action that
cannot be taken stays visible, disabled, with its reason appended to the label,
because a player who cannot see what is out of reach cannot plan around it. The
readout carries the turn and the rank, both read from the session and never
computed by the render layer. A run that ended shows the reason the phase machine
gave and offers no action buttons; a package without actions renders exactly as
it did before this section existed.

### 11.4 A first visit says what is coming

The payload is about 42 MB and it is cached by the generated service worker, not
by the page. The landing screen therefore says the size once per profile, before
any scene is opened, and asks the player to keep the tab open: switching tabs on
iOS suspends the transfer and the browser may discard it. The sentence is stored
in `user://welcome.txt` after it is shown, so a returning player never reads it
again.

Whether the payload actually landed is reported by the worker, not guessed by the
page. The export injects a probe into `index.html`: it asks the worker for
`lethebar-cache-state` over a `MessageChannel` and publishes `window.lethebarCache`
(`controlled`, `stored`, `error`, `ready`). The shell reads that object on the
landing screen and, when `error` is set, replaces the first-visit sentence with
the failure and the reason the Cache API gave. A write that fails is therefore
visible in the interface instead of only in a console nobody opens.


### 11.5 The scene states how the run stands

Three numbers decide a turn and the scene showed none of them. `Session.situation()`
reads them once: `turnsLeft` from `phases.turns` and the current turn, `leaning`
and `friction` from the sum of the relations each entity receives, and `tight`
from the fraction of each resource's declared range still above its floor. The
engine names no threshold, no turn budget and no resource: every number comes
from the package, and a section whose source is not declared is left out rather
than filled with a zero.

The scene prints the reading as one more segment of the readout line, through
`ui.turns_left`, `ui.leaning`, `ui.friction` and `ui.tight`, so the line follows
the interface language like the rest of the screen.

### 11.6 The labels a run is made of follow the locale

A run is not made of one sentence: it is a menu of actions, a rank, the words a
resource reads as, and the reason a run ended. The translation table used to
describe those things not at all, so an English run read an English scene and
then met Chinese buttons.

The table gains an optional `strings` section keyed by the thing being named:
`action.<id>`, `rank.<turn>`, `resource.<id>.<value>` for a label picked from a
declared list, and `failure.<index>` for the position in the phase machine's
declared failures. `Session.localise()` looks a key up when it builds the view,
so the shell keeps receiving plain strings and the render layer did not change.
A key the table leaves out falls back to the package's own text: a Chinese label
in an English run is a defect the gap check reports, while an empty button is a
broken run.

`V-22` measures the same keys it now can describe. A package that ships a table
for a locale must translate every action, rank, labelled value and failure it
declares, because a table that covers the scene and forgets the menu is the same
half-translation the check already refused.


### 11.7 A run can be played with cards

A run that declares a hand plays like a table: the scene shows the cards it can
play, keeps the ones it cannot pay for on screen with the reason, and treats
playing a card as a turn.

`app/core/hand.gd` reads the declaration — `hand.size`, `hand.draw_per_turn`,
`hand.reshuffle`, the `cards` table and the initial `deck` — and deals the
opening hand when the session starts. A card carries a `cost` and `effects` in
the same shape a rule uses, so the ledger is the only place a resource name is
checked. Playing one spends the cost, applies the effects through the same
clamping the rules use, discards the card, draws a replacement (returning the
discard pile only when the package asks for it) and advances the turn by one; a
card that cannot be paid for is refused with `S-08`, which names the resource
that is short, and stays in the hand.

The three piles belong to the run, not to the view: `snapshot()` carries
`hand`, `deck` and `discard` only when the package declares a hand, and
`save_store.resume()` puts them back before the scene is drawn. A deck that
names a card the package never declares (`V-38`), a card that names a resource
the ledger never declares (`V-37`) and a claimed `cards.hand@1` without a deck
file (`V-36`) are refused at install, so the scene never deals from a broken
deck.

### 11.8 A card can show a face

A card is a label with a cost, and a hand of labels is readable but hard to
tell apart at a glance. A card may name a picture the package declares:

```json
{"id": "heavy", "label": "A heavy blow", "icon": "assets/card-heavy.png"}
```

```json
{"type": "texture", "path": "assets/card-heavy.png", "slot": "card"}
```

The `card` slot is not drawn on the scene band: the scene band has one picture
and one portrait, and a face belongs beside its label in the hand. The hand
draws the picture to the left of the button, at `CARD_ICON_SIZE`, and keeps the
label as the button text.

Three things are fixed at install rather than at draw time:

- A card that names an icon no texture asset declares is refused (`V-39`). A
  card that silently loses its face is the same defect as a card that never had
  one, only slower to notice.
- A declared texture whose bytes do not decode keeps the label, leaves one
  `R-01` warning that names the path, and the run goes on.
- A card without an `icon` is drawn as before, with no picture and no warning.

REQ-037 maps to `Hand.icon_of()`, `Session.hand_view()` and
`Shell.card_rows()`.

### 11.9 A long hand wraps

A hand is a row of cards, not a column. The container asks the window how many
cells of `CARD_COLUMN_MIN` fit and puts the rest on the next row, so a hand of
eight wraps to three rows at 600 px and to one at 1200 px. The order the cards
are dealt in never changes, and the action menu keeps its single column below
the hand.

Three things are fixed when the hand is laid out rather than when it is drawn:

- The number of columns is measured from the width the window actually has
  (`Shell.hand_columns()`), so a constant would show up as a hand that never
  re-wraps.
- A card that shares a row has its label cut at `HAND_LABEL_CHARS` with an
  ellipsis; a hand that fits on one row keeps the whole label.
- The scene band, the scene text and the actions keep the widths they had. Only
  the hand stops being one card per line.

REQ-038 maps to `Shell.hand_columns()`, `Shell.hand_row_count()` and
`Shell._fill_hand_rows()`.

### 11.10 A reshuffle uses the run's seed

### 11.11 The world a package belongs to

A repository is cut by world (ADR-0010), so a world holds several packs. A
package says so in an optional `collection: {id, names}` block: `id` is the
world's slug and `names` maps a locale to the title a player reads.

`manifest_schema.gd` reads the block (`collection_of`) and checks the id's
alphabet (`is_collection_id`, the same one package ids use).
`package_validator.gd` refuses a malformed block with `V-32` — an id that is not
a slug, `names` that is not a locale-to-title map, or a title that is empty — and
warns with `W-04` when an installed pack describes the same world differently;
the engine keeps one world and takes its title from the pack whose id sorts
first, so the answer does not depend on install order.

`app/render/shell.gd` groups the installed packs into worlds (`worlds()`), and
`start_game()` opens the world screen only when more than one world exists, so a
repository with a single theme keeps the click count it has today. A pack that
declares no world belongs to the fallback world, whose title comes from the
interface (`ui.world_other`). The pack list honours the chosen world, and
`lethebarState.worlds` publishes ids and titles so a browser driver can click a
world by the name a player reads.


### 11.11 The world a package belongs to

A repository is cut by world (ADR-0010), so a world holds several packs. A
package says so in an optional `collection: {id, names}` block: `id` is the
world's slug and `names` maps a locale to the title a player reads.

`manifest_schema.gd` reads the block (`collection_of`) and checks the id's
alphabet (`is_collection_id`, the same one package ids use).
`package_validator.gd` refuses a malformed block with `V-32` — an id that is not
a slug, `names` that is not a locale-to-title map, or a title that is empty — and
warns with `W-04` when an installed pack describes the same world differently;
the engine keeps one world and takes its title from the pack whose id sorts
first, so the answer does not depend on install order.

`app/render/shell.gd` groups the installed packs into worlds (`worlds()`), and
`start_game()` opens the world screen only when more than one world exists, so a
repository with a single theme keeps the click count it has today. A pack that
declares no world belongs to the fallback world, whose title comes from the
interface (`ui.world_other`). The pack list honours the chosen world, and
`lethebarState.worlds` publishes ids and titles so a browser driver can click a
world by the name a player reads.


`Hand.draw_into()` stays a pure function: it takes the piles and, when the deck
runs out and the package allows a reshuffle, it hands the discard pile back as
the deck in the order of its caller. When no order is given it keeps play order,
which is what a package without `reshuffle` never reaches.

The session passes an order: `_shuffle_cards()`, a Fisher-Yates pass over the
run's own generator (`_next_rng()`, seeded from the plugin id and the start
counter). One seed therefore deals one order and another seed does not, and the
assertions can say so. The three piles travel with the save, so a resume keeps
the order it carries instead of shuffling again; a resumed run is the run that
was saved, not a new deal.

### 11.12 A run made of several packages

A session may be opened from an ordered list of installed packages. The first
supplies the nodes, the phase machine and the entry node; the rest may only
add resources, actions, cards and pools. `PackageLoader.assemble()` resolves
the list and refuses a name nothing installed provides, so a half-opened run
never reaches the screen (`V-33`).

Joining is not merging yet: a key two packages both declare keeps the earlier
package's value and leaves one `W-05` naming the key. Override, append and
disable arrive with the `layer` field (`ADR-0013`). The list travels in the
save, so a resumed run rebuilds the same set.

## 11.13 A layer changes the package it names

An assembly entry may carry a `target` beside its id (REQ-042). A package that
does so is a layer: it does not add another story, it edits the one below it.
Three semantics exist and no fourth: a resource definition the layer declares
replaces the base definition wholesale (bounds included, the current value
clamped into the new bounds); new actions, pools and cards are appended after
the base entries; names listed in `data/disable.json` are removed from
actions, pools, cards and the ledger.

The target is resolved at assembly time, not in the manifest, because
`manifest.layer` already means which of the six layers a package belongs to
(ADR-0007). A layer whose target is not in the same assembly, a layer that
sits on itself, a chain that returns to a package it already touched, and a
package named twice are all refused with `V-34` before a run opens.

## 11.14 A layer says what it edits

A layer package names its target in its own manifest (REQ-043). The format
requires a `target` on a package whose `kind` is `layer`, and refuses a
`target` on any other kind with `V-23`, because a target on a bundle would
read as a layer that forgot to say so. An assembly entry may still carry a
`target`; when it does and the manifest disagrees, the assembly wins, so a
tester can point the same layer at a different base without editing the
package.

Two layers over the same target are resolved in assembly order, and a field
the second layer writes after the first is refused with `V-35`, naming both
layers, the kind of field and its id. The check runs before the run opens, so
the conflict is reported at the assembly rather than discovered mid-run.

## 11.15 How a story reads is declared by the package

A package may carry a `content` block in its manifest: the view a story is told from (`first`, `third`, `ensemble`), how much the readout shows (`sparse`, `normal`, `dense`), the cast with an id, a name and an optional role, and an arc of labelled turns. `ContentLayer` normalises the block at install time and the session carries it into the view, where the scene reads it: the ensemble view keeps the roles, the dense readout names the arc stage and the turn that started it, and the sparse readout drops the situation line. `V-40` refuses a view or a density the engine does not know, naming the field and the value; `V-41` refuses a cast with a repeated id or an empty name, and an arc whose turns are not ascending and unique. The declaration travels in the save, so a resumed run reads the way the saved one did.

## 11.16 A package says who it is for

A package may carry a `meta` block: a `pitch` in one or more languages, an `audience` from `kids`, `teens`, `adults`, a `minutes` length and an optional `icon` that must be a texture the manifest already declares. `MetaLayer` reads the block; the pack list renders the pitch in the reader's language, then the package default, then any language it has, together with the length. `V-42` refuses an audience the engine does not know, a length that is not positive, a pitch entry with no text and an icon no texture provides, naming the field in every message. The block is never read by a run, so declaring it cannot change a save.

## 11.17 A pack travels as an artifact with a hash

A pack leaves the repository as a zip and a descriptor. `infra/tool/release/pack.py` builds the zip with one timestamp for every entry and the entries in a sorted order, so two builds of one directory are byte-identical; it writes `<id>-<version>.json` holding the id, the version, the byte count, the sha256, the `specVersion` and the engine range, and it can upload both files to a release (dry by default).

An engine installs such a pack through `PackageLoader.import_url(url, expected_sha256, context, fetch)`. The caller supplies the bytes, never a socket: `PackageLoader` sits under `res://core`, where no network path may be opened. The bytes are hashed first and compared in lowercase hex; a mismatch stops the install with `V-43`, naming the url and both digests, and an empty fetch is `V-01` naming the url. A match goes on to `import_bytes`, so every install-time rule (the envelope, the capability check, the story's own validation) applies to a downloaded pack exactly as it does to an imported one.

## 11.18 The engine proves itself with a package it owns

The four built-in stories are content, not contract. `app/tests/run_tests.gd` therefore asks whether a story is staged before it opens one: absent, the case records a skip and the summary counts it; present, the case runs as before. `TC-NEUTRAL-001` builds a small package inside the suite — two cards, one resource, two actions, a turn limit — and walks install, play, save and resume on it, so the engine's own proof survives a world repository taking the stories away.

With all four archives removed the suite reports `OK — 394 checks, 12 skipped`; with them staged it reports `OK — 526 checks, 0 skipped`. Defeating the guard and removing the archives gives twenty-six failures, which is what the guard is for.

## 11.19 A link is a second way in

`REQ-047`. The pack list offers two entries: a file, which the exporter injects
as an `<input type="file">`, and a link, which asks for an address and the
expected sha256.

The socket lives in `app/render/downloader.gd`, not in `core`, because
`TC-OFF-003` holds that no runtime source under `res://core` or
`res://protocols` opens a network path. `PackageLoader.import_url` therefore
takes a `Callable` and never a URL it can dial itself.

Three outcomes are reported, and only three: `installed` when the digest
matches, `already` when the id was already in the list, and `refused` when
`V-01` (nothing arrived) or `V-43` (the digest disagreed) stopped the install.
A refusal leaves the installed set untouched, and a link install without a
digest is refused as `V-43` rather than installed unverified.

## 11.20 A layer applies three of the six dimensions

A layer names one of the six dimensions, and the engine applies three of them:
`content` replaces the base package's block (§11.15), `mod` changes a number or a
cost the base declares (§11.13), and `assets` adds the layer's pictures to the
bundle's lookup. The other three — `genre`, `meta` and `profession` — are
pending: the package installs, the manifest is valid, and the run does not
change.

`ManifestSchema.APPLIED_LAYERS` is the one place that list lives, and
`layer_applied()` is what every reader asks. `PackageLoader.assemble()` records
the answer on the entry (`state` is `applied` or `pending`) and refuses a layer
whose `target` is installed but is not a bundle, with `V-44`, naming the layer
and the target. The pack page shows a pending layer with a sentence and no
tick: a tick that changes nothing would put a package into a save's assembly
that the engine does not apply, and the next engine version would change that
same save.

Assets join in assembly order: `PackageLoader._merge_layer_assets()` copies each
layer's declared bytes into the bundle's lookup and records which layer owns each
path. Two layers that declare the same path are refused with `V-45`, naming both
layers and the path, so the winner never depends on order. A scene that names a
picture only the layer declares draws that picture; removing the layer brings
back the bundle's own.

## 11.21 A package or a layer can be removed

The pack page offers a remove control beside every package and every layer. The
first press asks and the second removes, because the control sits next to the
tick a player presses to start a run; a bundle that still has layers says to
remove them first instead of removing the layers silently.

Removal erases the registry entry and the stored bytes
(`InstallRegistry.uninstall()` and `PackageStore.erase()`), drops the package
from the built-in list and from every ticked assembly, and closes the active
session if the removed package was the one open. `_saves_index()` lists only
installed packages, so the package's slots disappear from Continue; a save that
names a removed layer is refused with `E-02`, naming the layer, and the payload
is kept rather than deleted.

Removal is also what makes `V-03` survivable: once the old entry is gone, the
same id and version installs again, which is the only way out short of clearing
the site's storage.

## 11.22 A newer version replaces the one installed

A package whose `version` is newer than the installed one installs over it,
keeping exactly one copy of the version it replaced (`PackageStore.previous:<id>`).
`V-03` now refuses only a lower version; its message names both versions and says
to remove the package or import a newer one. Re-importing the same version is
allowed and changes nothing.

The pack page shows `Restore <version>` while a previous copy exists. One press
re-imports those bytes with `allow_downgrade` set, so the explicit rollback is
not a `V-03` refusal; the version it replaces becomes the new previous copy,
which makes the control a toggle between two versions. Removing the package
erases the previous copy with it.

Saves are not touched by any of this: a slot is keyed by package and slot, and
the payload names the version it ran under. A save made before an upgrade opens
on the new version when the node ids it names still exist; an upgrade that
renames or deletes those nodes makes the save unreadable, and `saveSchema` is
still one-way, so rolling back does not make a newer save readable.

## 12. Requirement mapping

| REQ | Design |
|---|---|
| `REQ-001` | §2.1 runtime topology, §11 first-run path |
| `REQ-002` | §9 offline strategy |
| `REQ-003` | §9 offline strategy, §2.3 dependency direction |
| `REQ-004` | §4.1 load pipeline |
| `REQ-005` | §4.2 validation checks |
| `REQ-006` | §4.3 install registry, §6.1 session shape |
| `REQ-007` | §5.1 protocol contract, §5.2 registry |
| `REQ-008` | §6.1 session shape, §3.2 manifest entry |
| `REQ-009` | §5.2 registry and versioning |
| `REQ-010` | §6.2 mechanics |
| `REQ-011` | §8.2 degradation |
| `REQ-012` | §7.1 slots |
| `REQ-013` | §7.3 compatibility |
| `REQ-014` | §10.1 三国 |
| `REQ-015` | §10.2 修仙 |
| `REQ-016` | §6.3 determinism |
| `REQ-017` | §11 first-run path |
| `REQ-018` | §11.1 interface language |
| `REQ-019` | §8.3 placement, §8.4 accepted formats |
| `REQ-020` | §11.2 package language, §4.2 validation (`V-22`) |
| `REQ-021` | §3.2 manifest fields, §4.2 validation (`V-23`, `V-24`, `W-01`) |
| `REQ-022` | §3.3 data files (`ledger.json`, `rules.json`, `labels`), §4.2 validation (`V-14`), §6.1 clamping |
| `REQ-023` | §3.3 data files (`actions.json`, `phases.json`, `checks.json`), §4.2 validation (`V-16`, `V-17`, `V-18`), §6.2 settlement and turns |
| `REQ-024` | §3.3 data files (`pools.json`, `relations.json`), §4.2 validation (`V-19`, `V-20`, `W-02`) |
| `REQ-025` | §3.2 manifest field (`clock`), §4.2 validation (`V-21`, `V-14`), §6.5 the clock |
| `REQ-026` | §6.1 when a run ends, §11 the scene draws the menu |
| `REQ-027` | §3.3 data file (`actions.json`, `requires` and `draw`), §4.2 validation (`V-25`, `V-26`), `engine-bricks` §7 conditions |
| `REQ-028` | §7.4 storage, §7.5 durability (`SaveStore` flush request and probe), `app/core/save_store.gd` |
| `REQ-029` | §4.2 validation (`V-27`, `W-03`), `docs/specs/capabilities.md`, `PackageValidator.KNOWN_CAPABILITIES` |
| `REQ-030` | §4.2 validation (`V-28`–`V-30`), `app/core/package_limits.gd`, loader envelope pass |
| `REQ-031` | §11.4 first-visit notice, `infra/export_web.py` cache probe |
| `REQ-032` | §4.2 `V-31`, `app/core/mechanics.gd` relation changes, `app/core/session.gd` writer and payload field |
| `REQ-033` | §11.5 situation reading, `app/core/session.gd` `situation()`, `app/render/shell.gd` readout |
| `REQ-034` | §10.1 the Sanguo run, `content/builtin/sanguo/**` data only |
| `REQ-035` | §11.6 the labels a run is made of, `Session.localise()`, `V-22` |
| `REQ-036` | §11.7 the hand, `app/core/hand.gd`, `V-36`–`V-38` |
| `REQ-037` | §11.8 card faces, `app/core/hand.gd`, `V-39` |
| `REQ-038` | §11.9 the wrapped hand, `Shell.hand_columns()`, no `V-` code |
| `REQ-039` | §11.10 the seeded reshuffle, `Session._shuffle_cards()`, no `V-` code |
| `REQ-040` | §11.11 the world a package declares, `ManifestSchema.collection_of()`, `V-32`, `W-04`, `Shell.worlds()` |
| `REQ-041` | §11.12 the assembly, `PackageLoader.assemble()`, `Session._merge_package()`, `V-33`, `V-44` |
| `REQ-042` | §11.13 the layer, `PackageLoader.assemble()`, `Session._apply_layer()`, `V-34` |
| `REQ-043` | §11.14 the declared target, `ManifestSchema.format_issues()`, `PackageLoader._layer_conflict()`, `V-35` |
| `REQ-044` | §11.15 the declared view, `ContentLayer`, `V-40`, `V-41` |
| `REQ-045` | §11.16 the declared meta, `MetaLayer`, `V-42` |
| `REQ-046` | §11.17 the artifact and the hash, `PackageLoader.import_url`, `V-43` |
| `REQ-047` | §11.19 the link entry, `app/render/downloader.gd`, three outcomes |
| `REQ-048` | §3.2 the identity the dispatch reads, `Session.create`, `InstallRegistry.entry()` |
| `REQ-049` | §11.20 the applied dimensions, `ManifestSchema.APPLIED_LAYERS` and `layer_applied()`, `V-44` |
| `REQ-050` | §11.20 asset merging, `PackageLoader._merge_layer_assets()`, `V-45` |
| `REQ-051` | §11.21 removal, `Shell.remove_package()`, `V-03`, `E-02` |

## 13. Decisions and open questions

Decisions recorded as ADRs:

- `ADR-0001` engine and language choice — `docs/decisions/0001-engine-and-language.md`
- `ADR-0002` plugin package as a plain zip — `0002-plugin-package-zip.md`
- `ADR-0003` plugins carry data, never code — `0003-plugins-carry-data.md`
- `ADR-0004` saves in IndexedDB — `0004-saves-in-indexeddb.md`

Open, carried from SRS: `TBD-001` slot extension rule, `TBD-002` 修仙 delivery
version, `TBD-003` spec compatibility window (§4.2 `V-04`, §5.2).
