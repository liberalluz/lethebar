#!/usr/bin/env python3
"""Check that the exported worker names each payload cache after its bytes.

`export_web.py` moves `index.wasm` and `index.pck` out of the timestamped shell
cache into one content-addressed cache each, so a build that only changes story
data does not force a 39.5 MB download. The invariant is about two builds, which
a browser can only ever see one of, so it is checked here: the names in the
worker are recomputed from the files on disk.

Usage:
    python infra/checks/check_payload_caches.py build/web
    python infra/checks/check_payload_caches.py build/web --compare build/web-before

Exit code is 0 only when every name matches the file it belongs to.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

PAYLOAD_FILES = ("index.wasm", "index.pck")
SERVICE_WORKER = "index.service.worker.js"


def digest(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            sha.update(chunk)
    return sha.hexdigest()[:12]


def expected_name(path: Path) -> str:
    stem = "wasm" if path.name.endswith(".wasm") else "pck"
    return f"Lethebar-payload-{stem}-{digest(path)}"


def declared_names(worker: Path) -> dict[str, str]:
    text = worker.read_text(encoding="utf-8")
    block = re.search(r"const PAYLOAD = \{(.*?)\n\};", text, re.S)
    if block is None:
        raise SystemExit(f"{worker.name} has no PAYLOAD map; the layering was not applied")
    return dict(re.findall(r'"([^"]+)":\s*"([^"]+)"', block.group(1)))


def check(build: Path) -> list[str]:
    problems: list[str] = []
    worker = build / SERVICE_WORKER
    if not worker.is_file():
        return [f"{build} has no {SERVICE_WORKER}"]
    names = declared_names(worker)
    for name in PAYLOAD_FILES:
        path = build / name
        if not path.is_file():
            problems.append(f"{name} is missing from {build}")
            continue
        want = expected_name(path)
        got = names.get(name)
        if got != want:
            problems.append(f"{name}: worker says {got}, bytes say {want}")
    text = worker.read_text(encoding="utf-8")
    cached = re.search(r"const CACHED_FILES\s*=\s*\[(.*?)\];", text, re.S)
    if cached is not None:
        for name in PAYLOAD_FILES:
            if f'"{name}"' in cached.group(1):
                problems.append(f"{name} is still in CACHED_FILES; it would be re-downloaded")
    for needle in (
        'const PAYLOAD_PREFIX = "Lethebar-payload-";',
        "key.startsWith(PAYLOAD_PREFIX)",
        "PAYLOAD[local]",
    ):
        if needle not in text:
            problems.append(f"the worker does not mention {needle}")
    install = re.search(r"addEventListener\('install'.*?\n\}\);", text, re.S)
    if install is not None and "PAYLOAD" in install.group(0):
        problems.append(
            "the install handler prefetches the payload; the engine's own load already fills it"
        )
    return problems


def compare(before: Path, after: Path) -> list[str]:
    problems: list[str] = []
    names_before = declared_names(before / SERVICE_WORKER)
    names_after = declared_names(after / SERVICE_WORKER)
    for name in PAYLOAD_FILES:
        same_bytes = digest(before / name) == digest(after / name)
        same_name = names_before.get(name) == names_after.get(name)
        if same_bytes != same_name:
            problems.append(
                f"{name}: bytes {'equal' if same_bytes else 'differ'} but cache name "
                f"{'equal' if same_name else 'differs'}"
            )
        else:
            print(
                f"  {name:12} bytes {'equal ' if same_bytes else 'differ'} "
                f"-> cache name {'kept    ' if same_name else 'replaced'} "
                f"({names_after.get(name)})"
            )
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("--compare", type=Path, default=None)
    args = parser.parse_args()

    problems = check(args.build)
    if args.compare is not None:
        problems.extend(compare(args.compare, args.build))
    for problem in problems:
        print(f"[fail] {problem}")
    if problems:
        print(f"{len(problems)} problem(s)")
        return 1
    print("[ok] payload caches are named after their bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
