#!/usr/bin/env python3
"""Run the three delivery checks from inside the gate.

`check_external`, `check_links` and `check_records` belong to the
`nebula-delivery` skill; this wrapper only decides when their answers are red.
A machine without the skill installed gets a sentence, not a traceback: the
same dependency `language` and `lifecycle` already have.

`check_external` also expects release evidence (`records/<YYYY-MM>-release-*`)
to sit in the batch index. `SKILL.md` says it does not, and `check_records`
refuses it there, so that one item is reported as a warning and the index is
left to `check_records`.
"""

from __future__ import annotations

import argparse
import json
import os
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
SKILL = Path("nebula-delivery") / "scripts"
KNOWN_EXTERNAL_CONFLICT = "双向对账"


def find_scripts(root: Path) -> Path | None:
    for base in SKILL_ROOTS:
        candidate = root / base / SKILL
        if candidate.is_dir():
            return candidate
    return None


def _run(args: list[str]) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
    return subprocess.run(
        args, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env
    )


def _tail(done: subprocess.CompletedProcess[str]) -> str:
    output = (done.stdout or "").strip() or (done.stderr or "").strip()
    return output.splitlines()[-1] if output else "no output"


def external(script: Path, docs: Path) -> tuple[str, str]:
    done = _run([sys.executable, str(script), str(docs), "--json"])
    try:
        data = json.loads(done.stdout)
    except ValueError:
        return ("failed" if done.returncode else "ok", _tail(done))
    items = data.get("items") or []
    fails = [item for item in items if item.get("status") == "fail"]
    known = [item for item in fails if KNOWN_EXTERNAL_CONFLICT in str(item.get("item", ""))]
    rest = [item for item in fails if KNOWN_EXTERNAL_CONFLICT not in str(item.get("item", ""))]
    if rest:
        item = rest[0]
        return ("failed", f"{item.get('item')}: {item.get('detail')}")
    if known:
        return ("warn", "release evidence is not in the batch index; check_records owns that table")
    return ("ok", f"{sum(1 for item in items if item.get('status') == 'ok')} items")


def plain(script: Path, docs: Path, project: Path, name: str) -> tuple[str, str]:
    args = [sys.executable, str(script), str(docs)]
    if name == "records":
        args += ["--project", str(project)]
    done = _run(args)
    return ("ok" if done.returncode == 0 else "failed", _tail(done))


def main(argv: list[str]) -> int:
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="backslashreplace")
    parser = argparse.ArgumentParser(description="run the delivery checks")
    parser.add_argument("--docs-root", type=Path, required=True)
    parser.add_argument("--project", type=Path, default=Path("."))
    args = parser.parse_args(argv)
    docs = args.docs_root
    if not docs.is_dir():
        print(f"check_delivery: no docs repository at {docs}", file=sys.stderr)
        return 2
    scripts = find_scripts(Path.cwd())
    if scripts is None:
        print("check_delivery: no nebula-delivery skill found; install it with the Nebula installer (see AGENTS.md)", file=sys.stderr)
        return 2
    results = [
        ("external", external(scripts / "check_external.py", docs)),
        ("links", plain(scripts / "check_links.py", docs, args.project, "links")),
        ("records", plain(scripts / "check_records.py", docs, args.project, "records")),
    ]
    failed = 0
    for name, (state, tail) in results:
        print(f"check_delivery: {name} {state}: {tail}")
        if state == "failed":
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
