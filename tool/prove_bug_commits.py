#!/usr/bin/env python3
"""Proves that each bug fix in a range repaired a bug that really existed.

Every bug lands as two commits: a repro holding only the failing test, then
the fix holding only production code. For each manifest entry this checks out
both commits in a scratch worktree and runs the named test:

  repro  must fail on an assertion, printing Expected and Actual
  fix    must pass

A repro that fails without an assertion (a compile error, a harness exception)
proves nothing and is reported.

  tool/prove_bug_commits.py <manifest.json> --base <rev> --out <results.json>

Manifest: [{"slug", "repro", "fix", "test", "name"}], where repro and fix are
commit subjects and name is the test's --plain-name. An optional tz runs the
test in that time zone, for a bug the machine's own zone cannot show.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from queue import Queue

ASSERTION = re.compile(r"^\s*(Expected|Actual|Which): .*$", re.MULTILINE)
LOAD_FAILURE = re.compile(r"Failed to load|Compilation failed|Error: Couldn't")


def run(cwd, *command, env=None):
    return subprocess.run(
        command, cwd=cwd, env=env, text=True, capture_output=True, check=False
    )


def checked(cwd, *command):
    result = run(cwd, *command)
    if result.returncode != 0:
        sys.exit(f"{' '.join(command)} failed:\n{result.stdout}{result.stderr}")
    return result.stdout


def commit_for(repo, base, subject):
    log = checked(repo, "git", "log", "--format=%H%x00%s", f"{base}..HEAD")
    matches = [
        line.split("\0")[0]
        for line in log.splitlines()
        if line.split("\0")[1] == subject
    ]
    if len(matches) != 1:
        sys.exit(f"expected one commit for {subject!r}, found {len(matches)}")
    return matches[0]


def changed_paths(repo, commit):
    return checked(
        repo, "git", "show", "--name-only", "--format=", commit
    ).splitlines()


def run_side(tree, commit, entry):
    checked(tree, "git", "checkout", "--quiet", "--force", "--detach", commit)
    checked(tree, "git", "clean", "-fdq", "--", "lib", "test", "packages")
    result = run(
        tree,
        "flutter", "test", "--no-pub", entry["test"],
        "--plain-name", entry["name"],
        env=os.environ | ({"TZ": entry["tz"]} if "tz" in entry else {}),
    )
    output = result.stdout + result.stderr
    return {
        "commit": commit,
        "exit_code": result.returncode,
        "assertion": [match.group(0).strip() for match in ASSERTION.finditer(output)],
        "load_failure": bool(LOAD_FAILURE.search(output)),
        "ran": "All tests passed" in output or "Some tests failed" in output,
        "tail": output[-1500:] if result.returncode != 0 else None,
    }


def prove(entry, base, repo, trees):
    tree = trees.get()
    try:
        repro = commit_for(repo, base, entry["repro"])
        fix = commit_for(repo, base, entry["fix"])
        print(f"{entry['slug']} repro", flush=True)
        before = run_side(tree, repro, entry)
        print(f"{entry['slug']} fix", flush=True)
        after = run_side(tree, fix, entry)
        return {
            "slug": entry["slug"],
            "test": entry["test"],
            "name": entry["name"],
            "repro_paths": changed_paths(repo, repro),
            "fix_paths": changed_paths(repo, fix),
            "before": before,
            "after": after,
        }
    finally:
        trees.put(tree)


def verdict(item):
    slug = item["slug"]
    failures = []
    if any(not path.startswith("test/") for path in item["repro_paths"]):
        failures.append(f"{slug}: repro commit touches production code")
    if any(path.startswith("test/") for path in item["fix_paths"]):
        failures.append(f"{slug}: fix commit touches tests")
    if item["before"]["exit_code"] == 0:
        failures.append(f"{slug}: passes without the fix, proves nothing")
    elif item["before"]["load_failure"] or not item["before"]["assertion"]:
        failures.append(f"{slug}: fails without an assertion")
    if item["after"]["exit_code"] != 0:
        failures.append(f"{slug}: still fails with the fix")
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--base", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=4)
    args = parser.parse_args()

    repo = Path(checked(Path.cwd(), "git", "rev-parse", "--show-toplevel").strip())
    head = checked(repo, "git", "rev-parse", "HEAD").strip()
    manifest = json.loads(args.manifest.read_text())

    scratch = Path(tempfile.mkdtemp(prefix="prove-bugs-", dir=args.out.parent))
    trees = Queue()
    worktrees = []
    try:
        for number in range(args.jobs):
            tree = scratch / f"tree-{number}"
            checked(repo, "git", "worktree", "add", "--detach", "--quiet", str(tree), head)
            checked(tree, "flutter", "pub", "get", "--enforce-lockfile")
            worktrees.append(tree)
            trees.put(tree)
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            proven = list(
                pool.map(lambda entry: prove(entry, args.base, repo, trees), manifest)
            )
    finally:
        for tree in worktrees:
            run(repo, "git", "worktree", "remove", "--force", str(tree))
        shutil.rmtree(scratch, ignore_errors=True)

    failures = [failure for item in proven for failure in verdict(item)]
    args.out.write_text(
        json.dumps({"head": head, "failures": failures, "proven": proven}, indent=1) + "\n"
    )
    for item in proven:
        print(f"\n{item['slug']}  {item['test']}")
        print(f"  repro exit {item['before']['exit_code']}, fix exit {item['after']['exit_code']}")
        for line in item["before"]["assertion"][:3]:
            print(f"  {line[:200]}")
    print()
    print("\n".join(failures) or f"all {len(proven)} proofs hold at {head}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
