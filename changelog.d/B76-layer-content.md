### Fixed

- An assembly now applies the `content` block a layer declares. `_apply_layer()`
  merged resources, actions, pools, cards and disabled names, and dropped
  content on the floor, so a published `layer: content` package installed,
  assembled, and changed nothing. The block is one object rather than a list, so
  a layer that declares it replaces the base package's block; a layer that
  declares none leaves it alone.
- `TC-CONTENT-002` covers the case: the same base package assembled without the
  layer reads its own cast and arc, and with the layer reads the layer's, while
  the nodes and the phase machine stay the base package's.
