# STP — Test plan (v0.0.0)

English · [简体中文](STP.zh-CN.md)

## Scope

Covers the thirty-eight P1 requirements of `SRS.md` (v0.0.0) against the design in
`SDD.md`. Does not cover the plugin market, the plugin editor, 3D, multiplayer,
accounts, cloud saves, or the native iOS build; those are out of scope for
v0.0.0 and have no tests here by design.

## Strategy

Three levels, cheapest first:

1. **Rule level** — protocol and package validation exercised without rendering,
   through a headless entry point. This is where most cases live.
2. **Integration level** — package import → validation → install → session, run
   in the engine without a visible window.
3. **Browser level** — the exported build driven by hand in a real browser,
   because "works in a browser" cannot be proven inside the engine.

Determinism and offline behaviour get dedicated cases because they are structural
claims: if they fail, the architecture claim fails, not just a feature.

## Environments

| Env | What | Used for |
|---|---|---|
| E1 | Godot 4 headless, Linux/Windows desktop | rule and integration cases |
| E2 | Chrome/Edge (latest, desktop) | browser cases, performance, offline |
| E3 | Safari on iOS (latest) | read-only smoke, offline reload |
| E4 | Node (no engine) | JSON-level fixture checks (manifest, save payload shape) |

## Entry criteria

- `SRS.md` and `SDD.md` reviewed and committed (`BL-1` candidate).
- Plugin specification 1.0.0 published in `SDD.md` §3–§5 and frozen for the test
  run.
- At least one valid package fixture and one invalid fixture per validation code.
- The headless entry point exists (see R-01).

## Exit criteria

- Every `TC-*` below executed and recorded with pass or fail plus evidence.
- No open blocking or severe defect.
- Every P1 requirement covered by a passing case or an explicitly recorded gap.
- Offline cases (TC-OFF-*) pass on E2 and E3, not only E2.

## Risks to the test plan

| ID | Risk | Effect | Mitigation |
|---|---|---|---|
| R-01 | Godot headless test running is unproven for this project | rule-level automation may not exist in week 1 | prove it in the first batch with a trivial assertion; fallback is a Node harness over the JSON fixtures plus manual engine runs, recorded as a coverage reduction |
| R-02 | Browser offline reload test depends on service-worker behaviour that differs between Chromium and Safari | offline claim may hold on one engine only | run TC-OFF-* on both E2 and E3; a Safari-only failure is a defect, not a caveat |
| R-03 | First-session timing (TC-PERF-001, TC-UX-001) is measured by humans and drifts | numbers are noisy | fix device class and network (cold cache), sample three runs, record the median |
| R-04 | Determinism test can pass accidentally if the seed is constant | false confidence | TC-DET-001 uses two different seeds and asserts the outputs differ |

## Test plan

| Test | Covers | Exit |
|---|---|---|
| `TC-PLAT-001` | `REQ-001` | Exported build served from a static directory opens in E2 with no account prompt and no installer step; the first screen is interactive. |
| `TC-OFF-001` | `REQ-002` | After one online load, disable the network, reload, and a new session starts from a built-in plugin with zero failed requests in the device log. |
| `TC-OFF-002` | `REQ-002` | With the network disabled after reload, slot 1 of a built-in plugin loads and the node shown equals the saved node. |
| `TC-OFF-003` | `REQ-003` | During a full session (choose, three advances, save) the request counter stays at zero except the initial document load. |
| `TC-OFF-004` | `REQ-002` | First-ever load happens online, then the device is taken offline and relaunched from the home screen: the entry screen renders and lists both built-in plugins. |
| `TC-PKG-001` | `REQ-004` | Importing a valid `.zip` through the file picker shows the plugin in the list within 2 seconds and it starts without a reload. |
| `TC-PKG-002` | `REQ-005` | A package that fails any of `V-01`…`V-07`, `V-09` is rejected with its code shown, is not installed, and the previous plugin still starts. |
| `TC-PKG-003` | `REQ-011` | A package whose manifest references one missing asset installs with `V-08` warning; the affected slot renders its text and the game does not crash. |
| `TC-PKG-004` | `REQ-006` | Three plugins installed: the list shows three, exactly one is active, and switching between them never leaves two sessions advancing. |
| `TC-PKG-005` | `REQ-007` | A plugin written only from `SDD.md` §3–§5 by someone who has not seen the engine source installs and runs with zero engine changes (verified by an unchanged build hash). |
| `TC-PROTO-001` | `REQ-009` | Two plugins using different protocols both run; switching the active plugin changes the interaction (planned advance vs turn choice) and the build hash is unchanged. |
| `TC-PROTO-002` | `REQ-010` | A plugin declaring a power-supply and a progress mechanic shows both effects in the session readout; a plugin declaring none shows neither. |
| `TC-SAVE-001` | `REQ-012` | Three slots are writable and independently readable; saving to slot 2 then loading slot 1 returns slot 1's node, and vice versa. |
| `TC-SAVE-002` | `REQ-013` | A save payload with `schema: 2.0.0` is refused with a visible message; the slot is not overwritten and the game stays playable. |
| `TC-BUILTIN-001` | `REQ-014`, `REQ-034` | The built-in Sanguo plugin installs and starts a run budgeted at twenty-four turns over four resources, shows the five ranks as the turn number passes them, offers its five actions, loses three declared ways (the case plays a run to the grain loss and reads the reason), moves a relation by rule, saves and resumes mid-run with the turn, the resources and the relation intact, and reads English in an English session. Every Chinese string it renders is drawn as glyphs, not boxes, and the font covers every character the package uses. |
| `TC-BUILTIN-002` | `REQ-015` | The built-in Xiuxian plugin starts, reaches its end node, and can be saved and resumed; if cut per `SRS.md` §4 this row records "not delivered", not "failed". |
| `TC-DET-001` | `REQ-016` | The same choice sequence with the same seed produces a byte-identical session snapshot on two runs, and a different seed produces a different one. |
| `TC-PERF-001` | `REQ-008` | From plugin selection to the first interactive scene is ≤ 5 s on E2 with a warm cache, measured as the median of three runs. |
| `TC-UX-001` | `REQ-017` | Five first-time participants with no instructions each reach an interactive first session in ≤ 10 minutes without help from the author; at least four succeed. With the window narrowed to 640 px the save-slot rows keep both `Save` and `Load` on screen, and with a picture drawn the last button stays inside the window. |
| `TC-LANG-001` | `REQ-018` | With the browser pinned to each language the interface strings come from that language's catalogue, the landing switch changes the language and keeps it across a reload, and no Chinese literal is left in `app/render`. |
| `TC-ASSET-001` | `REQ-019` | A package declaring a picture and a sound shows the picture in a band above the text at a non-zero size and plays the sound on entry; a package declaring no picture leaves no empty band; a declared-but-missing file leaves a placeholder and one `R-01` warning without aborting. |
| `TC-I18N-002` | `REQ-035` | The menu label, the rank title, a labelled resource and the reason a run ended all read from the package table for the locale, a locale with no table keeps the package text, a key the table leaves out falls back instead of blanking, and a table that covers the scene but not the menu is refused by `V-22`. |
| `TC-CARDS-001` | `REQ-036` | A package that declares a hand deals it, a card spends its cost and applies its effect as one turn, an unaffordable card is refused by name and stays in the hand, the three piles survive a save and a resume, and a deck naming an undeclared card, a card naming an undeclared resource and a claimed `cards.hand@1` without a deck file are refused at install with `V-38`, `V-37` and `V-36`. |
| `TC-CARDS-002` | `REQ-037` | A card that names a texture its package declares shows that picture beside its label and reports it in the view, a card that names none is drawn without a picture, a declared texture whose bytes do not decode keeps the label and leaves one warning, and a card naming an icon no texture asset declares is refused at install with `V-39` naming the missing path. |
| `TC-HAND-001` | `REQ-038` | A hand of eight wraps into rows inside the window, every card is laid out once, a wider window needs fewer rows, and a short hand keeps its whole label. |
| `TC-I18N-001` | `REQ-020` | A package with an English table shows English text and English choice labels when the reader's language is English, keeps its own text in the undeclared language, and a package whose table drops a scene or a choice is refused by `V-22`. |
| `TC-FMT-001` | `REQ-021` | A `2.0.0` bundle with no requirements installs; a package whose `kind`/`layer`/`requires` are malformed is refused with `V-23`; one whose requirement is missing or outside its range is refused with `V-24` naming the package and the installed version; a satisfiable requirement installs; a `1.0.0` package still installs and carries exactly one `W-01` warning. |
| `TC-LEDGER-001` | `REQ-022` | A declared resource starts at its `init` value; an effect above `max` is clamped rather than refused; a rule that names a resource `state.json` never declares is refused with `V-14` naming it; a rule that reads a value the same choice changed sees the new value; a labelled resource shows its label while the number is unchanged; the values survive a save and a resume. |
| `TC-TURN-001` | `REQ-023` | An action whose requirement fails is listed as unavailable with the failing condition and writes nothing when taken; an available action applies its costs and effects in one step; a `per_run` limit refuses the second use without changing any value; an action advances the turn and the rank follows it; a failing condition ends the run and its reason is shown; a check stores the numbers that decided it, and the same seed repeats the same roll. |
| `TC-POOL-001` | `REQ-024` | A draw takes the declared number of items and removes them unless the pool replaces them; what is left travels in the save; the same seed draws the same items; drawing past the pool without `replace` is refused with `V-19`. |
| `TC-REL-001` | `REQ-024` | Relations read only in the direction the package wrote; a state name comes from the package thresholds and not from the engine; an unknown entity is refused with `V-20`, and a pair that disagrees is warned about with `W-02` without being rewritten. |
| `TC-CLOCK-001` | `REQ-025` | A package that declares a clock advances the tick on the declared advance; a rule naming `tick` fires when the count reaches its number; the count survives a save and a resume; a rule that writes `tick` is refused with `V-14`, and a clock nobody reads is refused with `V-21`. |
| `TC-SCENE-001` | `REQ-026` | A package that declares actions opens its scene and is not finished by an empty choice list; each action is a button, an unavailable one is disabled with its reason, an action advances the turn and the readout shows the rank, an ended run shows the reason and no actions, and a package without actions renders as before. |
| `TC-WIRE-001` | `REQ-027` | An action waits on a relation state and on a drawn item; taking a drawing action draws in the same step and unlocks the action waiting on the item; the drawn item and the relation survive a resume; a condition naming an undeclared state is refused with `V-25` and a draw naming an undeclared pool with `V-26`. |
| `TC-SAVE-003` | `REQ-028` | A save is reported finished only after storage says it has nothing left to flush, and the slot screen shows the wait. |
| `TC-SAVE-004` | `REQ-028` | A run resumed from a slot reads in the locale of the interface: scene text, menu labels, rank and labelled resources follow the interface, and a payload without the field falls back to the package text. |
| `TC-CAP-001` | `REQ-029` | A package that names a capability the engine does not provide is refused, the refusal names it, and a 1.0.0 package with a bare name still installs with one warning. |
| `TC-SAFE-001` | `REQ-030` | A package outside the envelope is refused by code (V-28 size or count, V-29 path, V-30 asset) with the measured value named, and a package inside it still installs. |
| `TC-SITUATION-001` | `REQ-033` | The view carries turns left, the entity others lean toward, the entity they push against and the resource closest to its floor; each section disappears when its source is not declared; the scene draws one line that follows the interface language, and a finished run reports zero turns left. |
| `TC-REL-002` | `REQ-032` | A rule moves a relation the package declared, the moved value survives a save and a resume, a package that writes no relation behaves as before, and a rule naming an undeclared entity or a non-numeric change is refused with `V-31`. |
| `TC-BOOT-001` | `REQ-031` | A first visit names the payload size and asks for the tab to stay open, the page reports whether the worker kept the payload, and a reload does not repeat the notice. |
| `TC-BUILTIN-003` | `TC-BUILTIN-001`, `TC-WIRE-001` | A third shipped story, written only as data, installs and is played to an ending: the scene draws one button per declared action, the first turn shows the declared rank, drawing from the pool unlocks the action waiting on the item, playing on ends the run with the declared failure reason, and an English session reads the English table, all without a change under `app/core`. |
| `TC-BUILTIN-004` | `TC-CARDS-001`, `TC-BUILTIN-001` | A fourth shipped package, written only as data, plays a hand of declared cards: the scene shows the opening hand in the package's deck order, playing a card spends its cost, applies its effect and advances the turn, a card the run cannot pay stays in the hand and names the short resource, the rank and the failure reason are the package's words, and a save keeps the hand, the deck order and the discard pile, all without a change under `app/core` or `app/render`. |

## Gaps

None for v0.0.0. `TBD-001`…`TBD-003` in `SRS.md` §5 are specification gaps, not
test gaps: they change how many slots exist and which plugins ship, not whether
the product can be verified.
