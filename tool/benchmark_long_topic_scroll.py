#!/usr/bin/env python3
"""Alternate two compiled macOS long-topic profile applications."""

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
    binary = app / "Contents/MacOS/Discourse"
    environment = os.environ.copy()
    environment["FLUTTER_ENGINE_SWITCHES"] = "1"
    environment["FLUTTER_ENGINE_SWITCH_1"] = "enable-dart-profiling=false"
    process = subprocess.Popen(
        [str(binary)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
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
    deadline = time.monotonic() + 60
    try:
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1)
            except queue.Empty:
                if process.poll() is not None:
                    break
                continue
            log.append(line)
            if "LONG_TOPIC_SCROLL_PROFILE " in line:
                report = json.loads(line.split("LONG_TOPIC_SCROLL_PROFILE ", 1)[1])
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
    if report.get("streamPosts") != 16000 or report.get("loadedPosts") != 200:
        raise RuntimeError("Unexpected workload size")
    if report.get("frames", 0) <= 100 or report.get("updates", 0) <= 100:
        raise RuntimeError("Insufficient frames or scroll updates")
    excursions = report.get("excursions", [])
    if len(excursions) != 8 or any(
        abs(actual - (3600 if index % 2 == 0 else -3600)) > 1
        for index, actual in enumerate(excursions)
    ):
        raise RuntimeError("The workload did not complete every scroll leg")
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
    results = {"baseline": [], "candidate": []}
    for repeat in range(args.runs):
        for label in results:
            app = getattr(args, label).resolve()
            report = capture(app, args.output / f"{label}-{repeat + 1}.json")
            results[label].append(report)
            print(f"{label} {repeat + 1}: build={report['build']} "
                  f"raster={report['raster']}", flush=True)
    shapes = {
        (tuple(report["physicalSize"]), report["pixelRatio"])
        for reports in results.values() for report in reports
    }
    if len(shapes) != 1:
        raise RuntimeError("Viewport size or pixel ratio changed between runs")
    summaries = {}
    for label, reports in results.items():
        summaries[label] = {}
        for metric, group, value in [
            ("buildMeanMs", "build", "meanMs"),
            ("rasterMeanMs", "raster", "meanMs"),
        ]:
            values = [report[group][value] for report in reports]
            summaries[label][metric] = {
                "median": statistics.median(values), "min": min(values),
                "max": max(values), "samples": values,
            }
    hashes = {
        label: hashlib.sha256((getattr(args, label).resolve() /
            "Contents/Frameworks/App.framework/Versions/A/App").read_bytes()).hexdigest()
        for label in results
    }
    artifact = {"runsPerSide": args.runs, "failures": 0,
        "appFrameworkSha256": hashes, "summary": summaries, "runs": results}
    (args.output / "summary.json").write_text(json.dumps(artifact, indent=2) + "\n")
    print(json.dumps(artifact, indent=2))


if __name__ == "__main__":
    main()
