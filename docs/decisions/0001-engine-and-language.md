# ADR-0001 · Engine and language

## Context

One codebase must ship two targets: a browser build (v0.0.0) and a native iOS app
(v0.1.0) that is explicitly not a web wrapper. Gameplay must arrive through
third-party plugin packages loaded at runtime, and the specification reserves a
3D path even though v0.0.0 renders 2D only. The author is one person with a
JavaScript and Python background, has never written C#, and cannot spend the time
box on a language.

## Decision

Use **Godot 4 with GDScript**.

Rules, scenes and saves are neutral JSON; GDScript is an interpreter over that
data. The engine is split into a rules runtime and a render runtime, both generic,
both able to stay unchanged while plugins change.

## Consequences

- One project exports both the browser build and a native iOS app; no second
  implementation of the rules.
- GDScript is close enough to Python that the learning cost lands on the engine
  model rather than the syntax.
- 3D is available later by adding a render path, without changing the plugin
  specification.
- Web build size and cold start must be measured early; they are the main threat
  to the "first session within 10 minutes" metric.
- iOS export requires a Mac and Xcode plus a paid developer account; that cost is
  accepted at v0.1.0, not now.

## Rejected alternatives

- **Unity.** Stronger 3D and a bigger asset ecosystem, but the author has no C#
  experience, IL2CPP prevents loading C# assemblies at runtime (which is exactly
  what runtime plugin loading needs), and the licensing history is an avoidable
  risk for a solo project.
- **Flutter with Flame.** Rejected by the product definition: plugins may be 3D,
  and Flame has no 3D path.
- **A pure web/TypeScript engine.** Best for v0.0.0, but the v0.1.0 native iOS
  requirement would force a rewrite or a web wrapper, and the wrapper is
  explicitly rejected.
- **Swift native app plus a TypeScript web build.** Two implementations of the
  same rules; they drift, and a solo author pays that drift every change.
