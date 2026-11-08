#!/usr/bin/env python3
"""Fail when the commit types and scopes are written twice and disagree.

`docs/specs/git-conventions.md` is the contract: it names the seven commit
types and the closed list of scopes. `infra/tool/batch/config.json` repeats both
so the batch tool can refuse a card that picks a scope nobody allows. Two copies
of one list drift; this repository has already paid for that three times, once
per rule that lived in a document and again in a script.

The document stays the source of truth. This check only compares: it reads the
`Types:` line and the scope table out of the document, reads the same two lists
out of the config, and names the side that is wrong when they differ.

`--self-test` builds a scratch copy in both directions and proves the failure is
real: a scope added only to the document fails, and a scope added only to the
config fails.

The parsing functions are imported by `check_commit_body.py`, so the subject
line is checked against the same lists rather than a third copy.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DOC = Path("docs/specs/git-conventions.md")
CONFIG = Path("infra/tool/batch/config.json")

TYPES_LINE = re.compile(r"^Types:\s*(?P<list>.+)$", re.MULTILINE)
BACKTICKED = re.compile(r"`([a-z]+)`")
SCOPE_ROW = re.compile(r"^\|\s*`(?P<name>[a-z]+)`\s*\|", re.MULTILINE)


def read_types(text: str) -> list[str]:
    """The seven commit types, in the order the document names them."""

    match = TYPES_LINE.search(text)
    if match is None:
        raise ValueError("the document has no 'Types:' line")
    return BACKTICKED.findall(match.group("list"))


def read_scopes(text: str) -> list[str]:
    """The closed scope list, in table order."""

    scopes = SCOPE_ROW.findall(text)
    if not scopes:
        raise ValueError("the document has no scope table")
    return scopes


def load(root: Path) -> tuple[list[str], list[str], list[str], list[str]]:
    """(document types, document scopes, config types, config scopes)."""

    doc_text = (root / DOC).read_text(encoding="utf-8")
    config = json.loads((root / CONFIG).read_text(encoding="utf-8"))
    commit = config.get("commit") or {}
    return (
        read_types(doc_text),
        read_scopes(doc_text),
        list(commit.get("types") or []),
        list(commit.get("scopes") or []),
    )


def problems(document: list[str], configured: list[str], label: str) -> list[str]:
    """Side that differs, written so the reader knows which file to edit."""

    missing = [name for name in document if name not in configured]
    extra = [name for name in configured if name not in document]
    found: list[str] = []
    if missing:
        found.append(
            f"the document lists {', '.join(missing)} in {label}, "
            "and the config does not"
        )
    if extra:
        found.append(
            f"the config lists {', '.join(extra)} in {label}, "
            "and the document does not"
        )
    order_document = [name for name in document if name in configured]
    order_config = [name for name in configured if name in document]
    if not missing and not extra and order_document != order_config:
        found.append(
            f"{label} are in a different order: the document says "
            f"{', '.join(order_document)}, the config says "
            f"{', '.join(order_config)}"
        )
    return found


SUBJECT = re.compile(r"^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?: (?P<subject>.+)$")


def subject_problems(subject: str, types: list[str], scopes: list[str]) -> list[str]:
    """Why one commit subject breaks the contract, in the gate's wording."""

    match = SUBJECT.match(subject)
    if match is None:
        return ["the subject is not '<type>(<scope>): <subject>'"]
    found: list[str] = []
    kind = match.group("type")
    scope = match.group("scope")
    if kind not in types:
        found.append(f"'{kind}' is not one of the types: {', '.join(types)}")
    if scope is None:
        found.append(f"the subject carries no scope; pick one of: {', '.join(scopes)}")
    elif scope not in scopes:
        found.append(f"'{scope}' is not one of the scopes: {', '.join(scopes)}")
    return found


def report(root: Path) -> list[str]:
    document_types, document_scopes, config_types, config_scopes = load(root)
    found = problems(document_types, config_types, "types")
    found += problems(document_scopes, config_scopes, "scopes")
    return found


def self_test() -> int:
    from fixtures import fixture_dir

    failures = 0
    with fixture_dir("conventions") as work:
        doc = (
            "# Conventions\n\n"
            "Types: `feat`, `fix`, `docs`.\n\n"
            "| Scope | Covers |\n|---|---|\n"
            "| `app` | engine |\n| `infra` | build |\n"
        )
        config = {"commit": {"types": ["feat", "fix", "docs"], "scopes": ["app", "infra"]}}

        def build(name: str, document: str, commit: dict) -> Path:
            root = work / name
            (root / DOC).parent.mkdir(parents=True)
            (root / DOC).write_bytes(document.replace("\r\n", "\n").encode("utf-8"))
            (root / CONFIG).parent.mkdir(parents=True)
            (root / CONFIG).write_bytes(
                json.dumps({"commit": commit}, indent=2).encode("utf-8")
            )
            return root

        agreed = build("agreed", doc, config["commit"])
        if report(agreed):
            print(f"FAIL self-test: the copies agree but {report(agreed)}")
            failures += 1

        doc_only = build(
            "doc-only",
            doc.replace("| `infra` | build |", "| `infra` | build |\n| `docs` | prose |"),
            config["commit"],
        )
        found = report(doc_only)
        if not any("docs" in line and "config does not" in line for line in found):
            print(f"FAIL self-test: a scope only in the document was not named: {found}")
            failures += 1

        config_only = build(
            "config-only",
            doc,
            {"types": ["feat", "fix", "docs"], "scopes": ["app", "infra", "tools"]},
        )
        found = report(config_only)
        if not any("tools" in line and "document does not" in line for line in found):
            print(f"FAIL self-test: a scope only in the config was not named: {found}")
            failures += 1

        type_drift = build(
            "type-drift",
            doc.replace("`feat`, `fix`, `docs`", "`feat`, `fix`, `docs`, `chore`"),
            config["commit"],
        )
        found = report(type_drift)
        if not any("chore" in line for line in found):
            print(f"FAIL self-test: a type only in the document was not named: {found}")
            failures += 1

        reordered = build(
            "reordered",
            doc,
            {"types": ["feat", "fix", "docs"], "scopes": ["infra", "app"]},
        )
        found = report(reordered)
        if not any("different order" in line for line in found):
            print(f"FAIL self-test: a reordered list was not named: {found}")
            failures += 1

    print(f"self-test: 5 cases, {failures} failure(s)")
    return 1 if failures else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(REPO_ROOT))
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    root = Path(args.root).resolve()
    found = report(root)
    for line in found:
        print(f"[fail] {line}")
    if found:
        print(f"the two lists in {DOC} and {CONFIG} disagree")
        return 1
    print(f"conventions: {DOC} and {CONFIG} agree on types and scopes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
