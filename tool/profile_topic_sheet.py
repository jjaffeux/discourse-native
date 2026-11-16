#!/usr/bin/env python3
"""Summarize the phone topic sheet harness, first actions apart from repeats.

Pass integration_response_data.json files written by
integration_test/topic_sheet_open_profile_test.dart, grouped with --baseline
and --candidate, or alone to summarize one set. Each action window runs from
its trigger until frames settle. UI is the frame's build, layout and paint
time; a late frame took longer than one refresh from vsync to raster finish.
The first open includes the phone bar's one peek per session.
"""

import argparse
import json
import statistics
from collections import defaultdict


def load(path):
    with open(path) as handle:
        report = json.load(handle)["topic_sheet_frames"]
    if report["debug"] or not report["profile"]:
        raise ValueError(f"{path}: use a profile build for frame comparisons")
    return report


def windows(report):
    budget_us = 1e6 / report["refreshRate"]
    frames = report["frames"]
    for sample in report["samples"]:
        inside = [
            f for f in frames if sample["startUs"] <= f["vsyncUs"] <= sample["endUs"]
        ]
        first = next((f for f in frames if f["startUs"] >= sample["startUs"]), None)
        yield sample, {
            "firstFrameMs": (first["rasterEndUs"] - sample["startUs"]) / 1000
            if first
            else float("nan"),
            "frames": len(inside),
            "uiMaxMs": max((f["buildMs"] for f in inside), default=0),
            "uiSumMs": sum(f["buildMs"] for f in inside),
            "rasterSumMs": sum(f["rasterMs"] for f in inside),
            "late": sum(f["rasterEndUs"] - f["vsyncUs"] > budget_us for f in inside),
        }


def summarize(paths):
    groups = defaultdict(list)
    for path in paths:
        for sample, stats in windows(load(path)):
            which = "first" if sample["repeat"] == 0 else "repeat"
            groups[(sample["action"], which)].append(stats)
    return {
        key: {
            name: statistics.median(s[name] for s in stats) for name in stats[0]
        }
        | {"n": len(stats)}
        for key, stats in groups.items()
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="*")
    parser.add_argument("--baseline", nargs="*", default=[])
    parser.add_argument("--candidate", nargs="*", default=[])
    args = parser.parse_args()
    sets = {"runs": args.reports} if args.reports else {}
    if args.baseline:
        sets["baseline"] = args.baseline
    if args.candidate:
        sets["candidate"] = args.candidate
    columns = ["n", "firstFrameMs", "frames", "uiMaxMs", "uiSumMs", "rasterSumMs", "late"]
    print(f"{'set':<10}{'action':<11}{'which':<7}" + "".join(f"{c:>13}" for c in columns))
    summaries = {name: summarize(paths) for name, paths in sets.items()}
    for key in sorted({key for summary in summaries.values() for key in summary}):
        for name, summary in summaries.items():
            if key in summary:
                row = summary[key]
                print(
                    f"{name:<10}{key[0]:<11}{key[1]:<7}"
                    + "".join(f"{row[c]:>13.1f}" for c in columns)
                )


if __name__ == "__main__":
    main()
