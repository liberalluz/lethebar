# ADR-0011 · The marketplace records, it does not host

Amended: 2026-11-06 — the index grows `collection` and `layer`, preflight resolves
a composition rather than one package, and review is layered by `kind`.

## Context

Packages are installed from a `.zip` the player downloads. Today the only
packages are the three built into the build, and the only third-party package is
one a tester imported by hand. A marketplace changes that: there will be
packages nobody on this project wrote, and the question "can I trust this file"
gets asked by players.

Two different questions hide behind it:

- **Will it crash the engine?** That is installer and validator work
  (`ADR-0009`): the envelope, the path whitelist, the caps.
- **Should it be shown at all?** That is marketplace work: identity, licence,
  provenance, review, and removal when something is reported.

The engine must not be the second one. It has no server, no account, and no way to
know whether a story is obscene or infringing.

## Decision

The marketplace is an **index plus a review process**, and its repository is
called `lethebar-marketplace`. The index inside it is a registry — that word
describes the data, not the repository.

**What the index records per package version:**

| Field | Why |
| --- | --- |
| `id`, `version` | identity; `id` carries the author namespace (`liberalluz.sanguo`) |
| `sha256` | the file the index points at is the file that was reviewed |
| `specVersion`, `engine` | what formats and engines can run it |
| `capabilities` | what the engine must provide (`ADR-0008`) |
| `author`, `license`, `homepage`, `tags` | attribution and discovery |
| `collection` | the world a package belongs to, so a shelf can group by it (`ADR-0012`) |
| `layer` | for a mod, the package it changes; empty for everything else (`ADR-0014`) |
| `publishedAt`, `status` | when it appeared; `published` or `withdrawn` |

**A version is immutable.** Once published, a version's bytes and metadata do not
change; a fix is a new version. Withdrawing marks a version unavailable and keeps
its record, because someone may already have it installed and a silent
disappearance is worse than a visible removal.

**The index does not host files.** Each package's zip lives in its own
repository's release, and the index records its hash. The alternative — hosting
every zip in one place — turns the marketplace into a storage service with a
bandwidth bill and an abuse queue on day one.

**Preflight reuses the engine's validator.** The marketplace never has its own
idea of a valid package: the same code that decides whether an install works is
what a publisher runs before submitting (`package_check`), so "it passed review
but will not install" cannot happen.

**Preflight resolves a composition, not one file.** A world, a genre pack and a mod
are chosen together, so the check has to answer three questions before the first
download: every `requires` is satisfiable at the declared versions; every `layer`
names a package that is present and in range; and no two chosen mods write the same
field (`ADR-0013`). What can be proved statically is refused in the browser, not
after a restart. The same resolution is recorded with the install, so a later
withdrawal can name the compositions it affects.

**Review is layered by `kind`, not only by trust tier.**

| `kind` | Automatic lane | What a human still decides |
| --- | --- | --- |
| `bundle` (a playable pack) | envelope, manifest, licence, namespace, capabilities | content judgement |
| `mod` | the same, plus its `layer` target and its declared field set | whether changing someone else's fields is acceptable |
| genre material | not listed | nothing: templates are copied from a git repository, not installed |

A genre repository's `example/` may be listed once it is a real playable package;
its `template/` never is, because an empty shell installed from a shelf is a trap
for the player, not a demonstration.

**Review is layered.** A data-only package gets an automated lane: the envelope,
the manifest, the licence field, the id namespace. A scripted package, if that
tier ever ships, gets a manual lane and is never approved by automation. Content
judgement — offence, infringement, age suitability — belongs to the marketplace
and to its takedown process, not to the engine.

**The name is a product name, and that is deliberate.** Players see a
marketplace, not a registry; keeping the word `registry` for the index inside the
repository is what stops the two concepts from blurring. If the index and the site
ever split, the data repository takes the `-registry` name and the site keeps
`lethebar-marketplace`; until then one repository holds both.

## Consequences

- Publishing means: build, hash, submit, wait for review, and then the release is
  the hosted copy. The publisher's own release is the source of truth for bytes.
- The marketplace cannot silently change what is installed, and a taken-down
  package remains in the record as withdrawn.
- The engine stays neutral: it can state "this package needs `map@1` and fits the
  envelope", and nothing about whether the story is any good.
- `SECURITY.md` gains the boundary sentence: the engine refuses what it can prove
  unsafe; the marketplace is where trust in content is decided.
- The repository is not created until the ecosystem needs it; the name above is a
  decision, the date is not.

## Alternatives considered

- **Host the zips in the marketplace repository.** Rejected: storage, bandwidth
  and abuse handling in one place, before there is a single third-party package.
- **Mutable versions with re-upload.** Rejected: a hash then means nothing, and
  two players installing "the same version" could get different bytes.
- **Sign packages at the marketplace.** Rejected for the data-only tier: a
  signature proves who signed, and the marketplace is not the author. For the
  scripted tier, signatures are the author's obligation (`ADR-0009`).
- **Skip review; rely on the engine's validator.** Rejected: the validator answers
  "will it crash", and no amount of schema checking answers "should this be
  listed".
