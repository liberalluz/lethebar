# Changelog

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
