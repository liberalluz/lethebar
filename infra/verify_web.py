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
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PROBE = REPO_ROOT / "infra" / "checks" / "cdp_probe.mjs"
DEFAULT_DIR = REPO_ROOT / "build" / "web"
SCRATCH = REPO_ROOT / ".test-tmp"
PERF_BUDGET_MS = 5000

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
    url = f"http://127.0.0.1:{port}/index.html"
    print(f"serving {build} at {url}")
    print(f"driving {chrome}")

    SCRATCH.mkdir(exist_ok=True)
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
                ["node", str(PROBE), endpoint, url, str(args.reloads)],
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=150,
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
    if report.get("ok") and not (interaction.get("plugins") or {}).get("found"):
        report["ok"] = False
        report["interactionFailure"] = "the first screen did not answer a click on New game"
    click_to_scene = report.get("clickToSceneMs")
    if report.get("ok") and not (interaction.get("session") or {}).get("found"):
        report["ok"] = False
        report["interactionFailure"] = "the pack list did not answer a click on a pack"
    if report.get("ok") and (click_to_scene is None or click_to_scene > PERF_BUDGET_MS):
        report["ok"] = False
        report["perfFailure"] = f"pack choice reached a scene in {click_to_scene} ms, budget {PERF_BUDGET_MS} ms"

    print(json.dumps(report, indent=2))
    return 0 if report.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
