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

- Covers: `REQ-014`
- Preconditions: Sanguo listed as a built-in plugin; fresh session.
- Steps:
  1. Start Sanguo.
  2. Make the three decision turns, recording each chosen option.
  3. Reach the end node.
  4. Save to slot 1, reload, load slot 1.
- Exit: all three turns are playable, the end node is reached and shows its text,
  and the resumed session starts at the saved end node.

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