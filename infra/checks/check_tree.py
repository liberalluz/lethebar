#!/usr/bin/env python3
"""Check that this repository's tree matches the layout in git-conventions.md §7.

Two rules are enforced, and both are about **this** repository:

1. The root holds a known set of entries. Anything else is a directory or file
   that has no home in the layout.
2. No tracked path comes from a tool. Generated files are ignored, never
   committed.

An author repository is deliberately not checked here. A repository is a
project: it may hold a build script, a scratch directory or its own CI, and none
of that travels. What travels is the pack, so the pack is what gets checked
(`check_pack.py`), and this file stops having an opinion about someone else's
tree.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT_DIRECTORIES = {
    "app",
    "content",
    "docs",
    "infra",
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


def check_root_entries(root: Path) -> list[str]:
    failures = []
    directories: set[str] = set()
    files: set[str] = set()
    for path in git("-C", str(root), "ls-files"):
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


def check_staged_archives(root: Path) -> list[str]:
    """Every staged archive must still have a source directory.

    The engine reads `res://builtin/*.zip`, so an archive left behind by a
    deleted story is a package the build ships and the repository cannot
    explain. Staging prunes these; this rule is the second pair of eyes, in
    case staging did not run or could not delete.
    """
    failures = []
    staged = root / "app" / "builtin"
    sources = root / "content" / "builtin"
    if not staged.is_dir():
        return failures
    for archive in sorted(staged.glob("*.zip")):
        if not (sources / archive.stem).is_dir():
            failures.append(
                f"[tree] staged archive has no source directory: "
                f"app/builtin/{archive.name} (content/builtin/{archive.stem}/ is gone)"
            )
    return failures


def check_generated_tracked(root: Path) -> list[str]:
    failures = []
    for path in git("-C", str(root), "ls-files"):
        for label, matches in GENERATED_PATTERNS:
            if matches(path):
                failures.append(f"[tree] generated file is tracked ({label}): {path}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check this repository's tree against the layout."
    )
    parser.add_argument(
        "--root",
        default=".",
        help="the repository root to check (default: the current directory)",
    )
    args = parser.parse_args()
    root = Path(args.root).resolve()
    failures = (
        check_root_entries(root)
        + check_generated_tracked(root)
        + check_staged_archives(root)
    )
    for line in failures:
        print(line)
    if failures:
        print(f"[tree] {len(failures)} problem(s)")
        return 1
    print("[tree] layout matches")
    return 0


if __name__ == "__main__":
    sys.exit(main())
