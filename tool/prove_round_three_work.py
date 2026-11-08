import argparse
import json
import re
import subprocess
from pathlib import Path


TESTS = [
    "test/perf_round_three_app_test.dart",
    "test/perf_round_three_models_test.dart",
    "test/perf_round_three_services_test.dart",
]
COUNTER = re.compile(r"(?:WORK|PERF_R3) ([a-zA-Z0-9_]+)=(\d+)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    runs = {"baseline": [], "candidate": []}
    revisions = {}
    for side in runs:
        directory = getattr(args, side)
        subprocess.run(
            ["git", "diff", "--quiet", "HEAD", "--", "lib", "packages"],
            cwd=directory,
            check=True,
        )
        revisions[side] = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=directory, text=True
        ).strip()
    if not revisions["baseline"].startswith("44d621e91"):
        raise RuntimeError("Baseline checkout is not the recorded main revision")

    for trial in range(2):
        for side in runs:
            command = ["flutter", "test", "--no-pub"]
            if side == "baseline":
                command += ["--dart-define=PERF_BASELINE=true"]
            command += TESTS
            result = subprocess.run(
                command, cwd=getattr(args, side), capture_output=True, text=True,
                timeout=240,
            )
            output = result.stdout + result.stderr
            if result.returncode:
                raise RuntimeError(f"{side} failed\n{output}")
            pairs = COUNTER.findall(output)
            counters = {name: int(value) for name, value in pairs}
            if len(counters) != 8 or len(pairs) != 8:
                raise RuntimeError(f"Expected eight unique work counters: {pairs}")
            runs[side].append(counters)
            print(f"{side} trial {trial + 1}: {counters}", flush=True)

    for side, values in runs.items():
        if values[0] != values[1]:
            raise RuntimeError(f"{side} work counts were not deterministic")
    if set(runs["baseline"][0]) != set(runs["candidate"][0]):
        raise RuntimeError("Counter names differ between checkouts")
    if runs["baseline"][0] == runs["candidate"][0]:
        raise RuntimeError("No work reduction was observed")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({
        "revisions": revisions,
        "method": "Two alternating focused-test runs per side; results always checked",
        "runs": runs,
        "result_check_failures": 0,
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
