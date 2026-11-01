#!/usr/bin/env python3
"""Stage the built-in plugin packages into the Godot project.

The Godot project root is `app/`, so `res://` cannot reach `content/builtin/`
at the repository root. This script packs every `content/builtin/<id>/`
directory into `app/builtin/<id>.zip`, which the loader reads as an ordinary
package. It runs before the headless assertions and before an export.

The output directory is generated and git-ignored.
"""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SOURCE = REPO / "content" / "builtin"
TARGET = REPO / "app" / "builtin"


def pack(plugin_dir: Path) -> Path:
    """Pack one source-form plugin directory into a package zip."""
    target = TARGET / f"{plugin_dir.name}.zip"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as package:
        for path in sorted(plugin_dir.rglob("*")):
            if path.is_file():
                package.write(path, path.relative_to(plugin_dir).as_posix())
    return target


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
    print(f"[stage] staged {len(plugins)} package(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
