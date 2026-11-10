# The author's guide

English · [简体中文](README.zh-CN.md)

Guide v1.0.0. Ten pages about writing a pack: a zip of data that the engine
reads, decides and draws. No engine source is needed, and nothing here assumes
you read the rest.

## ① Start here

[What is this?](what-is-this.md) — what the engine is, what you write, how a run
works, and what a pack cannot do. Read this page first; the rest is detail.

If your world will hold several packs, read [one repository, several packs](repositories.md)
before you fix any id — the id is the save key.

## ② Write a pack

| Page | Answers |
|---|---|
| [pack-anatomy.md](pack-anatomy.md) | what a pack is, what may be inside, what happens on install |
| [manifest.md](manifest.md) | what each field means, which versions exist, what gets refused |
| [bricks.md](bricks.md) | the eight mechanisms a package can switch on |
| [protocols.md](protocols.md) | the two protocols, and why a third way in is a capability |
| [mod-layer.md](mod-layer.md) | changing numbers and costs of a pack that is already published, end to end |
| [repositories.md](repositories.md) | one repository, several packs, the two kinds and the six dimensions, and how to name them |

## ③ Publish

| Page | Answers |
|---|---|
| [publishing.md](publishing.md) | how to build, check, tag and publish |
| [errors.md](errors.md) | every refusal code, the sentence a player sees, the file to open |

## Templates and a repository to copy

- `templates/pack-min/` — the smallest pack that installs and plays, quoted whole in
  [pack-anatomy.md](pack-anatomy.md)
- `templates/pack-turn/` — the same story with a menu, actions and a phase clock
- `github.com/liberalluz/lethebar-pack-template` — a repository that already holds both
  tools, the gate and a working example; click **Use this template**

## These pages are not the specification

When one disagrees with a controlled document in [`docs/specs/controlled/`](../specs/controlled/),
the controlled document wins and the page has a bug — which is why the code table
in [errors.md](errors.md) is generated from the source.

Changing the engine is a different job: the contract is the controlled documents, not
this guide.
