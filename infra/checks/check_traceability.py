#!/usr/bin/env python3
"""Check that every requirement has a design landing and a test case.

The three documents live in the controlled set; this check only compares the
ids they name. A requirement that `SRS` states but `SDD` never lands, or `STP`
never covers, is a broken link in the chain `REQ -> SDD -> TC -> batch`.
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import tempfile
from pathlib import Path

REQ = re.compile(r"REQ-\d{3}")
SRS = Path("docs/specs/controlled/SRS.md")
SDD = Path("docs/specs/controlled/SDD.md")
STP = Path("docs/specs/controlled/STP.md")


def ids(path: Path) -> set[str]:
    return set(REQ.findall(path.read_text(encoding="utf-8")))


def audit(root: Path) -> list[str]:
    srs, sdd, stp = (root / path for path in (SRS, SDD, STP))
    for path in (srs, sdd, stp):
        if not path.is_file():
            raise FileNotFoundError(path)
    required = ids(srs)
    landed = ids(sdd)
    tested = ids(stp)
    problems: list[str] = []
    for req in sorted(required):
        if req not in landed:
            problems.append(f"{req}: no design landing")
        if req not in tested:
            problems.append(f"{req}: no test case")
    return problems


def _write_fixture(root: Path, srs: str, sdd: str, stp: str) -> None:
    base = root / "docs" / "specs" / "controlled"
    base.mkdir(parents=True, exist_ok=True)
    (base / "SRS.md").write_text(srs, encoding="utf-8")
    (base / "SDD.md").write_text(sdd, encoding="utf-8")
    (base / "STP.md").write_text(stp, encoding="utf-8")


def self_test() -> int:
    failures = 0

    def check(name: str, got, want) -> None:
        nonlocal failures
        if got != want:
            failures += 1
            print(f"[fail] {name}: got {got!r}, want {want!r}")
        else:
            print(f"[ok] {name}")

    holder = Path(".test-tmp") / "trace-selftest"
    shutil.rmtree(holder, ignore_errors=True)
    holder.mkdir(parents=True)
    try:
        good = ("| REQ-001 | a |\n| REQ-002 | b |\n", "REQ-001 REQ-002", "| REQ-001 |\n| REQ-002 |\n")
        _write_fixture(holder / "good", *good)
        check("a landed and tested requirement passes", audit(holder / "good"), [])

        case = ("| REQ-001 | a |\n| REQ-002 | b |\n", "REQ-001 REQ-002", "| REQ-001 |\n")
        _write_fixture(holder / "case", *case)
        check("a requirement with no case is named", audit(holder / "case"), ["REQ-002: no test case"])

        design = ("| REQ-001 | a |\n", "", "| REQ-001 |\n")
        _write_fixture(holder / "design", *design)
        check("a requirement with no landing is named", audit(holder / "design"), ["REQ-001: no design landing"])
    finally:
        shutil.rmtree(holder, ignore_errors=True)

    print(f"self-test: 3 cases, {failures} failure(s)")
    return 1 if failures else 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="check REQ -> SDD -> STP coverage")
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    try:
        problems = audit(args.root)
    except FileNotFoundError as exc:
        print(f"check_traceability: {exc.args[0]} not found", file=sys.stderr)
        return 2
    if problems:
        for problem in problems:
            print(f"[traceability] {problem}")
        print(f"check_traceability: {len(problems)} problem(s)")
        return 1
    print(f"check_traceability: {len(ids(args.root / SRS))} requirements, all landed and tested")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
