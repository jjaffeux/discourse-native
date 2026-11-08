"""Check native composer frame captures against the 120 Hz thread budget."""

import argparse
import json
import math
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("captures", nargs="+", type=Path)
    parser.add_argument("--platform", choices=["macOS", "iOS", "android"], required=True)
    parser.add_argument("--repetitions", type=int, default=5)
    parser.add_argument("--opening", choices=["empty", "resumed"], default="empty")
    parser.add_argument("--retained-drafts", type=int, default=0)
    parser.add_argument("--inactive-close", action="store_true")
    args = parser.parse_args()
    if args.repetitions <= 0 or args.retained_drafts < 0:
        parser.error("repetitions must be positive and retained drafts nonnegative")
    budget = 1000 / 120
    phases = {phase: [] for phase in ["opening", "scrolling", "closing"]}
    failures = []
    seen_paths = set()
    seen_windows = set()
    for path in args.captures:
        canonical = path.resolve()
        if canonical in seen_paths:
            failures.append(f"{path}: duplicate capture")
            continue
        seen_paths.add(canonical)
        capture = json.loads(path.read_text())
        result = capture.get("integrationTest", {})
        if capture.get("composerLifecycleComplete") is not True:
            failures.append(f"{path}: native lifecycle did not finish cleanup and invariants")
        if result.get("passed") is not True or result.get("failureCount") != 0:
            failures.append(f"{path}: missing successful integration result")
        data = capture["composerLifecycle"]
        if data.get("controller") != "native":
            failures.append(f"{path}: missing native-controller capture")
        if data.get("openingDraft") != args.opening or data["retainedDrafts"] != args.retained_drafts:
            failures.append(f"{path}: wrong opening or retained-draft workload")
        if data.get("closeInactive") != args.inactive_close:
            failures.append(f"{path}: wrong closing workload")
        if data.get("nativeTextInput") is not True:
            failures.append(f"{path}: mocked or unknown text input")
        if data.get("errors") != 0 or data.get("paragraphs") != 120:
            failures.append(f"{path}: missing successful workload checks")
        if data["debug"] or data["instrumented"]:
            failures.append(f"{path}: instrumented or debug capture")
        if data["hostPlatform"] != args.platform:
            failures.append(f"{path}: wrong native platform")
        if data.get("refreshRate", 0) < 120 or data.get("pixelRatio", 0) <= 0:
            failures.append(f"{path}: missing native 120 Hz display metadata")
        if data["mobile"] != (args.platform != "macOS"):
            failures.append(f"{path}: simulated platform layout")
        seen_reports = set()
        for report in data["reports"]:
            phase = report["phase"]
            if phase not in phases:
                failures.append(f"{path}: unknown phase {phase}")
                continue
            identity = (phase, report["iteration"])
            if identity in seen_reports:
                failures.append(f"{path}: duplicate phase iteration")
                continue
            seen_reports.add(identity)
            start = report.get("startMicros")
            end = report.get("endMicros")
            if not isinstance(start, int) or not isinstance(end, int) or end <= start:
                failures.append(f"{path}: invalid phase timestamp window")
                continue
            window = (phase, start, end)
            if window in seen_windows:
                failures.append(f"{path}: duplicated phase timestamp window")
                continue
            seen_windows.add(window)
            if args.platform != "macOS":
                before = report.get("keyboardBefore", 0)
                after = report.get("keyboardAfter", 0)
                if phase in ["scrolling", "closing"] and before <= 0:
                    failures.append(f"{path}: {phase} started without native keyboard")
                if phase in ["opening", "scrolling"] and after <= 0:
                    failures.append(f"{path}: {phase} ended without native keyboard")
                if phase == "closing" and not data["retainedDrafts"] and after != 0:
                    failures.append(f"{path}: closing did not dismiss native keyboard")
                if phase == "closing" and args.inactive_close and after <= 0:
                    failures.append(f"{path}: inactive close dismissed native keyboard")
            frames = report["frames"]
            if not frames or not any(frame["rasterMs"] > .001 for frame in frames):
                failures.append(f"{path}: {phase} has no meaningful raster work")
                continue
            if phase == "scrolling" and len(frames) < .9 * report["elapsedMs"] / budget:
                failures.append(f"{path}: scrolling capture was throttled below native 120 Hz")
            if any(not math.isfinite(frame[key]) or frame[key] < 0
                   for frame in frames for key in ["buildMs", "rasterMs"]):
                failures.append(f"{path}: invalid {phase} frame durations")
                continue
            phases[phase].append(frames)
    summary = {}
    for phase, repetitions in phases.items():
        frames = [frame for repetition in repetitions for frame in repetition]
        if len(repetitions) < args.repetitions:
            failures.append(f"{phase}: fewer than {args.repetitions} repetitions")
        summary[phase] = {
            "repetitions": len(repetitions),
            "frames": len(frames),
            **{key: {
                "maxMs": max((frame[key] for frame in frames), default=None),
                "overBudget": sum(frame[key] > budget for frame in frames),
            } for key in ["buildMs", "rasterMs"]},
        }
        if any(frame[key] > budget for frame in frames for key in ["buildMs", "rasterMs"]):
            failures.append(f"{phase}: exceeded the {budget:.6f} ms thread budget")
    print(json.dumps({"passed": not failures, "errorCount": len(failures), "budgetMs": budget,
                      "phases": summary, "failures": failures}, indent=2))
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
