#!/usr/bin/env python3
"""Reports what compiling one library to kernel costs.

    tool/library_kernel_cost.py [--rounds N] lib/src/some/library.dart ...

Kernel size is deterministic and answers how much code a library pulls in.
Wall time is the median across rounds and depends on machine load, so compare
it only against a control library measured in the same run.
"""

import argparse
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

DEFAULT_ENTRIES = [
    "lib/src/models/site_config.dart",
    "lib/src/models/topic.dart",
    "lib/discourse_ui.dart",
    "lib/src/data/discourse_api.dart",
    "lib/src/plugin_api/site_plugin_api.dart",
    "lib/src/shell/composer/controller.dart",
    "lib/src/shell/shell_controller.dart",
    "lib/discourse_plugin_sdk.dart",
]


def flutter_root() -> Path:
    executable = shutil.which("flutter")
    if executable is None:
        sys.exit("flutter is not on PATH")
    return Path(os.path.realpath(executable)).parent.parent


def compile_entry(root: Path, entry: str, output: Path) -> float:
    sdk = root / "bin/cache/dart-sdk"
    # The frontend server only compiles programs, so a library needs an entry.
    probe = output.with_name("probe.dart")
    probe.write_text(
        f"import 'package:discourse_native/{entry.removeprefix('lib/')}';\n"
        "void main() {}\n"
    )
    started = time.monotonic()
    result = subprocess.run(
        [
            str(sdk / "bin/dartaotruntime"),
            str(sdk / "bin/snapshots/frontend_server_aot.dart.snapshot"),
            "--sdk-root",
            str(root / "bin/cache/artifacts/engine/common/flutter_patched_sdk/"),
            "--target=flutter",
            "--packages",
            ".dart_tool/package_config.json",
            "--output-dill",
            str(output),
            "--no-link-platform",
            str(probe),
        ],
        capture_output=True,
        text=True,
    )
    elapsed = time.monotonic() - started
    if result.returncode != 0 or not output.exists():
        sys.exit(f"compiling {entry} failed:\n{result.stdout}\n{result.stderr}")
    return elapsed


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("entries", nargs="*", default=DEFAULT_ENTRIES)
    arguments = parser.parse_args()

    root = flutter_root()
    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / "out.dill"
        samples = {entry: [] for entry in arguments.entries}
        sizes = {}
        for _ in range(arguments.rounds):
            for entry in arguments.entries:
                samples[entry].append(compile_entry(root, entry, output))
                sizes[entry] = output.stat().st_size
                output.unlink()

    print("library\tkernel_bytes\tmedian_wall_seconds")
    for entry in arguments.entries:
        print(f"{entry}\t{sizes[entry]}\t{statistics.median(samples[entry]):.2f}")


if __name__ == "__main__":
    main()
