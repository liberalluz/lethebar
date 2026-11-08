# Publishing a pack

A pack reaches players as a file, and a file reaches them as a GitHub release asset. This page
covers the six commands that get you from a directory to a release, and the two things that fail
when you skip one.

## The six commands

Run them from the repository that holds your pack. `pack.py` and `check_pack.py` are two files you
copy from the engine; nothing else from the engine is needed.

```text
python infra/tool/release/pack.py self-test      # the tools work on this machine
python infra/tool/release/pack.py build packs/<id> --out dist
python infra/checks/check_pack.py dist/<id>.zip  # the envelope and the manifest
python infra/tool/release/pack.py hash dist/<id>.zip   # writes dist/<id>-<version>.json
python infra/tool/release/preflight.py --pack dist/<id>.zip --repo <owner>/<repo> --tag pack/<id>/v<version>
python infra/tool/release/pack.py publish dist/<id>.zip --repo <owner>/<repo> --tag pack/<id>/v<version> --apply
```

`self-test` builds its own fixture, so a failure there is about your Python and zip tooling, not
about your pack. `hash` writes the descriptor that sits beside the zip; never edit it by hand.

## Start from a repository that already works

`github.com/liberalluz/lethebar-pack-template` holds both tools, the three-step workflow and a
working example pack; click **Use this template**, replace the example, and skip the assembly
above. It is tested against engine `v0.6.0`, and its own gate ran green before it was offered.

## One tag, one release, two assets

| Thing | Value | Example |
| --- | --- | --- |
| tag | `pack/<id>/v<version>` | `pack/pack-min/v0.1.0` |
| asset one | `<id>.zip` | `pack-min.zip` |
| asset two | `<id>-<version>.json` | `pack-min-0.1.0.json` |

The version in the tag, in `manifest.json`, and in the descriptor filename is the same string. If
they disagree, nothing fails loudly — which is exactly why the contract is written down here.

A second release of the same pack is a new tag: `v0.1.1`. Tags are never moved.

## The author gate

Copy `infra/ci/author-gate.yml` from the engine into `.github/workflows/gate.yml` and change one
line: `ENGINE_REF`, which pins the engine version your checks run against. The workflow does three
things and nothing else:

1. `build` — the pack directory becomes a zip;
2. `check_pack` — the zip is refused or accepted;
3. `publish` — only for tags under `refs/tags/pack/`, and only if the first two passed.

Keeping `ENGINE_REF` a tag rather than `main` means a change in the engine cannot turn your build
red overnight.

## Two things that surprise people

**A release asset carries no `Access-Control-Allow-Origin`.** GitHub serves it, but a page on
another origin cannot fetch it. So a player installs a pack by downloading the zip and choosing it
with "Install a pack (.zip)…", not by pasting a link. The link entry exists for shells that can
fetch; in a browser it will fail every time.

**The engine's own test story is not your story.** After the engine stopped shipping the worlds,
a fresh install shows one smoke pack that has no gameplay worth reading. Yours replaces it.

## Before you publish

| Check | What "missing" usually means |
| --- | --- |
| `manifest.json` parses and names an entry node | a trailing comma, or a node renamed after the choice that points at it |
| the three versions agree | `version` bumped in one place only |
| `check_pack` accepts the zip | a stray file at the archive root, or a picture over the size limit |
| the descriptor exists and matches the zip's sha256 | `hash` was skipped, or the zip was rebuilt after hashing |
| the release has both assets | the upload ran twice under different tags |
| the asset is reachable over the network | the repository is private, or the release is still a draft |

If all six pass, a player who downloads the zip can install it. That is the whole test.

## Which template to start from

Two templates ship, and both are checked on every pass: each one is built, read
by `check_pack`, installed into the engine and played before a release goes out.

| Template | Protocol | What it adds |
| --- | --- | --- |
| `templates/pack-min/` | `linear@1` | a manifest and `data/nodes.json`; three nodes, two choices |
| `templates/pack-turn/` | `turn_based@1` | the same node, plus `data/state.json`, `data/actions.json` and `data/phases.json` |

Start from `pack-min` if the story moves from one scene to the next and that is
all it does. Start from `pack-turn` if a scene has a menu of actions under it, or
if the run needs a limit of turns. Copying one of them and rewriting the data
files is faster than starting from an empty directory, because the fields you
would otherwise forget are already in place.
