#!/usr/bin/env python3
"""Compare native topic thumb-drag profiles from two compiled macOS apps."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import statistics
import subprocess
import threading
import time


def capture(app, output):
    environment = os.environ.copy()
    environment["FLUTTER_ENGINE_SWITCHES"] = "1"
    environment["FLUTTER_ENGINE_SWITCH_1"] = "enable-dart-profiling=false"
    process = subprocess.Popen(
        [str(app / "Contents/MacOS/Discourse")],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1, env=environment,
    )
    lines = queue.Queue()

    def read_lines():
        for line in process.stdout:
            lines.put(line)

    threading.Thread(target=read_lines, daemon=True).start()
    log = []
    report = None
    passed = False
    deadline = time.monotonic() + 90
    try:
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1)
            except queue.Empty:
                if process.poll() is not None:
                    break
                continue
            log.append(line)
            if "TOPIC_SCROLLBAR_PROFILE " in line:
                report = json.loads(line.split("TOPIC_SCROLLBAR_PROFILE ", 1)[1])
            if "All tests passed!" in line:
                passed = True
                break
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        output.with_suffix(".log").write_text("".join(log))
    if not passed or report is None:
        raise RuntimeError(f"Workload failed; inspect {output.with_suffix('.log')}")
    if not report["profileMode"] or report["profileCpu"]:
        raise RuntimeError("Comparison requires profile mode without CPU sampling")
    if report["loadedPosts"] != 200 or report["pageFetchesDuringDrag"] != 0:
        raise RuntimeError("The loaded topic or page request count changed")
    if len(report["phases"]) != 4:
        raise RuntimeError("The workload did not complete all four drags")
    output.write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()
    if args.runs < 5:
        parser.error("Use at least five runs per side")
    args.output.mkdir(parents=True, exist_ok=True)
    apps = {label: getattr(args, label).resolve() for label in ["baseline", "candidate"]}
    reports = {label: [] for label in apps}
    for repeat in range(args.runs):
        for label, app in apps.items():
            report = capture(app, args.output / f"{label}-{repeat + 1}.json")
            reports[label].append(report)
            phase = report["phases"]["warmDown"]
            print(f"{label} {repeat + 1}: warm downward build p95={phase['build']['p95Ms']} ms, "
                  f"posts={phase['visiblePostBefore']} to {phase['visiblePostAfter']}",
                  flush=True)
    shapes = {
        (tuple(report["physicalSize"]), report["pixelRatio"], report["platform"])
        for side in reports.values() for report in side
    }
    comparison_errors = []
    if len(shapes) != 1:
        comparison_errors.append("Native viewport, density, or platform changed")
    for phase in reports["baseline"][0]["phases"]:
        phases = [report["phases"][phase] for side in reports.values() for report in side]
        for endpoint in ["visiblePostBefore", "visiblePostAfter"]:
            positions = [value[endpoint] for value in phases]
            if max(positions) - min(positions) > 2:
                comparison_errors.append(
                    f"{phase} traversed different replies: {endpoint}={positions}")
        distances = [abs(value["offsetAfter"] - value["offsetBefore"]) for value in phases]
        if max(distances) > min(distances) * 1.05:
            comparison_errors.append(
                f"{phase} changed scroll distance by more than 5%: {distances}")
    summaries = {}
    for label, side in reports.items():
        summaries[label] = {}
        for phase in side[0]["phases"]:
            summaries[label][phase] = {
                "updates": [report["phases"][phase]["updates"] for report in side],
                "frames": [report["phases"][phase]["frames"] for report in side],
                "reachedPosts": [report["phases"][phase]["visiblePostAfter"] for report in side],
            }
            for metric in ["build", "raster", "total"]:
                values = [report["phases"][phase][metric]["p95Ms"] for report in side]
                summaries[label][phase][metric] = {
                    "medianP95Ms": statistics.median(values),
                    "minP95Ms": min(values), "maxP95Ms": max(values),
                }
    hashes = {
        label: hashlib.sha256((app / "Contents/Frameworks/App.framework/Versions/A/App")
                             .read_bytes()).hexdigest()
        for label, app in apps.items()
    }
    baseline = summaries["baseline"]["warmDown"]["build"]
    candidate = summaries["candidate"]["warmDown"]["build"]
    verdict = "inconclusive"
    if not comparison_errors:
        if candidate["maxP95Ms"] < baseline["minP95Ms"]:
            verdict = "faster"
        elif candidate["minP95Ms"] > baseline["maxP95Ms"]:
            verdict = "slower"
    artifact = {"runsPerSide": args.runs, "failures": 0, "verdict": verdict,
                "comparisonErrors": comparison_errors,
                "appFrameworkSha256": hashes, "summary": summaries, "runs": reports}
    (args.output / "summary.json").write_text(json.dumps(artifact, indent=2) + "\n")
    print(json.dumps(summaries, indent=2))
    if comparison_errors:
        raise RuntimeError("Inconclusive comparison: " + "; ".join(comparison_errors))


if __name__ == "__main__":
    main()
