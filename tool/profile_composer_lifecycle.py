#!/usr/bin/env python3
"""Capture the native topic composer lifecycle from a prebuilt profile bundle.

From this checkout, after building the lifecycle integration-test target:

  python3 tool/profile_composer_lifecycle.py /tmp/baseline.app /tmp/baseline-0
  python3 tool/profile_composer_lifecycle.py /tmp/iphone.app /tmp/iphone-0 \
      --device DEVICE_UDID --label iphone-baseline

The iPhone bundle must use matching --dart-define values for
COMPOSER_ITERATIONS, COMPOSER_RETAINED_DRAFTS, COMPOSER_RESUME_DRAFT,
COMPOSER_CLOSE_INACTIVE and PROFILE_LABEL. Device launch does not forward
arbitrary environment variables. Desktop runs also support runtime settings.

Each output prefix must be new. The runner preserves .log and .visibility.json;
successful, validated captures become .json. A fresh driver report from an
unsuccessful run becomes .failed.json. The driver writes into a temporary output
directory, so an older shared build/integration_response_data.json cannot be
mistaken for this run. macOS activates and observes the exact new process,
without selecting another running app with the same bundle identifier.

Snapshot runnerMonotonicMicros is a runner clock, not the Dart Timeline clock;
wallTimeUnixMicros is provided only as a wall-clock correlation anchor.

These are thread-work captures and visibility observations. Use the separate
frame-budget checker; they do not establish GPU completion or presentation FPS.
"""

import argparse
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time


PHASES = ("opening", "scrolling", "closing")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="prebuilt .app bundle")
    parser.add_argument("output", type=Path, help="new output prefix, without extension")
    parser.add_argument("--device", default="macos")
    parser.add_argument("--iterations", type=int, default=2)
    parser.add_argument("--retained-drafts", type=int, default=0)
    parser.add_argument("--opening", choices=("empty", "resumed"), default="empty")
    parser.add_argument("--inactive-close", action="store_true")
    parser.add_argument("--label", help="expected compiled or runtime capture label")
    parser.add_argument("--timeout", type=float, default=180)
    args = parser.parse_args()
    if args.iterations < 1 or args.retained_drafts < 0 or args.timeout <= 0:
        parser.error("iterations and timeout must be positive; retained drafts nonnegative")
    if args.inactive_close and not args.retained_drafts:
        parser.error("inactive closing requires retained drafts")
    args.app = args.app.resolve()
    args.output = args.output.resolve()
    if not args.app.is_dir() or args.app.suffix != ".app":
        parser.error("app must name an existing .app bundle")
    for suffix in (".log", ".json", ".failed.json", ".visibility.json"):
        if Path(f"{args.output}{suffix}").exists():
            parser.error(f"output already exists: {args.output}{suffix}")
    return args


def bundle_executable(app):
    desktop_plist = app / "Contents/Info.plist"
    macos = desktop_plist.is_file()
    info_path = desktop_plist if macos else app / "Info.plist"
    with info_path.open("rb") as stream:
        executable = plistlib.load(stream)["CFBundleExecutable"]
    binary = app / "Contents/MacOS" / executable if macos else app / executable
    if not binary.is_file():
        raise ValueError(f"bundle executable is missing: {binary}")
    return macos, str(binary.resolve())


def matching_processes(binary):
    output = subprocess.run(
        ["ps", "-axo", "pid=,command="], check=True, capture_output=True, text=True,
    ).stdout
    matches = set()
    for row in output.splitlines():
        parts = row.strip().split(None, 1)
        if len(parts) == 2 and (parts[1] == binary or parts[1].startswith(binary + " ")):
            matches.add(int(parts[0]))
    return matches


def validate_capture(data, args, macos):
    result = data.get("integrationTest", {})
    if result.get("passed") is not True or result.get("failureCount") != 0:
        raise ValueError("integration test failed or omitted its result")
    if data.get("composerLifecycleComplete") is not True:
        raise ValueError("native lifecycle did not complete cleanup and invariants")
    capture = data.get("composerLifecycle", {})
    expected = {
        "controller": "native",
        "hostPlatform": "macOS" if macos else "iOS",
        "retainedDrafts": args.retained_drafts,
        "openingDraft": args.opening,
        "closeInactive": args.inactive_close,
    }
    if args.label is not None:
        expected["label"] = args.label
    for key, value in expected.items():
        if capture.get(key) != value:
            raise ValueError(f"capture {key}={capture.get(key)!r}; expected {value!r}")
    reports = capture.get("reports", [])
    expected_reports = {(phase, iteration) for phase in PHASES
                        for iteration in range(args.iterations)}
    actual_reports = {(report.get("phase"), report.get("iteration")) for report in reports}
    if len(reports) != len(expected_reports) or actual_reports != expected_reports:
        raise ValueError("capture does not contain exactly the requested lifecycle iterations")


def capture(args):
    root = Path(__file__).resolve().parent.parent
    args.output.parent.mkdir(parents=True, exist_ok=True)
    log_path = Path(f"{args.output}.log")
    states = []
    data = None
    process = None
    with log_path.open("x") as log, tempfile.TemporaryDirectory(prefix="composer-profile-") as temp:
        temp = Path(temp)
        report_path = temp / "driver/integration_response_data.json"
        report_path.parent.mkdir()
        try:
            macos, binary = bundle_executable(args.app)
            helper = temp / "composer-window-state"
            previous_processes = set()
            if macos:
                subprocess.run(
                    ["swiftc", "-O", str(root / "tool/composer_window_state.swift"),
                     "-o", str(helper)], check=True, stdout=log, stderr=subprocess.STDOUT,
                )
                previous_processes = matching_processes(binary)
            env = dict(
                os.environ,
                FLUTTER_TEST_OUTPUTS_DIR=str(report_path.parent),
                PROFILE_LABEL=args.label or args.output.name,
                COMPOSER_ITERATIONS=str(args.iterations),
                COMPOSER_RETAINED_DRAFTS=str(args.retained_drafts),
                COMPOSER_RESUME_DRAFT="1" if args.opening == "resumed" else "0",
                COMPOSER_CLOSE_INACTIVE="1" if args.inactive_close else "0",
            )
            command = [
                "flutter", "drive", "--no-pub", "--profile", "-d", args.device,
                f"--use-application-binary={args.app}",
                "--driver", "integration_test/performance_driver.dart",
                "--target", "integration_test/composer_lifecycle_performance_test.dart",
            ]
            process = subprocess.Popen(
                command, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT,
            )
            start = time.monotonic()
            next_sample = 0
            target = None
            activated = False
            while process.poll() is None:
                now = time.monotonic()
                if now - start > args.timeout:
                    raise TimeoutError(f"measurement exceeded {args.timeout:g} seconds")
                if macos and target is None:
                    candidates = matching_processes(binary) - previous_processes
                    if len(candidates) > 1:
                        raise ValueError("multiple new processes match the profiling executable")
                    if candidates:
                        target = candidates.pop()
                if target is not None and now >= next_sample:
                    command = [str(helper), str(target)]
                    if not activated:
                        command.append("--activate")
                    state = subprocess.run(command, capture_output=True, text=True)
                    if state.returncode == 0:
                        snapshot = json.loads(state.stdout)
                        snapshot["elapsedSeconds"] = time.monotonic() - start
                        snapshot["runnerMonotonicMicros"] = time.monotonic_ns() // 1000
                        snapshot["wallTimeUnixMicros"] = time.time_ns() // 1000
                        states.append(snapshot)
                        activated = activated or snapshot["active"]
                    next_sample = time.monotonic() + .5
                time.sleep(.1)
            if process.returncode:
                raise ValueError(f"flutter drive exited {process.returncode}; inspect {log_path}")
            if not report_path.is_file():
                raise ValueError("driver did not write a fresh capture")
            data = json.loads(report_path.read_text())
            validate_capture(data, args, macos)
            if macos:
                if not activated or not any(state["onScreenWindows"] for state in states):
                    raise ValueError("profiling process was not activated with an on-screen window")
                data["desktopVisibility"] = states
            Path(f"{args.output}.json").write_text(json.dumps(data, indent=2))
        except BaseException as error:
            log.write(f"\n[runner] {type(error).__name__}: {error}\n")
            log.flush()
            if report_path.is_file():
                Path(f"{args.output}.failed.json").write_bytes(report_path.read_bytes())
            raise
        finally:
            if process is not None and process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            Path(f"{args.output}.visibility.json").write_text(json.dumps(states, indent=2))
    print(json.dumps({
        "capture": f"{args.output}.json",
        "reports": len(data["composerLifecycle"]["reports"]),
        "inactiveDesktopSnapshots": sum(not state["active"] for state in states),
    }))


def main():
    args = parse_args()
    try:
        capture(args)
    except KeyboardInterrupt:
        return 130
    except Exception as error:
        print(f"Capture failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
