"""Build and compare the performance hot paths on Apple Silicon macOS."""

import argparse
import json
import math
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tempfile
from urllib.parse import urljoin


DRIVERS = (
    "benchmark_content_processing.dart",
    "benchmark_data_hot_paths.dart",
    "benchmark_chat_timeline.dart",
    "benchmark_search_hot_paths.dart",
)


ROUND_TWO_DRIVERS = (
    "benchmark_model_paths_round_two.dart",
    "benchmark_feed_paths_round_two.dart",
)


def baseline_packages(repo, baseline_dir, revision):
    archive = subprocess.check_output(["git", "archive", revision, "lib", "packages"])
    baseline_dir.mkdir()
    subprocess.run(["tar", "-xf", "-", "-C", baseline_dir], input=archive, check=True)
    config_path = repo / ".dart_tool/package_config.json"
    config = json.loads(config_path.read_text())
    for package in config["packages"]:
        root = urljoin(config_path.as_uri(), package["rootUri"])
        repo_uri = repo.as_uri()
        if root.rstrip("/") == repo_uri or root.startswith(repo_uri + "/packages/"):
            root = baseline_dir.as_uri() + root.removeprefix(repo_uri)
        package["rootUri"] = root
    dest = baseline_dir / "package_config.json"
    dest.write_text(json.dumps(config))
    return dest


def build(repo, flutter_sdk, driver, destination, packages):
    result = subprocess.run(
        [
            "zsh", str(repo / "tool/build_benchmark_macos_aot.sh"), str(flutter_sdk),
            str(repo / "tool" / driver), str(destination), str(packages),
        ],
        capture_output=True, text=True,
    )
    if result.returncode:
        raise RuntimeError(f"Build failed for {driver}\n{result.stdout}\n{result.stderr}")
    return destination / "Runner.app/Contents/MacOS/Runner"


def measure(binary):
    result = subprocess.run([binary], capture_output=True, text=True, timeout=120)
    if result.returncode:
        raise RuntimeError(f"{binary} failed\n{result.stdout}\n{result.stderr}")
    values = json.loads(result.stdout)
    if not values or any(
        not isinstance(value, (int, float)) or not math.isfinite(value) or value <= 0
        for value in values.values()
    ):
        raise ValueError(f"Invalid benchmark output from {binary}: {values}")
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", default="ac4e51af7")
    parser.add_argument("--flutter-sdk", type=Path)
    parser.add_argument("--runs", default=5, type=int)
    parser.add_argument("--driver", choices=DRIVERS + ROUND_TWO_DRIVERS, action="append")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.runs < 5:
        parser.error("Use at least five runs per revision")
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("This runner requires Apple Silicon macOS")
    flutter = shutil.which("flutter")
    flutter_sdk = args.flutter_sdk or (Path(flutter).resolve().parent.parent if flutter else None)
    if not flutter_sdk:
        parser.error("Put Flutter on PATH or pass --flutter-sdk")
    repo = Path(__file__).resolve().parents[1]
    if Path.cwd() != repo:
        parser.error("Run from the repository root")
    revision = subprocess.check_output(
        ["git", "rev-parse", args.baseline], text=True,
    ).strip()
    rows = {}
    with tempfile.TemporaryDirectory(prefix="discourse-perf-") as workspace:
        temp = Path(workspace)
        configs = {
            "before": baseline_packages(repo, temp / "baseline", revision),
            "after": repo / ".dart_tool/package_config.json",
        }
        for driver in args.driver or DRIVERS:
            print(f"Building {driver}", flush=True)
            binaries = {
                side: build(repo, flutter_sdk, driver, temp / driver / side, config)
                for side, config in configs.items()
            }
            for run in range(args.runs):
                order = ("before", "after") if run % 2 == 0 else ("after", "before")
                pair = {side: measure(binaries[side]) for side in order}
                before, after = pair["before"], pair["after"]
                if before.keys() != after.keys():
                    raise ValueError(f"Workloads differ between builds of {driver}")
                for key in before:
                    row = rows.setdefault(key, {"before": [], "after": []})
                    row["before"].append(before[key])
                    row["after"].append(after[key])
            for key in before:
                row = rows[key]
                print(
                    f"{key}: "
                    + " → ".join(
                        f"{statistics.median(samples):.3f} "
                        f"[{min(samples):.3f}, {max(samples):.3f}]"
                        for samples in row.values()
                    )
                    + " µs",
                    flush=True,
                )
    args.output.write_text(json.dumps({
        "baseline": revision,
        "platform": platform.platform(),
        "unit": "microseconds per operation",
        "runs": rows,
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
