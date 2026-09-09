#!/usr/bin/env python3
"""Serialize component reviewers' access to the shared desktop and main checkout."""

import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from uuid import uuid4


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("acquire", "status", "release", "cancel"))
    parser.add_argument("scope", choices=("desktop", "main"))
    parser.add_argument("--owner", help="Your Codex task ID")
    parser.add_argument("--component")
    parser.add_argument("--token", help="Token returned by acquire, for release")
    parser.add_argument("--repo", default=".")
    args = parser.parse_args()
    if args.action != "status" and not args.owner:
        parser.error("acquire, release and cancel require --owner")
    if args.action == "release" and not args.token:
        parser.error("release requires --token")
    if args.action == "cancel" and args.scope != "desktop":
        parser.error("only desktop access has a waiting queue")

    common = subprocess.check_output(
        ["git", "-C", args.repo, "rev-parse", "--path-format=absolute", "--git-common-dir"],
        text=True,
    ).strip()
    root = Path(common) / "component-review-locks"
    root.mkdir(exist_ok=True)
    # The short OS lock protects metadata updates, never the duration of a review.
    with (root / "metadata.lock").open("a") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX)
        return operate(args, root)


def operate(args, root):
    lock = root / args.scope
    metadata = lock / "owner.json"
    queue_file = root / "desktop-queue.json"

    def current():
        try:
            return json.loads(metadata.read_text())
        except FileNotFoundError:
            return {"status": "initializing"} if lock.exists() else None

    queue = []
    if args.scope == "desktop" and queue_file.exists():
        queue = json.loads(queue_file.read_text())

    def save_queue():
        if args.scope == "desktop":
            temporary = queue_file.with_suffix(".tmp")
            temporary.write_text(json.dumps(queue, indent=2) + "\n")
            temporary.replace(queue_file)

    def busy(lease):
        result = {"acquired": False, "scope": args.scope, "lease": lease}
        if queue:
            result["nextOwner"] = queue[0]["owner"]
            result["queuePosition"] = next(
                i + 1 for i, request in enumerate(queue) if request["owner"] == args.owner
            )
        print(json.dumps(result))
        return 75

    lease = current()
    if args.action == "status":
        print(json.dumps({"scope": args.scope, "lease": lease, "queue": queue}))
        return 0

    if args.action == "cancel":
        before = len(queue)
        queue[:] = [request for request in queue if request["owner"] != args.owner]
        save_queue()
        print(json.dumps({"cancelled": len(queue) < before, "scope": args.scope}))
        return 0

    if args.action == "acquire":
        if lease is not None and lease.get("owner") == args.owner:
            print(json.dumps({"acquired": True, "scope": args.scope, "lease": lease}))
            return 0
        if args.scope == "desktop":
            if not any(request["owner"] == args.owner for request in queue):
                queue.append({
                    "owner": args.owner,
                    "component": args.component,
                    "requestedAt": datetime.now(timezone.utc).isoformat(),
                })
                save_queue()
            if lease is not None or queue[0]["owner"] != args.owner:
                return busy(lease)
        try:
            os.mkdir(lock)
        except FileExistsError:
            return busy(current())
        lease = {
            "owner": args.owner,
            "component": args.component,
            "token": uuid4().hex,
            "acquiredAt": datetime.now(timezone.utc).isoformat(),
        }
        metadata.write_text(json.dumps(lease, indent=2) + "\n")
        if args.scope == "desktop":
            queue[:] = [request for request in queue if request["owner"] != args.owner]
            save_queue()
        print(json.dumps({"acquired": True, "scope": args.scope, "lease": lease}))
        return 0

    if lease is None:
        print(json.dumps({"released": False, "reason": "already_unlocked"}))
        return 0
    if lease.get("owner") != args.owner or lease.get("token") != args.token:
        print(json.dumps({"released": False, "reason": "owner_or_token_mismatch"}))
        return 76
    retired = root / (args.scope + "-released-" + uuid4().hex)
    os.rename(lock, retired)
    shutil.rmtree(retired)
    print(json.dumps({
        "released": True,
        "scope": args.scope,
        "nextOwner": queue[0]["owner"] if queue else None,
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
