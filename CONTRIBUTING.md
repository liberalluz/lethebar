# Contributing

English · [简体中文](CONTRIBUTING.zh-CN.md)

## Before you start

- Read `AGENTS.md`.
- Read `docs/specs/git-conventions.md` §2–§4.
- Read `CONTRIBUTING.ai.md` when AI assisted the change.
- One change = one batch = one PR.

## Flow

```text
branch -> commit -> PR -> review -> merge
```

- Do not push to `main`.
- Keep a branch short-lived.
- Fill the PR template; no placeholders.
- Required checks must pass before merge.

## Scope of a pull request

- A pull request is one batch: one behaviour that changed, and how it was verified. Not one day of work, not one commit.
- Fold into the current pull request: wording, typos, comments, template sync, moving a document to its correct place — same theme, listed under `Also changed` in the description.
- Open a separate pull request: changes crossing themes (tooling / docs / behaviour), and anything that changes a gate, a policy, or an acceptance criterion.
- Test: if the title needs the word "and", split it.
- Upper bound: a diff over roughly 400 lines, or three unrelated modules touched, means the batch was cut too large — split the batch, not just the pull request.

## Review

- The author does not self-approve. If the author is an AI, a human signs off.
- Review the diff, the tests, and the evidence.
- A waiver is recorded, not agreed verbally.

## Merge

- Merge with `gh pr merge --squash`; never push to `main`.
- A squash merge of several commits takes `--subject` and `--body-file`; the body is generated with
  `pr_merge.py`, never typed by hand. The rules and the two mistakes already in history are in
  `docs/specs/git-conventions.md` §4.
- After merging, run `pr_merge.py --verify-only`; §4 says what it reads and why nothing else checks
  that commit.
