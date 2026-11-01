# Intent 0001 — a narrative game whose gameplay lives in plugins

> This file answers *why the project exists*. It does not select technology and
> does not define requirements. Requirements live in `docs/specs/controlled/SRS.md`;
> technology choices become ADRs under `docs/decisions/`.

## Problem

A story-driven game usually hard-codes its gameplay: changing the setting means
rebuilding the game, and changing the gameplay means rebuilding the setting. For
a solo author this cost is paid every time an idea arrives, so ideas die before
they are playable.

The project attacks that cost with one structural bet: **the engine is generic,
the gameplay lives in plugins**. A plugin carries the setting, the story branch
and the rules it wants to be played by; the engine knows how to load, validate,
run and save a plugin, and knows nothing about any particular gameplay.

The rules are mapped from long-form novel structure (the four design source
documents, kept outside this repository), but **the product is the game, not the
mapping**. The mapping is the reason the rules exist; the deliverable is something
a player can open and play.

## Users and motivation

Two users, in order:

1. **The author.** Motivation is idea-driven: an idea appeared and wants to be
   playable. Success is that the author can play three sessions in a row without
   getting bored by the engine rather than by the content.
2. **Strangers on the internet.** Success is that a stranger reaches the first
   playable session within 10 minutes, from a link, with no account and no
   install.

The author is the first player and the only developer. Any design that only works
with a team behind it is wrong for this intent.

## What the game is

Four layers, and only the second one changes per book:

| Layer | Contains | Changes per book |
|---|---|---|
| Engine | rules runtime (progression curve, chapter/scene runner, validator, state tracking) + render runtime (2D/3D, assets, input, audio) | no |
| **Plugin layer** | career packs (setting, tier naming, terminology), category packs (how the player operates), mechanic mods (power supply, progress display) | **yes — this is the gameplay** |
| Asset layer | per-ownership supply: settings elements and terminology from career packs, level material and puzzle banks from category packs, prompt/结算 formats from mechanic mods, plus shared assets | partially |
| Meta config | platform, style, target audience, length and pacing, IP potential | fixed per book |

A plugin is authored against a published plugin specification — a package of
manifest plus data plus assets. Plugins are installed locally, one at a time is
played, and each plugin keeps its own save slots. A future plugin market is a
separate repository, not part of this project.

A session: install plugin(s) → choose one → enter that plugin's branch (scene,
story) → play by the protocol that plugin declares (linear, turn-based, ...) →
save and resume.

## Constraints

- **C-01 Offline.** The game is playable without network access. No feature may
  require a server to play a session.
- **C-02 The engine does not know gameplay.** Adding a plugin must not require
  editing engine code. If a new plugin needs an engine change, the plugin
  specification is wrong, not the plugin.
- **C-03 Third parties can author plugins.** The specification is public and
  complete enough that someone who has never seen the engine can produce a
  working plugin.
- **C-04 A bad plugin must not break others.** A failing or unknown plugin, or an
  unknown asset type, degrades to a visible warning; it does not corrupt other
  plugins or saves.
- **C-05 Browser first, native iOS app next.** v0.0.0 ships in a browser; the next
  version ships as a native iOS app (not a web wrapper). Windows is deferred until
  a concrete need appears. Android is not planned.
- **C-06 Solo scale.** One human plus AI agents, no team.

## Out of scope for v0.0.0

- Plugin market and online plugin download (local file import only).
- Plugin editor or authoring UI.
- 3D rendering (the specification reserves it; v0.0.0 implements one 2D path).
- Multiplayer, accounts, cloud saves.
- iOS build, Windows build, Android.
- Cross-version save migration.
- Art and audio polish (placeholders only).

## Decisions already taken

These are product decisions, recorded here; their technical justifications become
ADRs in the design stage.

1. **A game, not a mapping tool.** The mapping documents are design sources, not
   the deliverable.
2. **v0.0.0 targets the browser only.**
3. **Plugins may be 3D, but v0.0.0 implements a single 2D path.** The specification
   describes all fields now; the engine implements one path.
4. **The engine is split in two: a rules runtime and a render runtime.** Both are
   generic; a plugin declares what it needs and never ships its own renderer.

## Cost, risk, and reopen triggers

- **Time box:** v0.0.0 playable by **2026-12-31** (two months).
- **People:** one human, wearing the decision, product, technical-lead and
  development hats at different times; verification is executed by agents and
  signed by the human. An agent is capacity, not a role: it may not both write a
  change and judge it.
- **Money:** a few hundred CNY. The only unavoidable line is the Apple developer
  account (99 USD/year), needed at v0.1.0, not at v0.0.0.

Risks:

| Risk | Why it is real | Mitigation |
|---|---|---|
| First time with the chosen engine | Engine work competes with the actual product | Scope is cut to B1–B4; if a batch slips, later scope is dropped, never the date |
| Agent self-review blind spots | The author and the checker can be the same model | Judgement runs in a fresh context; the human signs every gate |
| The plugin mechanism may not hold | If loading an external package cannot carry gameplay, the product bet fails | It is the first batch (B1), not the last; if it fails, the fallback is build-time composition |

Reopen triggers — the project is re-opened at stage 0, not patched, when any of
these becomes true:

1. Plugin loading and playback cannot be demonstrated within two weeks of work.
2. 2026-12-31 arrives without a playable v0.0.0.
3. The idea changes (for example, it turns into a tool for authors instead of a
   game to play).
4. A platform hard constraint appears (for example, the app store rejects the
   engine's export, or the browser cannot run the render runtime).
