### Added

- The pack list offers "Install a pack…": a player picks a `.zip` from their own
  disk and it is validated and installed like a built-in one (V-01…V-09), with a
  refusal showing its code and leaving the installed packs alone.
- On the web build the file arrives through an `<input type="file">` injected
  next to the canvas; nothing is uploaded and a session still makes no network
  request. Desktop builds open a native picker.
- The smoke probe installs a real package through that button and asserts it is
  still installed after an offline reload, which closes the last unproven half
  of `TC-OFF-004`.
