#!/usr/bin/env python3
"""Every guide page has a Chinese twin with the same shape and the same tokens.

The guide is written in English and mirrored in `*.zh-CN.md`; a page added, a
section added, a version left behind or a data file renamed on one side only is
the drift this check is for. Wording is not compared: a translation is allowed to
read differently. What must survive are the things a reader copies — the version
tokens, the backticked `data/*.json` paths — and, in the controlled specs, the
REQ and TC codes.
"""
from __future__ import annotations

import argparse
import re
import shutil
import sys
from pathlib import Path

TWIN_SUFFIX = ".zh-CN.md"
VERSION = re.compile(r"\bv\d+\.\d+\.\d+\b")
DATA_PATH = re.compile(r"`(data/[a-z_]+\.json)`")
CODE = re.compile(r"\b(REQ-\d{3}|TC-[A-Z]+-\d{3})\b")
CONTROLLED = ("SRS", "SDD", "STP", "STD")


def sections(text: str) -> list[str]:
    return [line for line in text.splitlines() if line.startswith("## ")]


def twins(name: str) -> str:
    return name[: -len(".md")] + TWIN_SUFFIX


def compare(label: str, english: set[str], chinese: set[str], what: str) -> list[str]:
    failures: list[str] = []
    for token in sorted(english - chinese):
        failures.append(f"[pairs] {label}: the twin is missing the {what} {token}")
    for token in sorted(chinese - english):
        failures.append(f"[pairs] {label}: the twin carries the {what} {token}, the English page does not")
    return failures


def check_guide(guide: Path) -> list[str]:
    failures: list[str] = []
    pages = sorted(p for p in guide.glob("*.md") if not p.name.endswith(TWIN_SUFFIX))
    for page in pages:
        twin = page.with_name(twins(page.name))
        if not twin.exists():
            failures.append(f"[pairs] {page.name}: no Chinese twin ({twin.name})")
            continue
        english = page.read_text(encoding="utf-8")
        chinese = twin.read_text(encoding="utf-8")
        left, right = len(sections(english)), len(sections(chinese))
        if left != right:
            failures.append(f"[pairs] {page.name}: {left} sections, the twin has {right}")
        failures += compare(
            page.name, set(VERSION.findall(english)), set(VERSION.findall(chinese)), "version"
        )
        failures += compare(
            page.name,
            set(DATA_PATH.findall(english)),
            set(DATA_PATH.findall(chinese)),
            "data file",
        )
    return failures


def check_controlled(specs: Path) -> list[str]:
    failures: list[str] = []
    for name in CONTROLLED:
        page = specs / f"{name}.md"
        twin = specs / f"{name}{TWIN_SUFFIX}"
        if not page.exists() or not twin.exists():
            continue
        english = page.read_text(encoding="utf-8")
        chinese = twin.read_text(encoding="utf-8")
        left, right = len(sections(english)), len(sections(chinese))
        if left != right:
            failures.append(f"[pairs] {page.name}: {left} sections, the twin has {right}")
        failures += compare(
            page.name, set(CODE.findall(english)), set(CODE.findall(chinese)), "code"
        )
    return failures


def check(guide: Path, specs: Path | None = None) -> list[str]:
    failures = check_guide(guide)
    if specs is not None and specs.is_dir():
        failures += check_controlled(specs)
    return failures


def self_test() -> int:
    root = Path(".test-tmp") / "guide-pairs-selftest"
    shutil.rmtree(root, ignore_errors=True)
    guide = root / "docs" / "guide"
    specs = root / "docs" / "specs" / "controlled"
    guide.mkdir(parents=True)
    specs.mkdir(parents=True)
    (guide / "a.md").write_text(
        "# A\n\n## one\n\n## two\n\nEngine v1.2.3 reads `data/ledger.json`.\n",
        encoding="utf-8",
    )
    (guide / ("a" + TWIN_SUFFIX)).write_text(
        "# 甲\n\n## 一\n\n## 二\n\n引擎 v1.2.3 读 `data/ledger.json`。\n", encoding="utf-8"
    )
    (specs / "SDD.md").write_text("# SDD\n\n## 1\n\nREQ-001\n\nTC-A-001\n", encoding="utf-8")
    (specs / "SDD.zh-CN.md").write_text("# SDD\n\n## 1\n\nREQ-001\n\nTC-A-001\n", encoding="utf-8")
    cases = [("a page and its twin pass", check(guide, specs), [])]

    (guide / "b.md").write_text("# B\n", encoding="utf-8")
    cases.append(
        (
            "a page without a twin fails",
            check(guide, specs),
            ["[pairs] b.md: no Chinese twin (b.zh-CN.md)"],
        )
    )
    (guide / ("b" + TWIN_SUFFIX)).write_text("# 乙\n\n## 一\n", encoding="utf-8")
    cases.append(
        (
            "a twin with another section count fails",
            check(guide, specs),
            ["[pairs] b.md: 0 sections, the twin has 1"],
        )
    )

    (guide / "c.md").write_text("# C\n\n## one\n\nv1.2.3 `data/ledger.json`\n", encoding="utf-8")
    (guide / ("c" + TWIN_SUFFIX)).write_text("# 丙\n\n## 一\n\nv1.2.2 `data/state.json`\n", encoding="utf-8")
    for stale in ("b.md", "b" + TWIN_SUFFIX):
        (guide / stale).unlink()
    cases.append(
        (
            "a twin with another version and data file fails",
            check(guide, specs),
            [
                "[pairs] c.md: the twin is missing the version v1.2.3",
                "[pairs] c.md: the twin carries the version v1.2.2, the English page does not",
                "[pairs] c.md: the twin is missing the data file data/ledger.json",
                "[pairs] c.md: the twin carries the data file data/state.json, the English page does not",
            ],
        )
    )

    (specs / "SDD.zh-CN.md").write_text("# SDD\n\n## 1\n\nREQ-001\n", encoding="utf-8")
    for stale in ("c.md", "c" + TWIN_SUFFIX):
        (guide / stale).unlink()
    cases.append(
        (
            "a twin without a code fails",
            check(guide, specs),
            ["[pairs] SDD.md: the twin is missing the code TC-A-001"],
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
    if not guide.is_dir():
        print(f"[pairs] no guide directory at {guide}")
        return 2
    specs = root / "docs" / "specs" / "controlled"
    failures = check(guide, specs)
    for failure in failures:
        print(failure)
    pages = sorted(p for p in guide.glob("*.md") if not p.name.endswith(TWIN_SUFFIX))
    print(f"[pairs] {len(pages)} page(s), {len(failures)} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
