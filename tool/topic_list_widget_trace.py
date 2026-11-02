#!/usr/bin/env python3
"""Summarize --widget-trace captures without treating tracing as frame timing."""

import argparse
import collections
import gzip
import json
from pathlib import Path


def summarize(events):
    stacks = collections.defaultdict(list)
    totals = collections.defaultdict(lambda: [0, 0, 0])
    paths = collections.defaultdict(lambda: [0, 0])
    unmatched = 0
    for event in events:
        stack = stacks[(event.get("pid"), event.get("tid"))]
        kind = event.get("ph")
        if kind == "B":
            stack.append([event["name"], event["ts"], 0])
        elif kind == "E":
            if not stack:
                unmatched += 1
                continue
            name, start, children = stack.pop()
            duration = event["ts"] - start
            own = duration - children
            if stack:
                stack[-1][2] += duration
            total = totals[name]
            total[0] += 1
            total[1] += duration
            total[2] += own
            path = paths[" > ".join([entry[0] for entry in stack] + [name])]
            path[0] += 1
            path[1] += own
    return dict(
        eventCount=len(events), unmatchedEnds=unmatched,
        unclosedBegins=sum(map(len, stacks.values())),
        byName={name: dict(count=value[0], inclusiveUs=value[1], selfUs=value[2])
                for name, value in sorted(totals.items(), key=lambda x: -x[1][2])},
        selfTimePaths=[dict(path=path, count=value[0], selfUs=value[1])
                       for path, value in sorted(paths.items(), key=lambda x: -x[1][1])[:60]],
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = json.loads(args.capture.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    result = {}
    for key, trace in data.items():
        if not key.startswith("widgetTrace."):
            continue
        phase = key.split(".", 1)[1]
        with gzip.open(args.output / f"{phase}.trace.json.gz", "wt") as stream:
            json.dump(trace, stream)
        result[phase] = summarize(trace["traceEvents"])
        if (result[phase]["unmatchedEnds"] or result[phase]["unclosedBegins"]
                or not result[phase]["byName"]):
            raise ValueError(f"Incomplete synchronous widget trace: {phase}")
    if not result:
        parser.error("Capture contains no widget traces")
    (args.output / "widget-summary.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({phase: dict(eventCount=r["eventCount"],
                                 unmatchedEnds=r["unmatchedEnds"],
                                 unclosedBegins=r["unclosedBegins"],
                                 byName=dict(list(r["byName"].items())[:30]))
                      for phase, r in result.items()}, indent=2))


if __name__ == "__main__":
    main()
