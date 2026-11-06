### Added

- The landing screen says how large the first download is, once per profile, and
  asks the player to keep the tab open until it finishes (`REQ-031`).
- The page asks the generated service worker whether it kept the payload and
  publishes the answer as `window.lethebarCache` (`controlled`, `stored`,
  `error`, `ready`), so a failed cache write is visible in the interface.

### Changed

- The shell draws the first-visit sentence from the cache state rather than from
  a constant, so a build whose payload size changes says the new size.
