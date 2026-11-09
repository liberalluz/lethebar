#!/usr/bin/env python3
"""Run the lifecycle report from inside the gate.

The report itself belongs to the skill (`project_status.py`); this check only
decides when its answer is red. A machine without the skill installed gets a
sentence, not a traceback: the same dependency `language` already has.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

SKILL_ROOTS = (
    ".agents/skills",
    ".claude/skills",
    ".codex/skills",
    ".codebuddy/skills",
    ".workbuddy/skills",
)
REPORT = Path("nebula-project") / "scripts" / "project_status.py"


def find_report(root: Path) -> Path | None:
    for base in SKILL_ROOTS:
        candidate = root / base / REPORT
        if candidate.is_file():
            return candidate
    return None


def verdict(report: dict) -> list[str]:
    """Reasons the lifecycle report is red. Warnings are not reasons.

    The open batch's own exit record is written by `exit`, after the merge, so
    it cannot be required while the batch is still being checked. Every other
    missing piece of evidence is a reason.
    """
    reasons = [str(item) for item in (report.get("missing") or [])]
    active = report.get("active") or {}
    active_id = active.get("id") if isinstance(active, dict) else None
    if active_id:
        own = f"records/live/{active_id}-exit.md"
        reasons = [reason for reason in reasons if reason != own]
    return reasons


def _check(report: dict) -> int:
    reasons = verdict(report)
    if reasons:
        for reason in reasons:
            print(f"check_lifecycle: missing evidence: {reason}")
        return 1
    print(f"check_lifecycle: {report.get('stage', 'unknown stage')}; nothing missing")
    return 0


def _self_test() -> int:
    cases = [
        ("a missing exit record is red", bool(verdict({"missing": ["B86 has no exit record"]}))),
        ("an empty report is green", not verdict({"missing": []})),
        ("warnings alone stay green", not verdict({"missing": [], "warnings": ["B64 has no card"]})),
        (
            "the open batch's own exit is not demanded",
            not verdict({"active": {"id": "B87"}, "missing": ["records/live/B87-exit.md"]}),
        ),
        (
            "another batch's missing exit is still red",
            bool(verdict({"active": {"id": "B87"}, "missing": ["records/live/B85-exit.md"]})),
        ),
    ]
    failures = 0
    for title, ok in cases:
        print(f"[{'ok' if ok else 'fail'}] {title}")
        failures += 0 if ok else 1
    print(f"self-test: {len(cases)} cases, {failures} failure(s)")
    return 0 if failures == 0 else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--docs-root", default="../lethebar-docs")
    parser.add_argument("--report", type=Path, help="read a saved --json report instead of running it")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return _self_test()
    if args.report:
        return _check(json.loads(args.report.read_text(encoding="utf-8")))

    root = Path(args.root).resolve()
    script = find_report(root)
    if script is None:
        print("check_lifecycle: no nebula-project skill found; install it with the Nebula installer (see AGENTS.md)")
        return 2
    command = [
        sys.executable,
        str(script),
        "--root",
        str(root),
        "--docs-root",
        args.docs_root,
        "--json",
    ]
    done = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
    if done.returncode != 0:
        print("check_lifecycle: the lifecycle report itself failed")
        print(done.stderr.strip() or done.stdout.strip())
        return 1
    try:
        report = json.loads(done.stdout)
    except json.JSONDecodeError:
        print("check_lifecycle: the lifecycle report did not print JSON")
        return 1
    return _check(report)


if __name__ == "__main__":
    raise SystemExit(main())
