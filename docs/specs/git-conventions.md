# Git conventions

One-page defaults. Change this file when the team changes the rule.

## 1. Branches

```text
main                 long-lived, protected
feat/<topic>         user-visible feature
fix/<topic>          bug fix
process/<topic>      process/tooling only
```

- One branch = one change.
- Delete the branch after merge.

## 2. Commits

```text
<type>(<scope>): <subject>
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`.
Scopes: pick exactly one from the closed list below.

| Scope | Covers |
|---|---|
| `app` | Engine code: `app/core`, `app/protocols`, `app/render`, `app/ui` |
| `plugin` | Plugin contract: manifest fields, validation codes `V-0x`, protocol interface, `specVersion` |
| `content` | Built-in packs and their data: `content/builtin/*` |
| `infra` | Build, export, deploy, CI: `infra/checks`, `infra/export_presets`, `infra/*.py` |
| `docs` | Everything under `docs/` except the conventions below: specs, decisions, intent, runbooks |
| `repo` | Repository conventions: `README`, `CONTRIBUTING`, `SECURITY`, `CODEOWNERS`, `docs/specs/git-conventions.md`, topics, `.gitignore` |
| `tools` | Vendored Nebula tooling under `infra/tool/`: `batch`, `repo`, `release` |

- One scope per commit, no second level. `docs(srs)` is not allowed; write `docs(docs): add REQ-018 to the SRS`.
- The scope follows what the change is about, not where the file sits: `git-conventions.md` lives in `docs/` but its changes are `repo`.
- Adding a scope means editing this table first, in the same pull request as its first use.

- Subject is imperative and short.
- Body explains why, not what.
- The body carries two labelled lines, checked by `infra/checks/check_commit_body.py`:
  - `Why:` is required: one or more lines saying what problem the commit solves. Without it the
    reason for a change lives only in the pull request, which is a different document.
  - `Batch:` is required: `Batch: B8` when the commit implements a batch card, `Batch: none` when
    it does not. The card is the thing that decides scope, so the link belongs in history.
- The check reads only the commits a branch adds (`origin/main..HEAD`). It never rewrites or
  rejects merged history, so commits that predate the rule stay exactly as they are.
- No secrets, no generated build output.
- The body is plain text. A commit message is never rendered, so backticks, `**bold**` and
  `__bold__` reach the reader as characters: write `kind`, not `` `kind` ``. `check_commit_body.py`
  refuses all three outside a fenced block. `0bf59cd` carried ten backticks until it was amended.
- Detail like the above belongs in this file, not in `CONTRIBUTING.md`: that file is the door, and a
  rule copied into two places drifts in one of them.

## 3. Pull requests

- One PR = one behavior.
- Fill the PR template.
- Link the issue or record if one exists.
- Reference another pull request as a written link: `[#24](https://github.com/liberalluz/lethebar/pull/24)`.
  A bare `#24` is expanded by the renderer into that pull request's title, and plain text loses the
  link; the written link is the only form that stays a link and stays a reference.
- The three forms were compared side by side in a body and only the written link rendered as a plain
  link: `（#35）` became `PR (title) #35`, `（PR 35）` stayed plain text, `（[#35](…)）` stayed a link.
- Required checks must be green.
- Do not rewrite history after review unless asked.
- When text renders wrongly, ask the renderer before editing the text:
  `gh api -X POST /markdown -f mode=gfm -f context=liberalluz/lethebar -f text='…'`. A link renders as
  a link with a hover card over it; the card is not part of the body and is not a formatting defect.
- Fix the syntax, never the meaning. Deleting a reference or a sentence to make a page look right is
  not a fix.

## 4. Merge

- Squash merge by default.
- A squashed commit takes its subject from the branch commit, so the subject stays English and the PR title stays in the PR. Do not change the repository merge settings to route PR titles into `main`.
- Pass the body on its own: `pr_merge.py --body-only --pr <n> --out <file>` writes what goes into `--body-file`, and `--show` without `--out` writes the whole message for reading. Handing the whole message to `--body-file` puts the subject on the first body line as well, which is what #38 to #45 look like; those commits were merged before this rule and are not rewritten. Redirecting the output through a shell pipe decodes UTF-8 as the local code page and turns every character outside ASCII into U+FFFD, which is what #46 carried until it was amended; `--out` writes the file from Python and has no such step.
- The author does not self-approve.
- No direct push to `main`.
- A failed check is fixed, not bypassed.

## 5. Release

- Version lives in the declared manifest.
- Tag: `vX.Y.Z`.
- `CHANGELOG.md` must have the matching version before tagging.
- Content packs use `pack/<space>/vX.Y.Z` when tagged.

## 6. Language

Four kinds of output, four rules. The values live in `.nebula-scaffold.json` under
one `language` block; change that file first, then this table.

| Output | Language | Config key |
|---|---|---|
| `README`, `CONTRIBUTING`, `SECURITY` | both, English first; the Chinese file carries a `translation-of` marker | `language` (`primary` `en-US`, `supported` `en-US` + `zh-CN`) |
| `docs/specs/controlled/*` | English source plus `zh-CN` translation | `language` |
| Out-of-repo documents (`lethebar-docs`) | English | `language.external` (`en-US`) |
| Pull request title and body | English | `language.external` (`en-US`) |

- A PR title keeps the `type(scope)` prefix and reads as one English sentence:
  `docs(repo): write the v0.1.0 changelog and say what shipped`.
- A PR body uses the five template sections; do not invent another structure. The
  `Verification` section carries the command and its decisive output verbatim,
  because a body that only says "it passed" is not evidence.
- Commit messages stay English per §2, including the squashed commits on `main`.
  The subject of a squashed commit is the subject of the branch commit, so it is
  English as well; do not hand-translate it.
- This rule applies to pull requests opened from now on. Pull requests `#1` to
  `#61` were written in Chinese and are not rewritten; the same is true of the
  commits merged before `v0.0.0`.

## 7. Generated files

| Kind | Examples | Tracked |
|---|---|---|
| Written by a person | `.gd`, `.tscn`, `.tres`, `project.godot`, `export_presets.cfg`, `*.json`, `*.md`, `*.py` | yes |
| Produced by a tool | `app/.godot/`, `*.uid`, `app/builtin/*.zip`, `app/export_presets.cfg`, `build/`, `*.import` | no; add the ignore rule in the same pull request |

- The repository root holds only these entries: the directories `app/`, `content/`, `docs/`, `infra/`, `.github/`, `changelog.d/`, and the files `README.md`, `README.zh-CN.md`, `CONTRIBUTING.md`, `CONTRIBUTING.zh-CN.md`, `CONTRIBUTING.ai.md`, `SECURITY.md`, `CHANGELOG.md`, `LICENSE`, `NOTICE`, `AGENTS.md`, `.gitignore`, `.gitattributes`, `.nebula-scaffold.json`. Tooling lives under `infra/tool/`, so there is no root `tools/`.
- Adding an entry at the root means editing that list in the same pull request. A directory that has no home in the layout is not created.
- `python infra/checks/check_tree.py` enforces the list and the ignore rules; a local pass is required before opening a pull request.
- Run `git status` after any Godot or build command. An untracked file is either a new source file to add or a generated file to ignore; it is never left unexplained.
