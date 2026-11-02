### Fixed

- Opening the site offline now works. The generated service worker cached
  `index.html`, but a player navigates to the directory URL (`/lethebar/`), and
  the cache lookup compared whole URLs, so every offline reload fell through to
  the network. On iOS Safari that surfaced as "FetchEvent.respondWith received
  an error: TypeError: Load failed" instead of the game.
- The smoke check now navigates to the directory URL like a player does, so the
  offline phase would have caught this; it previously navigated to
  `/index.html` and passed.
