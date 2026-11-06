#!/usr/bin/env python3
"""Compare runs of tool/profile_desktop_scroll.py, baseline against candidate.

Give each run's --output prefix, in the order the runs alternated:

  python3 tool/compare_desktop_scroll_profiles.py \\
      --baseline /tmp/ab/1-base/run /tmp/ab/3-base/run \\
      --candidate /tmp/ab/2-cand/run /tmp/ab/4-cand/run

For every pass it prints, per run: the Dart CPU the UI isolate spent inside
frames, building and laying out (from the harness's CPU samples, when the
build profiled CPU), frame build and raster times, the scroll distance, the
elements and render objects mounted per row at the pass's end, and the
other processes' CPU while the pass ran. Runs that shared the machine
(background CPU far above the others) should be discarded rather than
averaged: they change frame counts and sampling.
"""

import argparse
import json
import re
import statistics
from pathlib import Path

FRAME = re.compile(r"handleBeginFrame|handleDrawFrame|drawFrame", re.I)
SAMPLE_MS = 0.25  # the harness samples every 250 microseconds


def cpu(folded):
    """Milliseconds inside frames, building and laying out."""
    totals = {"frames": 0, "build": 0, "layout": 0}
    for line in folded.splitlines():
        stack, count = line.rsplit(" ", 1)
        frames = stack.split(";")
        count = int(count)
        if any(FRAME.search(frame) for frame in frames):
            totals["frames"] += count
        if any(frame.startswith("BuildOwner.buildScope") for frame in frames):
            totals["build"] += count
        if any(frame.startswith("PipelineOwner.flushLayout") for frame in frames):
            totals["layout"] += count
    return {key: value * SAMPLE_MS for key, value in totals.items()}


def background(prefix, phase_name):
    path = Path(str(prefix) + ".phases.json")
    if not path.exists():
        return None
    saved = json.loads(path.read_text())
    start, end = saved["phases"].get(phase_name, (None, None))
    samples = [s[1] for s in saved.get("load", []) if start and start <= s[0] <= end]
    return statistics.mean(samples) if samples else None


def describe(prefix, label):
    data = json.loads(Path(str(prefix) + ".json").read_text())
    rows = []
    for name, phase in data["summary"]["phases"].items():
        short = name.split(".", 1)[-1]
        row = {
            "run": f"{label} {Path(prefix).parent.name}",
            "phase": short,
            "frames": phase["frames"],
            "moved": round(phase["moved"]),
            "build mean": phase["build"]["meanMs"],
            "build p99": phase["build"]["p99Ms"],
            "build >8.3": phase["build"]["over8ms"],
            "raster mean": phase["raster"]["meanMs"],
        }
        if folded := data.get(f"cpuFolded.{name}"):
            row.update({f"cpu {k}": v for k, v in cpu(folded).items()})
        if elements := data.get(f"elements.{name}"):
            rows_mounted = max(elements["rows"], 1)
            row["elements/row"] = elements["listElements"] / rows_mounted
            row["render objects/row"] = elements["listRenderObjects"] / rows_mounted
        if (load := background(prefix, name)) is not None:
            row["background %"] = load
        rows.append(row)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--baseline", nargs="+", required=True, type=Path)
    parser.add_argument("--candidate", nargs="+", required=True, type=Path)
    args = parser.parse_args()
    rows = [r for p in args.baseline for r in describe(p, "baseline")]
    rows += [r for p in args.candidate for r in describe(p, "candidate")]
    columns = ["frames", "moved", "cpu frames", "cpu build", "cpu layout",
               "build mean", "build p99", "build >8.3", "raster mean",
               "elements/row", "render objects/row", "background %"]
    for phase in dict.fromkeys(r["phase"] for r in rows):
        selected = [r for r in rows if r["phase"] == phase]
        present = [c for c in columns if any(c in r for r in selected)]
        print(f"\n== {phase}")
        print(f"{'run':28}" + "".join(f"{c:>19}" for c in present))
        for row in selected:
            cells = "".join(
                f"{row[c]:>19.2f}" if isinstance(row.get(c), float)
                else f"{row.get(c, ''):>19}" for c in present)
            print(f"{row['run']:28}{cells}")
        for side in ("baseline", "candidate"):
            side_rows = [r for r in selected if r["run"].startswith(side)]
            medians = "".join(
                f"{statistics.median(r[c] for r in side_rows if c in r):>19.2f}"
                if any(c in r for r in side_rows) else f"{'':>19}" for c in present)
            print(f"{side + ' median':28}{medians}")


if __name__ == "__main__":
    main()
