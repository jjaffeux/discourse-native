"""Run checked release workloads in alternating baseline/candidate order."""

import argparse
import json
import os
import platform
import statistics
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline")
    parser.add_argument("candidate")
    parser.add_argument("output", type=Path)
    parser.add_argument("--baseline-revision", default="ecafcb48a")
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--balanced-order", action="store_true")
    parser.add_argument("--focused", action="store_true")
    args = parser.parse_args()
    if args.runs < 5:
        parser.error("At least five runs per side are required")
    environment = os.environ.copy()
    environment.pop("PERF_FOCUS_ACTIVITY", None)
    if args.focused:
        environment["PERF_FOCUS_ACTIVITY"] = "1"
    results = {"baseline": [], "candidate": []}
    processes = []
    for run in range(args.runs):
        order = list(results)
        if args.balanced_order and run % 2:
            order.reverse()
        for side in order:
            process = subprocess.run(
                [getattr(args, side)], capture_output=True, text=True, timeout=180,
                env=environment,
            )
            marker = "ADDITIONAL_PERFORMANCE "
            lines = [line for line in process.stdout.splitlines() if marker in line]
            if process.returncode or len(lines) != 1:
                raise RuntimeError(
                    f"{side} run {run + 1} failed ({process.returncode})\n"
                    f"{process.stdout}\n{process.stderr}"
                )
            values = json.loads(lines[0].split(marker, 1)[1])
            if not values or any(value <= 0 for value in values.values()):
                raise RuntimeError(f"Invalid measurements: {values}")
            results[side].append(values)
            processes.append({"side": side, "run": run + 1, "exit_code": process.returncode})
            print(f"{side} run {run + 1} completed with {len(values)} checked workloads", flush=True)

    names = set(results["baseline"][0])
    if any(set(row) != names for rows in results.values() for row in rows):
        raise RuntimeError("Workload names differ between builds")
    summary = {}
    for name in sorted(names):
        row = {}
        for side, runs in results.items():
            values = [run[name] for run in runs]
            row[side] = {
                "median_us": statistics.median(values),
                "min_us": min(values),
                "max_us": max(values),
            }
        row["less_time_percent"] = 100 * (
            1 - row["candidate"]["median_us"] / row["baseline"]["median_us"]
        )
        row["nonoverlapping_gain"] = row["candidate"]["max_us"] < row["baseline"]["min_us"]
        summary[name] = row
    artifact = {
        "baseline_revision": args.baseline_revision,
        "runs_per_side": args.runs,
        "balanced_order": args.balanced_order,
        "workload_selection": "activity-and-chat-control" if args.focused else "all",
        "units": "microseconds per checked batch",
        "platform": platform.platform(),
        "processes": processes,
        "result_check_failures": 0,
        "runs": results,
        "summary": summary,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, indent=2) + "\n")
    for name, row in summary.items():
        print(f"{name}: {row['less_time_percent']:.1f}% less time; separated={row['nonoverlapping_gain']}")


if __name__ == "__main__":
    main()
