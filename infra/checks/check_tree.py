#!/usr/bin/env python3
"""Check that the repository tree matches the layout in git-conventions.md §7.

Two rules are enforced:

1. The repository root holds a known set of entries. Anything else is a
   directory or file that has no home in the layout.
2. No tracked path comes from a tool. Generated files are ignored, never
   committed.

The check reads the git index, not the working tree, so a local build does not
change the outcome. Run it before opening a pull request.
"""

from __future__ import annotations

import subprocess
import sys

ROOT_DIRECTORIES = {
    "app",
    "content",
    "docs",
    "infra",
    "tools",
    ".github",
    "changelog.d",
}

ROOT_FILES = {
    "README.md",
    "README.zh-CN.md",
    "CONTRIBUTING.md",
    "CONTRIBUTING.zh-CN.md",
    "CONTRIBUTING.ai.md",
    "SECURITY.md",
    "CHANGELOG.md",
    "LICENSE",
    "NOTICE",
    "AGENTS.md",
    ".gitignore",
    ".gitattributes",
    ".nebula-scaffold.json",
}

GENERATED_PATTERNS = (
    (".uid", lambda path: path.endswith(".uid")),
    (".godot/", lambda path: "/.godot/" in f"/{path}"),
    (".import", lambda path: path.endswith(".import")),
    ("app/builtin/", lambda path: path.startswith("app/builtin/")),
    ("staged export preset", lambda path: path == "app/export_presets.cfg"),
    ("build/", lambda path: path.startswith("build/") or "/build/" in path),
    (".test-tmp/", lambda path: "/.test-tmp/" in f"/{path}"),
)


def git(*args: str) -> list[str]:
    result = subprocess.run(
        ["git", *args],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return [line for line in result.stdout.splitlines() if line]


def check_root_entries() -> list[str]:
    failures = []
    directories: set[str] = set()
    files: set[str] = set()
    for path in git("ls-files"):
        parts = path.split("/")
        if len(parts) > 1:
            directories.add(parts[0])
        else:
            files.add(parts[0])
    for name in sorted(directories - ROOT_DIRECTORIES):
        failures.append(f"[tree] unexpected root directory: {name}/")
    for name in sorted(ROOT_DIRECTORIES - directories):
        failures.append(f"[tree] missing root directory: {name}/")
    for name in sorted(files - ROOT_FILES):
        failures.append(f"[tree] unexpected root file: {name}")
    return failures


def check_generated_tracked() -> list[str]:
    failures = []
    for path in git("ls-files"):
        for label, matches in GENERATED_PATTERNS:
            if matches(path):
                failures.append(f"[tree] generated file is tracked ({label}): {path}")
    return failures


def main() -> int:
    failures = check_root_entries() + check_generated_tracked()
    for line in failures:
        print(line)
    if failures:
        print(f"[tree] {len(failures)} problem(s)")
        return 1
    print("[tree] layout matches")
    return 0


if __name__ == "__main__":
    sys.exit(main())
