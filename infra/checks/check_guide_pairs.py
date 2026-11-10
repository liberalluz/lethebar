#!/usr/bin/env python3
"""Every guide page has a Chinese twin with the same section count.

The guide is written in English and mirrored in `*.zh-CN.md`; a page added or a
section added to one side and not the other is the drift this check is for. It
does not compare wording: a translation is allowed to read differently, only the
shape has to match.
"""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

TWIN_SUFFIX = ".zh-CN.md"


def sections(text: str) -> list[str]:
    return [line for line in text.splitlines() if line.startswith("## ")]


def check(guide: Path) -> list[str]:
    failures: list[str] = []
    pages = sorted(p for p in guide.glob("*.md") if not p.name.endswith(TWIN_SUFFIX))
    for page in pages:
        twin = page.with_name(page.name[: -len(".md")] + TWIN_SUFFIX)
        if not twin.exists():
            failures.append(f"[pairs] {page.name}: no Chinese twin ({twin.name})")
            continue
        left = len(sections(page.read_text(encoding="utf-8")))
        right = len(sections(twin.read_text(encoding="utf-8")))
        if left != right:
            failures.append(f"[pairs] {page.name}: {left} sections, the twin has {right}")
    return failures


def self_test() -> int:
    root = Path(".test-tmp") / "guide-pairs-selftest"
    shutil.rmtree(root, ignore_errors=True)
    root.mkdir(parents=True)
    (root / "a.md").write_text("# A\n\n## one\n\n## two\n", encoding="utf-8")
    (root / ("a" + TWIN_SUFFIX)).write_text("# 甲\n\n## 一\n\n## 二\n", encoding="utf-8")
    cases = [("a page and its twin pass", check(root), [])]
    (root / "b.md").write_text("# B\n", encoding="utf-8")
    cases.append(
        (
            "a page without a twin fails",
            check(root),
            ["[pairs] b.md: no Chinese twin (b.zh-CN.md)"],
        )
    )
    (root / ("b" + TWIN_SUFFIX)).write_text("# 乙\n\n## 一\n", encoding="utf-8")
    cases.append(
        (
            "a twin with another section count fails",
            check(root),
            ["[pairs] b.md: 0 sections, the twin has 1"],
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
    guide = Path(args.root) / "docs" / "guide"
    if not guide.is_dir():
        print(f"[pairs] no guide directory at {guide}")
        return 2
    failures = check(guide)
    for failure in failures:
        print(failure)
    pages = sorted(p for p in guide.glob("*.md") if not p.name.endswith(TWIN_SUFFIX))
    print(f"[pairs] {len(pages)} page(s), {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
