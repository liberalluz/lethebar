### Changed

- A published build no longer re-downloads the 39.5 MB engine payload when it did not change: `index.wasm` and `index.pck` now sit in their own caches, named after a digest of their bytes, while the page and its scripts keep the timestamped cache.
- Staging the built-in packages writes fixed timestamps into the zip entries, so packing the same sources twice produces the same bytes and a story build can keep its package cache.

### Fixed

- The worker declared `PAYLOAD` without `PAYLOAD_PREFIX`, so the first update that had old payload caches to clear would have thrown inside `activate` and left the player on the previous worker.
- Installing a new worker no longer prefetches the payload: that download competed with the engine's background write of the player's own `user://` data, which is how an imported pack could disappear before it reached IndexedDB.
