# ADR-0002 · Plugin package is a plain zip

## Context

Plugins are authored by third parties against a published specification, handed
over as a single file, imported through the browser's file picker, and must work
offline on both the web build and a native build. The author of a plugin should
not need the engine, the engine's tooling, or a build step.

## Decision

A plugin is a **plain zip file** with `manifest.json`, `data/` and `assets/`.
It is unpacked **in memory** at import time; nothing is written to the
filesystem, and nothing is compiled. Package bytes are kept in the install
registry so the plugin can be launched again offline.

## Consequences

- The format is engine-agnostic: any tool that can produce a zip can produce a
  plugin, and the same package works in the browser and in a native build.
- No engine-specific container to document, to version, or to explain to plugin
  authors.
- In-memory unpack means package size matters: large asset sets will need
  streaming or an on-disk cache later.
- There is no signature or trust model in v0.0.0; installation is an explicit
  player action, and that is the only control.

## Rejected alternatives

- **Engine-native package (Godot PCK).** Engine-specific, requires engine tooling
  to build, and is a moving target across engine versions — it would make
  third-party authoring a Godot skill instead of a specification skill.
- **Loose files plus a directory scan.** Impossible in a browser: no directory
  access without a user gesture per file, and no stable path the engine may read.
- **Install from a URL.** Makes play depend on the network, which contradicts the
  offline constraint and the first-session metric.
