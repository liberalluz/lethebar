### Fixed

- A layer that names `genre`, `profession`, `meta` or `assets` no longer
  offers a tick it cannot honour: the pack page says the layer is declared but
  not applied, and the engine names the two dimensions it does apply.
- `assemble()` refuses a layer whose target is not a bundle with `V-44`,
  naming the layer and the target, instead of applying it over another patch.
- `worlds()` no longer counts a layer as a world, so one bundle plus one layer
  is one world rather than an empty "Other stories" shelf.
- `V-42` checks a meta block only where the shell reads it: on the bundle. A
  layer's meta is still validated for shape but no longer refused for content
  nothing renders.
