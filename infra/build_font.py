"""Build the font the browser build ships.

The delivered file is a subset, not the Noto Sans SC release: the release covers
every CJK block and every weight, and a player downloads the payload on first
visit. B14 widened the subset from the BMP block alone to the BMP block plus
extension A, because names, place names and reprinted classical text reach for
extension A characters and drew them as boxes.

Usage:

    python infra/build_font.py --source path/to/NotoSansSC-Regular.ttf

The source is not vendored. Download the OFL release once (Google Fonts, or the
`@expo-google-fonts/noto-sans-sc` package on npm, which is what B14 used) and
point this script at `NotoSansSC_400Regular.ttf`. The subset is written over
`app/render/fonts/NotoSansSC-Regular.woff2`; Godot's import cache keys on the
file, so delete `app/.godot/imported/NotoSansSC-Regular*` afterwards and let
`--headless --editor --quit` rebuild it, or the tests keep reading the old glyphs.

The ranges below are the repertoire the project promises:

    U+0020-007E   printable ASCII
    U+00A0-00FF   Latin-1 punctuation
    U+2000-206F   general punctuation (dashes, quotes, ellipsis)
    U+3000-303F   CJK symbols and punctuation
    U+3400-4DBF   CJK unified ideographs extension A
    U+4E00-9FFF   CJK unified ideographs
    U+FF00-FFEF   halfwidth and fullwidth forms

`app/tests/run_tests.gd` asserts one character from each block the project
relies on, so a rebuild with a narrower range fails the suite instead of
shipping boxes.
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

TARGET = pathlib.Path("app/render/fonts/NotoSansSC-Regular.woff2")

UNICODES = ",".join(
    [
        "U+0020-007E",
        "U+00A0-00FF",
        "U+2000-206F",
        "U+3000-303F",
        "U+3400-4DBF",
        "U+4E00-9FFF",
        "U+FF00-FFEF",
    ]
)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, help="path to NotoSansSC-Regular.ttf/.otf")
    parser.add_argument("--target", default=str(TARGET), help="where to write the woff2 subset")
    args = parser.parse_args(argv)

    source = pathlib.Path(args.source)
    if not source.is_file():
        print(f"source font not found: {source}", file=sys.stderr)
        return 1

    target = pathlib.Path(args.target)
    target.parent.mkdir(parents=True, exist_ok=True)

    command = [
        sys.executable,
        "-m",
        "fontTools.subset",
        str(source),
        f"--output-file={target}",
        "--flavor=woff2",
        f"--unicodes={UNICODES}",
        "--layout-features=*",
        "--name-IDs=*",
        "--drop-tables+=DSIG",
    ]
    completed = subprocess.run(command, text=True, capture_output=True, encoding="utf-8", errors="replace")
    if completed.returncode != 0:
        print(completed.stdout, file=sys.stderr)
        print(completed.stderr, file=sys.stderr)
        return completed.returncode

    size = target.stat().st_size
    print(f"{target} {size} bytes")
    print("now delete app/.godot/imported/NotoSansSC-Regular* and reimport, or the suite reads the old glyphs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
