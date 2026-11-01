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
Scopes: the module or area.

- Subject is imperative and short.
- Body explains why, not what.
- No secrets, no generated build output.

## 3. Pull requests

- One PR = one behavior.
- Fill the PR template.
- Link the issue or record if one exists.
- Required checks must be green.
- Do not rewrite history after review unless asked.

## 4. Merge

- Squash merge by default.
- The author does not self-approve.
- No direct push to `main`.
- A failed check is fixed, not bypassed.

## 5. Release

- Version lives in the declared manifest.
- Tag: `vX.Y.Z`.
- `CHANGELOG.md` must have the matching version before tagging.
- Content packs use `pack/<space>/vX.Y.Z` when tagged.

## 6. Language

Four kinds of output, four rules. The values live in `.nebula-scaffold.json`; change that file first, then this table.

| Output | Language | Config key |
|---|---|---|
| `README`, `CONTRIBUTING`, `SECURITY` | both, English first | `repoLocale` (`en-US` primary, `zh-CN` supported) |
| `docs/specs/controlled/*` | English source plus `zh-CN` translation | `docsLocale` |
| Out-of-repo documents (`lethebar-docs`) | English | `docsLocale.external` |
| Pull request title and body | Chinese | `prLocale` (`zh-CN`) |

- A PR title keeps the `type(scope)` prefix in English and the text after the colon in Chinese: `docs(readme)：小节「目录」改名「项目结构」`.
- A PR body uses the five template sections; do not invent another structure.
- Commit subjects stay English per §2. Squash merge takes the PR title as the commit subject, so commits landing on `main` are Chinese from `v0.0.0` onward while branch commits stay English. Do not hand-translate either one.
