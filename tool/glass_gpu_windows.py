#!/usr/bin/env python3
"""GPU busy time for each glass GPU budget window in a Metal System Trace.

FrameTiming raster time is raster-thread time; Metal runs the GPU work
asynchronously, so only the trace shows what heats the device. Record the
trace while integration_test/glass_gpu_budget_test.dart runs and pass both.
"""

import argparse
import bisect
from datetime import datetime
import json
import re
import statistics
import subprocess
import xml.etree.ElementTree as ET


def export(trace, *args, **kwargs):
    return subprocess.run(
        ["xcrun", "xctrace", "export", "--input", trace, *args],
        capture_output=True, text=True, check=True, **kwargs,
    ).stdout


def table(schema):
    return f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'


def union(intervals):
    total, begin, end = 0.0, None, None
    for b, e in sorted(intervals):
        if end is None or b > end:
            total += 0 if end is None else end - begin
            begin, end = b, e
        else:
            end = max(end, e)
    return total + (0 if end is None else end - begin)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace")
    parser.add_argument("log", help="flutter drive output with GLASS_GPU_PROFILE lines")
    parser.add_argument("--process", default="Runner")
    args = parser.parse_args()

    toc = export(args.trace, "--toc")
    trace_start = datetime.fromisoformat(
        re.search(r"<start-date>([^<]+)</start-date>", toc).group(1),
    ).timestamp() * 1e6
    reports = [
        json.loads(line.split("GLASS_GPU_PROFILE ", 1)[1])
        for line in open(args.log)
        if "GLASS_GPU_PROFILE " in line
    ]
    windows = sorted(
        (r["wallStartUs"], r["wallEndUs"], i) for i, r in enumerate(reports)
    )
    starts = [w[0] for w in windows]
    spans = {i: [] for i in range(len(reports))}

    # The export repeats a value once and refers back to it by id afterwards.
    process = subprocess.Popen(
        ["xcrun", "xctrace", "export", "--input", args.trace,
         "--xpath", table("metal-gpu-intervals")],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    registry = {}
    for _, element in ET.iterparse(process.stdout, events=("end",)):
        if "id" in element.attrib:
            registry[element.attrib["id"]] = element
        if element.tag != "row":
            continue
        cells = [
            registry.get(cell.attrib["ref"], cell) if "ref" in cell.attrib else cell
            for cell in element
        ]
        if len(cells) < 11 or args.process not in cells[10].attrib.get("fmt", ""):
            continue
        if int(cells[5].text or 0) != 0:
            continue
        begin = int(cells[0].text) / 1000 + trace_start
        end = begin + int(cells[1].text) / 1000
        k = bisect.bisect_right(starts, end) - 1
        while k >= 0 and windows[k][1] > begin:
            window_start, window_end, i = windows[k]
            if end > window_start:
                spans[i].append((max(begin, window_start), min(end, window_end)))
            k -= 1
    process.wait()

    groups = {}
    for i, report in enumerate(reports):
        seconds = (report["wallEndUs"] - report["wallStartUs"]) / 1e6
        key = (report["scenario"], report["glass"], report["label"])
        groups.setdefault(key, []).append(union(spans[i]) / 1000 / seconds)
    for (scenario, glass, label), busy in sorted(groups.items()):
        print(
            f"{scenario:20} glass={str(glass):5} {label:12} "
            f"GPU busy {statistics.median(busy):6.1f} ms/s "
            f"(n={len(busy)}, {min(busy):.1f}-{max(busy):.1f})"
        )
    thermal = export(args.trace, "--xpath", table("device-thermal-state-intervals"))
    states = re.findall(r'thermal-state id="\d+" fmt="([^"]+)"', thermal)
    print("thermal state:", " -> ".join(states) or "not recorded")


if __name__ == "__main__":
    main()
