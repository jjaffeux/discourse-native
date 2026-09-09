"""Behavioral checks for the shared reviewer leases and desktop waiting order."""

import concurrent.futures
import json
from pathlib import Path
import subprocess
import tempfile
import unittest


LOCK_TOOL = Path(__file__).with_name("component_review_lock.py")


class ReviewLockTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="review-lease-test-")
        self.addCleanup(self.directory.cleanup)
        self.repo = self.directory.name
        subprocess.run(["git", "init", "-q", self.repo], check=True)

    def run_tool(self, action, scope="desktop", owner=None, token=None):
        command = ["python3", str(LOCK_TOOL), action, scope, "--repo", self.repo]
        if owner is not None:
            command.extend(["--owner", owner])
        if token is not None:
            command.extend(["--token", token])
        result = subprocess.run(command, text=True, capture_output=True)
        self.assertTrue(result.stdout, result.stderr)
        return result.returncode, json.loads(result.stdout)

    def release(self, lease, scope="desktop"):
        code, result = self.run_tool("release", scope, lease["owner"], lease["token"])
        self.assertEqual(code, 0)
        self.assertTrue(result["released"])

    def test_main_contenders_have_one_owner_and_independent_desktop(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(
                lambda i: self.run_tool("acquire", "main", f"owner-{i}"), range(8)
            ))
        winners = [result for code, result in results if code == 0]
        self.assertEqual(len(winners), 1)
        self.assertEqual(sum(code == 75 for code, _ in results), 7)
        self.assertEqual(self.run_tool("acquire", owner="desktop-owner")[0], 0)
        self.release(winners[0]["lease"], "main")
        self.assertEqual(self.run_tool("acquire", "main", "next")[0], 0)

    def test_desktop_waiters_keep_order_and_cannot_be_overtaken(self):
        _, holder = self.run_tool("acquire", owner="holder")
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(
                lambda i: self.run_tool("acquire", owner=f"waiter-{i}"), range(8)
            ))
        self.assertTrue(all(code == 75 for code, _ in results))
        _, state = self.run_tool("status")
        order = [request["owner"] for request in state["queue"]]
        self.assertEqual(len(set(order)), 8)
        self.run_tool("acquire", owner=order[-1])
        self.assertEqual(self.run_tool("status")[1]["queue"], state["queue"])
        self.release(holder["lease"])
        code, late = self.run_tool("acquire", owner="late")
        self.assertEqual(code, 75)
        self.assertEqual(late["nextOwner"], order[0])
        self.assertIsNone(late["lease"])
        for owner in order + ["late"]:
            code, acquired = self.run_tool("acquire", owner=owner)
            self.assertEqual(code, 0)
            self.release(acquired["lease"])
        self.assertEqual(self.run_tool("status")[1]["queue"], [])

    def test_cancel_does_not_release_holder_and_tokens_are_required(self):
        _, holder = self.run_tool("acquire", owner="holder")
        lease = holder["lease"]
        self.assertEqual(self.run_tool("acquire", owner="holder")[1]["lease"], lease)
        self.assertEqual(self.run_tool("release", owner="wrong", token=lease["token"])[0], 76)
        self.assertEqual(self.run_tool("release", owner="holder", token="wrong")[0], 76)
        self.run_tool("acquire", owner="cancel-me")
        self.run_tool("acquire", owner="next")
        self.assertTrue(self.run_tool("cancel", owner="cancel-me")[1]["cancelled"])
        self.run_tool("cancel", owner="holder")
        self.assertEqual(self.run_tool("status")[1]["lease"], lease)
        self.release(lease)
        self.assertEqual(self.run_tool("acquire", owner="next")[0], 0)


if __name__ == "__main__":
    unittest.main()
