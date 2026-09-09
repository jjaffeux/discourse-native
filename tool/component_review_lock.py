#!/usr/bin/env python3
"""Serialize component reviewers' access to the shared desktop and main checkout."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from uuid import uuid4


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("acquire", "status", "release"))
    parser.add_argument("scope", choices=("desktop", "main"))
    parser.add_argument("--owner", help="Your Codex task ID")
    parser.add_argument("--component")
    parser.add_argument("--token", help="Token returned by acquire, for release")
    parser.add_argument("--repo", default=".")
    args = parser.parse_args()
    if args.action != "status" and not args.owner:
        parser.error("acquire and release require --owner")
    if args.action == "release" and not args.token:
        parser.error("release requires --token")

    common = subprocess.check_output(
        ["git", "-C", args.repo, "rev-parse", "--path-format=absolute", "--git-common-dir"],
        text=True,
    ).strip()
    root = Path(common) / "component-review-locks"
    root.mkdir(exist_ok=True)
    lock = root / args.scope
    metadata = lock / "owner.json"

    def current():
        try:
            return json.loads(metadata.read_text())
        except FileNotFoundError:
            return {"status": "initializing"} if lock.exists() else None

    if args.action == "status":
        print(json.dumps({"scope": args.scope, "lease": current()}))
        return 0

    if args.action == "acquire":
        try:
            os.mkdir(lock)
        except FileExistsError:
            lease = current()
            owned = lease is not None and lease.get("owner") == args.owner
            print(json.dumps({"acquired": owned, "scope": args.scope, "lease": lease}))
            return 0 if owned else 75
        lease = {
            "owner": args.owner,
            "component": args.component,
            "token": uuid4().hex,
            "acquiredAt": datetime.now(timezone.utc).isoformat(),
        }
        metadata.write_text(json.dumps(lease, indent=2) + "\n")
        print(json.dumps({"acquired": True, "scope": args.scope, "lease": lease}))
        return 0

    lease = current()
    if lease is None:
        print(json.dumps({"released": False, "reason": "already_unlocked"}))
        return 0
    if lease.get("owner") != args.owner or lease.get("token") != args.token:
        print(json.dumps({"released": False, "reason": "owner_or_token_mismatch"}))
        return 76
    retired = root / (args.scope + "-released-" + uuid4().hex)
    os.rename(lock, retired)
    shutil.rmtree(retired)
    print(json.dumps({"released": True, "scope": args.scope}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
