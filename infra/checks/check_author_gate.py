#!/usr/bin/env python3
"""Check that the author-repository gate template keeps its four steps in order.

The template is copied into repositories that have no gate of their own, so the
only thing that can be wrong with it in this repository is its shape: the four
steps must exist, they must be named the same as the engine's own checks, and
they must appear in the order each one depends on.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

TEMPLATE = Path(__file__).resolve().parent.parent / "ci" / "author-gate.yml"
ORDER = ["tree", "stage", "import", "test"]


def steps(text: str) -> list[str]:
    found = []
    for line in text.splitlines():
        match = re.match(r"\s*- name: (\w+)\s*$", line)
        if match:
            found.append(match.group(1))
    return found


def main() -> int:
    if not TEMPLATE.is_file():
        print(f"[author-gate] missing template: {TEMPLATE.name}")
        return 1
    text = TEMPLATE.read_text(encoding="utf-8")
    found = steps(text)
    problems = []
    for name in ORDER:
        if name not in found:
            problems.append(f"[author-gate] the template has no {name} step")
    positions = [found.index(name) for name in ORDER if name in found]
    if positions != sorted(positions):
        problems.append(
            f"[author-gate] steps are out of order: {' -> '.join(found)}"
        )
    if "--profile world" not in text:
        problems.append("[author-gate] the tree step does not check the world profile")
    if not problems:
        print(f"[author-gate] {len(found)} step(s), tree -> stage -> import -> test")
        return 0
    for problem in problems:
        print(problem)
    return 1


if __name__ == "__main__":
    sys.exit(main())
