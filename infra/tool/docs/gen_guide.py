"""Rewrite the reference tables in the author guide from the engine source.

Three pages carry tables that describe what the engine enforces: the manifest
fields, the refusal codes, the bricks, and the protocols. Typing those by hand
means a page can describe a schema or a code list the source no longer has, so
each table sits between markers and this tool fills it.

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
REGISTRY = ROOT / "app" / "core" / "protocol_registry.gd"
VALIDATOR = ROOT / "app" / "core" / "package_validator.gd"
GUIDE = ROOT / "docs" / "guide"

SCALAR = re.compile(r'^const (?P<name>[A-Z_0-9]+) := "(?P<value>[^"]*)"', re.MULTILINE)
ARRAY = re.compile(r"^const (?P<name>[A-Z_0-9]+) := \[(?P<body>[^\]]*)\]", re.MULTILINE)
ITEMS = re.compile(r'"([^"]*)"|([A-Za-z_][A-Za-z_0-9]*)')

# A line that raises a refusal carries the code and, usually, the sentence a
# player sees next to it. Taking the last quoted string on the line covers the
# three shapes the source uses: `_issue("V-03", "id", "must match ...")`,
# `reject("S-05", "%s is not available: %s")` and
# `_problem(CODE_NOTHING, "nothing to save: no active session", slot)`.
CODE_LINE = re.compile(r'"(?P<code>(?:V|S|M|SAVE)-\d{2})"')
QUOTED = re.compile(r'"((?:[^"\\]|\\.)*)"')
CONST_CODE = re.compile(r'^const (?P<name>CODE_[A-Z_0-9]+) := "(?P<code>SAVE-\d{2})"', re.MULTILINE)
PROBLEM_CONST = re.compile(r"_problem\((?P<name>CODE_[A-Z_0-9]+)")

# Reader files that raise codes without naming the code as a literal.
SCAN = (
    ROOT / "app" / "core" / "package_validator.gd",
    ROOT / "app" / "core" / "session.gd",
    ROOT / "app" / "core" / "mechanics.gd",
    ROOT / "app" / "core" / "checks.gd",
    ROOT / "app" / "core" / "save_store.gd",
    ROOT / "app" / "core" / "hand.gd",
    ROOT / "app" / "core" / "menu.gd",
)

# The eight bricks. Each row names the data file that turns it on and the file
# that reads it; the generator refuses to run when a reader file disappears.
BRICKS = (
    ("1. State ledger", "data/ledger.json", "app/core/ledger.gd",
     "the resources a run keeps, each with a start, a floor and a ceiling"),
    ("2. Settlement rules", "data/rules.json", "app/core/mechanics.gd",
     "when a state looks like this, change that state by this much"),
    ("3. Action menu", "data/actions.json", "app/core/menu.gd",
     "what a player can do, what it costs, what it changes, how often"),
    ("4. Phase machine", "data/phases.json", "app/core/phases.gd",
     "the turns a run has, the ranks it passes through, the ways it ends"),
    ("5. Checks", "data/checks.json", "app/core/checks.gd",
     "a named test on the state that a choice or a card can ask for"),
    ("6. Pools", "data/pools.json", "app/core/pools.gd",
     "a set of items drawn without repeats, or dealt as a hand"),
    ("7. Relations", "data/relations.json", "app/core/relations.gd",
     "who stands where with whom, and what a change of standing moves"),
    ("8. Clock", "manifest.json `clock`", "app/core/session.gd",
     "when a turn passes: every choice, every node, or every n of them"),
)

# One line per protocol, keyed by the id in the registry. A protocol added to
# the registry without a line here stops the generator, so the page cannot miss
# it.
PROTOCOLS = {
    "linear@1": (
        "one node at a time, choices lead to other nodes; a node without choices ends the run",
        "`data/nodes.json` with `entry`, every choice naming a `next` node",
    ),
    "turn_based@1": (
        "the same walk, plus a round counter that advances when a node is left",
        "`data/nodes.json`; `data/phases.json` if the run should have a limit",
    ),
}

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
    "persist": ("object", "a small table that survives across runs: `{key: default}`", "no"),
    "rolls": ("object", "named integer ranges for `roll.<name>`: `{name: {from, to}}`", "no"),
}

TYPE_BY_ARRAY = (
    ("STRING_FIELDS", "string"),
    ("LIST_FIELDS", "list"),
    ("OPTIONAL_STRING_FIELDS", "string"),
    ("OPTIONAL_LIST_FIELDS", "list of strings"),
    ("OPTIONAL_MAP_FIELDS", "object"),
)

# page -> the blocks it carries
PAGES = {
    "manifest.md": ("fields", "vocabulary"),
    "errors.md": ("errors",),
    "bricks.md": ("bricks",),
    "protocols.md": ("protocols",),
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


def message_of(line: str, code: str) -> str:
    """The sentence next to a code, with the substitutions blanked out."""
    quoted = QUOTED.findall(line)
    if not quoted:
        return "-"
    sentence = quoted[-1]
    sentence = re.sub(r"%[sd]", "…", sentence)
    sentence = sentence.replace("|", "\\|").strip()
    return sentence or "-"


def error_rows() -> list[tuple[str, str, str]]:
    """(code, file:line, sentence) for every refusal the source can raise."""
    rows: dict[str, tuple[str, str, str]] = {}
    for path in SCAN:
        if not path.exists():
            raise SystemExit(f"generator: {path.relative_to(ROOT)} is missing")
        text = path.read_text(encoding="utf-8")
        constants = {m.group("name"): m.group("code") for m in CONST_CODE.finditer(text)}
        for number, line in enumerate(text.splitlines(), start=1):
            found = CODE_LINE.search(line)
            code = found.group("code") if found else None
            if code is None:
                alias = PROBLEM_CONST.search(line)
                if alias:
                    code = constants.get(alias.group("name"))
            if code is None:
                continue
            where = f"`{path.relative_to(ROOT).as_posix()}:{number}`"
            rows.setdefault(code, (code, where, message_of(line, code)))
    if not rows:
        raise SystemExit("generator: no refusal codes found in the source")
    return [rows[code] for code in sorted(rows)]


def render_errors(rows: list[tuple[str, str, str]]) -> str:
    lines = [
        "| Code | Raised at | What it says |",
        "| --- | --- | --- |",
    ]
    for code, where, sentence in rows:
        lines.append(f"| `{code}` | {where} | {sentence} |")
    return "\n".join(lines)


def brick_rows() -> list[tuple[str, str, str, str]]:
    """(brick, declared in, read by, what it owns) for the eight bricks."""
    rows: list[tuple[str, str, str, str]] = []
    for brick, declared, reader, owns in BRICKS:
        path = ROOT / reader
        if not path.exists():
            raise SystemExit(f"generator: brick {brick!r} names {reader}, which is missing")
        rows.append((brick, declared, f"`{reader}`", owns))
    return rows


def render_bricks(rows: list[tuple[str, str, str, str]]) -> str:
    lines = [
        "| Brick | Turned on by | Read by | What it owns |",
        "| --- | --- | --- | --- |",
    ]
    for brick, declared, reader, owns in rows:
        lines.append(f"| {brick} | `{declared}` | {reader} | {owns} |")
    return "\n".join(lines)


def protocol_rows() -> list[tuple[str, str, str, str]]:
    text = REGISTRY.read_text(encoding="utf-8")
    pairs = re.findall(r'"(?P<id>[a-z_]+@\d)":\s*preload\("res://(?P<file>[a-z_/0-9]+\.gd)"\)', text)
    if not pairs:
        raise SystemExit("generator: the protocol registry lists no implementations")
    rows: list[tuple[str, str, str, str]] = []
    for protocol, file in pairs:
        if protocol not in PROTOCOLS:
            raise SystemExit(
                f"generator: the registry implements {protocol}, which the guide does not describe"
            )
        expects, declares = PROTOCOLS[protocol]
        rows.append((f"`{protocol}`", f"`app/{file}`", expects, declares))
    known = {row[0].strip("`") for row in rows}
    for protocol in PROTOCOLS:
        if protocol not in known:
            raise SystemExit(f"generator: the guide describes {protocol}, which the registry lost")
    return rows


def render_protocols(rows: list[tuple[str, str, str, str]]) -> str:
    lines = [
        "| Protocol | Implemented by | What the story has to look like | What to declare |",
        "| --- | --- | --- | --- |",
    ]
    for protocol, where, expects, declares in rows:
        lines.append(f"| {protocol} | {where} | {expects} | {declares} |")
    return "\n".join(lines)


def build() -> dict[tuple[str, str], str]:
    """(page, block) -> rendered body, for every block the guide carries."""
    schema_text = SCHEMA.read_text(encoding="utf-8")
    consts = read_consts(schema_text)
    for name in EXTRA:
        if f'"{name}"' not in schema_text:
            raise SystemExit(
                f"generator: the schema never mentions {name!r}; the table would lie"
            )
    if not consts.get("REQUIRED_FIELDS"):
        raise SystemExit("generator: no REQUIRED_FIELDS in the schema")
    bodies = {
        ("manifest.md", "fields"): render_fields(field_rows(consts)),
        ("manifest.md", "vocabulary"): render_vocabulary(consts),
        ("errors.md", "errors"): render_errors(error_rows()),
        ("bricks.md", "bricks"): render_bricks(brick_rows()),
        ("protocols.md", "protocols"): render_protocols(protocol_rows()),
    }
    return bodies


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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report drift, write nothing")
    parser.add_argument("--write", action="store_true", help="rewrite the generated blocks")
    args = parser.parse_args()
    if not args.check and not args.write:
        parser.error("say --check or --write")

    bodies = build()
    pages: dict[str, str] = {}
    drift: dict[tuple[str, str], str] = {}
    for (page_name, block_name), body in bodies.items():
        path = GUIDE / page_name
        if not path.exists():
            raise SystemExit(f"generator: {path.relative_to(ROOT)} is missing")
        if page_name not in pages:
            pages[page_name] = path.read_text(encoding="utf-8")
        try:
            current = block(pages[page_name], block_name)
        except ValueError as error:
            raise SystemExit(f"generator: {page_name} has no {block_name} block") from error
        if current != body:
            drift[(page_name, block_name)] = body

    if args.check:
        if not drift:
            print(f"[guide] {len(bodies)} table(s) match the source")
            return 0
        for page_name, block_name in drift:
            print(f"[guide] {page_name}: the {block_name} table does not match the source")
        print("[guide] run python infra/tool/docs/gen_guide.py --write")
        return 1

    for page_name, text in pages.items():
        for block_name in PAGES[page_name]:
            text = replace(text, block_name, bodies[(page_name, block_name)])
        (GUIDE / page_name).write_bytes(text.encode("utf-8"))
    print(f"[guide] wrote {len(bodies)} block(s) into {len(pages)} page(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
