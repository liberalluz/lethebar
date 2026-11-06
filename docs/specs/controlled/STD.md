# STD — Test design (v0.0.0)

English · [简体中文](STD.zh-CN.md)

Case bodies for every test in `STP.md`. Each case states what must be true before
it runs, the actions in order, and the observation that decides pass or fail.
Where a case needs a fixture, the fixture is named by its purpose, not by a file
path, so the case survives fixture renames.

## Cases

### `TC-PLAT-001`

- Covers: `REQ-001`
- Preconditions: E2 browser with a clean profile; the exported build copied to a
  static directory and served over plain HTTP; network available.
- Steps:
  1. Open the served URL.
  2. Observe the first screen.
  3. Do not install anything; interact with the first control.
- Exit: the entry screen renders with both built-in plugins listed, no account
  prompt appears, and the first control responds within one second of the screen
  being visible.

### `TC-OFF-001`

- Covers: `REQ-002`
- Preconditions: TC-PLAT-001 passed; the profile has been loaded online once and
  the cache is populated.
- Steps:
  1. Disable the network in the browser devtools.
  2. Reload the page.
  3. Start a session from a built-in plugin.
  4. Read the network panel for the whole reload and session.
- Exit: the entry screen renders offline, the session starts, and the network
  panel shows zero failed requests after the reload.

### `TC-OFF-002`

- Covers: `REQ-002`
- Preconditions: a slot 1 save exists for a built-in plugin; network disabled.
- Steps:
  1. Reload offline.
  2. Open the save list for that plugin and load slot 1.
- Exit: the session resumes at the node recorded in the save, and no request is
  attempted.

### `TC-OFF-003`

- Covers: `REQ-003`
- Preconditions: the build is loaded once; network recording starts after the
  document load.
- Steps:
  1. Choose a plugin.
  2. Advance three times.
  3. Save to slot 1.
  4. Stop recording.
- Exit: the request log contains zero entries attributable to the session; the
  only traffic recorded belongs to the initial document and its own assets.

### `TC-OFF-004`

- Covers: `REQ-002`
- Preconditions: E3 (iOS Safari) device that has loaded the build once online.
- Steps:
  1. Enable airplane mode.
  2. Reopen the browser and navigate to the build's URL, or launch from the home
     screen if added.
  3. Start a built-in plugin.
- Exit: the entry screen renders and both built-in plugins are listed; starting
  one reaches an interactive scene. Same result is required on E2.

### `TC-PKG-001`

- Covers: `REQ-004`
- Preconditions: a valid fixture package built from `SDD.md` §3; the game is on
  the plugin list screen.
- Steps:
  1. Use the import control and pick the fixture file.
  2. Observe the list.
  3. Start the imported plugin.
- Exit: the plugin appears within 2 s with its declared name and version, and it
  starts without a page reload.

### `TC-PKG-002`

- Covers: `REQ-005`
- Preconditions: one invalid fixture per validation code `V-01`…`V-07` and
  `V-09`; one plugin already installed and playable.
- Steps:
  1. Import each invalid fixture in turn.
  2. Read the message shown.
  3. Start the previously installed plugin.
- Exit: each import is rejected with its own code visible, nothing is added to
  the list, and the previously installed plugin still starts.

### `TC-PKG-003`

- Covers: `REQ-011`
- Preconditions: a fixture whose manifest declares one asset that the package
  does not contain; everything else valid.
- Steps:
  1. Import the fixture.
  2. Start it.
  3. Reach the node that would use the missing asset.
- Exit: a `V-08` warning is shown once at import, the node renders its text with a
  placeholder where the asset would be, and no crash or blank screen occurs.

### `TC-PKG-004`

- Covers: `REQ-006`
- Preconditions: three valid fixtures installed, at least two sharing the same
  protocol.
- Steps:
  1. Open the plugin list.
  2. Start plugin A, advance once, switch to B, advance once, switch back to A.
- Exit: the list shows three entries; at any moment exactly one plugin is marked
  active; returning to A resumes at the node reached before switching (no double
  advance, no lost state).

### `TC-PKG-005`

- Covers: `REQ-007`
- Preconditions: an author who has not read the engine source; a published copy
  of `SDD.md` §3–§5 only; a build hash of the current export.
- Steps:
  1. Have the author produce a small plugin from the specification alone.
  2. Import and run it on the unchanged build.
  3. Compare the build hash.
- Exit: the plugin installs and runs; the build hash equals the recorded one; the
  author needed no engine-specific instruction beyond the specification.

### `TC-PROTO-001`

- Covers: `REQ-009`
- Preconditions: fixture A uses `linear@1`, fixture B uses `turn_based@1`; both
  built from the specification.
- Steps:
  1. Run A and record the interaction (single advance control).
  2. Run B and record the interaction (choice among options).
  3. Compare the build hash before and after.
- Exit: both run; the interaction differs as each protocol defines; the build hash
  is unchanged, proving the switch needs no engine change.

### `TC-PROTO-002`

- Covers: `REQ-010`
- Preconditions: fixture C declares a power-supply mechanic and a progress
  mechanic; fixture D declares neither.
- Steps:
  1. Run C and open the session readout.
  2. Run D and open the session readout.
- Exit: C shows both the power-supply value and the progress display, each
  computed from C's own rule table; D shows neither, and no default is invented.

### `TC-SAVE-001`

- Covers: `REQ-012`
- Preconditions: a built-in plugin at a known node; empty save store.
- Steps:
  1. Save to slot 1.
  2. Advance twice; save to slot 2.
  3. Load slot 1, record the node.
  4. Load slot 2, record the node.
  5. Load slot 1 again.
- Exit: the three read-backs return slot 1's first node, slot 2's later node, and
  slot 1's first node again; slot 3 is writable and readable on the same run.

### `TC-SAVE-002`

- Covers: `REQ-013`
- Preconditions: a save payload whose `schema` is `2.0.0`, injected into slot 1;
  a valid save in slot 2.
- Steps:
  1. Attempt to load slot 1.
  2. Attempt to load slot 2.
- Exit: slot 1 is refused with a message naming the schema mismatch and is not
  overwritten; slot 2 loads normally; the game remains interactive.

### `TC-BUILTIN-001`

- Covers: `REQ-014`, `REQ-034`
- Preconditions: Sanguo listed as a built-in plugin; fresh session.
- Steps:
  1. Start Sanguo and read the view: four resources, the turn budget, the rank
     and the menu.
  2. Take `farm`; read the grain and the turn number.
  3. Take `envoys` twice; read the standing and the relation between Cao and
     Shao.
  4. Save to slot 1, reload, load slot 1; compare the turn, the grain and the
     relation.
  5. Start a second run and take `recruit` until the run ends; read the reason.
  6. Start an English session and read the opening text.
- Exit: the run is budgeted at twenty-four turns over four resources and five
  ranks, `farm` feeds the army and spends a turn, the relation moves once the
  standing crosses the declared threshold, the resumed run keeps the turn, the
  resources and the relation, the second run ends by running out of grain and
  says so, and the English session reads English.

### `TC-BUILTIN-002`

- Covers: `REQ-015`
- Preconditions: Xiuxian listed as a built-in plugin; fresh session. If `SRS.md`
  §4 cut order was applied, this case is recorded as not delivered.
- Steps:
  1. Start Xiuxian.
  2. Advance to the end node.
  3. Save and resume.
- Exit: the end node is reached with its text, and resume returns to the saved
  node; or the row records "not delivered per §4" with the cut decision linked.

### `TC-DET-001`

- Covers: `REQ-016`
- Preconditions: a fixture with a fixed seed source; two distinct seeds available.
- Steps:
  1. Run the same choice sequence with seed S and capture the session snapshot.
  2. Repeat with seed S and capture again.
  3. Run the same sequence with seed S′ and capture.
- Exit: the two snapshots for S are byte-identical; the snapshot for S′ differs
  from them; no snapshot contains a wall-clock timestamp outside `savedAt`.

### `TC-PERF-001`

- Covers: `REQ-008`
- Preconditions: E2 desktop, warm cache, build served locally.
- Steps:
  1. From the plugin list, start a built-in plugin; start timing at the click.
  2. Stop timing when the first scene accepts input.
  3. Repeat three times, discard none, take the median.
- Exit: the median is ≤ 5 s; the three raw values are recorded.

### `TC-UX-001`

- Covers: `REQ-017`
- Preconditions: five participants who have never seen the game; a clean browser
  profile; no instructions from the author; a stopwatch.
- Steps:
  1. Give each participant the URL only.
  2. Start timing when the page is handed over.
  3. Stop when the participant performs an in-game action without asking anything.
- Exit: at least four of five reach that point in ≤ 10 minutes; each participant's
  time and any help requested are recorded.
### `TC-LANG-001`

- Covers: `REQ-018`
- Preconditions: headless run of `app/tests/run_tests.gd`; the exported build with
  the probe pinned to `--lang=en-US`.
- Steps:
  1. In the headless run, ask `Locale` for a key before any choice: it answers in
     English and the string is the catalogue's, not the key name.
  2. Switch to `zh-CN`, read the same key, then reload the catalogue: the Chinese
     string survives the reload.
  3. Scan every file under `app/render` for a character in the CJK range; the scan
     must find none.
  4. In the browser, click the language button on the landing screen, confirm the
     reported locale changed, reload, and confirm it persisted, then switch back.
- Exit: steps 1–3 pass in the headless run and step 4 reports `switched`,
  `persisted` and `restored` all true.

### `TC-ASSET-001`

- Covers: `REQ-019`
- Preconditions: headless run; a package fixture whose manifest declares one
  picture slot and one audio asset, a fixture that declares none, and a fixture
  whose declared file is absent from the archive.
- Steps:
  1. Import the fixture with a picture and open its first scene: the picture band
     is visible, the picture texture is not null, and the filled slot is reported.
  2. Import the fixture that declares no assets: the band stays hidden and no slot
     is reported.
  3. Import the fixture whose file is missing: the session still starts, the
     texture is a placeholder, and exactly one `R-01` warning is recorded.
  4. Open the same scene in the exported build and confirm the picture is drawn
     and every button stays inside the window.
- Exit: steps 1–3 pass in the headless run; step 4 reports the picture slot filled,
  no button outside the window, and zero extra requests.

### `TC-I18N-001`

- Covers: `REQ-020`
- Preconditions: headless run; a package fixture carrying `data/i18n/en.json`
  with full coverage, a fixture with one scene or one choice missing, and the
  built-in Sanguo package with its English table.
- Steps:
  1. Create a session in `en` for the fully translated fixture: the scene text and
     every choice label come from the table, not from the package's own text.
  2. Create a session in `zh-CN` for the same fixture: the package's own text is
     shown, and the English table is not consulted.
  3. Ask for a locale the package does not declare: the package's own text is
     shown instead of an empty string.
  4. Install the partial fixture: validation reports `V-22` and the package is not
     installed.
- Exit: steps 1–4 pass, and the built-in package shows English text when the
  reader's language is English.

### `TC-FMT-001`

- Covers: `REQ-021`
- Preconditions: headless run; fixture manifests built from one template
  (`fmt-bundle`, `fmt-no-layer`, `fmt-bad-layer`, `fmt-needs`, `fmt-layer`,
  `fmt-range`, `fmt-ok`, `fmt-legacy`); no fixture installed except where a step
  installs one first.
- Steps:
  1. Install `fmt-bundle` (format `2.0.0`, `kind: bundle`, no requirements): it
     installs and the session plays as before.
  2. Install `fmt-no-layer` (`kind: layer`, no `layer`) and `fmt-bad-layer`
     (`layer: weather`): both are refused with `V-23`.
  3. Install `fmt-needs`, whose only requirement is a package that is neither
     installed nor built in: refused with `V-24`.
  4. Install `fmt-layer` (`1.0.0`, `kind: layer`, `layer: mod`), then
     `fmt-range`, which requires `>=2.0.0 <3.0.0`: refused with `V-24`, and the
     message names both `fmt-layer` and its installed version.
  5. Install `fmt-ok`, which requires `fmt-layer` at `>=1.0.0 <2.0.0`: installs.
  6. Install `fmt-legacy` (`specVersion: 1.0.0`): installs, and its warning list
     is exactly one `W-01`.
- Exit: steps 1–6 pass; a `2.0.0` package that cannot resolve its requirements
  never reaches the play screen.

### `TC-LEDGER-001`

- Covers: `REQ-022`
- Preconditions: headless run; four fixture packages, all built from one
  template: `ledger-basic` (resources `power` `init 3`, `min 0`, `max 5`; one
  choice whose effect adds 10), `ledger-undeclared` (same ledger, one rule that
  reads `gold`), `ledger-ordered` (`power` and `standing`, one rule that reads
  `power` and writes `standing`; the choice sets `power` to 0), and one packaged
  save slot.
- Steps:
  1. Install `ledger-basic` and open its first scene: the session state carries
     `power` = 3, the declared `init` value.
  2. Take the only choice, whose effect adds 10: `power` reads 5, the declared
     `max`, instead of 13 and instead of the choice being refused.
  3. Install `ledger-undeclared`: refused with `V-14`, and the message names
     `gold`.
  4. Install `ledger-ordered`, open the first scene and take the choice: `power`
     becomes 0 and `standing` becomes 0 in the same step, because the rules run
     after the effects.
  5. Open a save slot on that run and save it; read the payload back and resume:
     the resumed state carries `power` = 0 and `standing` = 0.
- Exit: steps 1–5 pass; no value ever leaves its declared bounds, and no rule
  survives installation while naming a resource the ledger does not declare.

### `TC-TURN-001`

- Covers: `REQ-023`
- Preconditions: headless run; fixture `turn-menu` (ledger `grain` 10, `pop` 0,
  `prestige` 4; actions `recruit` costing 20 grain and requiring 20, and `drill`
  adding 1 pop; phase machine with ranks and one failure at `pop >= 3`; one check
  named `battle`) and fixture `turn-run` (grain 25; one action `spend` with
  `per_run: 1`; a phase machine with two ranks and no failures).
- Steps:
  1. Install `turn-menu` and read the menu: `recruit` is listed as unavailable
     and the reason names `grain`.
  2. Take `recruit`: nothing changes, because an unavailable action writes nothing.
  3. Take `drill` twice: the second ends the run, because `pop` reaches the
     failure threshold and the reason is shown.
  4. Install `turn-run`, take `spend`: grain drops by 20 and pop rises by 1 in one
     step, and the turn reads 2.
  5. Take `spend` again: the per-run limit refuses it and both values stay as they
     were.
  6. Resolve the `battle` check on two sessions built from the same seed: both
     store `roll`, `bonus`, `total`, `target` and `passed`, and the two rolls are
     equal.
- Exit: steps 1–6 pass; a disabled action never changes state, a limit is counted
  per run, and the same seed reproduces the same roll.

### `TC-POOL-001`

- Covers: `REQ-024`
- Preconditions: headless run; fixture `pool-draw` (one pool of three items that
  draws one and does not replace, one pool of two that draws both and replaces)
  and fixture `pool-too-big` (a pool of one that draws two without replace), plus
  `pool-dupes` (the same item listed twice).
- Steps:
  1. Install `pool-draw` and draw once: exactly one item comes back and the pool
     is one item shorter.
  2. Build a second session from the same entry and draw once: the same item
     comes back, because both sessions share the seed.
  3. Draw twice from the replacing pool: it is still two items long.
  4. Save the run, read it back and resume it: the pool that lost an item is
     still one item shorter.
  5. Install `pool-too-big`: refused with `V-19` and the message says the draw
     exceeds the pool without `replace`.
  6. Install `pool-dupes`: refused with `V-19` for the repeated item.
- Exit: steps 1–6 pass; a draw is not re-rolled by a reload and the same seed
  reproduces the same draw.

### `TC-REL-001`

- Covers: `REQ-024`
- Preconditions: headless run; fixture `rel-map` (thresholds `ally` 60 and
  `hostile` -60; `wei` carries `shu` -40 and `wu` 70, `shu` and `wu` carry their
  own values back), fixture `rel-lopsided` (70 one way, 10 the other) and
  `rel-ghost` (`wei` points at an undeclared `ghost`).
- Steps:
  1. Install `rel-map` and read the two directions of a pair: each returns the
     number the package wrote for that direction.
  2. Read `wei → wu` and `wei → shu` as states: the first is `ally`, the second is
     empty because -40 crosses neither a floor of 60 nor a ceiling of -60.
  3. Read the faction map: the labels are the ones the package wrote.
  4. Install `rel-lopsided`: it installs, and the issue list carries `W-02` for
     the pair that disagrees.
  5. Install `rel-ghost`: refused with `V-20` naming the unknown entity.
- Exit: steps 1–5 pass; the engine invents no state names, assumes no symmetry
  and never rewrites a pair.

### `TC-CLOCK-001`

- Covers: `REQ-025`
- Preconditions: an engine build with the clock brick, and four fixtures:
  `clock-turn` (declares `per: turn`, one rule reads `tick` and sets `grown`),
  `clock-node` (declares `per: node`), `clock-unread` (declares a clock no rule
  reads) and `clock-write` (a rule writes `tick`).
- Steps:
  1. Install `clock-turn` and start a run; read `tick`, take the `wait` action
     twice and read `tick` together with the value the rule sets.
  2. Advance a node in the same run without taking an action, and read `tick`.
  3. Install `clock-node`, start it and advance one node.
  4. Save the turn run into slot 1, resume it and read `tick`.
  5. Install `clock-unread` and then `clock-write`.
- Exit: `tick` starts at zero, is one after the first action and two after the
  second; the rule that reads `tick` writes its value once the count reaches
  two; the `turn` clock does not move on a plain node advance while the `node`
  clock counts every advance; the resumed run reports the saved count;
  `clock-unread` is refused with `V-21` and `clock-write` with `V-14`.

### `TC-SCENE-001`

- Covers: `REQ-026`
- Preconditions: an engine build with the menu, phase and ledger bricks, and a
  fixture `scene-menu` whose entry node offers no choices, declares two actions
  (`feast` costs grain the run cannot afford, `drill` is always available) and a
  phase machine with two ranks and a failure condition on `pop`.
- Steps:
  1. Install `scene-menu` and open its scene; read the buttons the scene offers.
  2. Find the button for `feast` and read whether it is disabled and what its
     label says.
  3. Press `drill` once; read the turn and the readout.
  4. Press `drill` twice more so the failure condition fires; read the text and
     the buttons.
  5. Open the built-in `sanguo` and read its buttons and readout.
- Exit: the scene opens at all — the run is not finished by the empty choice
  list; both actions are buttons and `feast` is disabled with a reason naming
  grain; the turn moves from one to two and the readout names the second rank;
  the ended run shows the failure reason and offers no action buttons; `sanguo`
  shows five buttons and no turn in its readout.


### `TC-WIRE-001`

- Covers: `REQ-027`
- Preconditions: a package that declares `data/actions.json`, `data/pools.json` and
  `data/factions.json`. Its entry node has no choices, its thresholds declare
  `ally` and `hostile`, one entity stands at `ally` toward another, and one pool
  holds a single item.
- Steps:
  1. Install the package and open its scene.
  2. Read the action that waits on the relation state, the one that waits on the
     item, and the one that draws.
  3. Take the drawing action once.
  4. Read the same two waiting actions again.
  5. Save to a slot, load it back, and read the drawn items and the relation.
  6. Install a package whose condition names an undeclared state, then one whose
     `draw` names an undeclared pool.
- Exit: the scene opens; the action waiting on the relation state is available
  while the one waiting on a state no entity has is disabled with that reason; the
  action waiting on the item is disabled until it is drawn; taking the drawing
  action puts exactly that item in the drawn list, the readout names it, and the
  action waiting on it becomes available; after a resume the drawn items and the
  relation state are unchanged; the package with the undeclared state is refused
  with `V-25` and the one with the undeclared pool with `V-26`.


### `TC-BUILTIN-003`

- Covers: `TC-BUILTIN-001`, `TC-WIRE-001`
- Preconditions: the shipped `jianghu` package, staged into the build. It declares
  one node with no choices, a ledger of three resources, four actions, one pool
  holding a single item, a phase machine with three ranks and one failure
  condition, and an English table.
- Steps:
  1. Install the package and open its scene.
  2. Read the buttons and the readout of the first turn.
  3. Read the action that waits on the item, then take the drawing action and read
     it again.
  4. Keep taking the training action until the run ends.
  5. Start a session with the English locale and read the entry text.
- Exit: the package installs with no fatal finding; the scene draws six buttons
  (four actions plus Saves and Back to packs); the readout names the first rank;
  the waiting action is disabled before the draw and enabled after it, with the
  drawn item named in the readout; the run ends with the declared failure reason;
  the English session reads the English text.

## TC-SAVE-003 — a save is reportable only after storage settles

- Covers: `REQ-028`.
- Fixture: a shell whose store reports `pending` for two probes and clean after
  that, plus a store whose backend has no flush at all.
- Steps:
  1. Save into a slot and read what the store returned.
  2. While the backend still reports busy, read the slot screen.
  3. Answer the probe, then read the slot screen again.
  4. Repeat with a backend that has nothing to flush.
- Exit: the first write reports `pending`; the screen says it is writing while the
  backend is busy and says saved only after it agrees; the slot screen stays where
  it is; without a flush hook the write is finished at once.

### `TC-CAP-001` capabilities are checked at install

- Covers: `REQ-029`.
- Fixture: four packages that differ only in `capabilities` — `["ledger@1","text@1"]`,
  `["map@1"]`, `["text"]` written for format 2.0.0, and `["text"]` written for
  format 1.0.0.
- Steps:
  1. Install the first package and read the result.
  2. Install the second and read the code and the message.
  3. Install the third and read the code and the message.
  4. Install the fourth and read its warnings.
  5. Ask the validator for its capability table and parse every id in it.
- Exit: the first installs; the second is rejected with `V-27` naming `map@1`;
  the third is rejected with `V-27` naming `text`; the fourth installs with
  exactly one `W-03`; every id in the table parses as `name@major`.

### `TC-SAFE-001` the install-time envelope is enforced

- Covers: `REQ-030`.
- Fixture: a package with 501 extra entries; one whose extra file is `../evil.json`;
  one with `Data/Extra.json`; one carrying a 5 MB entry; one declaring a
  5000x5000 picture; one declaring a ninety-second WAV; and one ordinary package
  with a 100x100 picture and a small extra file.
- Steps:
  1. Install each package in turn and read the code and message.
  2. Read the archive and total helpers with a 9 MB and a 40 MB value.
- Exit: the crowded, heavy, wide and long packages are refused with `V-28`,
  `V-28`, `V-30` and `V-30`; the two path packages with `V-29`; every message
  gives the measured value or the limit; the ordinary package installs.

## TC-SITUATION-001 - the scene states how the run stands

- Covers: `REQ-033`.
- Fixture: a package with two resources bounded 0..10 and 0..100, three
  entities whose relations sum to a clear lean and a clear friction, and a phase
  machine with six turns.
- Steps: import it and read the view; read the readout line; switch the language
  and read the line again; move the turn past the budget and read again; import a
  package that declares neither factions nor phases.
- Exit: the view carries `turnsLeft` 6, `leaning` is the entity with the highest
  incoming sum, `friction` the lowest, `tight` the resource with the smallest
  share of its range left; the line names all four and changes language; a turn
  past the budget reports 0; the bare package produces no situation section.

## TC-REL-002 - a rule moves a relation, and the save keeps it

- Covers: `REQ-032`.
- Fixture: a package whose `data/factions.json` declares two entities and one
  relation at 70, and whose `data/rules.json` adds -20 to that same pair.
- Steps: create the session and read the relation before any rule runs; start
  the run; read the relation and its state; run the rules once more; save the
  session to slot 1 and resume it; import two packages whose rule names an
  undeclared entity and a non-numeric change.
- Exit: the relation is 70 before the rule, 50 after it, the state is no longer
  `ally`, the opposite direction is untouched, the save keeps 50, the two
  malformed packages are refused with `V-31`, and the run still reports the
  same checks as before.

## TC-BOOT-001 — the first visit says what is coming

- Covers: `REQ-031`.
- Fixture: a fresh profile (no `user://welcome.txt`), then the same profile again.
- Steps:
  1. Open the landing screen in a fresh profile and read `notice`.
  2. Read `window.lethebarCache` once the page has answered.
  3. Reload in the same profile and read `notice` again.
  4. Ask the shell for the notice text with a `QuotaExceededError` in the cache
     state, then with no error.
- Exit: the first read names the size and asks for the tab to stay open; the cache
  state reports whether the worker stored the payload; the reload says nothing;
  the failure text replaces the first-visit sentence and contains the reason.
