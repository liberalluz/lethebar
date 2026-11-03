### Added

- A pack can declare pictures and sound, and a scene now draws them: one wide slot for a scene (or its background fallback) and one narrow slot for a portrait. The bytes are read out of the package once, at import, and decoded only when a scene asks for them.
- `sanguo` ships a painted scene and a short theme, so the first story is no longer text only.

### Changed

- The picture band collapses to zero height when a pack declares no asset, so text-only books keep exactly the layout they had before pictures existed.
- The browser check now fails when a picture band pushes a button out of the window, and it proves an imported pack was written to storage before it blames the cache for losing it.
