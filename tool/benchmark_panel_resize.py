#!/usr/bin/env python3
"""Alternate compiled macOS panel-resize profile applications."""

import argparse
import json
import os
from pathlib import Path
import queue
import re
import statistics
import subprocess
import threading
import time

CASES = ("sidebar", "main-panel", "reader-scroll")
MARKER = "PANEL_RESIZE_FRAMES "


def gpu_utilization():
    """System-wide GPU busy share, which includes the window server's work."""
    try:
        text = subprocess.run(
            ["ioreg", "-r", "-d", "1", "-c", "IOAccelerator"],
            capture_output=True, text=True, timeout=2,
        ).stdout
    except subprocess.TimeoutExpired:
        return None
    match = re.search(r'"Device Utilization %"=(\d+)', text)
    return int(match.group(1)) if match else None


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
    samples = []
    sampling = threading.Event()

    # System glass is composited outside the app, so its GPU time never
    # reaches FrameTiming; the device's own counter sees both.
    def sample_gpu():
        while not sampling.is_set():
            value = gpu_utilization()
            if value is not None:
                samples.append((time.time() * 1e6, value))
            sampling.wait(0.1)

    threading.Thread(target=sample_gpu, daemon=True).start()
    log = []
    reports = {}
    passed = False
    deadline = time.monotonic() + 120
    try:
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1)
            except queue.Empty:
                if process.poll() is not None:
                    break
                continue
            log.append(line)
            if MARKER in line:
                report = json.loads(line.split(MARKER, 1)[1])
                reports[report["case"]] = report
            if "All tests passed!" in line:
                passed = True
                break
    finally:
        sampling.set()
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        output.with_suffix(".log").write_text("".join(log))
    if not passed or set(reports) != set(CASES):
        raise RuntimeError(f"Workload failed; inspect {output.with_suffix('.log')}")
    if any(report["frames"] < 120 for report in reports.values()):
        raise RuntimeError("A case drew fewer than 120 measured frames")
    # Each drag grows its pane by 60 two-pixel steps before shrinking it.
    if any(abs(reports[case].get("grewPx", 0) - 120) > 1
           for case in ("sidebar", "main-panel")):
        raise RuntimeError("A drag did not resize its pane by 120 pixels")
    for report in reports.values():
        window = [
            value for at, value in samples
            if report["wallStartUs"] <= at <= report["wallEndUs"]
        ]
        report["gpuBusyPct"] = statistics.mean(window) if window else None
    output.write_text(json.dumps(reports, indent=2) + "\n")
    return reports


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--app", action="append", required=True, metavar="LABEL=PATH",
        help="a compiled Discourse.app; repeat for each side",
    )
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()
    if args.runs < 5:
        parser.error("--runs must be at least 5")
    apps = []
    for value in args.app:
        label, _, path = value.partition("=")
        app = Path(path)
        if not label or not (app / "Contents/MacOS/Discourse").is_file():
            parser.error(f"not a compiled application: {value}")
        apps.append((label, app))
    args.output.mkdir(parents=True, exist_ok=True)

    results = {label: [] for label, _ in apps}
    failures = []
    for run in range(args.runs):
        # Rotate the order so warmup and drift favour no side.
        for label, app in apps[run % len(apps):] + apps[:run % len(apps)]:
            for attempt in range(2):
                output = args.output / f"{label}-{run + 1}.json"
                try:
                    results[label].append(capture(app, output))
                    break
                except RuntimeError as error:
                    failures.append(f"{label} run {run + 1}: {error}")
                    print(f"run {run + 1} {label} failed: {error}", flush=True)
                    output.with_suffix(".log").rename(
                        output.with_suffix(f".failed{attempt + 1}.log")
                    )
            else:
                raise RuntimeError(f"{label} failed twice in run {run + 1}")
            print(f"run {run + 1} {label} done", flush=True)

    # Glass cost follows the window's pixel count, and a zoomed window does not
    # always reach the same size, so sides are compared within one size only.
    groups = {}
    for label, runs in results.items():
        for run in runs:
            width, height, ratio = run["sidebar"]["view"]
            key = f"{label}@{width:g}x{height:g}@{ratio:g}x"
            groups.setdefault(key, []).append(run)

    summary = {}
    for key, runs in groups.items():
        summary[key] = {"runs": len(runs)}
        for case in CASES:
            metrics = {}
            for phase in ("build", "raster"):
                for metric in ("meanMs", "p50Ms", "p95Ms"):
                    values = [run[case][phase][metric] for run in runs]
                    metrics[f"{phase}.{metric}"] = {
                        "median": statistics.median(values),
                        "min": min(values),
                        "max": max(values),
                    }
                values = [run[case][phase]["over8ms"] / run[case]["frames"]
                          for run in runs]
                metrics[f"{phase}.over8msShare"] = {
                    "median": statistics.median(values),
                    "min": min(values),
                    "max": max(values),
                }
            values = [run[case]["gpuBusyPct"] for run in runs
                      if run[case].get("gpuBusyPct") is not None]
            if values:
                metrics["gpuBusyPct"] = {
                    "median": statistics.median(values),
                    "min": min(values),
                    "max": max(values),
                }
            summary[key][case] = metrics
    summary["failures"] = failures
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"failed captures: {len(failures)}")
    for case in CASES:
        print(f"\n{case}")
        for key in sorted(groups):
            row = summary[key][case]
            print(
                f"  {key} n={summary[key]['runs']}  "
                + "  ".join(
                    f"{metric} {row[metric]['median']:.2f} "
                    f"[{row[metric]['min']:.2f}-{row[metric]['max']:.2f}]"
                    for metric in (
                        "build.meanMs", "build.p95Ms",
                        "raster.meanMs", "raster.p95Ms", "gpuBusyPct",
                    )
                    if metric in row
                )
            )


if __name__ == "__main__":
    main()
