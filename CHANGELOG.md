# Changelog

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
