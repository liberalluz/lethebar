### Fixed

- The browser probe walks the world screen before it picks a story. A
  repository cut by world opens a world list first, so the old probe waited for
  a pack list that never appeared and reported a missing session on every
  release build since v0.3.0.
- The probe now prefers a story whose picture actually reaches the scene band.
  A deck of cards declares one texture per face, and a picture count was being
  read as "the band will be visible".

### Changed

- The story is clicked by the name the current screen shows, not the one read
  from the landing screen before the world narrowed the list.
