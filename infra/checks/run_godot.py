#!/usr/bin/env python3
"""Run Godot with a binary that is not on PATH.

`infra/tool/batch/config.json` stores command lines, and the Godot executable is
installed outside the repository. Hard-coding one machine's path would put a user
home directory into a public repository, so the batch checks call this wrapper:

    python infra/checks/run_godot.py --headless --path app -s res://tests/run_tests.gd

The wrapper looks for `GODOT_BIN` first, then for `godot` on `PATH`, and passes
every argument through unchanged. It exits 2 with a short message when neither is
usable, so a missing engine shows up as a check failure instead of a stack trace.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys


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
    completed = subprocess.run([engine, *argv])
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
