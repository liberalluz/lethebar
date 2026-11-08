"""Rewrite the reference tables in the author guide from the manifest schema.

The tables a page shows about fields, kinds, layers and asset types are the ones
the engine enforces. Typing them by hand means the page can describe a schema the
code no longer has, so the page carries markers and this tool fills them.

Usage:
    python infra/tool/docs/gen_guide.py --check
    python infra/tool/docs/gen_guide.py --write

`--check` compares and exits 1 on drift; `--write` rewrites the blocks.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCHEMA = ROOT / "app" / "core" / "manifest_schema.gd"
PAGE = ROOT / "docs" / "guide" / "manifest.md"

SCALAR = re.compile(r'^const (?P<name>[A-Z_0-9]+) := "(?P<value>[^"]*)"', re.MULTILINE)
ARRAY = re.compile(r"^const (?P<name>[A-Z_0-9]+) := \[(?P<body>[^\]]*)\]", re.MULTILINE)
ITEMS = re.compile(r'"([^"]*)"|([A-Za-z_][A-Za-z_0-9]*)')

# Fields the format 2.0 checks in `format_issues()` know about and the const
# arrays above never mention. Every name here has to appear somewhere in the
# schema file, or the generator refuses to run: a rename in the schema has to
# reach this list.
EXTRA = {
    "kind": ("string", "`bundle` or `layer`; format 2.0.0 and later", "yes (2.0.0)"),
    "target": ("string", "the package a layer changes; required when `kind` is `layer`", "if layered"),
    "requires": ("list of ids", "packages this layer needs before it can be played", "no"),
    "layer": ("string", "which of the six layers a non-playable package is", "if layered"),
    "collection": ("object", "the world this package belongs to: `{id, names}`", "no"),
    "clock": ("object", "`{per: turn or node, every: n}`; absent means every turn", "no"),
    "meta": ("object", "audience, minutes, pitch, icon: what a shop would show", "no"),
    "content": ("object", "view, density, cast, arc: how this pack tells its story", "no"),
}

TYPE_BY_ARRAY = (
    ("STRING_FIELDS", "string"),
    ("LIST_FIELDS", "list"),
    ("OPTIONAL_STRING_FIELDS", "string"),
    ("OPTIONAL_LIST_FIELDS", "list of strings"),
    ("OPTIONAL_MAP_FIELDS", "object"),
)

MARKERS = {
    "fields": ("fields", "Field table"),
    "vocabulary": ("vocabulary", "Kind, layer and asset-type vocabulary"),
}


def read_consts(text: str) -> dict[str, list[str]]:
    """Every `const NAME := [...]` in the schema file, with names resolved.

    An element is either a quoted string or the name of another constant, which
    is how `KINDS := [KIND_BUNDLE, KIND_LAYER]` is written.
    """
    scalars = {m.group("name"): m.group("value") for m in SCALAR.finditer(text)}
    found: dict[str, list[str]] = {}
    for match in ARRAY.finditer(text):
        values: list[str] = []
        for quoted, bare in ITEMS.findall(match.group("body")):
            if quoted:
                values.append(quoted)
                continue
            if bare not in scalars:
                raise SystemExit(
                    f"generator: {match.group('name')} lists {bare!r}, which is not a string constant"
                )
            values.append(scalars[bare])
        found[match.group("name")] = values
    return found


def field_rows(consts: dict[str, list[str]]) -> list[tuple[str, str, str, str]]:
    """(field, required, type, note) for every manifest field."""
    required = consts.get("REQUIRED_FIELDS", [])
    typed: dict[str, tuple[str, bool]] = {}
    for array, kind in TYPE_BY_ARRAY:
        optional = array.startswith("OPTIONAL_")
        for name in consts.get(array, []):
            typed[name] = (kind, not optional)

    rows: list[tuple[str, str, str, str]] = []
    notes = {
        "id": "permanent slug, `[a-z0-9-]+`; the save key is `save:<id>:<slot>`",
        "version": "this pack's own version; the tag carries the same string",
        "specVersion": "the pack format this pack is written in; `2.0.0` today",
        "engine": "`>=x.y.z <x.y.z`: the engine versions this pack runs on",
        "name": "the title a player sees, in `defaultLocale`",
        "protocol": "`linear@1`, `turn_based@1` or a protocol the engine implements",
        "capabilities": "`name@version` list; each one must exist in the engine",
        "mechanics": "resource names this pack keeps; empty is allowed",
        "entry": "the node the session starts at",
        "saveSchema": "integer; bump it when a save from an older build stops loading",
        "assets": "`{type, path, slot}` list; `texture`, `audio` or `text`",
        "defaultLocale": "the language the text in `data/nodes.json` is already in",
        "locales": "extra languages carried in `data/i18n/<locale>.json`",
        "names": "per-locale titles for this pack",
    }
    for name in required:
        kind, _ = typed.get(name, ("number", True))
        rows.append((name, "yes", kind, notes.get(name, "")))
    for name, (kind, needed) in sorted(typed.items()):
        if needed or name in EXTRA:
            continue
        rows.append((name, "no", kind, notes.get(name, "")))
    for name, (kind, note, needed) in EXTRA.items():
        rows.append((name, needed, kind, note))
    return rows


def render_fields(rows: list[tuple[str, str, str, str]]) -> str:
    lines = ["| Field | Required | Type | What it means |", "| --- | --- | --- | --- |"]
    for field, needed, kind, note in rows:
        lines.append(f"| `{field}` | {needed} | {kind} | {note} |")
    return "\n".join(lines)


def render_vocabulary(consts: dict[str, list[str]]) -> str:
    kinds = consts.get("KINDS", [])
    layers = consts.get("LAYERS", [])
    assets = consts.get("ASSET_TYPES", [])
    units = consts.get("CLOCK_UNITS", [])
    lines = [
        "| Vocabulary | Values |",
        "| --- | --- |",
        f"| `kind` | {', '.join(f'`{v}`' for v in kinds)} |",
        f"| `layer` | {', '.join(f'`{v}`' for v in layers)} |",
        f"| asset `type` | {', '.join(f'`{v}`' for v in assets)} |",
        f"| `clock.per` | {', '.join(f'`{v}`' for v in units)} |",
    ]
    return "\n".join(lines)


def block(text: str, name: str) -> str:
    open_tag = f"<!-- generated:{name} -->"
    close_tag = f"<!-- /generated:{name} -->"
    start = text.index(open_tag) + len(open_tag)
    end = text.index(close_tag)
    return text[start:end].strip("\n")


def replace(text: str, name: str, body: str) -> str:
    open_tag = f"<!-- generated:{name} -->"
    close_tag = f"<!-- /generated:{name} -->"
    start = text.index(open_tag) + len(open_tag)
    end = text.index(close_tag)
    return text[:start] + "\n\n" + body + "\n\n" + text[end:]


def build() -> tuple[str, dict[str, str]]:
    schema_text = SCHEMA.read_text(encoding="utf-8")
    consts = read_consts(schema_text)
    for name in EXTRA:
        if f'"{name}"' not in schema_text:
            raise SystemExit(
                f"generator: the schema never mentions {name!r}; the table would lie"
            )
    if not consts.get("REQUIRED_FIELDS"):
        raise SystemExit("generator: no REQUIRED_FIELDS in the schema")
    rows = field_rows(consts)
    return schema_text, {
        "fields": render_fields(rows),
        "vocabulary": render_vocabulary(consts),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report drift, write nothing")
    parser.add_argument("--write", action="store_true", help="rewrite the generated blocks")
    args = parser.parse_args()
    if not args.check and not args.write:
        parser.error("say --check or --write")

    page = PAGE.read_text(encoding="utf-8")
    _, bodies = build()
    drift = {name: body for name, body in bodies.items() if block(page, name) != body}

    if args.check:
        if not drift:
            print(f"[guide] {PAGE.relative_to(ROOT)}: tables match the schema")
            return 0
        for name in drift:
            print(f"[guide] {name}: the page does not match app/core/manifest_schema.gd")
        print("[guide] run python infra/tool/docs/gen_guide.py --write")
        return 1

    for name, body in bodies.items():
        page = replace(page, name, body)
    PAGE.write_bytes(page.encode("utf-8"))
    print(f"[guide] wrote {len(bodies)} block(s) into {PAGE.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
