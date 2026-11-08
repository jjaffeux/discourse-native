#!/usr/bin/env python3
"""Measure cold starts of a profile build, alternating builds on macOS or iOS.

Build tool/startup_profile_main.dart in profile mode once per side. The
entrypoint seeds six forums and serves them from a second isolate, so a launch
needs no network and every side sees the same data. See
docs/performance/startup.md for the build recipe.

  python3 tool/profile_startup.py --app base=/tmp/base.app --app fix=/tmp/fix.app \
      --runs 11 --output /tmp/startup.json

  python3 tool/profile_startup.py --device <udid> \
      --app base=/tmp/base-ios.app --app fix=/tmp/fix-ios.app --runs 11 \
      --output /tmp/startup-ios.json

On a device the sides share one bundle id and its seeded state. Each block
installs a side, discards one launch so the install's cold pages land on none of
the sides, and then records --block launches. Use a bundle id of its own, so a
run never replaces the installed app.

Every milestone is milliseconds since the kernel created the process, reported
by the process itself:

  mark:*        a markStartup() point in the app
  first-raster  the first Flutter frame reached the screen
  shell-raster  the first frame built after local state was restored
  feed-raster   the first frame built after the first feed page was published

Spans subtract two points of one launch, so whatever slowed the process before
Dart ran drops out of them:

  span:to-first-frame  Dart main to the first frame on screen
  span:local-state     the start of the local-state load to the shell being ready
  span:to-shell        Dart main to the restored shell on screen
  span:to-feed         Dart main to the first feed page on screen
  span:feed-request    the feed request leaving to its response being parsed

Sides run in turn so that drift on the machine lands on all of them. --dump
adds the VM timeline and Dart CPU samples of each macOS launch; sampling slows
the isolate, so never report numbers from a --dump run.
"""

import argparse
import json
import math
import os
from pathlib import Path
import plistlib
import queue
import re
import statistics
import subprocess
import tempfile
import threading
import time
import urllib.parse
import urllib.request

LINE = re.compile(r"STARTUP_PROFILE (\w+) (-?\d+) ?(.*)")
SERVICE = re.compile(r"(http://127\.0\.0\.1:\d+/[^/\s]*/?)")
FRAME = re.compile(r"(\d+) built=(-?\d+)")


def milestones(records):
    marks, frames, requests, cpu = {}, [], [], {}
    for kind, micros, name in records:
        if kind == "mark":
            marks.setdefault(name, micros)
        elif kind == "frame":
            match = FRAME.match(name)
            frames.append((int(match.group(2)), micros))
        elif kind == "request":
            requests.append(f"{micros / 1000:8.1f} {name}")
        elif kind == "cpu":
            cpu[name] = micros / 1000
    frames.sort()
    out = {f"mark:{name}": value / 1000 for name, value in marks.items()}
    out.update({f"cpu:{name}": value for name, value in cpu.items()})
    if frames:
        out["first-raster"] = frames[0][1] / 1000

    def raster_after(mark):
        at = marks.get(mark)
        if at is None:
            return None
        return next((end for built, end in frames if built >= at), None)

    for label, mark in (("shell-raster", "shell ready"), ("feed-raster", "feed shown")):
        value = raster_after(mark)
        if value is not None:
            out[label] = value / 1000

    for label, start, end in (
        ("span:to-first-frame", "mark:main", "first-raster"),
        ("span:local-state", "mark:load start", "mark:shell ready"),
        ("span:to-shell", "mark:main", "shell-raster"),
        ("span:to-feed", "mark:main", "feed-raster"),
        ("span:feed-request", "mark:feed requested", "mark:feed received"),
    ):
        if start in out and end in out:
            out[label] = out[end] - out[start]
    return out, requests, frames


def rpc(service, method, **params):
    query = urllib.parse.urlencode(params)
    url = f"{service.rstrip('/')}/{method}" + (f"?{query}" if query else "")
    with urllib.request.urlopen(url, timeout=60) as response:
        body = json.load(response)
    if "error" in body:
        raise RuntimeError(f"{method}: {body['error']}")
    return body.get("result", body)


def macos_environment(seed, dump):
    environment = os.environ.copy()
    environment["FLUTTER_ENGINE_SWITCHES"] = "2"
    environment["FLUTTER_ENGINE_SWITCH_1"] = f"trace-startup={str(dump).lower()}"
    environment["FLUTTER_ENGINE_SWITCH_2"] = f"enable-dart-profiling={str(dump).lower()}"
    if seed:
        environment["DISCOURSE_STARTUP_SEED"] = "1"
    return environment


def stream(process):
    lines = queue.Queue()

    def pump():
        for line in process.stdout:
            lines.put(line)
        lines.put(None)

    threading.Thread(target=pump, daemon=True).start()
    return lines


def stop(process, grace):
    process.terminate()
    try:
        process.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def attribute(service):
    vm = rpc(service, "getVM")
    isolate = next(i["id"] for i in vm["isolates"] if i["name"].startswith("main"))
    return {
        "timeline": rpc(service, "getVMTimeline")["traceEvents"],
        "cpu": rpc(
            service,
            "getCpuSamples",
            isolateId=isolate,
            timeOriginMicros=0,
            timeExtentMicros=2**62,
        ),
    }


def run_macos(app, seed, timeout, dump):
    binary = Path(app) / "Contents/MacOS/Discourse"
    process = subprocess.Popen(
        [str(binary)],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=macos_environment(seed, dump),
    )
    lines = stream(process)
    records, service, attribution = [], None, None
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=max(0.0, deadline - time.monotonic()))
            except queue.Empty:
                break
            if line is None:
                break
            found = SERVICE.search(line)
            if found:
                service = found.group(1)
            match = LINE.search(line)
            if not match:
                continue
            kind, micros, name = match.group(1), int(match.group(2)), match.group(3)
            records.append((kind, micros, name))
            if dump and service and kind == "mark" and name == "feed shown":
                time.sleep(2.0)
                attribution = attribute(service)
            if kind in ("done", "seeded"):
                break
    finally:
        stop(process, 10)
    return records, attribution


def install_ios(device, app):
    subprocess.run(
        ["xcrun", "devicectl", "device", "install", "app", "--device", device, str(app)],
        check=True,
        capture_output=True,
        text=True,
    )


def bundle_identifier(app):
    with open(Path(app) / "Info.plist", "rb") as info:
        return plistlib.load(info)["CFBundleIdentifier"]


def copy_from_ios(device, bundle_id, name):
    with tempfile.TemporaryDirectory() as folder:
        destination = Path(folder) / name
        copied = subprocess.run(
            [
                "xcrun", "devicectl", "device", "copy", "from",
                "--device", device,
                "--domain-type", "appDataContainer",
                "--domain-identifier", bundle_id,
                "--source", f"tmp/{name}",
                "--destination", str(destination),
            ],
            capture_output=True,
            text=True,
        )
        if copied.returncode != 0 or not destination.exists():
            return []
        return destination.read_text().splitlines()


def request_ios_seed(device, bundle_id):
    with tempfile.NamedTemporaryFile(suffix=".seed") as request:
        subprocess.run(
            [
                "xcrun", "devicectl", "device", "copy", "to",
                "--device", device,
                "--domain-type", "appDataContainer",
                "--domain-identifier", bundle_id,
                "--source", request.name,
                "--destination", "tmp/startup_seed",
            ],
            check=True,
            capture_output=True,
        )


def run_ios(device, bundle_id, seed, timeout):
    # Dart's print does not reach the console on iOS: the process writes its
    # records to a file and exits, and the file is copied off the device.
    if seed:
        request_ios_seed(device, bundle_id)
    process = subprocess.Popen(
        [
            "xcrun", "devicectl", "device", "process", "launch",
            "--device", device,
            "--terminate-existing",
            "--console",
            bundle_id,
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        stop(process, 20)
    records = []
    for name in ("startup_profile.log", "startup_profile_requests.log"):
        for line in copy_from_ios(device, bundle_id, name):
            match = LINE.search(line)
            if match:
                records.append((match.group(1), int(match.group(2)), match.group(3)))
    return records, None


def summarize(runs):
    keys = {k for run in runs for k in run["milestones"]}
    table = {}
    for key in keys:
        values = sorted(r["milestones"][key] for r in runs if key in r["milestones"])
        table[key] = {
            "n": len(values),
            "median": statistics.median(values),
            "min": values[0],
            "max": values[-1],
        }
    return table


def rank_sum_p(first, second):
    """Two-sided Mann-Whitney U p-value with the normal approximation."""
    if len(first) < 2 or len(second) < 2:
        return None
    pooled = sorted(
        [(value, 0) for value in first] + [(value, 1) for value in second]
    )
    ranks = [0.0] * len(pooled)
    index = 0
    while index < len(pooled):
        end = index
        while end + 1 < len(pooled) and pooled[end + 1][0] == pooled[index][0]:
            end += 1
        for position in range(index, end + 1):
            ranks[position] = (index + end) / 2 + 1
        index = end + 1
    u = sum(rank for rank, (_, side) in zip(ranks, pooled) if side == 0)
    u -= len(first) * (len(first) + 1) / 2
    mean = len(first) * len(second) / 2
    deviation = math.sqrt(len(first) * len(second) * (len(pooled) + 1) / 12)
    if deviation == 0:
        return 1.0
    return math.erfc(abs(u - mean) / deviation / math.sqrt(2))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", action="append", required=True, help="label=path")
    parser.add_argument("--runs", type=int, default=11)
    parser.add_argument("--timeout", type=float, default=45)
    parser.add_argument("--warmups", type=int, default=2)
    parser.add_argument("--pause", type=float, default=1.0)
    parser.add_argument("--device", help="UDID of an iOS device")
    parser.add_argument(
        "--block",
        type=int,
        default=1,
        help="launches recorded each time a side takes its turn",
    )
    parser.add_argument(
        "--fresh",
        action="store_true",
        help="reseed before each launch, so every launch restores nothing",
    )
    parser.add_argument("--dump", help="keep CPU samples and timelines in this file")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    apps = [tuple(value.split("=", 1)) for value in args.app]

    def launch(app, seed=False, dump=False):
        if args.device:
            return run_ios(args.device, bundle_identifier(app), seed, args.timeout)
        return run_macos(app, seed, args.timeout, dump)

    def seed(app):
        records, _ = launch(app, seed=True)
        if not any(kind == "seeded" for kind, _, _ in records):
            raise SystemExit(f"seeding failed: {records}")

    def prepare(app):
        if args.device:
            install_ios(args.device, app)
            launch(app)

    if args.device:
        install_ios(args.device, apps[0][1])
    seed(apps[0][1])

    # The first launches write what they learn from the forums, which a
    # returning user would already have on disk.
    for label, app in apps:
        prepare(app)
        for index in range(args.warmups):
            records, _ = launch(app)
            found, requests, _ = milestones(records)
            print(
                f"warmup {label} #{index}: feed={found.get('feed-raster')} "
                f"requests={len(requests)}",
                flush=True,
            )

    results = {label: [] for label, _ in apps}
    failures = {label: 0 for label, _ in apps}
    dumps = {}
    for iteration in range(args.runs):
        for label, app in apps:
            if len(apps) > 1:
                prepare(app)
            for _ in range(args.block):
                load = os.getloadavg()[0]
                if args.fresh:
                    launch(app, seed=True)
                try:
                    records, attribution = launch(app, dump=bool(args.dump))
                    found, requests, frames = milestones(records)
                    if "feed-raster" not in found:
                        raise RuntimeError(f"no feed frame: {sorted(found)}")
                except Exception as error:  # noqa: BLE001
                    failures[label] += 1
                    print(f"{label} #{iteration}: FAILED {error}", flush=True)
                    continue
                results[label].append(
                    {
                        "milestones": found,
                        "load_before": load,
                        "requests": requests,
                        "frames": frames,
                    }
                )
                if attribution:
                    dumps.setdefault(label, []).append(attribution)
                print(
                    f"{label} #{iteration}: load={load:.1f} "
                    + " ".join(
                        f"{key}={value:.0f}"
                        for key, value in found.items()
                        if key.startswith("span:")
                    ),
                    flush=True,
                )
                time.sleep(args.pause)

    report = {
        label: {
            "summary": summarize(runs),
            "failures": failures[label],
            "runs": runs,
        }
        for label, runs in results.items()
    }
    Path(args.output).write_text(json.dumps(report, indent=1))
    if args.dump:
        Path(args.dump).write_text(json.dumps(dumps))

    labels = [label for label, _ in apps]
    keys = sorted(
        {k for label in labels for k in report[label]["summary"]},
        key=lambda k: min(
            report[label]["summary"][k]["median"]
            for label in labels
            if k in report[label]["summary"]
        ),
    )
    for key in keys:
        cells = []
        for label in labels:
            row = report[label]["summary"].get(key)
            cells.append(
                f"{label} {row['median']:8.1f} [{row['min']:.0f}-{row['max']:.0f}]"
                if row
                else f"{label} -"
            )
        if len(labels) == 2:
            first, second = (
                [run["milestones"][key] for run in results[label] if key in run["milestones"]]
                for label in labels
            )
            p_value = rank_sum_p(first, second)
            if p_value is not None:
                cells.append(f"p={p_value:.4f}")
        print(f"{key:30} " + "  ".join(cells))
    print("failures", failures)


if __name__ == "__main__":
    main()
