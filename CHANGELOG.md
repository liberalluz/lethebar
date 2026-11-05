# Changelog

## v0.1.0 - 2026-11-05

### Added
- A package says which format it speaks, whether it is playable on its own (`kind: bundle`) or a piece another package requires (`kind: layer` with a `layer` name), and what it needs (`requires`), as ADR-0007 settles.
- The installer refuses a package whose `kind`/`layer`/`requires` are malformed (`V-23`) or whose requirement is missing or outside its range (`V-24`), and says which package and which version it wanted.
- The built-in stories declare format `2.0.0` with no requirements, so what players install is the shape the format asks for.
- A package can declare its numbers and their bounds in `data/state.json`, and a resource may map values to display text with `labels`.
- `data/rules.json` settles values in file order after the chosen action's own effects, so a rule reads what the effect just wrote.
- `V-14`: a rule that names a resource the ledger never declares is refused at installation, naming the resource.
- A package can declare an action menu in `data/actions.json`: costs, effects and `requires` are applied together, and an action whose requirement fails is listed as unavailable with the failing condition instead of vanishing.
- `data/phases.json` gives a run a length, ranks read from the turn number, and failure conditions whose reason is shown when they end the run.
- `data/checks.json` resolves dice checks from the session RNG and records the numbers that decided them under `state.checks.<id>`.
- `V-16`, `V-17` and `V-18` refuse a malformed menu, phase machine or check at install time.
- A package can declare item pools in `data/pools.json`: a draw takes the declared number of items and removes them unless the pool replaces them, and what is left travels in the save so a reload cannot re-roll it.
- `data/factions.json` declares directed relations between factions, with the state names supplied by the package through `thresholds`.
- `V-19` refuses a pool that lists an item twice or draws past its size without `replace`; `V-20` refuses a relation that points at an undeclared entity, and `W-02` reports a pair that disagrees in direction without rewriting it.
- A package can declare `clock.per` and a rule can read the engine tick, so content that grows per turn no longer has to fake a counter with resources.
- `TC-CLOCK-001` asserts the tick, both advance modes, the save, and the two refusals.
- A package that declares actions is playable: the scene draws one button per action, keeps an unavailable action visible and disabled with its reason, and shows the turn and the rank.
- `TC-SCENE-001` covers the six lines: the run opens with an empty choice list, every action is a button, an unavailable one is disabled, an action advances the turn and the rank, an ended run shows why and offers nothing, and a package without actions renders as before.
- An action can wait on a relation state the package declares, and on an item a run has already drawn; both read the same numbers the scene shows.
- An action can draw from a pool as part of itself, so the draw and the action's own effects commit in one step and the item unlocks whatever waited on it.
- Validation codes V-25 and V-26 refuse a condition that names a state or an item the package never declared, and a draw that names a pool it never declared.
- Test case TC-WIRE-001 covers the two gates, the joined draw, a save and resume, and both refusals.
- A third built-in story, `jianghu`, written only as data: a ledger of three resources, four actions, one pool, a phase machine with three ranks and a failure condition, and an English table.
- Test case TC-BUILTIN-003 installs that story from the shipped build and plays it to an ending, so a whole new kind of story is shown to run on the bricks the engine already ships.

### Changed
- A package that still declares `1.0.0` installs and carries one `W-01` warning; from v0.2.0 on it is refused.
- Sanguo now keeps `power` and `standing` as numbers with labels (`兵微将寡`, `初露锋芒`, `名动诸侯`) instead of writing a string from a rule.
- Values are clamped into their declared `min`/`max` after both effects and rules; a choice that would overflow stops at the bound instead of failing.
- A save now carries the turn number and the per-action counters, so a restored run keeps its rank and its used-up actions.
- A save now carries what is left of every pool and the order the session RNG fixed on its first draw, so a restored run draws the same way it would have.
- The tick travels in the save payload, so a resumed run continues counting from where the player left instead of starting over.
- A run no longer ends merely because the node it lands on offers no choices when the package declares a phase machine; the phase machine's failure condition or turn limit ends it instead, which is what a menu-driven package needs.
- The readout names the items a run has drawn, because the player can now act on them.
- The build now stages three packages instead of two; `chars.txt` grows to cover the new story's text.
- The browser check waits for that state instead of sleeping two seconds before reloading, and it counts restored slots from the cross-pack list on the landing screen rather than from whichever pack it happened to open.
- `CONTRIBUTING.md`, `CONTRIBUTING.zh-CN.md` and `docs/specs/git-conventions.md` now name `--out` as the way to produce the `--body-file` argument, and record both ways it has gone wrong: the subject repeated in the body (`#38` to `#45`) and U+FFFD from a redirect (`#46`).
- `CONTRIBUTING.md` and `CONTRIBUTING.zh-CN.md` point at `docs/specs/git-conventions.md` §2 and §4 instead of repeating the merge rules, which had already grown three paragraphs of history.

### Fixed
- A save now reports itself as pending until the storage layer says it has nothing left to flush, so the slot screen says "Saving…" before it says the slot is saved and a reload cannot outrun the write. Installing a package passes through the same gate.
- `pr_merge.py --body-only` prints the body alone, so `gh pr merge --body-file` no longer puts the subject on the first body line. `#38` to `#45` were merged with the whole message and each carries that duplicate; they are left as they are, and §4 of `git-conventions.md` now says which flag feeds which argument.
- `pr_merge.py --body-only --out <file>` writes the merge body to a file itself, so the text never passes through a shell pipe that decodes UTF-8 as the local code page; `#46` lost an em dash to that step and was amended.
- `infra/checks/check_commit_body.py` refuses backticks, `**bold**` and `__bold__` in a commit body outside a fenced block: a commit message is never rendered, so the markers reached the reader as characters. `0bf59cd` carried ten backticks until it was amended.

## v0.0.2 - 2026-11-04

### Added
- The `修仙` pack now carries an English table: an English reader meets English scene text and English choice labels in the second built-in story, not Chinese.
- `TC-I18N-001` in the suite: the shipped Xiuxian pack is played in English and must leave no Chinese ideograph in its entry scene or its labels.

### Changed
- `xiuxian`'s manifest declares `defaultLocale`, `locales` and `names`, so it is listed as `Cultivation` on an English landing page and as `修仙` on a Chinese one.
- The font subset is rebuilt from the full Noto Sans SC with `infra/build_font.py`, so the repertoire is reproducible instead of being whatever the last person happened to cut.
- The web payload grows from 3,473,468 to 4,142,764 bytes (`index.pck`), the only file that changes: the engine payload is byte-identical and keeps its cache name.

### Fixed
- An ideograph from CJK extension A (`U+3400-U+4DBF`) now draws as a glyph instead of a box: the shipped font covers that block as well as the BMP block it already covered.

## v0.0.1 - 2026-11-03

### Added
- A package may declare `defaultLocale`, `locales` and `names`, and carry one table of text per language under `data/i18n/<locale>.json`. The Sanguo pack now ships English text for every node and choice.
- `V-22` refuses a package whose declared locale is unsupported, has no table, or leaves a node text or a choice label empty.
- `app/i18n/en.tsv` and `app/i18n/zh_CN.tsv`, the two interface catalogues.
- a language switch on the landing screen; the choice is stored and survives a reload.
- A pack can declare pictures and sound, and a scene now draws them: one wide slot for a scene (or its background fallback) and one narrow slot for a portrait. The bytes are read out of the package once, at import, and decoded only when a scene asks for them.
- `sanguo` ships a painted scene and a short theme, so the first story is no longer text only.
- `infra/tool/merge/pr_merge.py`: builds the message for a squash merge and checks the commit one leaves behind. One commit keeps its own subject and body, so a single-commit pull request needs no arguments; more than one needs `--why` and `--batch`, because there is no single reason to take from them.
- `python infra/tool/merge/pr_merge.py --verify-only` reads the top commit of the default branch. Nothing read that commit before: the commit-body gate only looks at `origin/main..HEAD` on a branch, so a missing `Why:` on `main` stayed invisible.

### Changed
- A new session plays in the language the interface is in, and falls back to the package's own text when the package carries no table for it.
- The pack list shows the pack's title in the current language when the manifest supplies one.
- The picture band now takes what the text and buttons leave over instead of a fixed share of the window, so a longer English scene keeps every button on screen.
- A published build no longer re-downloads the 39.5 MB engine payload when it did not change: `index.wasm` and `index.pck` now sit in their own caches, named after a digest of their bytes, while the page and its scripts keep the timestamped cache.
- Staging the built-in packages writes fixed timestamps into the zip entries, so packing the same sources twice produces the same bytes and a story build can keep its package cache.
- every interface sentence now comes from `Locale.text()`, so `app/render` holds no user-visible text of its own.
- The picture band collapses to zero height when a pack declares no asset, so text-only books keep exactly the layout they had before pictures existed.
- The browser check now fails when a picture band pushes a button out of the window, and it proves an imported pack was written to storage before it blames the cache for losing it.
- `CONTRIBUTING.md` and `CONTRIBUTING.zh-CN.md`: the merge step says to run that check after merging, and says what a multi-commit pull request has to pass to `gh pr merge`.

### Fixed
- The worker declared `PAYLOAD` without `PAYLOAD_PREFIX`, so the first update that had old payload caches to clear would have thrown inside `activate` and left the player on the previous worker.
- Installing a new worker no longer prefetches the payload: that download competed with the engine's background write of the player's own `user://` data, which is how an imported pack could disappear before it reached IndexedDB.
- `pr_merge.py --verify-only` now reports a commit that sits on the default branch without its `(#<number>)` suffix. It used to pass any commit whose pull request was not named, which is how a merged subject lost `(#36)` for a few minutes.
- `pr_merge.py --show` appends the number only once. A subject that already ended in `(#<number>)` came out as `(#36) (#36)`.

## v0.0.0 - 2026-11-02

### Added
- Import a plugin package from a zip file; a package with a missing field, an out-of-range engine version or an unknown protocol is rejected with a coded reason (B1).
- Play a `linear@1` flow to its ending, with a snapshot that repeats byte for byte when the same seed and the same choices are replayed (B2).
- Play `turn_based@1` rounds and the built-in `sanguo` package: three decision rounds to an ending, with power supply read out per round (B3).
- Keep three save slots and imported packages across a reload; a save written by an unknown schema is refused with a reason instead of being migrated (B4).
- A first-time player can open the app, pick the shipped `sanguo` pack, play it to the end, save to a slot and load that slot back — the shell now renders the landing screen, the plugin list, the session screen with its mechanic readout, and three save slots.
- The web build draws that first screen in a browser: the smoke probe reloads it three times and reports the median time until the screen settles.
- A package that fails validation is refused with its code shown to the player, and the pack list still works afterwards.
- A second built-in genre ships: `xiuxian` plays a five-scene segment on `linear@1` and shows how far along the segment the player is (`step 2/5`), which is the first use of the `progress` mechanic.
- The shell lists whatever has been staged into `res://builtin/` instead of naming one package, so a new genre appears without touching the render layer.
- The web build installs a service worker that caches the whole payload on first load, so a reload with the network off still starts a game.
- The smoke check now drives the build with the network off: it reloads, starts a game, and reads back the save slot it wrote before going offline.
- The pack list offers "Install a pack…": a player picks a `.zip` from their own disk and it is validated and installed like a built-in one (V-01…V-09), with a refusal showing its code and leaving the installed packs alone.
- On the web build the file arrives through an `<input type="file">` injected next to the canvas; nothing is uploaded and a session still makes no network request. Desktop builds open a native picker.
- The smoke probe installs a real package through that button and asserts it is still installed after an offline reload, which closes the last unproven half of `TC-OFF-004`.
- `app/render/fonts/NotoSansSC-Regular.woff2`: one Noto Sans SC subset (SIL OFL 1.1) owned by the render layer and shared by every pack, so a pack carries its text and never a font. Coverage is `U+4E00-9FFF` plus punctuation, ASCII and Latin-1; rare ideographs outside it still fall back to boxes.
- A headless check that fails when a character a shipped pack can show — or a character the shell puts on screen — has no glyph in the font the project ships. String assertions passed while every Chinese line was unreadable, so the coverage is now asserted on characters rather than trusted.
- `PROBE_SHOT=<path>` on the smoke probe writes the first scene as a PNG, for the parts of the picture a person has to read.
- `Continue` on the landing screen lists every saved run in this browser - each row names its story, its slot, a preview of the scene and the time it was written - and opens that pack exactly where the player stopped. It only appears when something is saved.
- The web smoke check now clicks the first screens instead of only screenshotting them: the probe presses "New game" and a pack with real mouse events and fails if the canvas does not answer.
- The product version lives in `app/project.godot` (`application/config/version`) and the shell reports it as `lethebarState.version`, so a release has one number to keep in step instead of three.
- Export the project for the web with `infra/export_web.py`, and load the exported build in a headless browser with `infra/verify_web.py` (no batch; the browser pipeline was previously unproven).

### Changed
- Saves and imported packs live in the engine's own storage (IndexedDB on the web build) instead of memory, so they survive a reload.
- A session is proven not to touch the network by counting browser requests during play, not by grepping the source for an HTTP client.
- The landing screen is a way in again, not a menu: one line says what the game is, then `New game` leads to the stories. Listing the stories on the landing screen made every visit start with a choice before the player saw the game.
- The pack list shows each pack's own name and hides the protocol identifier: `sanguo — turn_based@1, 0.1.0` read like a turn-based strategy game.
- The save screen says what a slot holds ("Saving keeps your place in this story"), and an unused slot reads "nothing saved yet" instead of "empty".
- The shell names the current screen in the window title and, on the web build, in a `window.lethebarScreen` global, so a browser driver can tell which screen a click landed on without reading pixels.
- The landing screen shows the version at the end of its one line, which makes it obvious which build a phone is running.

### Fixed
- Imported packs disappeared after a reload because the stored packages were never restored; they are restored at boot now.
- The screen's text column grew past the window when the text wrapped, which pushed every button, including "New game", below the fold.
- Pack text renders in the browser. The engine shipped its built-in font, which has Latin glyphs only, so every Chinese string in `sanguo` and `xiuxian` drew as a box; a player could start a game and see nothing readable.
- Opening a download link on the site (for example `/lethebar/test-pack.zip`) showed the game instead of the file: the offline document fallback answered every top level navigation. Only a directory or `index.html` URL now gets the document.
- Opening the site offline now works. The generated service worker cached `index.html`, but a player navigates to the directory URL (`/lethebar/`), and the cache lookup compared whole URLs, so every offline reload fell through to the network. On iOS Safari that surfaced as "FetchEvent.respondWith received an error: TypeError: Load failed" instead of the game.
- The smoke check now navigates to the directory URL like a player does, so the offline phase would have caught this; it previously navigated to `/index.html` and passed.
- The Continue list showed each save's time in UTC, so a save made at 14:20 in UTC+8 read `06:20`. It now shows the player's own clock.
- In a narrow window the save slots pushed `Save` and `Load` past the right edge, so a player could not save or load at all. Each row now wraps its text inside the width the window leaves for the two buttons, and the stored preview is clipped to 24 characters with an ellipsis instead of taking the first 40 characters of the scene.

### Removed
