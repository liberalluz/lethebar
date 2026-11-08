# The author's guide

Eight pages about writing a pack: a zip of data that the engine reads, decides
and draws. No engine source is needed, and nothing here assumes you read the rest.

If you read only two pages, read [what a pack is](pack-anatomy.md) and
[publishing](publishing.md): together they take a directory to a release.

## Three ways in

**You want to write a pack.** [What a pack is](pack-anatomy.md) → [manifest.json](manifest.md)
→ [publishing](publishing.md) → [the eight bricks](bricks.md) → [protocols](protocols.md).

**Your world will hold several packs.** Read [one repository, several
packs](repositories.md) before you fix any id: the id is the save key and cannot
change once a player has a save under it. When you add a layer over a published
pack, [a mod layer](mod-layer.md) is the worked example.

**You are changing the engine.** The two pages above are the contract you must
keep — a pack that installs today installs after your change. The authoritative
version of that contract is [`docs/specs/controlled/`](../specs/controlled/).

## The pages

| Page | Answers |
|---|---|
| [pack-anatomy.md](pack-anatomy.md) | what a pack is, what may be inside, what happens on install |
| [manifest.md](manifest.md) | what each field means, which versions exist, what gets refused |
| [publishing.md](publishing.md) | how to build, check, tag and publish |
| [repositories.md](repositories.md) | one repository, several packs, the two kinds and the six dimensions, and how to name them |
| [mod-layer.md](mod-layer.md) | changing numbers and costs of a pack that is already published, end to end |
| [bricks.md](bricks.md) | the eight mechanisms a package can switch on |
| [protocols.md](protocols.md) | the two protocols, and why a third way in is a capability |
| [errors.md](errors.md) | every refusal code, the sentence a player sees, the file to open |

## Templates and a repository to copy

- `templates/pack-min/` — the smallest pack that installs and plays, quoted whole in
  [pack-anatomy.md](pack-anatomy.md)
- `templates/pack-turn/` — the same story with a menu, actions and a phase clock
- `github.com/liberalluz/lethebar-pack-template` — a repository that already holds both
  tools, the gate and a working example; click **Use this template**

These pages are not the specification. When one disagrees with a controlled
document, the controlled document wins and the page has a bug — which is why the
code table in [errors.md](errors.md) is generated from the source.
