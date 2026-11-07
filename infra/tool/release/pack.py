"""Build a pack directory into a reproducible zip, hash it, and publish it.

A pack reaches a player either compiled into the build or imported by hand. Once a
world repository owns its packs, both stop working: the pack has to travel as an
artifact with a hash an engine can check. This tool is that step.

Reproducibility is the point. Zip records a timestamp per entry and walks the
directory in whatever order the filesystem hands back, so a build fixes both: one
timestamp for every entry and a sorted name list. Two builds of one directory are
then byte-identical, which is what makes a hash worth writing down.

    python infra/tool/release/pack.py build content/builtin/<id> --out dist
    python infra/tool/release/pack.py hash dist/<id>.zip
    python infra/tool/release/pack.py publish dist/<id>.zip --repo o/r --tag 1.0.0

`hash` writes `<id>-<version>.json` next to the zip: the id, the version, the byte
count, the sha256, the specVersion and the engine range, which is what an engine
needs to decide whether it can install the artifact at all.

`publish` is dry by default and only touches the network with `--apply`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

FIXED_TIME = (1980, 1, 1, 0, 0, 0)
MANIFEST = "manifest.json"


def files_of(root: Path) -> list[Path]:
    """Every file of the pack, in a stable order, manifest first."""
    entries: list[Path] = []
    for path in sorted(root.rglob("*")):
        if path.is_file():
            entries.append(path.relative_to(root))
    entries.sort(key=lambda item: (item.as_posix() != MANIFEST, item.as_posix()))
    return entries


def build(root: Path, out_dir: Path | None = None) -> Path:
    """Write a zip of `root` and return its path."""
    manifest_path = root / MANIFEST
    if not manifest_path.is_file():
        raise SystemExit(f"{root} carries no {MANIFEST}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    pack_id = str(manifest.get("id", "")).strip()
    if pack_id == "":
        raise SystemExit(f"{manifest_path} names no id")

    out_dir = out_dir or Path("dist")
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"{pack_id}.zip"

    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for relative in files_of(root):
            info = zipfile.ZipInfo(relative.as_posix(), date_time=FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, (root / relative).read_bytes())
    return target


def digest(target: Path) -> str:
    return hashlib.sha256(target.read_bytes()).hexdigest()


def describe(target: Path) -> dict:
    """The manifest an engine reads before it installs the artifact."""
    with zipfile.ZipFile(target) as archive:
        manifest = json.loads(archive.read(MANIFEST).decode("utf-8"))
    data = target.read_bytes()
    return {
        "id": str(manifest.get("id", "")),
        "version": str(manifest.get("version", "")),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "specVersion": str(manifest.get("specVersion", "")),
        "engine": str(manifest.get("engine", "")),
    }


def write_descriptor(target: Path) -> Path:
    described = describe(target)
    sidecar = target.with_name(f"{described['id']}-{described['version']}.json")
    sidecar.write_text(
        json.dumps(described, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    return sidecar


def publish_command(target: Path, repo: str, tag: str) -> list[str]:
    sidecar = write_descriptor(target)
    return ["gh", "release", "upload", tag, str(target), str(sidecar), "--repo", repo, "--clobber"]


def write_fixture(directory: Path) -> Path:
    """Write a pack for the self-test, so the tool needs no shipped story."""
    root = directory / "fixture-pack"
    (root / "data").mkdir(parents=True)
    manifest = {
        "id": "fixture-pack",
        "version": "0.1.0",
        "specVersion": "2.0.0",
        "engine": ">=4.7.0 <5.0.0",
    }
    (root / MANIFEST).write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    (root / "data" / "nodes.json").write_text(
        '{"n1": {"text": "a fixture pack"}}\n',
        encoding="utf-8",
        newline="\n",
    )
    return root


def self_test() -> int:
    """Assert the properties this tool exists for, without touching the network."""
    problems: list[str] = []
    with (
        tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as source,
        tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as first,
        tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as second,
    ):
        root = write_fixture(Path(source))
        one = build(root, Path(first))
        two = build(root, Path(second))
        if one.read_bytes() != two.read_bytes():
            problems.append("two builds of one directory differ")
        if digest(one) != digest(two):
            problems.append("two builds hash differently")
        described = describe(one)
        for field in ("id", "version", "bytes", "sha256", "specVersion", "engine"):
            if not described.get(field):
                problems.append(f"the descriptor has no {field}")
        if described["sha256"] != digest(one):
            problems.append("the descriptor hash is not the file hash")
        if described["bytes"] != one.stat().st_size:
            problems.append("the descriptor size is not the file size")
        sidecar = write_descriptor(one)
        written = json.loads(sidecar.read_text(encoding="utf-8"))
        if written != described:
            problems.append("the sidecar disagrees with the descriptor")
        command = publish_command(one, "liberalluz/example", "v0.0.0")
        if command[:2] != ["gh", "release"]:
            problems.append("the publish command is not a release upload")
        if "--clobber" not in command:
            problems.append("the publish command does not replace an artifact")
    if problems:
        for problem in problems:
            print(f"[fail] {problem}")
        return 1
    print("[ok] two builds are identical; the descriptor names the bytes; publish uploads both files")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build, hash and publish a pack.")
    commands = parser.add_subparsers(dest="command", required=True)

    build_parser = commands.add_parser("build", help="build a pack directory into a zip")
    build_parser.add_argument("root")
    build_parser.add_argument("--out", default="dist")

    hash_parser = commands.add_parser("hash", help="name the bytes of a built pack")
    hash_parser.add_argument("zip")

    publish_parser = commands.add_parser("publish", help="upload a pack to a release")
    publish_parser.add_argument("zip")
    publish_parser.add_argument("--repo", required=True)
    publish_parser.add_argument("--tag", required=True)
    publish_parser.add_argument("--apply", action="store_true")

    commands.add_parser("self-test", help="assert reproducibility and the descriptor")

    args = parser.parse_args(argv)

    if args.command == "build":
        target = build(Path(args.root), Path(args.out))
        print(f"built {target} sha256:{digest(target)}")
        return 0

    if args.command == "hash":
        target = Path(args.zip)
        if not target.is_file():
            raise SystemExit(f"{target} does not exist")
        sidecar = write_descriptor(target)
        described = describe(target)
        print(f"sha256:{described['sha256']} {described['bytes']} bytes")
        print(f"wrote {sidecar}")
        return 0

    if args.command == "publish":
        target = Path(args.zip)
        if not target.is_file():
            raise SystemExit(f"{target} does not exist")
        command = publish_command(target, args.repo, args.tag)
        print(" ".join(command))
        if not args.apply:
            print("dry run; pass --apply to upload")
            return 0
        return subprocess.run(command, check=False).returncode

    return self_test()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
