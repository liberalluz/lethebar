#!/usr/bin/env python3
"""Check that the author-repository gate template keeps its three steps in order.

The template is copied into repositories that publish packs and nothing else, so
the only thing that can be wrong with it here is its shape: the steps must be
the three a pack can fail at, they must appear in the order each one depends on,
and they must not mention a repository layout - a plugin repository is a
project, and only its archive is checked.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

DEFAULT_TEMPLATE = Path(__file__).resolve().parent.parent / "ci" / "author-gate.yml"
ORDER = ["build", "check_pack", "publish"]
# Every one of these was in the template before B66 and was wrong for a
# repository that has no engine tree of its own.
FORBIDDEN = [
    ("infra/stage_packs.py", "asks the world to supply an engine-side stager"),
    ("--path app", "opens the engine's project directory"),
    ("app/builtin", "reads the engine's built-in packages"),
    ("--profile world", "checks the repository layout instead of the pack"),
    ("check_tree.py", "checks the repository layout instead of the pack"),
]


def steps(text: str) -> list[str]:
    found = []
    for line in text.splitlines():
        match = re.match(r"\s*- name: ([\w-]+)\s*$", line)
        if match:
            found.append(match.group(1))
    return found


def main(argv: list[str]) -> int:
    target = DEFAULT_TEMPLATE
    if "--template" in argv:
        target = Path(argv[argv.index("--template") + 1])
    if not target.is_file():
        print(f"[author-gate] missing template: {target.name}")
        return 1
    text = target.read_text(encoding="utf-8")
    found = steps(text)
    problems = []
    for name in ORDER:
        if name not in found:
            problems.append(f"[author-gate] the template has no {name} step")
    positions = [found.index(name) for name in ORDER if name in found]
    if positions and positions != sorted(positions):
        problems.append(
            f"[author-gate] steps are out of order: {' -> '.join(found)}"
        )
    if "This file is a template" not in text:
        problems.append(
            "[author-gate] the template does not say it is a template to copy"
        )
    for needle, reason in FORBIDDEN:
        if needle in text:
            problems.append(f"[author-gate] the template {reason} ({needle})")
    if not problems:
        print(f"[author-gate] {len(found)} step(s), build -> check_pack -> publish")
        return 0
    for problem in problems:
        print(problem)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
