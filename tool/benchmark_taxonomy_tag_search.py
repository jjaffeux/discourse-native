#!/usr/bin/env python3
"""Compare tag search controller revisions in an isolated worktree."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--samples", default=5, type=int)
    args = parser.parse_args()
    if args.samples < 1:
        parser.error("--samples must be positive")
    root = Path(__file__).resolve().parents[1]

    def git(*parts):
        return subprocess.check_output(["git", "-C", str(root), *parts])

    git_dir = Path(git("rev-parse", "--absolute-git-dir").decode().strip())
    common_dir = Path(git("rev-parse", "--git-common-dir").decode().strip())
    if not common_dir.is_absolute():
        common_dir = root / common_dir
    if git_dir.resolve() == common_dir.resolve():
        parser.error("run this comparison in an isolated Git worktree")
    relative = "lib/src/shell/taxonomy_directory_controller.dart"
    controller = root / relative
    dirty = bool(git("status", "--porcelain", "--", relative).strip())
    baseline_rev = git("rev-parse", args.baseline).decode().strip()
    baseline = git("show", f"{baseline_rev}:{relative}")
    candidate = controller.read_bytes()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    records = []
    try:
        for sample in range(1, args.samples + 1):
            for label, source in [("baseline", baseline), ("candidate", candidate)]:
                controller.write_bytes(source)
                result_path = output / f"{label}-{sample}.json"
                log_path = output / f"{label}-{sample}.log"
                with log_path.open("w") as stream:
                    subprocess.run(
                        [args.flutter, "test", "--no-pub", "--reporter", "expanded",
                         "test/taxonomy_tag_search_benchmark_test.dart"],
                        cwd=root,
                        env={**os.environ, "TAXONOMY_TAG_SEARCH_OUTPUT": str(result_path)},
                        stdout=stream, stderr=subprocess.STDOUT, check=True,
                    )
                records.append({
                    "label": label, "sample": sample,
                    "baseline_revision": baseline_rev,
                    "candidate_revision": git("rev-parse", "HEAD").decode().strip(),
                    "controller_sha256": hashlib.sha256(source).hexdigest(),
                    "candidate_source_dirty": dirty,
                    "result": json.loads(result_path.read_text()),
                })
                (output / "samples.json").write_text(json.dumps(records, indent=2) + "\n")
                print(f"{label} sample {sample} passed", flush=True)
    finally:
        controller.write_bytes(candidate)


if __name__ == "__main__":
    main()
