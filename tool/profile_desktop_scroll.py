#!/usr/bin/env python3
"""Run integration_test/desktop_scroll_profile_test.dart once and report it.

Build the app first (see docs/performance/desktop-scrolling.md), then:

  python3 tool/profile_desktop_scroll.py build/macos/Build/Products/Profile/Discourse.app \
      --output /tmp/desktop-scroll

One launch records, for every pass the test brackets with
DESKTOP_SCROLL_PHASE lines:

  - frame timings and the UI isolate's Dart CPU samples (from the test),
  - the Dart, Embedder and GC timeline (from the test), and for a timing
    pass the GC timeline alone, which covers the whole pass, with the
    classes it allocated,
  - an Instruments Time Profiler trace of the whole process, so native
    frames on the raster and platform threads are attributed per pass, with
    the core tier each sample ran on,
  - the system-wide GPU busy share, which includes the window server.

--trace metal records a Metal System Trace instead. It holds the same CPU
samples, and adds every GPU encoder of every process, so GPU time is
attributed per pass to the app's own render passes, the window server and
anything else on the GPU.

It writes <output>.txt (all tables), <output>.<pass>.svg / .focused.svg /
.folded for Dart CPU, <output>.<pass>.native.<thread>.svg / .folded for
native threads, and keeps the raw JSON and trace beside them.
"""

import argparse
import bisect
import collections
import importlib.util
import json
import os
from pathlib import Path
import queue
import re
import signal
import statistics
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET

_here = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "topic_media_scroll_profile", _here / "topic_media_scroll_profile.py"
)
media = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(media)
_spec = importlib.util.spec_from_file_location("dart_gc_pauses", _here / "dart_gc_pauses.py")
gc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gc)

PHASE = re.compile(r"DESKTOP_SCROLL_PHASE (start|end) (\S+) (\d+)")
NUMBERED = re.compile(r"/\d+")


def gpu_utilization():
    try:
        text = subprocess.run(
            ["ioreg", "-r", "-d", "1", "-c", "IOAccelerator"],
            capture_output=True, text=True, timeout=2,
        ).stdout
    except subprocess.TimeoutExpired:
        return None
    match = re.search(r'"Device Utilization %"=(\d+)', text)
    return int(match.group(1)) if match else None


TEMPLATES = {"time": "Time Profiler", "metal": "Metal System Trace"}


def record(pid, template, path, seconds=None):
    subprocess.run(["rm", "-rf", str(path)])
    return subprocess.Popen(
        ["xcrun", "xctrace", "record", "--template", template,
         "--attach", str(pid), "--output", str(path), "--no-prompt"]
        + ([f"--time-limit", f"{seconds}s"] if seconds else []),
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )


def phase_trace(output, name):
    return output.with_name(f"{output.name}.{name}.trace")


def run(app, output, timeout, trace, gpu_phases, gpu_seconds):
    binary = app / "Contents/MacOS/Discourse"
    process = subprocess.Popen(
        [str(binary)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )
    lines = queue.Queue()
    threading.Thread(
        target=lambda: [lines.put(line) for line in process.stdout], daemon=True
    ).start()

    gpu = []
    stop = threading.Event()

    def sample_gpu():
        while not stop.is_set():
            value = gpu_utilization()
            if value is not None:
                gpu.append((time.time() * 1e6, value))
            stop.wait(0.1)

    threading.Thread(target=sample_gpu, daemon=True).start()

    # Other processes' CPU, so a comparison can discard runs that shared the
    # machine with a build, a test suite or a game.
    load = []

    def sample_load():
        while not stop.is_set():
            try:
                rows = subprocess.run(
                    ["ps", "-axo", "pcpu=,pid=,comm="],
                    capture_output=True, text=True, timeout=2,
                ).stdout.splitlines()
            except subprocess.TimeoutExpired:
                rows = []
            others = []
            for row in rows:
                parts = row.split(None, 2)
                if len(parts) == 3 and parts[1] != str(process.pid):
                    others.append((float(parts[0]), parts[2]))
            if others:
                busiest = max(others)
                load.append((time.time() * 1e6, sum(c for c, _ in others),
                             busiest[0], Path(busiest[1]).name))
            stop.wait(2)

    threading.Thread(target=sample_load, daemon=True).start()

    # A Metal System Trace of a whole run is tens of gigabytes, more than
    # xctrace can export, so it records a window at the start of each
    # selected pass instead.
    recorders = []
    if trace == "time":
        recorders.append(record(process.pid, TEMPLATES[trace], output.with_suffix(".trace")))
    log, phases, starts = [], {}, {}
    result_path = None
    passed = False
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1)
            except queue.Empty:
                if process.poll() is not None:
                    break
                continue
            log.append(line)
            if match := PHASE.search(line):
                kind, name, us = match.groups()
                if kind == "start":
                    starts[name] = int(us)
                    if (trace == "metal" and re.search(gpu_phases, name)
                            and all(r.poll() is not None for r in recorders)):
                        recorders.append(record(
                            process.pid, TEMPLATES[trace],
                            phase_trace(output, name), gpu_seconds))
                else:
                    phases[name] = (starts.pop(name), int(us))
                print(line.rstrip(), flush=True)
            if "DESKTOP_SCROLL_PROFILE " in line:
                result_path = line.split("DESKTOP_SCROLL_PROFILE ", 1)[1].strip()
            if "All tests passed!" in line:
                passed = True
                break
            if "Some tests failed" in line or "EXCEPTION CAUGHT" in line:
                print(line.rstrip(), flush=True)
    finally:
        stop.set()
        for recorder in recorders:
            if recorder.poll() is None:
                recorder.send_signal(signal.SIGINT)
            try:
                recorder.wait(timeout=300)
            except subprocess.TimeoutExpired:
                recorder.kill()
            log.append("\n[xctrace]\n" + (recorder.stdout.read() or ""))
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        output.with_suffix(".log").write_text("".join(log))
    if not passed or result_path is None:
        raise RuntimeError(f"Run failed; inspect {output.with_suffix('.log')}")
    data = json.loads(Path(result_path).read_text())
    data = data.get("data", data)
    (output.with_suffix(".json")).write_text(json.dumps(data))
    return data, phases, gpu, load


def load_tables(phases, load):
    lines = ["", "Background CPU of other processes (% of one core):"]
    for name, (start, end) in phases.items():
        samples = [sample for sample in load if start <= sample[0] <= end]
        if samples:
            busiest = max(samples, key=lambda sample: sample[2])
            lines.append(
                f"  {name:24} mean {statistics.mean(s[1] for s in samples):6.0f}%  "
                f"max {max(s[1] for s in samples):6.0f}%  busiest {busiest[3]} "
                f"{busiest[2]:.0f}%  n={len(samples)}"
            )
    return lines


def gpu_tables(phases, gpu):
    lines = ["", "GPU busy share (system-wide, includes WindowServer):"]
    for name, (start, end) in phases.items():
        values = [v for t, v in gpu if start <= t <= end]
        if values:
            lines.append(
                f"  {name:24} mean {statistics.mean(values):5.1f}%  "
                f"p90 {sorted(values)[int(len(values) * .9)]:3d}%  n={len(values)}"
            )
    return lines


def trace_origin_us(trace_path):
    toc = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", str(trace_path), "--toc"],
        capture_output=True, text=True, check=True,
    ).stdout
    start = ET.fromstring(toc).find(".//start-date").text
    from datetime import datetime
    return datetime.fromisoformat(start.replace("Z", "+00:00")).timestamp() * 1e6


def native_samples(trace_path):
    """Yields (wall_us, thread, core, frames root-first) from a trace's CPU samples."""
    origin = trace_origin_us(trace_path)
    xml = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", str(trace_path), "--xpath",
         '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'],
        capture_output=True, text=True, check=True,
    ).stdout
    root = ET.fromstring(xml)
    by_id = {}

    def resolve(element):
        if element is None:
            return None
        ref = element.get("ref")
        if ref is not None:
            return by_id[ref]
        if element.get("id") is not None:
            by_id[element.get("id")] = element
        for child in element:
            resolve(child)
        return element

    for row in root.iter("row"):
        resolve(row)
        time_el = resolve(row.find("sample-time"))
        thread_el = resolve(row.find("thread"))
        backtrace = resolve(row.find("tagged-backtrace") or row.find("backtrace"))
        if time_el is None or backtrace is None:
            continue
        thread = thread_el.get("fmt", "?") if thread_el is not None else "?"
        core_el = resolve(row.find("core"))
        core = core_el.get("fmt", "?") if core_el is not None else "?"
        core = m.group(1) if (m := re.search(r"\((\w+) Core\)", core)) else "?"
        frames = []
        for frame in backtrace.iter("frame"):
            frame = resolve(frame)
            name = frame.get("name") or frame.get("addr") or "?"
            binary = frame.find("binary")
            binary = resolve(binary) if binary is not None else None
            lib = binary.get("name") if binary is not None else ""
            frames.append(f"{name} [{lib}]".replace(";", ":"))
        yield origin + int(time_el.text) / 1000, thread, core, list(reversed(frames))


def thread_key(thread):
    name = re.sub(r"\s*0x[0-9a-f]+.*", "", thread)
    name = re.sub(r"\s*\(\d+\)", "", name)
    return re.sub(r"[^A-Za-z0-9.]+", "_", name).strip("_") or "thread"


def native_tables(trace_path, phases, output, top):
    lines = ["", "=== Native time profile (Instruments) ==="]
    per_phase = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    cores = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    for wall, thread, core, frames in native_samples(trace_path):
        for name, (start, end) in phases.items():
            if start <= wall <= end:
                per_phase[name][thread_key(thread)][";".join(frames)] += 1
                cores[name][thread_key(thread)][core] += 1
    for name in phases:
        threads = per_phase.get(name, {})
        seconds = (phases[name][1] - phases[name][0]) / 1e6
        lines += ["", f"--- {name} ({seconds:.1f}s): samples per thread, share by core tier ---"]
        for thread, stacks in sorted(threads.items(), key=lambda kv: -sum(kv[1].values())):
            total = sum(stacks.values())
            tiers = "  ".join(
                f"{tier} {count / total:4.0%}"
                for tier, count in cores[name][thread].most_common()
            )
            lines.append(f"  {total:7d}  {thread:32} {tiers}")
        for thread, stacks in sorted(threads.items(), key=lambda kv: -sum(kv[1].values()))[:3]:
            parsed = [(s.split(";"), c) for s, c in stacks.items()]
            prefix = f"{output}.{name}.native.{thread}"
            with open(prefix + ".folded", "w") as f:
                f.write("\n".join(f"{s} {c}" for s, c in stacks.items()))
            with open(prefix + ".svg", "w") as f:
                f.write(media.flame_svg(parsed, f"{name} native {thread}"))
            lines += ["", f"{name} / {thread}:"] + media.cpu_tables(parsed, top)
    return lines


def table_rows(trace_path, schema):
    """Streams a trace table as {column mnemonic: (fmt, text)} dicts."""
    export = subprocess.Popen(
        ["xcrun", "xctrace", "export", "--input", str(trace_path), "--xpath",
         f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'],
        stdout=subprocess.PIPE,
    )
    columns, values = [], {}
    for event, element in ET.iterparse(export.stdout, events=("end",)):
        if element.tag == "mnemonic":
            columns.append(element.text)
        elif element.tag == "row":
            row = {}
            for column, cell in zip(columns, element):
                ref = cell.get("ref")
                if ref is not None:
                    row[column] = values[ref]
                    continue
                value = (cell.get("fmt") or "", cell.text or "")
                if cell.get("id") is not None:
                    values[cell.get("id")] = value
                row[column] = value
                for nested in cell.iter():
                    if nested is not cell and nested.get("id") is not None:
                        values[nested.get("id")] = (nested.get("fmt") or "", nested.text or "")
            element.clear()
            yield row
    export.wait()


def pass_label(label):
    """The encoder label without its process suffix or surface ids."""
    label = re.sub(r"\s+\([^()]*\(\d+\)\)\s+0x[0-9a-f]+$", "", label).strip()
    return re.sub(r"Surface: [\d\u202f ]+", "Surface: N ", label).strip()


def union_us(intervals):
    total, reach = 0, None
    for start, end in sorted(intervals):
        if reach is None or start > reach:
            total += end - start
            reach = end
        elif end > reach:
            total += end - reach
            reach = end
    return total


def gpu_pass_tables(trace_path, phases, summary):
    """Attributes GPU time per pass from a Metal System Trace."""
    origin = trace_origin_us(trace_path)
    # Durations stretch as the GPU lowers its clock, so each encoder is also
    # attributed to the performance state it started in.
    timeline = []
    for row in table_rows(trace_path, "gpu-performance-state-intervals"):
        start = origin + int(row["start"][1]) / 1000
        timeline.append((start, start + int(row["duration"][1]) / 1000,
                         row["gpu-performance-state"][0]))
    timeline.sort()
    starts = [start for start, _, _ in timeline]

    def state_at(us):
        index = bisect.bisect_right(starts, us) - 1
        return timeline[index][2] if index >= 0 and us <= timeline[index][1] else "?"

    per_phase = {name: collections.defaultdict(list) for name in phases}
    by_state = {name: collections.defaultdict(lambda: collections.defaultdict(list)) for name in phases}
    busy = {name: collections.defaultdict(list) for name in phases}
    for row in table_rows(trace_path, "metal-gpu-intervals"):
        start = origin + int(row["start"][1]) / 1000
        duration = int(row["duration"][1]) / 1000
        process = row.get("process", ("?", ""))[0].split(" (")[0] or "?"
        for name, (begin, end) in phases.items():
            if begin <= start <= end:
                busy[name][process].append((start, start + duration))
                if process == "Discourse":
                    key = (row["channel-name"][0], pass_label(row["event-label"][0]))
                    per_phase[name][key].append(duration)
                    by_state[name][key][state_at(start)].append(duration)
                break
    states = {name: collections.Counter() for name in phases}
    for start, end, state in timeline:
        for name, (begin, finish) in phases.items():
            if begin <= start <= finish:
                states[name][state] += end - start
    lines = []
    for name, (begin, end) in phases.items():
        # The recording covers only part of the pass: scale to what it saw.
        seen = [start for intervals in busy[name].values() for start, _ in intervals]
        if not seen:
            continue
        span = max(seen) - min(seen)
        frames = summary.get("phases", {}).get(name, {}).get("frames")
        frames = frames * span / (end - begin) if frames else None
        lines += ["", f"--- {name} ({span / 1e6:.1f}s traced, {frames or 0:.0f} frames) ---",
                  "  GPU busy share by process (union of vertex and fragment work):"]
        for process, intervals in sorted(busy[name].items(), key=lambda kv: -union_us(kv[1]))[:6]:
            lines.append(f"    {union_us(intervals) / span:6.1%}  {process}")
        # Busy shares are at whatever clock the GPU chose: it lowers its
        # performance state until the work fills the frame.
        total = sum(states[name].values()) or 1
        lines.append("  GPU performance state: " + "  ".join(
            f"{state} {us / total:4.0%}" for state, us in states[name].most_common()))
        lines.append("  Discourse encoders:      count  per frame   mean us    p90 us  ms/frame  busy")
        rows = sorted(per_phase[name].items(), key=lambda kv: -sum(kv[1]))
        for (channel, label), durations in rows[:20]:
            durations.sort()
            per_frame = f"{sum(durations) / frames / 1000:8.3f}" if frames else "       ?"
            count = f"{len(durations) / frames:9.2f}" if frames else "        ?"
            lines.append(
                f"    {channel[:4]:4} {len(durations):7d} {count} {statistics.mean(durations):9.1f} "
                f"{durations[int(len(durations) * .9)]:9.1f} {per_frame} {sum(durations) / span:5.1%}  {label}"
            )
        lines.append("  Mean us by GPU performance state (n):")
        for (channel, label), _ in rows[:4]:
            cells = "  ".join(
                f"{state} {statistics.mean(values):7.1f} ({len(values)})"
                for state, values in sorted(by_state[name][(channel, label)].items())
            )
            lines.append(f"    {channel[:4]:4} {cells}  {label[-40:]}")
    return lines


def census_tables(data, top):
    """Requests, mounted elements and per-frame build/layout/paint counts."""
    lines = []
    for key in sorted(k for k in data if k.startswith("requests.")):
        requests = data[key]
        paths = collections.Counter(
            method + " " + NUMBERED.sub("/N", path) + (" REFUSED" if refused else "")
            for _, method, _, path, refused in requests)
        lines += ["", f"Requests {key.split('.', 1)[1]} ({len(requests)}):"]
        lines += [f"  {n:5d}  {path}" for path, n in paths.most_common(12)]
    for key in sorted(k for k in data if k.startswith("legs.")):
        legs = data[key]
        stuck = [leg for leg in legs if abs(leg[2] - leg[1]) < 1]
        lines += ["", f"Legs {key.split('.', 1)[1]}: {len(legs)}, {len(stuck)} did not move"]
        for _, start, end, reaches, first in legs:
            if abs(end - start) < 1 or not reaches:
                lines.append(f"  {start:9.0f} -> {end:9.0f}  reaches list {reaches}  hit {first}")
    for key in sorted(k for k in data if k.startswith("elements.")):
        census = data[key]
        lines += ["", f"Mounted at the end of {key.split('.', 1)[1]}: tree {census['tree']}  "
                  f"list {census['listElements']}  render objects {census['listRenderObjects']}  "
                  f"ticker states {census['listTickerStates']}  rows {census['rows']}"]
        lines += [f"  {n:6d}  {name}" for name, n in list(census["byType"].items())[:15]]
    for key in sorted(k for k in data if k.startswith("census.")):
        census = data[key]
        per_frame = sorted(census["blocksPerFrame"])
        if not per_frame:
            continue
        at = lambda q: per_frame[min(len(per_frame) - 1, int(len(per_frame) * q))]
        lines += ["", f"=== Census {key.split('.', 1)[1]}: {census['frames']} frames, "
                  f"{sum(per_frame)} widget/render blocks; per frame p50 {at(.5)} "
                  f"p90 {at(.9)} p99 {at(.99)} max {per_frame[-1]} ==="]
        names = census["byName"]
        lines.append("  By self time:      count    self ms   incl ms  name")
        for name, (count, self_us, incl_us) in sorted(names.items(), key=lambda kv: -kv[1][1])[:top]:
            lines.append(f"    {count:15d} {self_us / 1000:10.1f} {incl_us / 1000:9.1f}  {name}")
        lines.append("  By count:")
        for name, (count, self_us, incl_us) in sorted(names.items(), key=lambda kv: -kv[1][0])[:top]:
            lines.append(f"    {count:15d} {self_us / 1000:10.1f} {incl_us / 1000:9.1f}  {name}")
        for frame in census["slowFrames"][:8]:
            lines.append(f"  Slow frame at {frame['startUs']}: build {frame['buildUs'] / 1000:.2f} ms, "
                         f"{frame['blocks']} blocks")
            rows = sorted(frame["byName"].items(), key=lambda kv: -kv[1][1])[:10]
            lines += [f"    {c:6d} {s / 1000:7.2f} ms self {i / 1000:7.2f} incl  {n}"
                      for n, (c, s, i) in rows]
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--top", type=int, default=40)
    parser.add_argument(
        "--trace", choices=["time", "metal", "none"], default="time",
        help="Instruments recording: Time Profiler, Metal System Trace "
        "(CPU samples and per-pass GPU time), or none")
    parser.add_argument(
        "--gpu-phases", default=r"warmTiming$",
        help="with --trace metal: regex of the passes to record")
    parser.add_argument(
        "--gpu-seconds", type=int, default=4,
        help="with --trace metal: length of each pass's recording")
    parser.add_argument("--reanalyze", action="store_true",
                        help="reuse <output>.json/.trace/.phases.json")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    phases_path = args.output.with_suffix(".phases.json")
    if args.reanalyze:
        data = json.loads(args.output.with_suffix(".json").read_text())
        saved = json.loads(phases_path.read_text())
        phases = {k: tuple(v) for k, v in saved["phases"].items()}
        gpu = saved["gpu"]
        load = saved.get("load", [])
    else:
        data, phases, gpu, load = run(
            args.app.resolve(), args.output, args.timeout,
            None if args.trace == "none" else args.trace,
            args.gpu_phases, args.gpu_seconds)
        phases_path.write_text(
            json.dumps({"phases": phases, "gpu": gpu, "load": load}))

    summary = data.get("summary", {})
    lines = ["Summary:", json.dumps({k: v for k, v in summary.items() if k != "phases"}, indent=2), "", "Frame timings (ms):"]
    for name, phase in summary.get("phases", {}).items():
        b, r = phase["build"], phase["raster"]
        lines.append(
            f"  {name:24} frames {phase['frames']:5d}  build mean {b['meanMs']:5.2f} "
            f"p90 {b['p90Ms']:5.2f} p99 {b['p99Ms']:6.2f} >8.3 {b['over8ms']:4d} | "
            f"raster mean {r['meanMs']:5.2f} p90 {r['p90Ms']:5.2f} p99 {r['p99Ms']:6.2f} "
            f">8.3 {r['over8ms']:4d}"
        )
    lines += gpu_tables(phases, gpu)
    lines += load_tables(phases, load)
    for name in summary.get("phases", {}):
        lines += gc.table(name, data.get(f"gcTimeline.{name}"), data.get(f"frameTimings.{name}", []))
        lines += gc.allocation_table(name, data.get(f"allocations.{name}"))
    lines += census_tables(data, args.top)
    for key in sorted(k for k in data if k.startswith("cpuFolded.")):
        phase = key.split(".", 1)[1]
        stacks = media.parse_folded(data[key])
        if not stacks:
            continue
        lines += ["", f"=== Dart CPU {phase} ==="]
        prefix = f"{args.output}.{phase}"
        if phase.endswith(".slow"):
            lines += media.slow_frame_tables(stacks)
            stacks = [(stack[1:], count) for stack, count in stacks]
        with open(prefix + ".folded", "w") as f:
            f.write(data[key])
        with open(prefix + ".svg", "w") as f:
            f.write(media.flame_svg(stacks, f"{phase} UI isolate"))
        with open(prefix + ".focused.svg", "w") as f:
            f.write(media.flame_svg(media.focused(stacks), f"{phase} UI isolate, plumbing removed"))
        lines += media.cpu_tables(media.focused(stacks), args.top)
    for key in sorted(k for k in data if k.startswith("timeline.")):
        events = data[key] or []
        lines += ["", f"=== Timeline {key.split('.', 1)[1]} ==="]
        lines += media.timeline_tables(events, 25)
    trace_path = args.output.with_suffix(".trace")
    if trace_path.exists():
        try:
            lines += native_tables(trace_path, phases, args.output, args.top)
        except Exception as error:  # noqa: BLE001 - the Dart report still stands
            lines += ["", f"Native trace export failed: {error!r}"]
    gpu_lines = []
    for name, window in phases.items():
        path = phase_trace(args.output, name)
        if not path.exists():
            continue
        try:
            gpu_lines += gpu_pass_tables(path, {name: window}, summary)
            gpu_lines += native_tables(path, {name: window}, f"{args.output}.gpu", args.top)[2:]
        except Exception as error:  # noqa: BLE001 - the other reports still stand
            gpu_lines += ["", f"GPU trace export of {name} failed: {error!r}"]
    if gpu_lines:
        lines += ["", "=== GPU passes (Metal System Trace) ==="] + gpu_lines
    args.output.with_suffix(".txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:60]))


if __name__ == "__main__":
    sys.exit(main())
