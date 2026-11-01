### Added

- The web smoke check now clicks the first screens instead of only screenshotting
  them: the probe presses "New game" and a pack with real mouse events and fails
  if the canvas does not answer.

### Changed

- The shell names the current screen in the window title and, on the web build,
  in a `window.lethebarScreen` global, so a browser driver can tell which screen
  a click landed on without reading pixels.
