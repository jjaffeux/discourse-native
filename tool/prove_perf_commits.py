#!/usr/bin/env python3
"""Proves that each PERF commit in a range earns its numbers.

For every commit named in the manifest this checks out the commit in a scratch
worktree and runs its proof tests twice per side, alternating:

  before  the commit with its own lib/ and packages/ changes reverse-applied
  after   the commit as it stands

A proof test prints `PERF_PROOF <slug> <metric>=<value>` lines and asserts its
budget, so a real proof fails before and passes after. A side that fails
without printing its metrics did not measure anything (usually a test that no
longer compiles against the older code) and is reported as such.

The counts are deterministic, so they do not depend on a quiet machine.

  tool/prove_perf_commits.py <manifest.json> --base <rev> --out <results.json>
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from queue import Queue

PROOF = re.compile(r"PERF_PROOF (\S+) ([A-Za-z0-9_.-]+)=(\S+)")
PRODUCTION_PATHS = ["lib", "packages"]
ROUNDS = 2


def run(cwd, *command):
    return subprocess.run(
        command, cwd=cwd, text=True, capture_output=True, check=False
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


def checkout(tree, commit, side):
    checked(tree, "git", "checkout", "--quiet", "--force", "--detach", commit)
    checked(tree, "git", "clean", "-fdq", "--", *PRODUCTION_PATHS, "test")
    if side == "after":
        return
    patch = checked(
        tree, "git", "diff", "--binary", f"{commit}~", commit, "--", *PRODUCTION_PATHS
    )
    subprocess.run(
        ["git", "apply", "--reverse", "--whitespace=nowarn"],
        cwd=tree,
        input=patch,
        text=True,
        check=True,
    )


def run_proof(tree, proof):
    command = ["flutter", "test", "--no-pub", proof["path"]]
    if "name" in proof:
        command += ["--plain-name", proof["name"]]
    result = run(tree, *command)
    output = result.stdout + result.stderr
    metrics = {f"{m[0]}.{m[1]}": m[2] for m in PROOF.findall(output)}
    return {
        "test": proof["path"],
        "name": proof.get("name"),
        "exit_code": result.returncode,
        "metrics": metrics,
        "tail": None if metrics else output[-1500:],
    }


def prove(entry, base, repo, trees):
    tree = trees.get()
    try:
        commit = commit_for(repo, base, entry["subject"])
        runs = []
        for number in range(ROUNDS):
            for side in ("before", "after"):
                checkout(tree, commit, side)
                for proof in entry["proofs"]:
                    print(f"{entry['slug']} {side} {number + 1}", flush=True)
                    runs.append(
                        {"side": side, "round": number + 1} | run_proof(tree, proof)
                    )
        return {"slug": entry["slug"], "subject": entry["subject"], "commit": commit, "runs": runs}
    finally:
        trees.put(tree)


def verdict(proven):
    failures = []
    for run_ in proven["runs"]:
        where = f"{proven['slug']} {run_['test']} {run_['side']} {run_['round']}"
        if run_["side"] == "after" and run_["exit_code"] != 0:
            failures.append(f"{where}: fails with the change applied")
        if run_["side"] == "before" and run_["exit_code"] == 0:
            failures.append(f"{where}: passes without the change, proves nothing")
        if run_["side"] == "before" and not run_["metrics"]:
            failures.append(f"{where}: measured nothing")
    by_side = {}
    for run_ in proven["runs"]:
        by_side.setdefault(run_["side"], []).append(run_["metrics"])
    for side, metrics in by_side.items():
        for key in {key for sample in metrics for key in sample}:
            values = {sample[key] for sample in metrics if key in sample}
            if len(values) > 1:
                failures.append(f"{proven['slug']} {key} varies on {side}: {values}")
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

    scratch = Path(tempfile.mkdtemp(prefix="prove-perf-", dir=args.out.parent))
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
    print("\n".join(failures) or f"all {len(proven)} proofs hold at {head}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
