#!/usr/bin/env python3
"""Run Godot with a binary that is not on PATH.

`infra/tool/batch/config.json` stores command lines, and the Godot executable is
installed outside the repository. Hard-coding one machine's path would put a user
home directory into a public repository, so the batch checks call this wrapper:

    python infra/checks/run_godot.py --headless --path app -s res://tests/run_tests.gd

The wrapper looks for `GODOT_BIN` first, then for `godot` on `PATH`, and passes
every argument through unchanged. It exits 2 with a short message when neither is
usable, so a missing engine shows up as a check failure instead of a stack trace.

The wrapper also reads the suite's summary line. `B57` taught the suite to skip a
case when the package it needs is not staged, which is right for an engine that
ships no story, but it also means a green run can be green because almost
nothing ran. The summary says how many cases were skipped; this wrapper compares
that number with `LETHEBAR_MAX_SKIPS` (default 0) and fails when the run skipped
more than the allowance.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SKIPPED = re.compile(r"^(?:OK|FAILED) \u2014 \d+ checks?, (?:\d+ failures?, )?(\d+) skipped$")


def find_godot() -> str | None:
    configured = os.environ.get("GODOT_BIN", "").strip()
    if configured:
        return configured if os.path.isfile(configured) else None
    return shutil.which("godot") or shutil.which("godot4")


def main(argv: list[str]) -> int:
    engine = find_godot()
    if engine is None:
        print(
            "godot not found: set GODOT_BIN to the executable, or put godot on PATH",
            file=sys.stderr,
        )
        return 2
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", suffix=".log", delete=False
    ) as log:
        path = Path(log.name)
    try:
        with path.open("w", encoding="utf-8") as stream:
            completed = subprocess.run(
                [engine, *argv],
                stdout=stream,
                stderr=subprocess.STDOUT,
            )
        text = path.read_text(encoding="utf-8", errors="replace")
    finally:
        path.unlink(missing_ok=True)
    print(text, end="" if text.endswith("\n") else "\n")
    if completed.returncode != 0:
        return completed.returncode
    allowance_text = os.environ.get("LETHEBAR_MAX_SKIPS", "0").strip()
    try:
        allowance = int(allowance_text)
    except ValueError:
        print(f"LETHEBAR_MAX_SKIPS is not a number: {allowance_text}", file=sys.stderr)
        return 2
    skipped = 0
    for line in text.splitlines():
        match = SKIPPED.match(line.strip())
        if match:
            skipped = int(match.group(1))
    if skipped > allowance:
        print(
            f"[test] {skipped} case(s) were skipped, the allowance is {allowance}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
