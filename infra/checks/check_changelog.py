#!/usr/bin/env python3
"""Fail when a branch carries a `feat` or `fix` commit without a changelog fragment.

The check compares the current branch against `main` (or `origin/main` when it
exists), so it looks at the commits a pull request would add, not at the whole
history. On `main` itself there is nothing to compare and it passes.

A fragment is a file in `changelog.d/` that is new on this branch, carries one of
the Keep a Changelog headings, and has at least one bullet. See
`changelog.d/README.md` for the convention.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
FRAGMENT_DIR = "changelog.d"
FRAGMENT_README = f"{FRAGMENT_DIR}/README.md"
CHANGE_SUBJECT = re.compile(r"^(feat|fix)(\(|:)")
SECTION = re.compile(r"^### (Added|Changed|Fixed|Removed)$", re.MULTILINE)
BULLET = re.compile(r"^- ", re.MULTILINE)


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


def main() -> int:
    base = base_ref()
    if base is None:
        print("[changelog] no main branch to compare against; nothing to check")
        return 0

    try:
        subjects = [
            line
            for line in git("log", "--format=%s", f"{base}..HEAD").splitlines()
            if line.strip()
        ]
        added = [
            path
            for path in git(
                "diff", "--name-only", "--diff-filter=A", f"{base}...HEAD", "--", FRAGMENT_DIR
            ).splitlines()
            if path and path != FRAGMENT_README
        ]
    except RuntimeError as error:
        print(f"[changelog] cannot read history: {error}")
        return 1

    changes = [subject for subject in subjects if CHANGE_SUBJECT.match(subject)]
    if not changes:
        print(f"[changelog] no feat or fix commit against {base}; nothing to check")
        return 0

    problems: list[str] = []
    if not added:
        problems.append(f"{len(changes)} feat/fix commit(s) but no new fragment in {FRAGMENT_DIR}/")
        problems.extend(f"  {subject}" for subject in changes)
        problems.append(
            f"add {FRAGMENT_DIR}/<batch-or-slug>.md with a '### Added' bullet "
            "(see changelog.d/README.md)"
        )

    for path in added:
        text = (REPO_ROOT / path).read_text(encoding="utf-8")
        if not SECTION.search(text):
            problems.append(f"{path}: needs an '### Added', '### Changed', '### Fixed' or '### Removed' heading")
        if not BULLET.search(text):
            problems.append(f"{path}: needs at least one '- ' bullet")

    if problems:
        for problem in problems:
            print(f"[changelog] {problem}")
        return 1

    print(f"[changelog] {len(added)} fragment(s) cover {len(changes)} feat/fix commit(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
