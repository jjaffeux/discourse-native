#!/usr/bin/env python3
"""Prints the architecture graph numbers for every commit in a range.

    tool/architecture_scorecard.py <base> <head>

Runs this checkout's tool/architecture_graph.dart against a detached copy of
each commit, so every row comes from the same instrument. A reviewer can rerun
it to see which commit moved which number.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

ROWS = [
    ("largest", r"largest cycle (\d+)"),
    ("cycles", r"cycles (\[[^\]]*\])"),
    ("in_cycles", r"libraries in cycles (\d+)"),
    ("mutual", r"mutual layer pairs \[([^\]]*)\]"),
    ("shell_widgets", r"widget libraries reached by ShellController (\d+)"),
    ("test_reach", r"mean application libraries per test file (\d+)"),
    ("shell_reach", r"shell_controller\.dart reaches (\d+)"),
    ("topic_reach", r"models/topic\.dart reaches (\d+)"),
    ("ui_reach", r"discourse_ui\.dart reaches (\d+)"),
]


def git(*arguments: str) -> str:
    return subprocess.run(
        ["git", "-C", str(ROOT), *arguments],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def measure(commit: str, directory: Path) -> str:
    checkout = directory / commit
    git("worktree", "add", "--quiet", "--detach", str(checkout), commit)
    try:
        return subprocess.run(
            [
                "dart",
                f"--packages={ROOT / '.dart_tool/package_config.json'}",
                "run",
                str(ROOT / "tool/architecture_graph.dart"),
            ],
            cwd=checkout,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
    finally:
        git("worktree", "remove", "--force", str(checkout))


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    base, head = sys.argv[1:]
    commits = [base, *reversed(git("rev-list", f"{base}..{head}").split())]
    print("commit\t" + "\t".join(name for name, _ in ROWS) + "\tsubject")
    with tempfile.TemporaryDirectory() as directory:
        for commit in commits:
            report = measure(commit, Path(directory))
            cells = [
                match.group(1) if (match := re.search(pattern, report)) else "?"
                for _, pattern in ROWS
            ]
            subject = git("log", "-1", "--format=%s", commit)
            print(f"{commit[:9]}\t" + "\t".join(cells) + f"\t{subject}", flush=True)


if __name__ == "__main__":
    main()
