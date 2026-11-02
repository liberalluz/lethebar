#!/usr/bin/env python3
"""Load the exported web build in a headless browser and report what happened.

This checks the web pipeline, not gameplay: a browser fetches the build, the wasm
module instantiates, the shell draws its first screen, no dialog blocks it, no
exception escapes, and browser storage is usable. The first screen is measured
on three reloads and reported as a median, because REQ-008 gives it five seconds.

The settled screen is a proxy for "click start, see the first scene" — the probe
screenshots instead of clicking, so the measured span is load → first screen.
The gap is recorded in the batch exit record rather than hidden here.

The browser is started here and killed by process tree afterwards, because a
headless Chrome left behind by a crashed probe keeps a port and a profile lock.

Environment:
    CHROME_BIN  Browser to drive. Defaults to the first Chrome or Edge install.

Usage:
    python infra/verify_web.py [--dir build/web] [--reloads 3]
"""

from __future__ import annotations

import argparse
import http.server
import json
import os
import shutil
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PROBE = REPO_ROOT / "infra" / "checks" / "cdp_probe.mjs"
DEFAULT_DIR = REPO_ROOT / "build" / "web"
SCRATCH = REPO_ROOT / ".test-tmp"
PERF_BUDGET_MS = 5000
SMOKE_PACK_ID = "smoke-pack"

CHROME_CANDIDATES = (
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
)


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def find_chrome() -> str:
    configured = os.environ.get("CHROME_BIN")
    if configured:
        if not Path(configured).is_file():
            raise SystemExit(f"CHROME_BIN points at {configured}, which does not exist")
        return configured
    for candidate in CHROME_CANDIDATES:
        if Path(candidate).is_file():
            return candidate
    raise SystemExit("no Chrome or Edge found; set CHROME_BIN to the browser executable")


def serve(directory: Path, port: int) -> http.server.ThreadingHTTPServer:
    handler = lambda *args, **kwargs: http.server.SimpleHTTPRequestHandler(
        *args, directory=str(directory), **kwargs
    )
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def devtools_endpoint(port: int, deadline: float) -> str | None:
    url = f"http://127.0.0.1:{port}/json/version"
    # Never route a loopback probe through a machine proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    while time.monotonic() < deadline:
        try:
            with opener.open(url, timeout=2) as response:
                endpoint = json.load(response).get("webSocketDebuggerUrl")
            if endpoint:
                return endpoint
        except Exception:
            pass
        time.sleep(0.25)
    return None


def write_smoke_pack() -> Path:
    """A package the build has never seen, for the browser to install.

    It is written here rather than shipped: a file the export already contains
    would be a cache hit, not an import (TC-PKG-001, TC-OFF-004).
    """
    SCRATCH.mkdir(exist_ok=True)
    path = SCRATCH / f"{SMOKE_PACK_ID}.zip"
    manifest = {
        "id": SMOKE_PACK_ID,
        "version": "1.0.0",
        "specVersion": "1.0.0",
        "engine": ">=4.3.0 <5.0.0",
        "name": "Smoke Pack",
        "protocol": "linear@1",
        "capabilities": ["text"],
        "mechanics": ["basic"],
        "entry": "s1",
        "saveSchema": 1,
        "assets": [],
    }
    nodes = {"nodes": [{"id": "s1", "text": "A pack that came from a file.", "assets": [], "choices": []}]}
    mechanics = {"rules": []}
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("manifest.json", json.dumps(manifest, indent=2))
        archive.writestr("data/nodes.json", json.dumps(nodes, indent=2))
        archive.writestr("data/mechanics.json", json.dumps(mechanics, indent=2))
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", type=Path, default=DEFAULT_DIR, help="exported build")
    parser.add_argument("--reloads", type=int, default=3, help="reloads timed for the median")
    args = parser.parse_args()

    build = args.dir.resolve()
    if not (build / "index.html").is_file():
        raise SystemExit(f"{build}/index.html is missing; run infra/export_web.py first")

    chrome = find_chrome()
    port = free_port()
    debug_port = free_port()
    server = serve(build, port)
    # Navigate to the directory, not to index.html: that is the URL a player
    # opens, and the two are different service-worker cache keys. Navigating to
    # the file hid an offline failure that only Safari reported.
    url = f"http://127.0.0.1:{port}/"
    print(f"serving {build} at {url}")
    print(f"driving {chrome}")

    SCRATCH.mkdir(exist_ok=True)
    smoke_pack = write_smoke_pack()
    profile = SCRATCH / f"chrome-{debug_port}"
    log = SCRATCH / "chrome.log"
    profile.mkdir(parents=True, exist_ok=True)

    with open(log, "w", encoding="utf-8") as logfile:
        browser = subprocess.Popen(
            [
                chrome,
                "--headless=new",
                "--no-sandbox",
                "--disable-gpu",
                "--no-first-run",
                "--no-default-browser-check",
                # The interface follows `navigator.language`, and the probe
                # clicks and reads English labels. Pin the browser language so
                # the run does not depend on the machine it happens to run on;
                # the Chinese path is checked by the language stage instead.
                "--lang=en-US",
                # Chrome only accepts `--flag=value`; a space-separated value
                # would be parsed as a page to open.
                f"--remote-debugging-port={debug_port}",
                f"--user-data-dir={profile}",
            ],
            stdout=logfile,
            stderr=logfile,
        )

    try:
        endpoint = devtools_endpoint(debug_port, time.monotonic() + 30)
        if not endpoint:
            print(log.read_text(encoding="utf-8", errors="replace")[-1200:])
            print("the browser never opened a DevTools endpoint")
            return 1

        try:
            result = subprocess.run(
                ["node", str(PROBE), endpoint, url, str(args.reloads), str(smoke_pack)],
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=180,
            )
        except subprocess.TimeoutExpired as expired:
            print("the probe did not finish; its trace follows")
            print((expired.stderr or "")[-1500:])
            return 1
    finally:
        subprocess.run(
            ["taskkill", "/PID", str(browser.pid), "/T", "/F"],
            capture_output=True,
            text=True,
        )
        browser.wait(timeout=30)
        server.shutdown()
        shutil.rmtree(profile, ignore_errors=True)

    payload = result.stdout.strip()
    try:
        report = json.loads(payload)
    except json.JSONDecodeError:
        print(payload)
        print(result.stderr.strip()[-1500:])
        return 1

    # REQ-008 gives the first screen five seconds; the probe reports a median
    # over the reloads, so a single slow run does not decide the batch.
    median = report.get("bootMedianMs")
    if report.get("ok") and (median is None or median > PERF_BUDGET_MS):
        report["ok"] = False
        report["perfFailure"] = f"first screen settled at {median} ms, budget {PERF_BUDGET_MS} ms"

    # TC-PLAT-001 asks for a usable first screen, which means a click has to
    # work, and TC-PERF-001 measures selecting a pack to accepting input — not
    # page load. The probe clicks "New game" and a pack with real mouse events
    # and reports how long the two clicks took to land on the first scene.
    interaction = report.get("interaction") or {}
    if report.get("ok") and not interaction.get("plugins"):
        report["ok"] = False
        report["interactionFailure"] = "the first screen did not answer a click on New game"
    click_to_scene = report.get("clickToSceneMs")
    if report.get("ok") and not interaction.get("session"):
        report["ok"] = False
        report["interactionFailure"] = "the pack list did not answer a click on a pack"
    if report.get("ok") and not interaction.get("saved"):
        report["ok"] = False
        report["interactionFailure"] = "the save screen did not answer a click on Save"
    if report.get("ok") and (click_to_scene is None or click_to_scene > PERF_BUDGET_MS):
        report["ok"] = False
        report["perfFailure"] = f"pack choice reached a scene in {click_to_scene} ms, budget {PERF_BUDGET_MS} ms"

    # TC-OFF-001/002: after a real disconnect the page must reload to the same
    # landing screen with its packs and its saved slot. TC-OFF-003: playing a
    # session must not touch the network at all.
    offline = report.get("offline") or {}

    # TC-PKG-001: installing a pack is a click on a real file, and TC-OFF-004
    # asks whether that pack is still installed after a reload with the network
    # cut. Both are answered by the same click, so a failure here is one of two
    # defects and the probe report says which half broke.
    if report.get("ok") and not interaction.get("imported"):
        report["ok"] = False
        report["interactionFailure"] = (
            f"installing {SMOKE_PACK_ID}.zip through the button did not add a pack"
        )
    if report.get("ok") and offline.get("importedRestored") is not True:
        report["ok"] = False
        report["offlineFailure"] = "the installed pack did not come back after the offline reload"

    if report.get("ok") and not offline.get("landing"):
        report["ok"] = False
        report["offlineFailure"] = "the page did not come back from cache while offline"
    if report.get("ok") and (offline.get("packs") or 0) < 2:
        report["ok"] = False
        report["offlineFailure"] = f"offline reload showed {offline.get('packs')} pack(s), expected 2"
    if report.get("ok") and not offline.get("sessions"):
        report["ok"] = False
        report["offlineFailure"] = "a pack could not be opened offline"
    if report.get("ok") and (offline.get("slotsRestored") or 0) < 1:
        report["ok"] = False
        report["offlineFailure"] = "the saved slot did not survive the offline reload"
    if report.get("ok") and report.get("interactionRequests") != 0:
        report["ok"] = False
        report["offlineFailure"] = (
            f"a session made {report.get('interactionRequests')} network request(s), expected 0"
        )
    direct_file = report.get("directFile") or {}
    if report.get("ok") and direct_file.get("servedGame") is not False:
        # The document fallback that makes an offline root work must not answer
        # every navigation: a download link would open the game instead of the file.
        report["ok"] = False
        report["offlineFailure"] = "a navigation to a file URL was answered with the game"

    print(json.dumps(report, indent=2))
    if not report.get("ok"):
        # The probe's stderr is its trace: it says which click missed.
        print(result.stderr.strip()[-2000:])
    return 0 if report.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
