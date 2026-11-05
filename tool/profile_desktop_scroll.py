#!/usr/bin/env python3
"""Run integration_test/desktop_scroll_profile_test.dart once and report it.

Build the app first (see docs/performance/desktop-scrolling.md), then:

  python3 tool/profile_desktop_scroll.py build/macos/Build/Products/Profile/Discourse.app \
      --output /tmp/desktop-scroll

One launch records, for every pass the test brackets with
DESKTOP_SCROLL_PHASE lines:

  - frame timings and the UI isolate's Dart CPU samples (from the test),
  - the Dart, Embedder and GC timeline (from the test),
  - an Instruments Time Profiler trace of the whole process, so native
    frames on the raster and platform threads are attributed per pass,
  - the system-wide GPU busy share, which includes the window server.

It writes <output>.txt (all tables), <output>.<pass>.svg / .focused.svg /
.folded for Dart CPU, <output>.<pass>.native.<thread>.svg / .folded for
native threads, and keeps the raw JSON and trace beside them.
"""

import argparse
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

PHASE = re.compile(r"DESKTOP_SCROLL_PHASE (start|end) (\S+) (\d+)")


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


def run(app, output, timeout, trace):
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

    recorder = None
    if trace:
        trace_path = output.with_suffix(".trace")
        subprocess.run(["rm", "-rf", str(trace_path)])
        recorder = subprocess.Popen(
            ["xcrun", "xctrace", "record", "--template", "Time Profiler",
             "--attach", str(process.pid), "--output", str(trace_path),
             "--no-prompt"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
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
        if recorder:
            recorder.send_signal(signal.SIGINT)
            try:
                recorder.wait(timeout=120)
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
    return data, phases, gpu


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


def native_samples(trace_path):
    """Yields (wall_us, thread, frames root-first) from a Time Profiler trace."""
    toc = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", str(trace_path), "--toc"],
        capture_output=True, text=True, check=True,
    ).stdout
    start = ET.fromstring(toc).find(".//start-date").text
    from datetime import datetime
    origin = datetime.fromisoformat(start.replace("Z", "+00:00")).timestamp() * 1e6
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
        frames = []
        for frame in backtrace.iter("frame"):
            frame = resolve(frame)
            name = frame.get("name") or frame.get("addr") or "?"
            binary = frame.find("binary")
            binary = resolve(binary) if binary is not None else None
            lib = binary.get("name") if binary is not None else ""
            frames.append(f"{name} [{lib}]".replace(";", ":"))
        yield origin + int(time_el.text) / 1000, thread, list(reversed(frames))


def thread_key(thread):
    name = re.sub(r"\s*0x[0-9a-f]+.*", "", thread)
    name = re.sub(r"\s*\(\d+\)", "", name)
    return re.sub(r"[^A-Za-z0-9.]+", "_", name).strip("_") or "thread"


def native_tables(trace_path, phases, output, top):
    lines = ["", "=== Native time profile (Instruments) ==="]
    per_phase = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    for wall, thread, frames in native_samples(trace_path):
        for name, (start, end) in phases.items():
            if start <= wall <= end:
                per_phase[name][thread_key(thread)][";".join(frames)] += 1
    for name in phases:
        threads = per_phase.get(name, {})
        seconds = (phases[name][1] - phases[name][0]) / 1e6
        lines += ["", f"--- {name} ({seconds:.1f}s): samples per thread ---"]
        for thread, stacks in sorted(threads.items(), key=lambda kv: -sum(kv[1].values())):
            lines.append(f"  {sum(stacks.values()):7d}  {thread}")
        for thread, stacks in sorted(threads.items(), key=lambda kv: -sum(kv[1].values()))[:3]:
            parsed = [(s.split(";"), c) for s, c in stacks.items()]
            prefix = f"{output}.{name}.native.{thread}"
            with open(prefix + ".folded", "w") as f:
                f.write("\n".join(f"{s} {c}" for s, c in stacks.items()))
            with open(prefix + ".svg", "w") as f:
                f.write(media.flame_svg(parsed, f"{name} native {thread}"))
            lines += ["", f"{name} / {thread}:"] + media.cpu_tables(parsed, top)
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--top", type=int, default=40)
    parser.add_argument("--no-trace", action="store_true")
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
    else:
        data, phases, gpu = run(args.app.resolve(), args.output, args.timeout,
                                not args.no_trace)
        phases_path.write_text(json.dumps({"phases": phases, "gpu": gpu}))

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
    args.output.with_suffix(".txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[:60]))


if __name__ == "__main__":
    sys.exit(main())
