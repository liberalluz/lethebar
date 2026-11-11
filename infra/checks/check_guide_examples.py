#!/usr/bin/env python3
"""The guide names the data files the loader reads, and nothing else.

Two drifts this check is for. A page that teaches a file name the loader does not
have (`clock.json`, or the pre-B105 `state.json`) sends an author to a package
that silently loses a block. A `requires` example written as bare ids is refused
by the schema, so the guide would be teaching a shape the engine rejects.

The allowed names are read from `app/core/package_loader.gd`; there is no second
list to keep in step.
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

FILE_PATTERN = re.compile(r"data/[a-z0-9_]+\.json")
CONSTANT_PATTERN = re.compile(r'const\s+\w+_PATH\s*:=\s*"([^"]+)"')
BARE_REQUIRES = re.compile(r'"requires"\s*:\s*\[\s*"')
LEGACY_MARKERS = ("before v0.7.5", "published before", "v0.7.5 之前")


def loader_files(loader: Path) -> set[str]:
    found = set()
    for line in loader.read_text(encoding="utf-8").splitlines():
        match = CONSTANT_PATTERN.search(line)
        if match:
            found.add(match.group(1))
    return found


def check(guide: Path, loader: Path) -> list[str]:
    allowed = loader_files(loader)
    if not allowed:
        return [f"[examples] no data file constants in {loader}"]
    failures: list[str] = []
    for page in sorted(guide.glob("*.md")):
        text = page.read_text(encoding="utf-8")
        for number, line in enumerate(text.splitlines(), start=1):
            if any(marker in line for marker in LEGACY_MARKERS):
                continue
            for name in FILE_PATTERN.findall(line):
                if name not in allowed:
                    failures.append(f"[examples] {page.name}:{number}: {name} is not a file the loader reads")
            if "preflight.py --pack" in line and ".zip" in line:
                failures.append(f"[examples] {page.name}:{number}: preflight takes a pack directory, not a zip")
        for number, line in enumerate(text.splitlines(), start=1):
            if BARE_REQUIRES.search(line):
                failures.append(f"[examples] {page.name}:{number}: requires must be objects, not bare ids")
    return failures


def self_test() -> int:
    root = Path(".test-tmp") / "guide-examples-selftest"
    shutil.rmtree(root, ignore_errors=True)
    guide = root / "docs" / "guide"
    loader = root / "app" / "core" / "package_loader.gd"
    guide.mkdir(parents=True)
    loader.parent.mkdir(parents=True)
    loader.write_text(
        'const NODES_PATH := "data/nodes.json"\nconst LEDGER_PATH := "data/ledger.json"\n',
        encoding="utf-8",
    )
    (guide / "a.md").write_text(
        "# A\n\n`data/ledger.json` and `data/nodes.json`.\n\n```json\n\"requires\": [{ \"id\": \"x\", \"version\": \"1.0.0\" }]\n```\n",
        encoding="utf-8",
    )
    cases = [("a page naming loader files passes", check(guide, loader), [])]
    (guide / "b.md").write_text("# B\n\n`data/clock.json`.\n", encoding="utf-8")
    cases.append(
        (
            "a file the loader does not read fails",
            check(guide, loader),
            ["[examples] b.md:3: data/clock.json is not a file the loader reads"],
        )
    )
    (guide / "c.md").write_text('# C\n\n"requires": ["x"],\n', encoding="utf-8")
    cases.append(
        (
            "a bare requires id fails",
            check(guide, loader),
            [
                "[examples] b.md:3: data/clock.json is not a file the loader reads",
                "[examples] c.md:3: requires must be objects, not bare ids",
            ],
        )
    )
    (guide / "d.md").write_text("# D\n\npython preflight.py --pack dist/x.zip\n", encoding="utf-8")
    cases.append(
        (
            "preflight with a zip fails",
            check(guide, loader),
            [
                "[examples] b.md:3: data/clock.json is not a file the loader reads",
                "[examples] c.md:3: requires must be objects, not bare ids",
                "[examples] d.md:3: preflight takes a pack directory, not a zip",
            ],
        )
    )
    failures = 0
    for name, got, want in cases:
        if got != want:
            print(f"[fail] {name}: got {got!r}, want {want!r}")
            failures += 1
        else:
            print(f"[ok] {name}")
    shutil.rmtree(root, ignore_errors=True)
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".", help="repository root")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    root = Path(args.root)
    guide = root / "docs" / "guide"
    loader = root / "app" / "core" / "package_loader.gd"
    if not guide.is_dir():
        print(f"[examples] no guide directory at {guide}")
        return 2
    if not loader.is_file():
        print(f"[examples] no loader at {loader}")
        return 2
    failures = check(guide, loader)
    for failure in failures:
        print(failure)
    print(f"[examples] {len(list(guide.glob('*.md')))} page(s), {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
