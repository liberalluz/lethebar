#!/usr/bin/env python3
"""Stage the built-in plugin packages into the Godot project.

The Godot project root is `app/`, so `res://` cannot reach `content/builtin/`
at the repository root. This script packs every `content/builtin/<id>/`
directory into `app/builtin/<id>.zip`, which the loader reads as an ordinary
package. It runs before the headless assertions and before an export.

The output directory is generated and git-ignored, and it is the only place
the engine can see a package. That makes a stale archive a real defect rather
than clutter: B59 deleted a story, staging rebuilt the three that remained, and
the build happily shipped a fourth whose source no longer existed. So staging
prunes: an archive whose source directory is gone is removed and named, and a
removal that fails is an error rather than a line in a log.
"""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "content" / "builtin"
TARGET = REPO / "app" / "builtin"
CHARS = TARGET / "chars.txt"


FIXED_TIME = (1980, 1, 1, 0, 0, 0)


def pack(plugin_dir: Path) -> Path:
    """Pack one source-form plugin directory into a package zip.

    The entries carry a fixed timestamp and mode, so packing the same sources
    twice gives the same bytes. The exported build names its cache after the
    bytes it holds; without this, every run would change the package file and
    the player would download a payload that did not change.
    """
    target = TARGET / f"{plugin_dir.name}.zip"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as package:
        for path in sorted(plugin_dir.rglob("*")):
            if path.is_file():
                entry = zipfile.ZipInfo(path.relative_to(plugin_dir).as_posix(), FIXED_TIME)
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = 0o644 << 16
                package.writestr(entry, path.read_bytes())
    return target


def collect_characters(plugins: list[Path]) -> str:
    """Every character a built-in pack can show, as one line for the font check.

    The headless suite cannot read `content/` (the project root is `app/`), so
    the characters are carried over as a generated file. The glyph-coverage
    assertion reads it and fails when the shipped font would draw a box.
    """
    characters: set[str] = set()
    for plugin in plugins:
        for path in sorted(plugin.rglob("*.json")):
            characters.update(path.read_text(encoding="utf-8"))
    return "".join(sorted(character for character in characters if ord(character) > 0x1F))


def prune(staged: set[str]) -> tuple[list[str], list[str]]:
    """Remove archives the source no longer backs.

    Returns what was removed and what could not be, so the caller can fail on a
    removal that was blocked by a file handle rather than believe it happened.
    """
    removed: list[str] = []
    failed: list[str] = []
    if not TARGET.is_dir():
        return removed, failed
    for archive in sorted(TARGET.glob("*.zip")):
        if archive.stem in staged:
            continue
        try:
            archive.unlink()
        except OSError:
            failed.append(archive.stem)
            continue
        removed.append(archive.stem)
    return removed, failed


def main() -> int:
    if not SOURCE.is_dir():
        print(f"[stage] missing source directory: {SOURCE}")
        return 1
    plugins = sorted(path for path in SOURCE.iterdir() if path.is_dir())
    if not plugins:
        print(f"[stage] no plugin directories under {SOURCE}")
        return 1
    TARGET.mkdir(parents=True, exist_ok=True)
    for plugin in plugins:
        target = pack(plugin)
        size = target.stat().st_size
        print(f"[stage] {plugin.name} -> {target.relative_to(REPO).as_posix()} ({size} bytes)")
    removed, failed = prune({plugin.name for plugin in plugins})
    for name in removed:
        print(f"[stage] removed {name}.zip (its source directory is gone)")
    if failed:
        for name in failed:
            print(f"[stage] could not remove {name}.zip")
        return 1
    characters = collect_characters(plugins)
    CHARS.write_text(characters, encoding="utf-8")
    print(f"[stage] {len(characters)} character(s) -> {CHARS.relative_to(REPO).as_posix()}")
    print(f"[stage] staged {len(plugins)} package(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
