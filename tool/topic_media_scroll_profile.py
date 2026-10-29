#!/usr/bin/env python3
"""Summarize integration_test/topic_media_scroll_profile_test.dart output.

Reads the driver's response data and writes, next to --output:

  <output>.<phase>.svg     a flame graph of the UI isolate's CPU samples
  <output>.<phase>.focused.svg
                           the same graph without native frames and the
                           element, zone and binding plumbing between them
  <output>.<phase>.folded  the samples in collapsed-stack format
  <output>.txt             frame timing per phase, the hottest functions by
                           self and by inclusive time, and the timeline's
                           attribution per thread

The timeline window runs with per-widget build, layout and paint events, so
its durations attribute work but overstate it.
"""

import argparse
import collections
import html
import json
import re
import sys


def flame_svg(stacks, title, width=1600, row=16):
    root = {"name": "all", "value": 0, "children": {}}
    for frames, count in stacks:
        node = root
        node["value"] += count
        for frame in frames:
            child = node["children"].setdefault(
                frame, {"name": frame, "value": 0, "children": {}}
            )
            child["value"] += count
            node = child

    total = root["value"] or 1
    rects = []
    depth_max = 0

    def walk(node, x, depth):
        nonlocal depth_max
        depth_max = max(depth_max, depth)
        w = node["value"] / total * width
        if w >= 1:
            rects.append((x, depth, w, node["name"], node["value"]))
        cx = x
        for child in sorted(node["children"].values(), key=lambda c: c["name"]):
            walk(child, cx, depth + 1)
            cx += child["value"] / total * width

    walk(root, 0.0, 0)
    height = (depth_max + 2) * row + 40
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" '
        f'height="{height}" font-family="Menlo, monospace" font-size="11">',
        f'<text x="8" y="20" font-size="14">{html.escape(title)}</text>',
    ]
    for x, depth, w, name, value in rects:
        y = height - (depth + 1) * row
        library = name.rsplit("[", 1)[-1].rstrip("]") if "[" in name else ""
        hue = {
            "flutter": 30,
            "app": 120,
            "dart": 200,
        }.get(library, 280)
        light = 55 + (hash(name) % 20)
        pct = value / total * 100
        label = html.escape(name)
        out.append(
            f'<g><title>{label} ({value} samples, {pct:.2f}%)</title>'
            f'<rect x="{x:.2f}" y="{y}" width="{w:.2f}" height="{row - 1}" '
            f'fill="hsl({hue},70%,{light}%)" rx="2"/>'
        )
        if w > 40:
            chars = int(w / 6.6)
            text = name if len(name) <= chars else name[: max(0, chars - 2)] + ".."
            out.append(
                f'<text x="{x + 3:.2f}" y="{y + row - 4}">{html.escape(text)}</text>'
            )
        out.append("</g>")
    out.append("</svg>")
    return "\n".join(out)


# Frames that carry work between the frames that name it: element mounting
# and rebuilding, layout recursion, zones, bindings, and native entry points.
_PLUMBING = re.compile(
    r"\[Native\]$"
    r"|^(_?[A-Za-z]*Element|BuildOwner|BuildScope)\."
    r"|^(_rootRun|_CustomZone|_invoke|_drawFrame|_beginFrame|PlatformDispatcher)"
    r"|^_MixinApplication\d+&BindingBase"
    r"|^(LiveTestWidgetsFlutterBinding|TestPlatformDispatcher)\."
    r"|^RenderObject\.(layout|_layoutWithoutResize|invokeLayoutCallback) "
    r"|^(ChildLayoutHelper|invokeLayoutCallback|runLayoutCallback)\b"
    r"|^_MixinApplication\d+&RenderBox"
)


def focused(stacks):
    merged = collections.Counter()
    for stack, count in stacks:
        kept = tuple(frame for frame in stack if not _PLUMBING.search(frame))
        merged[kept or ("(plumbing only)",)] += count
    return [(list(stack), count) for stack, count in merged.items()]


def cpu_tables(stacks, top):
    self_counts = collections.Counter()
    inclusive = collections.Counter()
    total = 0
    for frames, count in stacks:
        total += count
        self_counts[frames[-1]] += count
        for frame in set(frames):
            inclusive[frame] += count
    lines = [f"CPU samples: {total}", "", "Self time:"]
    for name, count in self_counts.most_common(top):
        lines.append(f"  {count / total * 100:6.2f}%  {name}")
    lines += ["", "Inclusive time:"]
    for name, count in inclusive.most_common(top):
        lines.append(f"  {count / total * 100:6.2f}%  {name}")
    return lines


# Frames that say where a frame's time went, rather than how it got there.
_FRAMEWORK_SPINE = (
    "_rootRun",
    "_CustomZone",
    "_invoke",
    "Binding",
    "_drawFrame",
    "_beginFrame",
    "PlatformDispatcher",
    "Timeline",
    "[Native]",
)


def slow_frame_tables(stacks, per_frame=6):
    frames = collections.defaultdict(list)
    for stack, count in stacks:
        frames[stack[0]].append((stack[1:], count))
    lines = [f"Slow frames: {len(frames)}"]
    for root in sorted(frames):
        inclusive = collections.Counter()
        total = 0
        for stack, count in frames[root]:
            total += count
            for name in set(stack):
                if not any(part in name for part in _FRAMEWORK_SPINE):
                    inclusive[name] += count
        hottest = ", ".join(
            f"{name.split(' [')[0]} {count}" for name, count in inclusive.most_common(per_frame)
        )
        lines.append(f"  {root} ({total} samples): {hottest}")
    return lines


def timeline_tables(events, top):
    names = {}
    for e in events:
        if e.get("ph") == "M" and e.get("name") == "thread_name":
            names[e["tid"]] = e["args"]["name"]
    by_thread = collections.defaultdict(list)
    for e in events:
        if e.get("ph") in ("B", "E", "X"):
            by_thread[e["tid"]].append(e)

    lines = []
    for tid, items in sorted(by_thread.items(), key=lambda kv: -len(kv[1])):
        thread = names.get(tid, str(tid))
        items.sort(key=lambda e: (e["ts"], 0 if e["ph"] == "E" else 1))
        totals = collections.Counter()
        selfs = collections.Counter()
        counts = collections.Counter()
        stack = []
        complete = []
        for e in items:
            if e["ph"] == "X":
                complete.append((e["ts"], e["ts"] + e.get("dur", 0), e["name"]))
            elif e["ph"] == "B":
                stack.append([e["name"], e["ts"], 0])
            elif stack:
                name, start, child = stack.pop()
                dur = e["ts"] - start
                totals[name] += dur
                selfs[name] += dur - child
                counts[name] += 1
                if stack:
                    stack[-1][2] += dur
        for start, end, name in complete:
            totals[name] += end - start
            counts[name] += 1
        frames = counts.get("Animator::BeginFrame") or counts.get(
            "GPURasterizer::Draw"
        )
        if not totals:
            continue
        lines += [
            "",
            f"Thread {thread} ({len(items)} events"
            + (f", {frames} frames" if frames else "")
            + "): top by inclusive ms (count, self ms)",
        ]
        for name, dur in totals.most_common(top):
            lines.append(
                f"  {dur / 1000:9.1f} ms  x{counts[name]:<6} self {selfs[name] / 1000:8.1f}  {name}"
            )
    return lines


def parse_folded(folded):
    stacks = []
    for line in folded.splitlines():
        stack, _, count = line.rpartition(" ")
        if stack:
            stacks.append((stack.split(";"), int(count)))
    return stacks


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("response", help="integration_response_data.json")
    parser.add_argument("--output", required=True, help="output path prefix")
    parser.add_argument("--top", type=int, default=45)
    args = parser.parse_args()

    with open(args.response) as f:
        data = json.load(f)
    data = data.get("data", data)

    summary = data.get("summary", {})
    label = summary.get("label", "profile")
    lines = ["Summary:", json.dumps(summary, indent=2)]
    for key in sorted(k for k in data if k.startswith("cpuFolded.")):
        phase = key.split(".", 1)[1]
        folded = data[key]
        stacks = parse_folded(folded)
        base, _, slow = phase.partition(".")
        lines += ["", f"=== {phase} ==="]
        if slow:
            lines += slow_frame_tables(stacks)
            # One graph for every slow frame, rather than a tower per frame.
            stacks = [(stack[1:], count) for stack, count in stacks]
            subject = "frames that built for more than 4 ms"
        else:
            subject = f"{summary.get('phases', {}).get(base, {}).get('frames')} frames"
            timings = data.get(f"frameTimings.{base}")
            if timings:
                worst = sorted(timings, key=lambda t: -(t[1] + t[2]))[:15]
                lines.append("Worst frames (build us, raster us):")
                for start, build, raster, _ in worst:
                    lines.append(f"  t={start} build={build} raster={raster}")
        prefix = f"{args.output}.{phase}"
        with open(prefix + ".folded", "w") as f:
            f.write(folded)
        title = (
            f"{label} {phase}: UI isolate CPU while scrolling "
            f"({summary.get('platform')}, {subject})"
        )
        with open(prefix + ".svg", "w") as f:
            f.write(flame_svg(stacks, title))
        with open(prefix + ".focused.svg", "w") as f:
            f.write(flame_svg(focused(stacks), title + ", plumbing removed"))
        lines += cpu_tables(stacks, args.top)
    timeline = data.get("timeline")
    if timeline:
        lines += timeline_tables(timeline.get("traceEvents", []), args.top)
    with open(args.output + ".txt", "w") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines[:80]))


if __name__ == "__main__":
    sys.exit(main())
