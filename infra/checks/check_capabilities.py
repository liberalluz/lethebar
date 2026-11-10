#!/usr/bin/env python3
"""The capability table and the engine's list say the same thing.

`docs/specs/capabilities.md` is the promise a package reads; `KNOWN_CAPABILITIES`
in `package_validator.gd` is what the engine enforces at `V-27`. A capability
added to one and not the other is either a promise the engine refuses or a power
nobody can ask for, so the two lists have to match exactly.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ID = re.compile(r"^[a-z][a-z0-9.]*@\d+$")
CODE_LIST = re.compile(r"KNOWN_CAPABILITIES\s*:=\s*\[(.*?)\]", re.S)
QUOTED = re.compile(r'"([^"]+)"')


def documented(text: str) -> list[str]:
    if "## Implemented" not in text:
        return []
    section = text.split("## Implemented", 1)[1].split("\n## ", 1)[0]
    ids: list[str] = []
    for line in section.splitlines():
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if not cells:
            continue
        name = cells[0].strip("`")
        if ID.match(name):
            ids.append(name)
    return ids


def enforced(text: str) -> list[str]:
    found = CODE_LIST.search(text)
    return QUOTED.findall(found.group(1)) if found else []


def compare(doc_ids: list[str], code_ids: list[str]) -> list[str]:
    failures: list[str] = []
    for name in doc_ids:
        if name not in code_ids:
            failures.append(f"[capabilities] {name}: documented, not provided")
    for name in code_ids:
        if name not in doc_ids:
            failures.append(f"[capabilities] {name}: provided, not documented")
    for name in sorted({name for name in doc_ids if doc_ids.count(name) > 1}):
        failures.append(f"[capabilities] {name}: documented twice")
    return failures


def self_test() -> int:
    root = Path(".test-tmp") / "capabilities-selftest"
    doc = root / "capabilities.md"
    code = root / "validator.gd"
    root.mkdir(parents=True, exist_ok=True)
    doc.write_text(
        "# Capabilities\n\n## Implemented\n\n| Capability | What |\n| --- | --- |\n"
        "| `text@1` | text |\n\n## Not scheduled\n\n| `map@1` | map |\n",
        encoding="utf-8",
    )
    code.write_text('const KNOWN_CAPABILITIES := [\n\t"text@1",\n]\n', encoding="utf-8")
    cases = [("the two lists agree", compare(documented(doc.read_text()), enforced(code.read_text())), [])]
    code.write_text('const KNOWN_CAPABILITIES := [\n\t"text@1",\n\t"audio@1",\n]\n', encoding="utf-8")
    cases.append(
        (
            "a provided capability with no row fails",
            compare(documented(doc.read_text()), enforced(code.read_text())),
            ["[capabilities] audio@1: provided, not documented"],
        )
    )
    code.write_text('const KNOWN_CAPABILITIES := [\n\t"text@1",\n]\n', encoding="utf-8")
    doc.write_text(
        "# Capabilities\n\n## Implemented\n\n| Capability | What |\n| --- | --- |\n"
        "| `text@1` | text |\n| `map@1` | map |\n\n## Not scheduled\n",
        encoding="utf-8",
    )
    cases.append(
        (
            "a documented capability with no provider fails",
            compare(documented(doc.read_text()), enforced(code.read_text())),
            ["[capabilities] map@1: documented, not provided"],
        )
    )
    failures = 0
    for name, got, want in cases:
        if got != want:
            print(f"[fail] {name}: got {got!r}, want {want!r}")
            failures += 1
        else:
            print(f"[ok] {name}")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    root = Path(args.root)
    doc = root / "docs" / "specs" / "capabilities.md"
    code = root / "app" / "core" / "package_validator.gd"
    for path in (doc, code):
        if not path.is_file():
            print(f"[capabilities] missing {path}")
            return 2
    doc_ids = documented(doc.read_text(encoding="utf-8"))
    code_ids = enforced(code.read_text(encoding="utf-8"))
    if not doc_ids or not code_ids:
        print("[capabilities] could not read one of the lists")
        return 2
    failures = compare(doc_ids, code_ids)
    for failure in failures:
        print(failure)
    print(f"[capabilities] {len(doc_ids)} documented, {len(code_ids)} provided, {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
