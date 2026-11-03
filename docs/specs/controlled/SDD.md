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

### 3.3 Data files

- `nodes.json`: nodes with `id`, `text`, `assets`, `choices[]`; each choice has
  `label`, `next`, and `effects[]`.
- `mechanics.json`: named rule tables. A rule is `{when, set}` over declared
  state keys; there is no control flow and no expression language beyond
  comparisons and arithmetic.

### 3.4 Asset types

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
| `V-07` | `entry` node exists in `nodes.json` | reject |
| `V-08` | every declared asset path exists in the package | warn, skip asset |
| `V-09` | `saveSchema` is a positive integer | reject |

Every rejection names its code and the offending field; a rejection never
disturbs already-installed plugins or their saves.

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

A session holds: plugin identity, protocol instance, current node, progression
state (mechanic-owned keys), RNG state, and a warning list. Sessions are created
from a plugin and are never shared between plugins.

### 6.2 Mechanics

Mechanics are declarative: the plugin names mechanic ids and supplies rule tables
in `mechanics.json`; the session applies matching rules after each node advance.
Two mechanics are part of v0.0.0: a power supply (a resource that changes on
choices) and a progress display (a derived value shown in the scene header).

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

Protocol `turn_based@1`. One segment: entry scene, three decision rounds, one
mechanic (power supply), save/resume at any node boundary.

### 10.2 修仙 (`xiuxian`)

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

## 13. Decisions and open questions

Decisions recorded as ADRs:

- `ADR-0001` engine and language choice — `docs/decisions/0001-engine-and-language.md`
- `ADR-0002` plugin package as a plain zip — `0002-plugin-package-zip.md`
- `ADR-0003` plugins carry data, never code — `0003-plugins-carry-data.md`
- `ADR-0004` saves in IndexedDB — `0004-saves-in-indexeddb.md`

Open, carried from SRS: `TBD-001` slot extension rule, `TBD-002` 修仙 delivery
version, `TBD-003` spec compatibility window (§4.2 `V-04`, §5.2).
