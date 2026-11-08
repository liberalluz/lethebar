### Added

- The pack page offers the layers installed against that pack. None of them
  starts ticked, so a player who never asks for one keeps the run the pack
  describes.
- Starting with layers ticked builds the run from the assembly of the pack and
  those layers, and the scene reads what the assembly resolved.
- A save records the set it was written with. Continuing rebuilds that set, not
  what happens to be ticked now, so resume means the run the player left.

### Fixed

- Two ticked layers that write the same field are refused before a run starts,
  with the message the assembly produces rather than a generic failure.
- A save whose layer is no longer installed is refused with `E-02` and the name
  of the missing package, instead of opening a run that is missing a layer.
