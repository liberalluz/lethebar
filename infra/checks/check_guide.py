"""Check the author guide: the generated tables, and the template it points at.

Three things happen here, in order:

1. the field and vocabulary tables in `docs/guide/manifest.md` still match
   `app/core/manifest_schema.gd`;
2. `templates/pack-min/` builds into a zip that `check_pack.py` accepts;
3. a headless Godot probe installs that zip, walks one choice, and saves.

`--no-probe` stops after step 2, which is what a machine without Godot can still
run.
"""

from __future__ import annotations

import argparse
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
TEMPLATE = ROOT / "templates" / "pack-min"

PROBE = """extends SceneTree

func _init() -> void:
	var zip := "res://tests/guide-pack.zip"
	if not FileAccess.file_exists(zip):
		print("guide error=missing zip")
		quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes(zip)
	var loader := PackageLoader.new()
	var result: Dictionary = loader.import_bytes(
		bytes, {"engine_version": "4.7.2", "work_dir": "user://guide"}
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


def run(command: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, encoding="utf-8", **kwargs)


def generated_tables() -> list[str]:
    """Regenerate the guide tables; an empty list means no drift."""
    done = run([sys.executable, str(GUIDE_TOOL), "--check"])
    if done.returncode == 0:
        return []
    return (done.stdout + done.stderr).strip().splitlines()


def built_zip(work: Path) -> tuple[Path | None, list[str]]:
    out = work / "guide"
    done = run(
        [sys.executable, str(PACK_TOOL), "build", str(TEMPLATE), "--out", str(out)]
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


def probe_problems(archive: Path) -> list[str]:
    godot = shutil.which("godot") or __import__("os").environ.get("GODOT_BIN", "")
    if not godot:
        return ["GODOT_BIN is not set, so the template cannot be installed and played"]
    staged = APP / "tests" / "guide-pack.zip"
    script = APP / "tests" / "probe_guide.gd"
    shutil.copyfile(archive, staged)
    script.write_bytes(PROBE.encode("utf-8"))
    try:
        done = run(
            [godot, "--headless", "--path", str(APP), "-s", "res://tests/probe_guide.gd"],
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        staged.unlink(missing_ok=True)
        script.unlink(missing_ok=True)
        return ["the probe did not finish within 180 s; a script error in a probe never quits"]
    finally:
        staged.unlink(missing_ok=True)
        script.unlink(missing_ok=True)

    output = done.stdout + done.stderr
    problems: list[str] = []
    if "SCRIPT ERROR" in output:
        problems.append("the probe hit a script error")
    wanted = [
        (r"guide import status=installed", "the template does not install"),
        (r"guide text length=([1-9]\d*)", "the entry node has no text"),
        (r"guide choices=2", "the entry node does not offer two choices"),
        (r"guide finished=true", "the first choice does not reach an ending"),
        (r"guide saved=true", "the run does not save"),
        (r"guide read back=true", "the save does not read back"),
    ]
    for pattern, message in wanted:
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
    print("[guide] tables match the schema")

    with tempfile.TemporaryDirectory(dir=ROOT / ".test-tmp", prefix="guide-") as raw:
        archive, build_problems = built_zip(Path(raw))
        if build_problems:
            print("[guide] the template does not build")
            for line in build_problems:
                print("  " + line)
            return 1
        assert archive is not None
        problems = envelope_problems(archive)
        if problems:
            print("[guide] the template does not pass the envelope check")
            for line in problems:
                print("  " + line)
            return 1
        print(f"[guide] template builds and passes the envelope ({archive.stat().st_size} bytes)")

        if args.no_probe:
            print("[guide] probe skipped")
            return 0
        problems = probe_problems(archive)
        if problems:
            print("[guide] the template does not install and play")
            for line in problems:
                print("  " + line)
            return 1
    print("[guide] the template installs, plays one choice and saves")
    return 0


if __name__ == "__main__":
    sys.exit(main())
