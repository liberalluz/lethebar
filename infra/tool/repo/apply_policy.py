#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Check or apply the GitHub repository policy recorded in .nebula-scaffold.json.

The policy is provider-neutral. This adapter intentionally implements GitHub
only; GitLab is recorded in the scaffold but is not applied by this script.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def read_policy(root: Path) -> dict:
    path = root / ".nebula-scaffold.json"
    if not path.is_file():
        raise ValueError(f"missing {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    policy = data.get("repoPolicy")
    if not isinstance(policy, dict):
        raise ValueError("missing repoPolicy in .nebula-scaffold.json")
    return policy


def gh(root: Path, *args: str, stdin: str | None = None) -> str:
    proc = subprocess.run(
        ["gh", *args],
        cwd=root,
        input=stdin,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(f"gh {' '.join(args)} failed: {detail}")
    return proc.stdout


def repo_slug(root: Path) -> str:
    value = gh(
        root,
        "repo",
        "view",
        "--json",
        "nameWithOwner",
        "--jq",
        ".nameWithOwner",
    ).strip()
    if not value:
        raise RuntimeError("cannot resolve repository slug with gh repo view")
    return value


def protection_payload(policy: dict) -> dict:
    review = policy["review"]
    required_review = None
    if review["requirePullRequest"]:
        required_review = {
            "dismiss_stale_reviews": bool(review["dismissStaleApprovals"]),
            "require_code_owner_reviews": bool(review["requireCodeOwnerReview"]),
            "required_approving_review_count": int(review["requiredApprovals"]),
            "require_last_push_approval": bool(review["requireLastPushApproval"]),
        }

    required_checks = policy["checks"]["required"]
    status_checks = None
    if required_checks:
        status_checks = {
            "strict": bool(policy["checks"]["requireUpToDate"]),
            "contexts": list(required_checks),
        }

    return {
        "required_status_checks": status_checks,
        "enforce_admins": True,
        "required_pull_request_reviews": required_review,
        "restrictions": None,
        "required_linear_history": bool(policy["linearHistory"]),
        "allow_force_pushes": bool(policy["push"]["allowForce"]),
        "allow_deletions": bool(policy["push"]["allowDeletions"]),
        "required_conversation_resolution": bool(
            review["requireConversationResolution"]
        ),
    }


def diff_policy(policy: dict, visibility: str, protection: dict | None) -> list[str]:
    diffs: list[str] = []
    if visibility != policy["visibility"]:
        diffs.append(f"visibility: {visibility} -> {policy['visibility']}")
    if protection is None:
        return diffs + ["branch protection is not configured"]

    review = policy["review"]
    current_review = protection.get("required_pull_request_reviews") or {}
    if bool(current_review) != bool(review["requirePullRequest"]):
        diffs.append("pull request review requirement differs")
    if review["requirePullRequest"]:
        expected = {
            "required_approving_review_count": int(review["requiredApprovals"]),
            "dismiss_stale_reviews": bool(review["dismissStaleApprovals"]),
            "require_code_owner_reviews": bool(review["requireCodeOwnerReview"]),
            "require_last_push_approval": bool(review["requireLastPushApproval"]),
        }
        for key, value in expected.items():
            if current_review.get(key) != value:
                diffs.append(f"review.{key}: {current_review.get(key)} -> {value}")

    current_checks = protection.get("required_status_checks") or {}
    expected_checks = list(policy["checks"]["required"])
    if list(current_checks.get("contexts") or []) != expected_checks:
        diffs.append("required status checks differ")
    if bool(current_checks.get("strict")) != bool(policy["checks"]["requireUpToDate"]):
        diffs.append("required status checks strict mode differs")

    comparisons = {
        "required_linear_history": bool(policy["linearHistory"]),
        "allow_force_pushes": bool(policy["push"]["allowForce"]),
        "allow_deletions": bool(policy["push"]["allowDeletions"]),
        "required_conversation_resolution": bool(
            review["requireConversationResolution"]
        ),
    }
    for key, value in comparisons.items():
        recorded = protection.get(key)
        if isinstance(recorded, dict):
            recorded = recorded.get("enabled", False)
        if bool(recorded) != value:
            diffs.append(f"{key}: {bool(recorded)} -> {value}")
    return diffs


def current_visibility(root: Path, slug: str) -> str:
    value = gh(
        root,
        "api",
        f"repos/{slug}",
        "--jq",
        ".visibility",
    ).strip()
    return value or "private"


def current_protection(root: Path, slug: str, branch: str) -> dict | None:
    proc = subprocess.run(
        [
            "gh",
            "api",
            f"repos/{slug}/branches/{branch}/protection",
        ],
        cwd=root,
        text=True,
        capture_output=True,
    )
    if proc.returncode != 0:
        if "404" in (proc.stderr or "") or "Not Found" in (proc.stderr or ""):
            return None
        raise RuntimeError((proc.stderr or proc.stdout or "").strip())
    return json.loads(proc.stdout or "{}")


def apply(root: Path, slug: str, policy: dict, *, confirm_public: bool) -> None:
    visibility = current_visibility(root, slug)
    if visibility != policy["visibility"]:
        if policy["visibility"] == "public" and not confirm_public:
            raise ValueError("changing a repository to public requires --confirm-public")
        gh(
            root,
            "api",
            "-X",
            "PATCH",
            f"repos/{slug}",
            "-f",
            f"visibility={policy['visibility']}",
        )
        print(f"visibility: {visibility} -> {policy['visibility']}")

    branch = policy["defaultBranch"]
    payload = protection_payload(policy)
    gh(
        root,
        "api",
        "-X",
        "PUT",
        f"repos/{slug}/branches/{branch}/protection",
        "--input",
        "-",
        stdin=json.dumps(payload),
    )
    print(f"branch protection: {branch} updated")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="check or apply repository policy")
    parser.add_argument("--root", type=Path, default=Path("."))
    parser.add_argument("--repo", default="", help="OWNER/NAME; default from gh repo view")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--confirm-public", action="store_true")
    args = parser.parse_args(argv)
    if args.check and args.apply:
        print("--check and --apply are mutually exclusive", file=sys.stderr)
        return 2

    try:
        policy = read_policy(args.root.resolve())
        provider = policy.get("provider", "none")
        if provider == "gitlab":
            print("gitlab: policy is recorded only; no apply adapter")
            return 0
        if provider != "github":
            print(f"{provider}: no remote policy adapter")
            return 0
        slug = args.repo or repo_slug(args.root)
        visibility = current_visibility(args.root, slug)
        if args.apply:
            apply(args.root, slug, policy, confirm_public=args.confirm_public)
            return 0
        protection = current_protection(args.root, slug, policy["defaultBranch"])
        diffs = diff_policy(policy, visibility, protection)
        if diffs:
            print(f"{slug}: policy drift")
            for item in diffs:
                print(f"  - {item}")
            return 1
        print(f"{slug}: policy matches")
        return 0
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as exc:
        print(f"repo policy: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
