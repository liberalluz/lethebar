#!/usr/bin/env python3
"""Check that a pull request body answers the five questions of the template.

The batch tool writes the body from ``.batch/<id>/pr-body.source.md`` and
refuses to prepare one that is missing a section, but a body can also be
written by hand and pasted, and a merged pull request cannot be re-prepared.
This checker is the same rule applied from the outside.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

SECTIONS = (
    "## Summary",
    "## Impact",
    "## Verification",
    "## Risks",
    "## Self-check",
)


def problems(body: str) -> list[str]:
    found: list[str] = []
    positions = []
    for name in SECTIONS:
        if name not in body:
            found.append(f"missing section: {name}")
        else:
            positions.append((body.index(name), name))
    ordered = [name for _, name in sorted(positions)]
    if ordered != [name for name in SECTIONS if name in body]:
        found.append("sections are out of order: " + " -> ".join(ordered))
    for name in SECTIONS:
        if name not in body:
            continue
        start = body.index(name) + len(name)
        end = len(body)
        for other in SECTIONS:
            if other in body and body.index(other) > start:
                end = min(end, body.index(other))
        if not body[start:end].strip():
            found.append(f"section is empty: {name}")
    return found


def body_from_pr(number: str) -> str:
    result = subprocess.run(
        ["gh", "pr", "view", number, "--json", "body"],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if result.returncode != 0:
        raise SystemExit(f"cannot read pull request {number}: {result.stderr.strip()}")
    return json.loads(result.stdout).get("body") or ""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--body", type=Path, help="a file holding the body")
    parser.add_argument("--pr", help="a pull request number, read through gh")
    args = parser.parse_args()
    if not args.body and not args.pr:
        parser.error("give --body or --pr")
    body = (
        args.body.read_text(encoding="utf-8")
        if args.body
        else body_from_pr(str(args.pr))
    )
    found = problems(body)
    if found:
        for problem in found:
            print(f"[pr-body] {problem}")
        return 1
    print("[pr-body] the five sections are present, ordered and filled in")
    return 0


if __name__ == "__main__":
    sys.exit(main())
