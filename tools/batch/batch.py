#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Project-local batch execution skeleton.

The tool is deliberately stack-agnostic. It owns a small state machine:

    plan -> approve -> start -> check -> pr -> merge

Checks and PR provider commands come from ``tools/batch/config.json``. The
defaults only do local work; a project can add its own commands without
changing this file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import secrets
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence

ROOT = Path(__file__).resolve().parents[2]
STATE_DIR = ".batch"
CONFIG_REL = Path("tools") / "batch" / "config.json"
DEFAULT_CONFIG: dict[str, Any] = {
    "base": "main",
    "branch_prefix": "batch/",
    "scope": {"ignore": [], "generated": []},
    "checks": [],
    "pr_create": [],
    "merge": [],
}
ID_RE = re.compile(r"^[0-9]{8}-[0-9a-f]{6}$")


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def load_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8", newline="\n")


def run_git(root: Path, args: Sequence[str]) -> tuple[int, str, str]:
    proc = subprocess.run(
        ["git", *args],
        cwd=root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def git_required(root: Path) -> None:
    code, _, err = run_git(root, ["rev-parse", "--show-toplevel"])
    if code != 0:
        raise SystemExit(f"not a git repository: {root} ({err})")


def config_path(root: Path) -> Path:
    return root / CONFIG_REL


def load_config(root: Path) -> dict[str, Any]:
    config = dict(DEFAULT_CONFIG)
    config["scope"] = dict(DEFAULT_CONFIG["scope"])
    raw = load_json(config_path(root))
    if raw is not None:
        for key in DEFAULT_CONFIG:
            if key in raw:
                config[key] = raw[key]
    scope = config.get("scope")
    if not isinstance(scope, dict):
        raise SystemExit("config.scope must be an object")
    config["scope"] = dict(DEFAULT_CONFIG["scope"])
    for key in ("ignore", "generated"):
        value = scope.get(key, [])
        if not isinstance(value, list):
            raise SystemExit(f"config.scope.{key} must be a list")
        config["scope"][key] = [str(item) for item in value]
    if not isinstance(config.get("checks"), list):
        raise SystemExit("config.checks must be a list")
    for key in ("pr_create", "merge"):
        value = config.get(key)
        if value and not isinstance(value, list):
            raise SystemExit(f"config.{key} must be a command array")
    return config


def state_root(root: Path) -> Path:
    return root / STATE_DIR


def batch_dir(root: Path, batch_id: str) -> Path:
    return state_root(root) / batch_id


def active_id(root: Path) -> str | None:
    path = state_root(root) / "active"
    try:
        value = path.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    return value or None


def clear_active(root: Path) -> None:
    path = state_root(root) / "active"
    try:
        path.unlink()
    except FileNotFoundError:
        pass


def set_active(root: Path, batch_id: str) -> None:
    write_text(state_root(root) / "active", batch_id + "\n")


def resolve_id(root: Path, value: str | None) -> str:
    if value:
        if not ID_RE.fullmatch(value):
            raise SystemExit(f"invalid batch id: {value}")
        if not batch_dir(root, value).is_dir():
            raise SystemExit(f"batch not found: {value}")
        return value
    active = active_id(root)
    if active:
        return active
    if not state_root(root).is_dir():
        raise SystemExit("no batch found; run 'plan' first")
    candidates = sorted(
        (path.name for path in state_root(root).iterdir() if path.is_dir()),
        key=lambda name: (state_root(root) / name).stat().st_mtime,
    )
    if not candidates:
        raise SystemExit("no batch found; run 'plan' first")
    return candidates[-1]


def new_id(root: Path) -> str:
    prefix = datetime.now().strftime("%Y%m%d")
    for _ in range(50):
        candidate = f"{prefix}-{secrets.token_hex(3)}"
        if not batch_dir(root, candidate).exists():
            return candidate
    raise SystemExit("could not allocate a batch id")


def parse_list(values: list[str] | None, default: list[str]) -> list[str]:
    out: list[str] = []
    for value in values or []:
        for item in value.replace(";", ",").split(","):
            item = item.strip()
            if item and item not in out:
                out.append(item)
    return out or default


def card_hash(card: dict[str, Any]) -> str:
    canonical = json.dumps(card, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def read_card(root: Path, batch_id: str) -> dict[str, Any]:
    card = load_json(batch_dir(root, batch_id) / "card.json")
    if card is None:
        raise SystemExit(f"card not found: {batch_id}")
    return card


def read_state(root: Path, batch_id: str) -> dict[str, Any]:
    state = load_json(batch_dir(root, batch_id) / "state.json")
    if state is None:
        raise SystemExit(f"batch not started: {batch_id}")
    return state


def glob_regex(pattern: str) -> re.Pattern[str]:
    i = 0
    out = ""
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pattern.startswith("**", i):
            out += ".*"
            i += 2
        elif pattern[i] == "*":
            out += "[^/]*"
            i += 1
        elif pattern[i] == "?":
            out += "[^/]"
            i += 1
        else:
            out += re.escape(pattern[i])
            i += 1
    return re.compile("^" + out + "$")


def matches(path: str, patterns: Sequence[str]) -> bool:
    normalized = path.replace("\\", "/")
    return any(glob_regex(pattern).fullmatch(normalized) for pattern in patterns)


def changed_paths(root: Path, base: str, config: dict[str, Any]) -> list[str]:
    paths: set[str] = set()
    for args in (
        ["diff", "--name-only", f"{base}...HEAD"],
        ["diff", "--name-only", "HEAD"],
        ["ls-files", "--others", "--exclude-standard"],
    ):
        code, out, _ = run_git(root, args)
        if code != 0:
            continue
        paths.update(line.strip() for line in out.splitlines() if line.strip())

    ignored = list(DEFAULT_CONFIG["scope"]["ignore"])
    ignored.extend(DEFAULT_CONFIG["scope"]["generated"])
    scope = config.get("scope")
    if isinstance(scope, dict):
        ignored.extend(str(item) for item in scope.get("ignore", []))
        ignored.extend(str(item) for item in scope.get("generated", []))
    ignored.extend([".batch/**", ".batch"])
    return sorted(
        path
        for path in paths
        if not matches(path, ignored) and path != ".batch"
    )


def check_scope(
    root: Path, card: dict[str, Any], base: str, config: dict[str, Any]
) -> tuple[list[str], list[str]]:
    allowed = [str(item) for item in card.get("allowed", [])] or ["**"]
    forbidden = [str(item) for item in card.get("forbidden", [])]
    changed = changed_paths(root, base, config)
    violations: list[str] = []
    for path in changed:
        if matches(path, forbidden):
            violations.append(f"forbidden: {path}")
        elif not matches(path, allowed):
            violations.append(f"out of scope: {path}")
    return changed, violations


def append_evidence(root: Path, batch_id: str, line: str) -> None:
    path = batch_dir(root, batch_id) / "evidence.log"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(f"[{utc_now()}] {line}\n")


def command_list(value: Any) -> list[str]:
    if isinstance(value, str):
        return shlex.split(value)
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return list(value)
    raise SystemExit("command must be a string or an array of strings")


def run_hook(
    root: Path, command: Sequence[str], values: dict[str, str]
) -> tuple[int, str, str]:
    resolved = [
        item.replace("{id}", values["id"])
        .replace("{title}", values["title"])
        .replace("{body}", values["body"])
        .replace("{branch}", values["branch"])
        .replace("{root}", values["root"])
        .replace("{pr}", values.get("pr", ""))
        for item in command
    ]
    proc = subprocess.run(
        resolved,
        cwd=root,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def run_checks(
    root: Path, batch_id: str, config: dict[str, Any]
) -> dict[str, dict[str, Any]]:
    results: dict[str, dict[str, Any]] = {}
    for item in config.get("checks", []):
        if not isinstance(item, dict):
            raise SystemExit("each check must be an object")
        name = str(item.get("name", "")).strip()
        if not name or not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
            raise SystemExit(f"invalid check name: {name!r}")
        command = command_list(item.get("command"))
        timeout = int(item.get("timeout", 600))
        raw_cwd = str(item.get("cwd", ".") or ".").strip() or "."
        check_cwd = (root / raw_cwd).resolve()
        try:
            check_cwd.relative_to(root.resolve())
        except ValueError:
            raise SystemExit(f"check {name}: cwd escapes project root: {raw_cwd}")
        try:
            proc = subprocess.run(
                command,
                cwd=check_cwd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
            )
            status = "pass" if proc.returncode == 0 else "fail"
            output = (proc.stdout + proc.stderr).strip()
            code = proc.returncode
        except subprocess.TimeoutExpired:
            status, output, code = "fail", f"timeout after {timeout}s", 124
        log = batch_dir(root, batch_id) / "evidence" / f"{name}.log"
        write_text(log, output + ("\n" if output else ""))
        results[name] = {"status": status, "exit": code, "at": utc_now()}
        append_evidence(root, batch_id, f"check {name}: {status.upper()} (exit {code})")
        print(f"[{status}] check {name}")
        if status == "fail":
            print(output[-2000:], file=sys.stderr)
    return results


def print_status(root: Path, batch_id: str, as_json: bool) -> None:
    card = read_card(root, batch_id)
    state = load_json(batch_dir(root, batch_id) / "state.json") or {}
    payload = {
        "id": batch_id,
        "goal": card.get("goal"),
        "card_hash": card_hash(card)[:8],
        "status": state.get("status", "planned"),
        "base": state.get("base"),
        "branch": state.get("branch"),
        "checks": state.get("checks", {}),
        "active": active_id(root) == batch_id,
    }
    if as_json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        return
    print(f"batch:  {batch_id}")
    print(f"goal:   {payload['goal']}")
    print(f"hash:   {payload['card_hash']}")
    print(f"status: {payload['status']}")
    if payload["base"]:
        print(f"base:   {payload['base']}")
    if payload["branch"]:
        print(f"branch: {payload['branch']}")
    if payload["checks"]:
        for name, result in payload["checks"].items():
            print(f"check:  {name} = {result.get('status')}")
    print(f"active: {'yes' if payload['active'] else 'no'}")


def cmd_plan(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    git_required(root)
    batch_id = args.id or new_id(root)
    if not ID_RE.fullmatch(batch_id):
        print("invalid batch id; use YYYYMMDD-<6 hex>", file=sys.stderr)
        return 2
    target = batch_dir(root, batch_id)
    if target.exists():
        print(f"batch already exists: {batch_id}", file=sys.stderr)
        return 1
    card = {
        "id": batch_id,
        "goal": args.goal,
        "allowed": parse_list(args.allowed, ["**"]),
        "forbidden": parse_list(args.forbidden, []),
        "exit_criteria": parse_list(args.exit_criterion, []),
        "created_at": utc_now(),
    }
    write_json(target / "card.json", card)
    print(f"planned {batch_id}")
    print(f"hash: {card_hash(card)[:8]}")
    return 0


def cmd_approve(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    batch_id = resolve_id(root, args.id)
    card = read_card(root, batch_id)
    digest = card_hash(card)
    if args.confirm != digest[:8]:
        print(f"confirm mismatch: expected {digest[:8]}", file=sys.stderr)
        return 1
    approval = {
        "batch": batch_id,
        "card_hash": digest,
        "approved_by": args.by,
        "approved_at": utc_now(),
    }
    write_json(batch_dir(root, batch_id) / "approval.json", approval)
    print(f"approved {batch_id}")
    return 0


def cmd_start(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    git_required(root)
    batch_id = resolve_id(root, args.id)
    card = read_card(root, batch_id)
    approval = load_json(batch_dir(root, batch_id) / "approval.json")
    if approval is None or approval.get("card_hash") != card_hash(card):
        print("card is not approved (or approval is stale)", file=sys.stderr)
        return 1
    current = active_id(root)
    if current:
        print(f"another batch is active: {current}", file=sys.stderr)
        return 1

    config = load_config(root)
    base = args.base or str(config.get("base", "main"))
    branch = args.branch or f"{config.get('branch_prefix', 'batch/')}{batch_id}"
    if not args.no_branch:
        code, _, err = run_git(root, ["switch", "-c", branch])
        if code != 0:
            print(f"could not create branch {branch}: {err}", file=sys.stderr)
            return 1

    state = {
        "batch": batch_id,
        "status": "started",
        "base": base,
        "branch": branch,
        "started_at": utc_now(),
        "checks": {},
    }
    write_json(batch_dir(root, batch_id) / "state.json", state)
    set_active(root, batch_id)
    print(f"started {batch_id} on {branch} (base {base})")
    return 0


def cmd_check(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    git_required(root)
    batch_id = resolve_id(root, args.id)
    card = read_card(root, batch_id)
    state = read_state(root, batch_id)
    config = load_config(root)
    base = state.get("base") or str(config.get("base", "main"))
    changed, violations = check_scope(root, card, base, config)

    append_evidence(
        root,
        batch_id,
        f"scope: {'PASS' if not violations else 'FAIL'} ({len(changed)} changed paths)",
    )
    for path in changed:
        append_evidence(root, batch_id, f"changed: {path}")
    for violation in violations:
        append_evidence(root, batch_id, f"scope: {violation}")
        print(f"[fail] {violation}", file=sys.stderr)

    results = run_checks(root, batch_id, config) if not violations else {}
    passed = not violations and all(item.get("status") == "pass" for item in results.values())
    state["status"] = "checked" if passed else "check_failed"
    state["checks"] = results
    state["checked_at"] = utc_now()
    write_json(batch_dir(root, batch_id) / "state.json", state)
    print(f"scope: {'PASS' if not violations else 'FAIL'} ({len(changed)} paths)")
    print(f"result: {'PASS' if passed else 'FAIL'}")
    return 0 if passed else 1


def pr_body(root: Path, batch_id: str) -> str:
    card = read_card(root, batch_id)
    state = read_state(root, batch_id)
    changed = changed_paths(root, str(state.get("base", "main")), load_config(root))
    lines = [
        f"# {card.get('goal', '')}",
        "",
        "## Batch",
        "",
        f"- ID: `{batch_id}`",
        f"- Branch: `{state.get('branch', '')}`",
        f"- Base: `{state.get('base', '')}`",
        "",
        "## Scope",
        "",
        "Allowed:",
        *[f"- `{item}`" for item in card.get("allowed", [])],
        "",
        f"Changed files: {len(changed)}",
        *[f"- `{item}`" for item in changed],
        "",
        "## Checks",
        "",
    ]
    checks = state.get("checks", {})
    if checks:
        lines.extend(f"- {name}: {result.get('status')}" for name, result in checks.items())
    else:
        lines.append("- none configured")
    lines.extend(["", "## Exit criteria", ""])
    criteria = card.get("exit_criteria", [])
    lines.extend(f"- {item}" for item in criteria) if criteria else lines.append("- none recorded")
    lines.extend(
        [
            "",
            "## Evidence",
            "",
            f"- `.batch/{batch_id}/evidence.log`",
            "",
        ]
    )
    return "\n".join(lines)


def cmd_pr(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    batch_id = resolve_id(root, args.id)
    state = read_state(root, batch_id)
    if state.get("status") not in {"checked", "pr_ready"}:
        print("run 'check' successfully before preparing a PR", file=sys.stderr)
        return 1
    body = pr_body(root, batch_id)
    body_path = args.body_file or (batch_dir(root, batch_id) / "pr-body.md")
    body_path = body_path if body_path.is_absolute() else root / body_path
    write_text(body_path, body + "\n")
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
    print(f"prepared {body_path.relative_to(root)}")
    print(f"body hash: {digest[:8]}")
    state["status"] = "pr_ready"
    state["pr_body"] = str(body_path.relative_to(root))
    write_json(batch_dir(root, batch_id) / "state.json", state)

    if not args.create:
        return 0
    if args.confirm != digest[:8]:
        print(f"confirm mismatch: expected {digest[:8]}", file=sys.stderr)
        return 1
    config = load_config(root)
    command = config.get("pr_create")
    if not command:
        print("config.pr_create is empty; use --prepare only", file=sys.stderr)
        return 2
    card = read_card(root, batch_id)
    code, out, err = run_hook(
        root,
        command,
        {
            "id": batch_id,
            "title": str(card.get("goal", batch_id)),
            "body": str(body_path),
            "branch": str(state.get("branch", "")),
            "root": str(root),
        },
    )
    if out:
        print(out)
    if err:
        print(err, file=sys.stderr)
    if code != 0:
        return 1
    state["status"] = "pr_created"
    state["pr_output"] = out
    write_json(batch_dir(root, batch_id) / "state.json", state)
    print(f"created PR for {batch_id}")
    return 0


def cmd_merge(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    batch_id = resolve_id(root, args.id)
    state = read_state(root, batch_id)
    if not args.yes:
        print("merge requires --yes", file=sys.stderr)
        return 2
    if state.get("status") != "pr_created":
        print("batch has no created PR", file=sys.stderr)
        return 1
    config = load_config(root)
    command = config.get("merge")
    if not command:
        print("config.merge is empty; merge externally", file=sys.stderr)
        return 2
    code, out, err = run_hook(
        root,
        command,
        {
            "id": batch_id,
            "title": batch_id,
            "body": "",
            "branch": str(state.get("branch", "")),
            "root": str(root),
            "pr": args.pr,
        },
    )
    if out:
        print(out)
    if err:
        print(err, file=sys.stderr)
    if code != 0:
        return 1
    state["status"] = "merged"
    state["merged_at"] = utc_now()
    write_json(batch_dir(root, batch_id) / "state.json", state)
    clear_active(root)
    print(f"merged {batch_id}")
    return 0


def cmd_abort(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    batch_id = resolve_id(root, args.id)
    state = read_state(root, batch_id)
    if state.get("status") == "merged":
        print("cannot abort a merged batch", file=sys.stderr)
        return 1
    state["status"] = "aborted"
    state["aborted_at"] = utc_now()
    write_json(batch_dir(root, batch_id) / "state.json", state)
    if active_id(root) == batch_id:
        clear_active(root)
    print(f"aborted {batch_id}")
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    root_dir = state_root(root)
    if not root_dir.is_dir():
        print("no batches")
        return 0
    for path in sorted(root_dir.iterdir()):
        if not path.is_dir():
            continue
        state = load_json(path / "state.json") or {}
        card = load_json(path / "card.json") or {}
        print(f"{path.name}\t{state.get('status', 'planned')}\t{card.get('goal', '')}")
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    root = args.root.resolve()
    try:
        batch_id = resolve_id(root, args.id)
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print_status(root, batch_id, args.json)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="project-local batch execution skeleton")
    parser.add_argument("--root", type=Path, default=ROOT)
    sub = parser.add_subparsers(dest="command", required=True)

    plan = sub.add_parser("plan", help="create a batch card")
    plan.add_argument("id", nargs="?")
    plan.add_argument("--goal", required=True)
    plan.add_argument("--allowed", action="append")
    plan.add_argument("--forbidden", action="append")
    plan.add_argument("--exit-criterion", action="append")
    plan.set_defaults(func=cmd_plan)

    approve = sub.add_parser("approve", help="approve a card by hash")
    approve.add_argument("id", nargs="?")
    approve.add_argument("--confirm", required=True)
    approve.add_argument("--by", default="")
    approve.set_defaults(func=cmd_approve)

    start = sub.add_parser("start", help="start an approved batch")
    start.add_argument("id", nargs="?")
    start.add_argument("--base")
    start.add_argument("--branch")
    start.add_argument("--no-branch", action="store_true")
    start.set_defaults(func=cmd_start)

    check = sub.add_parser("check", help="check scope and configured commands")
    check.add_argument("id", nargs="?")
    check.set_defaults(func=cmd_check)

    pr = sub.add_parser("pr", help="prepare or create a PR body")
    pr.add_argument("id", nargs="?")
    pr.add_argument("--prepare", action="store_true")
    pr.add_argument("--create", action="store_true")
    pr.add_argument("--body-file")
    pr.add_argument("--confirm")
    pr.set_defaults(func=cmd_pr)

    merge = sub.add_parser("merge", help="run the configured merge command")
    merge.add_argument("id", nargs="?")
    merge.add_argument("--pr", required=True)
    merge.add_argument("--yes", action="store_true")
    merge.set_defaults(func=cmd_merge)

    abort = sub.add_parser("abort", help="abort an unmerged batch")
    abort.add_argument("id", nargs="?")
    abort.set_defaults(func=cmd_abort)

    listing = sub.add_parser("list", help="list batches")
    listing.set_defaults(func=cmd_list)

    status = sub.add_parser("status", help="show one batch")
    status.add_argument("id", nargs="?")
    status.add_argument("--json", action="store_true")
    status.set_defaults(func=cmd_status)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
