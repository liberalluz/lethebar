#!/usr/bin/env python3
"""Fail when a new commit does not say why it exists or which batch it serves.

Two lines are required in every commit body this branch adds:

    Why: <one or more lines explaining the reason for the change>
    Batch: B<n>   (or: Batch: none)

The check looks at `base..HEAD`, so merged history is never rewritten by it: a
commit that is already on `main` is not examined. The subject line is not
checked again here; `docs/specs/git-conventions.md` §2 covers its shape and the
review covers its quality.

`Why:` must be followed by non-empty text, either on the same line or in the
lines up to the next `Key:` line. `Batch:` accepts `B<n>`, `B<n><letter>`
(`B5a`) or `none`.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SEPARATOR = "\x1f"
BATCH_VALUE = re.compile(r"^(B\d+[a-z]?|none)$")
FENCE = re.compile(r"^```")


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or " ".join(args))
    return result.stdout


def base_ref() -> str | None:
    for candidate in ("origin/main", "main"):
        try:
            git("rev-parse", "--verify", "--quiet", candidate)
        except RuntimeError:
            continue
        return candidate
    return None


def field(body: str, name: str) -> str:
    """Return the text that follows `Name:` up to the next `Key:` line."""
    lines = body.splitlines()
    collected: list[str] = []
    inside = False
    in_fence = False
    for line in lines:
        if FENCE.match(line):
            in_fence = not in_fence
        if not in_fence and re.match(rf"^{name}:\s?", line):
            inside = True
            collected.append(line.split(":", 1)[1].strip())
            continue
        if inside:
            if not in_fence and re.match(r"^[A-Za-z][A-Za-z-]*:", line):
                break
            collected.append(line.strip())
    return " ".join(part for part in collected if part).strip()


def main() -> int:
    base = base_ref()
    if base is None:
        print("[commit-body] no main branch to compare against; nothing to check")
        return 0

    try:
        raw = git("log", f"--format=%H{SEPARATOR}%B{SEPARATOR}", f"{base}..HEAD")
    except RuntimeError as error:
        print(f"[commit-body] cannot read history: {error}")
        return 1

    entries = [chunk for chunk in raw.split(SEPARATOR) if chunk.strip()]
    commits: list[tuple[str, str]] = []
    for index in range(0, len(entries) - 1, 2):
        commits.append((entries[index].strip(), entries[index + 1]))

    if not commits:
        print(f"[commit-body] no new commit against {base}; nothing to check")
        return 0

    problems: list[str] = []
    for sha, body in commits:
        subject = body.splitlines()[0] if body.splitlines() else ""
        if not field(body, "Why"):
            problems.append(f"{sha[:8]} {subject}: missing 'Why:'")
        batch = field(body, "Batch")
        if not batch:
            problems.append(f"{sha[:8]} {subject}: missing 'Batch:' (write 'Batch: none' when there is no card)")
        elif not BATCH_VALUE.match(batch.split()[0]):
            problems.append(
                f"{sha[:8]} {subject}: 'Batch: {batch}' should be B<n>, B<n><letter>, or none"
            )

    if problems:
        for problem in problems:
            print(f"[commit-body] {problem}")
        print("[commit-body] see docs/specs/git-conventions.md §2")
        return 1

    print(f"[commit-body] {len(commits)} commit(s) carry Why: and Batch:")
    return 0


if __name__ == "__main__":
    sys.exit(main())
