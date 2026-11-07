### Added

- A package may declare `view`, `density`, `cast` and `arc` in its manifest, and the scene honours them: the cast line above the text, the sparse readout without the situation, the dense readout with the arc stage and its turn.
- `V-40` refuses a `view` or a `density` the engine does not know, naming the field and the value.
- `V-41` refuses a cast with a repeated id or an empty name, and an arc whose turns are not ascending and unique.

### Changed

- The save payload carries the declaration, so a resumed run reads the way the saved one did.
