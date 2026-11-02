#!/usr/bin/env python3
"""Profile or alternate compiled macOS topic-list scroll workloads."""

import argparse
import collections
import gzip
import hashlib
import json
import os
from pathlib import Path
import queue
import statistics
import subprocess
import threading
import time

from topic_media_scroll_profile import cpu_tables, flame_svg, parse_folded


def write_profiles(response, output):
    data = json.loads(response.read_text())
    lines = []
    for key, folded in data.items():
        if not key.startswith("cpuFolded."):
            continue
        phase = key.split(".", 1)[1]
        stacks = parse_folded(folded)
        lines.extend([f"=== {phase} ===", *cpu_tables(stacks, 30), ""])
        with gzip.open(output / f"{phase}.folded.gz", "wt") as stream:
            stream.write(folded)
        # Keep the work-bearing callers visible while collapsing recursion.
        # Full native and framework stacks remain in the collapsed output.
        callers = ("Topic", "_Topic", "_Conversation", "Shell", "_Shell",
                   "_topic", "EventTopic", "AssignmentTopic", "PluginRegistry.",
                   "TextPainter.", "RenderParagraph.", "RenderSuperSliverList.",
                   "ExtentManager.", "_ItemLayout.", "_InactiveElements._unmount",
                   "ImplicitlyAnimatedWidgetState.", "ChangeNotifier.",
                   "DButton.", "_DInlineButton", "_DPopoverState.")
        compact = collections.Counter()
        for stack, count in stacks:
            kept = tuple(dict.fromkeys(frame for frame in stack
                                       if frame.startswith(callers)
                                       or "TickerProviderStateMixin" in frame))
            compact[kept or ("other UI/runtime work",)] += count
        title = (f"{output.name}: {phase} — selected Dart callers "
                 "(native cost included; recursion collapsed)")
        (output / f"{phase}.svg").write_text(flame_svg(list(compact.items()), title))
    (output / "cpu.txt").write_text("\n".join(lines))


def capture(app, output, cpu=False):
    output.unlink(missing_ok=True)
    environment = os.environ.copy()
    environment.update(TOPIC_LIST_OUTPUT=str(output.resolve()),
                       TOPIC_LIST_CPU="1" if cpu else "0",
                       FLUTTER_ENGINE_SWITCHES="1",
                       FLUTTER_ENGINE_SWITCH_1="enable-dart-profiling=false")
    process = subprocess.Popen(
        [str(app / "Contents/MacOS/Discourse")], env=environment,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
    )
    lines = queue.Queue()

    def read_lines():
        for line in process.stdout:
            lines.put(line)

    threading.Thread(target=read_lines, daemon=True).start()
    log = []
    passed = False
    expired = False
    deadline = time.monotonic() + 90
    try:
        while time.monotonic() < deadline:
            try:
                line = lines.get(timeout=1)
            except queue.Empty:
                if process.poll() is not None:
                    break
                continue
            log.append(line)
            output.with_suffix(".log").write_text("".join(log))
            if "Some tests failed" in line:
                break
            if "All tests passed!" in line:
                passed = True
                break
        expired = time.monotonic() >= deadline
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        output.with_suffix(".log").write_text("".join(log))
    if not passed or not output.exists():
        if expired:
            raise TimeoutError(f"Native test timed out; inspect {output.with_suffix('.log')}")
        raise RuntimeError(f"Workload failed; inspect {output.with_suffix('.log')}")
    data = json.loads(output.read_text())
    report = data["summary"]
    if not report["profileMode"] or report["profileCpu"] != cpu:
        raise RuntimeError("Unexpected profiling configuration")
    if report["topics"] != 3000 or report["failures"] or len(report["phases"]) != 3:
        raise RuntimeError("Incomplete or incorrect scroll workload")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", required=True, type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--cpu", action="store_true")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--runs", type=int, default=5)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    if args.cpu:
        if args.candidate:
            parser.error("CPU sampling is a separate diagnostic, not a timing comparison")
        capture(args.baseline.resolve(), args.output / "cpu.json", cpu=True)
        write_profiles(args.output / "cpu.json", args.output)
        return
    if not args.candidate or args.runs < 5:
        parser.error("Comparison requires both bundles and at least five alternating runs")
    apps = {label: getattr(args, label).resolve() for label in ("baseline", "candidate")}
    reports = {label: [] for label in apps}
    failed_attempts = []
    for repeat in range(args.runs):
        for attempt in range(3):
            pair = {}
            try:
                for label, app in apps.items():
                    report = capture(app, args.output / f"{label}-{repeat + 1}-{attempt + 1}.json")
                    pair[label] = report
                    print(f"{label} {repeat + 1}: fast down build p95 "
                          f"{report['phases']['fastDown']['build']['p95Ms']} ms", flush=True)
            except TimeoutError as error:
                failed_attempts.append(dict(pair=repeat + 1, attempt=attempt + 1,
                                            error=str(error)))
                print(f"Discarding incomplete pair {repeat + 1}: {error}", flush=True)
                if attempt == 2:
                    raise
                continue
            for label, report in pair.items():
                reports[label].append(report)
            break
    errors = []
    shapes = {(tuple(r["physicalSize"]), r["pixelRatio"], r["platform"])
              for side in reports.values() for r in side}
    if len(shapes) != 1:
        errors.append("Viewport or platform changed")
    for phase in reports["baseline"][0]["phases"]:
        samples = [r["phases"][phase] for side in reports.values() for r in side]
        distances = [abs(p["offsetAfter"] - p["offsetBefore"]) for p in samples]
        if max(distances) > min(distances) * 1.05:
            errors.append(f"{phase}: scroll distance varied by more than 5%")
        if len({p["updates"] for p in samples}) != 1:
            errors.append(f"{phase}: input count changed")
        for endpoint in ("firstTitleBefore", "firstTitleAfter"):
            rows = [int(p[endpoint].split()[1]) for p in samples]
            if max(rows) - min(rows) > 2:
                errors.append(f"{phase}: visible topics changed at {endpoint}: {rows}")
    summary = {}
    for label, side in reports.items():
        summary[label] = {}
        for phase in side[0]["phases"]:
            summary[label][phase] = {}
            for metric in ("build", "raster", "total"):
                values = [r["phases"][phase][metric]["p95Ms"] for r in side]
                summary[label][phase][metric] = dict(
                    medianP95Ms=statistics.median(values), minP95Ms=min(values),
                    maxP95Ms=max(values))
    phase_verdicts = {}
    for phase in summary["baseline"]:
        before = summary["baseline"][phase]["build"]
        after = summary["candidate"][phase]["build"]
        verdict = "inconclusive"
        if not errors:
            if after["maxP95Ms"] < before["minP95Ms"]:
                verdict = "faster"
            elif after["minP95Ms"] > before["maxP95Ms"]:
                verdict = "slower"
        phase_verdicts[phase] = verdict
    artifact = dict(
        runsPerSide=args.runs, failures=0, primaryPhase="fastDown",
        verdict=phase_verdicts["fastDown"], phaseVerdicts=phase_verdicts,
        comparisonErrors=errors, failedAttempts=failed_attempts,
        appFrameworkSha256={
            label: hashlib.sha256((app / "Contents/Frameworks/App.framework/Versions/A/App")
                                  .read_bytes()).hexdigest()
            for label, app in apps.items()}, summary=summary, runs=reports,
    )
    (args.output / "summary.json").write_text(json.dumps(artifact, indent=2) + "\n")
    print(json.dumps(artifact["summary"], indent=2))
    if errors:
        raise RuntimeError("Inconclusive comparison: " + "; ".join(errors))


if __name__ == "__main__":
    main()
