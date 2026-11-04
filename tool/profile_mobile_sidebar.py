#!/usr/bin/env python3
"""Summarize native sidebar frame reports, excluding idle frames.

Pass one or more integration_response_data.json files from the sidebar harness.
Profile traces are diagnostic only and must not be compared with untraced runs.
"""

import argparse
import json
import statistics
from collections import defaultdict
from pathlib import Path


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(len(ordered) * fraction))]


def summarize(report):
    if report["debug"] or not report["profile"]:
        raise ValueError("Use a native profile build for frame comparisons")
    samples = report["samples"]
    if len(samples) != 24:
        raise ValueError(f"Expected 24 completed transitions; got {len(samples)}")
    actions = defaultdict(list)
    for sample in samples:
        actions[sample["action"]].append(sample)
    result = {}
    budget = 1000 / report["refreshRate"]
    for action, windows in actions.items():
        frames = [
            frame
            for frame in report["frames"]
            if any(w["startUs"] <= frame["startUs"] <= w["endUs"] for w in windows)
        ]
        if not frames or len(windows) != 6:
            raise ValueError(f"Missing frames or completed transitions for {action}")
        result[action] = {
            "transitions": len(windows),
            "frames": len(frames),
            "elapsedMedianMs": statistics.median(w["elapsedMs"] for w in windows),
            "settleMedianMs": statistics.median(w["settleMs"] for w in windows),
            "buildP50Ms": percentile([f["buildMs"] for f in frames], .5),
            "buildP95Ms": percentile([f["buildMs"] for f in frames], .95),
            "rasterP50Ms": percentile([f["rasterMs"] for f in frames], .5),
            "rasterP95Ms": percentile([f["rasterMs"] for f in frames], .95),
            "overBudgetPercent": 100 * sum(
                max(f["buildMs"], f["rasterMs"]) > budget for f in frames
            ) / len(frames),
        }
    return {"trace": report["trace"], "frameBudgetMs": budget, "actions": result}


def trace_summary(events):
    stacks = defaultdict(list)
    totals = defaultdict(lambda: [0, 0])
    for event in events:
        thread = (event.get("pid"), event.get("tid"))
        phase = event.get("ph")
        if phase == "B":
            stacks[thread].append(event)
        elif phase == "E" and stacks[thread]:
            start = stacks[thread].pop()
            duration = event["ts"] - start["ts"]
            totals[start["name"]][0] += duration
            totals[start["name"]][1] += 1
        elif phase == "X":
            totals[event["name"]][0] += event["dur"]
            totals[event["name"]][1] += 1
    return [
        {"event": name, "inclusiveMs": duration / 1000, "count": count}
        for name, (duration, count) in sorted(
            totals.items(), key=lambda entry: -entry[1][0]
        )[:60]
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--trace", action="store_true")
    args = parser.parse_args()
    for path in args.reports:
        data = json.loads(path.read_text())
        result = {"file": str(path), **summarize(data["sidebar_frames"])}
        if args.trace:
            events = data["sidebar_timeline"]["traceEvents"]
            times = [event["ts"] for event in events if "ts" in event]
            samples = data["sidebar_frames"]["samples"]
            result["trace"] = {
                "spanMs": (max(times) - min(times)) / 1000,
                "coversAllSamples": min(times) <= samples[0]["startUs"]
                and max(times) >= samples[-1]["endUs"],
                "events": trace_summary(events),
            }
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
