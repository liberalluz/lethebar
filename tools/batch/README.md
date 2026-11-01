# Project-local batch execution

Optional, project-local execution layer for the implementation stage. It is not
a core Nebula skill and is only installed when bootstrap is called with
`--with-execution`.

The tool is stack-agnostic. It owns the state machine:

```text
plan -> approve -> start -> check -> pr -> merge
```

A stage skill or the project itself provides the checks and provider commands
through `tools/batch/config.json`; `batch.py` only runs commands, reads exit
codes, and writes evidence.

## Files

```text
tools/batch/
  batch.py       state machine
  config.json    project-owned commands and defaults
  README.md      this file
.batch/          local state and evidence; never commit
```

## Commands

```bash
python tools/batch/batch.py plan --goal "add login screen" --allowed "app/**"
python tools/batch/batch.py approve <id> --confirm <hash8>
python tools/batch/batch.py start <id>
python tools/batch/batch.py check <id>
python tools/batch/batch.py pr <id> --prepare
python tools/batch/batch.py pr <id> --create --confirm <body-hash8>
python tools/batch/batch.py merge <id> --pr 123 --yes
python tools/batch/batch.py status
```

`plan` prints the card hash. `approve` records approval of that exact card;
changing the card invalidates the approval.

## Configuration

`config.json`:

```json
{
  "base": "main",
  "branch_prefix": "batch/",
  "scope": {"ignore": [], "generated": []},
  "checks": [
    {
      "name": "test",
      "command": ["python", "-m", "pytest"],
      "cwd": ".",
      "timeout": 600
    }
  ],
  "pr_create": ["gh", "pr", "create", "--title", "{title}", "--body-file", "{body}"],
  "merge": ["gh", "pr", "merge", "{pr}", "--merge"]
}
```

- `checks`: commands run by `check`; each writes `evidence/<name>.log`.
  `cwd` is relative to the project root.
- `pr_create` / `merge`: optional provider hooks. Placeholders:
  `{id}`, `{title}`, `{body}`, `{branch}`, `{root}`, `{pr}`.
- `scope.ignore`: paths ignored by scope checks; `.batch/` is always ignored.
- `scope.generated`: generated paths ignored by scope checks, kept separate
  from hand-written ignores so a project can review the stack's output.
- Empty hooks mean the tool stops at `pr --prepare` or reports that merge must
  be done externally.
- `--with-execution` fills `checks`/`scope` from the selected stack's
  `execution.yaml`; it never overwrites an existing `config.json`.

## Boundaries

- It does not decide whether a change should be batched.
- It does not know Flutter, Swift, or any other stack.
- It does not replace review or human merge approval.
- It does not store records or release notes.
- The project owns `config.json`; bootstrap does not overwrite it on re-run.
