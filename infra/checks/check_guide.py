"""Check the author guide: the generated tables, and the templates it points at.

Four things happen here, in order:

1. every generated table in `docs/guide/` still matches the source it is built
   from;
2. each template under `templates/` builds into a zip that `check_pack.py`
   accepts;
3. a headless Godot probe installs and plays it — the linear template walks one
   choice, the turn-based one crosses a rank boundary;
4. nothing is left behind: the staged zip and the probe script are removed even
   when the probe crashes.

`--no-probe` stops after step 2, which is what a machine without Godot can still
run.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
PACK_TOOL = ROOT / "infra" / "tool" / "release" / "pack.py"
ENVELOPE = ROOT / "infra" / "checks" / "check_pack.py"
GUIDE_TOOL = ROOT / "infra" / "tool" / "docs" / "gen_guide.py"

PROBE_MIN = """extends SceneTree

func _init() -> void:
	var zip := "res://tests/guide-pack-min.zip"
	if not FileAccess.file_exists(zip):
		print("guide error=missing zip")
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(zip)
	var loader := PackageLoader.new()
	var result: Dictionary = loader.import_bytes(
		bytes, {"engine_version": "4.7.2", "work_dir": "user://guide-min"}
	)
	print("guide import status=%s" % str(result.get("status", "")))
	if str(result.get("status", "")) != "installed":
		print("guide issues=%s" % JSON.stringify(result.get("issues", [])))
		quit(1)
		return
	var entry: Dictionary = loader.registry.entry("pack-min")
	var session := Session.create(entry, {"start_counter": 1})
	session.start()
	var view: Dictionary = session.view()
	var choices: Array = view.get("choices", [])
	print("guide text length=%d" % str(view.get("text", "")).length())
	print("guide choices=%d" % choices.size())
	if choices.is_empty():
		quit(1)
		return
	session.goto(str(choices[0].get("next", "")))
	var after: Dictionary = session.view()
	print("guide finished=%s" % str(after.get("finished", false)))
	var store := SaveStore.new()
	var written: Dictionary = store.write(entry, 1, session.snapshot(), "pack-min")
	print("guide saved=%s" % str(written.get("ok", false)))
	var read: Dictionary = store.read(entry, 1)
	print("guide read back=%s" % str(read.get("ok", false)))
	quit(0)
"""

PROBE_TURN = """extends SceneTree

func _init() -> void:
	var zip := "res://tests/guide-pack-turn.zip"
	if not FileAccess.file_exists(zip):
		print("guide error=missing zip")
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(zip)
	var loader := PackageLoader.new()
	var result: Dictionary = loader.import_bytes(
		bytes, {"engine_version": "4.7.2", "work_dir": "user://guide-turn"}
	)
	print("guide import status=%s" % str(result.get("status", "")))
	if str(result.get("status", "")) != "installed":
		print("guide issues=%s" % JSON.stringify(result.get("issues", [])))
		quit(1)
		return
	var entry: Dictionary = loader.registry.entry("pack-turn")
	var session := Session.create(entry, {"start_counter": 1})
	session.start()
	print("guide turn start=%d" % session.turn)
	print("guide rank start=%s" % session.rank())
	session.act("gather")
	session.act("gather")
	print("guide turn now=%d" % session.turn)
	print("guide rank now=%s" % session.rank())
	print("guide coin=%d" % int(session.state.get("coin", 0)))
	var store := SaveStore.new()
	var written: Dictionary = store.write(entry, 1, session.snapshot(), "pack-turn")
	print("guide saved=%s" % str(written.get("ok", false)))
	var read: Dictionary = store.read(entry, 1)
	print("guide read back=%s" % str(read.get("ok", false)))
	quit(0)
"""

TEMPLATES = (
    {
        "id": "pack-min",
        "probe": PROBE_MIN,
        "wanted": [
            (r"guide import status=installed", "pack-min does not install"),
            (r"guide text length=([1-9]\d*)", "the entry node has no text"),
            (r"guide choices=2", "the entry node does not offer two choices"),
            (r"guide finished=true", "the first choice does not reach an ending"),
            (r"guide saved=true", "the run does not save"),
            (r"guide read back=true", "the save does not read back"),
        ],
        "promise": "installs, plays one choice and saves",
    },
    {
        "id": "pack-turn",
        "probe": PROBE_TURN,
        "wanted": [
            (r"guide import status=installed", "pack-turn does not install"),
            (r"guide turn start=1", "the run does not start on turn one"),
            (r"guide rank start=Traveller", "the first rank is not the one the package declares"),
            (r"guide turn now=3", "two actions did not advance the turn twice"),
            (r"guide rank now=Guide", "the rank did not move when the turn passed its boundary"),
            (r"guide coin=10", "the two actions did not add up: 6 + 2 + 2"),
            (r"guide saved=true", "the run does not save"),
            (r"guide read back=true", "the save does not read back"),
        ],
        "promise": "installs, plays two turns across a rank boundary and saves",
    },
)


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, encoding="utf-8", **kwargs)


def generated_tables() -> list[str]:
    """Regenerate the guide tables; an empty list means no drift."""
    done = run([sys.executable, str(GUIDE_TOOL), "--check"])
    if done.returncode == 0:
        return []
    return (done.stdout + done.stderr).strip().splitlines()


def built_zip(template: dict, work: Path) -> tuple[Path | None, list[str]]:
    out = work / template["id"]
    done = run(
        [sys.executable, str(PACK_TOOL), "build", str(ROOT / "templates" / template["id"]), "--out", str(out)]
    )
    if done.returncode != 0:
        return None, (done.stdout + done.stderr).strip().splitlines()
    zips = sorted(out.glob("*.zip"))
    if len(zips) != 1:
        return None, [f"build wrote {len(zips)} archives into {out}"]
    return zips[0], []


def envelope_problems(archive: Path) -> list[str]:
    done = run([sys.executable, str(ENVELOPE), str(archive)])
    if done.returncode == 0:
        return []
    return (done.stdout + done.stderr).strip().splitlines()


def godot_binary() -> str:
    return shutil.which("godot") or os.environ.get("GODOT_BIN", "")


def probe_problems(template: dict, archive: Path) -> list[str]:
    godot = godot_binary()
    if not godot:
        return ["GODOT_BIN is not set, so the template cannot be installed and played"]
    staged = APP / "tests" / f"guide-{template['id']}.zip"
    script = APP / "tests" / f"probe_{template['id'].replace('-', '_')}.gd"
    shutil.copyfile(archive, staged)
    script.write_bytes(template["probe"].encode("utf-8"))
    relative = f"res://tests/{script.name}"
    try:
        done = run(
            [godot, "--headless", "--path", str(APP), "-s", relative],
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        return ["the probe did not finish within 180 s; a script error in a probe never quits"]
    finally:
        staged.unlink(missing_ok=True)
        script.unlink(missing_ok=True)

    output = done.stdout + done.stderr
    problems: list[str] = []
    if "SCRIPT ERROR" in output:
        problems.append("the probe hit a script error")
    for pattern, message in template["wanted"]:
        if not re.search(pattern, output):
            problems.append(message)
    if problems:
        tail = "\n".join(output.strip().splitlines()[-6:])
        problems.append("probe output:\n" + tail)
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-probe", action="store_true", help="skip the Godot probe")
    args = parser.parse_args()

    drift = generated_tables()
    if drift:
        print("[guide] the generated tables are stale")
        for line in drift:
            print("  " + line)
        return 1
    print("[guide] tables match the source")

    with tempfile.TemporaryDirectory(dir=ROOT / ".test-tmp", prefix="guide-") as raw:
        work = Path(raw)
        for template in TEMPLATES:
            archive, build_problems = built_zip(template, work)
            if build_problems:
                print(f"[guide] {template['id']} does not build")
                for line in build_problems:
                    print("  " + line)
                return 1
            assert archive is not None
            problems = envelope_problems(archive)
            if problems:
                print(f"[guide] {template['id']} does not pass the envelope check")
                for line in problems:
                    print("  " + line)
                return 1
            print(f"[guide] {template['id']} builds and passes the envelope ({archive.stat().st_size} bytes)")

            if args.no_probe:
                continue
            problems = probe_problems(template, archive)
            if problems:
                print(f"[guide] {template['id']} does not install and play")
                for line in problems:
                    print("  " + line)
                return 1
            print(f"[guide] {template['id']} {template['promise']}")

    if args.no_probe:
        print("[guide] probes skipped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
