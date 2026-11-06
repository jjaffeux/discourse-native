"""Garbage collection on the UI isolate's thread, measured against frames.

The desktop scroll harnesses save a pass's GC timeline (Chrome trace
events of the VM's `GC` stream) and its frame timings as
`[buildStart, buildUs, rasterUs, rasterFinish, vsyncStart]`. A collection
the mutator runs while a frame builds adds its whole pause to that frame;
one it runs in the idle time between frames costs nothing visible.
"""

import re

UI_THREAD = re.compile(r"io\.flutter\.(ui|platform)")
BUDGET_US = 8333


def _ui_tid(events):
    names = {
        e["tid"]: e["args"]["name"]
        for e in events
        if e.get("ph") == "M" and e.get("name") == "thread_name"
    }
    collecting = {
        e["tid"] for e in events
        if e.get("name") in ("CollectNewGeneration", "CollectOldGeneration")
    }
    candidates = [tid for tid, name in names.items() if UI_THREAD.search(name)]
    for tid in candidates:
        if tid in collecting:
            return tid
    return candidates[0] if candidates else None


def pauses(events):
    """Outermost GC spans on the UI thread as (start, end, name, args)."""
    tid = _ui_tid(events)
    spans, stack = [], []
    timed = sorted(
        (e for e in events if e.get("tid") == tid and e.get("cat") == "GC"
         and e.get("ph") in ("B", "E", "X")),
        key=lambda e: (e["ts"], e["ph"] != "E"))
    for e in timed:
        if e["ph"] == "X":
            if not stack:
                spans.append((e["ts"], e["ts"] + e.get("dur", 0), e["name"], e.get("args", {})))
        elif e["ph"] == "B":
            stack.append(e)
        elif stack:
            begin = stack.pop()
            if not stack:
                args = {**begin.get("args", {}), **e.get("args", {})}
                spans.append((begin["ts"], e["ts"], begin["name"], args))
    return spans


def _kb(args, key):
    try:
        return float(args.get(key, "nan"))
    except ValueError:
        return float("nan")


def report(events, frames):
    """What collection cost the pass, and how much of it frames waited for."""
    spans = pauses(events or [])
    if not spans:
        return None
    builds = sorted((f[0], f[0] + f[1]) for f in frames)

    def inside(start, end):
        total = 0
        for b0, b1 in builds:
            if b0 >= end:
                break
            if b1 > start:
                total += min(end, b1) - max(start, b0)
        return total

    scavenges = [s for s in spans if s[2] == "CollectNewGeneration"]
    old = [s for s in spans if s[2] == "CollectOldGeneration"]
    promoted = sum(
        max(0.0, _kb(a, "After.Old.Used (kB)") - _kb(a, "Before.Old.Used (kB)"))
        for _, _, _, a in scavenges)
    over = [b for b in builds if b[1] - b[0] > BUDGET_US]
    over_gc = [b for b in over if any(s[0] < b[1] and s[1] > b[0] for s in spans)]
    in_frame = [s for s in scavenges if inside(s[0], s[1]) > 0]
    return {
        "scavenges": len(scavenges),
        "scavenge ms": sum(e - s for s, e, _, _ in scavenges) / 1000,
        "scavenge max ms": max((e - s for s, e, _, _ in scavenges), default=0) / 1000,
        "scavenges in frames": len(in_frame),
        "old collections": len(old),
        "gc ms in frames": sum(inside(s, e) for s, e, _, _ in spans) / 1000,
        "promoted MB": promoted / 1024,
        "over 8.3": len(over),
        "over 8.3 with gc": len(over_gc),
    }


def table(name, events, frames):
    summary = report(events, frames)
    if summary is None:
        return []
    lines = ["", f"=== GC {name} (UI thread) ==="]
    lines += [f"  {key:22} {value:10.1f}" if isinstance(value, float)
              else f"  {key:22} {value:10d}" for key, value in summary.items()]
    lines.append("  scavenges (ms, new kB before -> after, old kB before -> after, in frame):")
    builds = [(f[0], f[0] + f[1]) for f in frames]
    for start, end, name_, args in pauses(events):
        if name_ != "CollectNewGeneration":
            continue
        waited = any(b0 < end and b1 > start for b0, b1 in builds)
        lines.append(
            f"    {(end - start) / 1000:6.1f}  {args.get('Before.New.Used (kB)', '?'):>6} -> "
            f"{args.get('After.New.Used (kB)', '?'):>6}  {args.get('Before.Old.Used (kB)', '?'):>7} -> "
            f"{args.get('After.Old.Used (kB)', '?'):>7}  {'frame' if waited else 'idle'}")
    return lines


def allocation_table(name, allocations, top=30):
    if not allocations:
        return []
    lines = ["", f"=== Allocations {name} ==="]
    for key in ("accumulated", "current"):
        rows = allocations.get(key) or []
        lines.append(f"  {key} (MB, instances):")
        for cls, library, size, count in rows[:top]:
            lines.append(f"    {size / 1048576:8.2f} {count:9d}  {cls} [{library}]")
    return lines
