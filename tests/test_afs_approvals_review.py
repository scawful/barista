#!/usr/bin/env python3
"""bin/afs-approvals-review drives `afs approvals` by request id, never on its own."""
from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REVIEWER = ROOT / "bin" / "afs-approvals-review"

PENDING = [
    {"agent": "mission-runner", "action": "file_delete", "detail": "Mission 'git-hygiene'",
     "timestamp": "2026-07-16T21:50:54+00:00", "status": "pending", "request_id": "gate_older000000"},
    {"agent": "mission-runner", "action": "git_push", "detail": "Mission 'pr-review-prep'",
     "timestamp": "2026-09-01T10:00:00+00:00", "status": "pending", "request_id": "gate_newer000000"},
]

FAKE_AFS = r'''#!/usr/bin/env python3
# Stand-in for `python -m afs`: logs every call, serves `approvals list --json`
# from a fixture, and drops a request from the fixture on approve/reject so the
# reviewer sees the queue shrink.
import json, sys, pathlib
log = pathlib.Path(__import__("os").environ["FAKE_AFS_LOG"])
fixture = pathlib.Path(__import__("os").environ["FAKE_AFS_FIXTURE"])
args = sys.argv[1:]
with log.open("a") as fh:
    fh.write(json.dumps(args) + "\n")
if args[:2] == ["approvals", "list"]:
    print(fixture.read_text())
    sys.exit(0)
if args[0] == "approvals" and args[1] in ("approve", "reject"):
    rid = args[args.index("--request-id") + 1]
    rows = [r for r in json.loads(fixture.read_text()) if r["request_id"] != rid]
    fixture.write_text(json.dumps(rows))
    print(f"{args[1]}d {rid}")
    sys.exit(0)
sys.exit(64)
'''


class ReviewerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.fake = base / "fake_afs.py"
        self.fake.write_text(FAKE_AFS)
        self.fake.chmod(self.fake.stat().st_mode | stat.S_IXUSR)
        self.log = base / "calls.log"
        self.fixture = base / "pending.json"
        self.fixture.write_text(json.dumps(PENDING))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_reviewer(self, stdin: str, *args: str) -> subprocess.CompletedProcess:
        env = dict(os.environ)
        env.update({
            "BARISTA_AFS_REVIEW_CMD": f"{sys.executable} {self.fake}",
            "FAKE_AFS_LOG": str(self.log),
            "FAKE_AFS_FIXTURE": str(self.fixture),
        })
        env.pop("AFS_APPROVALS_FILE", None)
        return subprocess.run(
            [sys.executable, str(REVIEWER), *args],
            input=stdin, text=True, capture_output=True, env=env, check=False,
        )

    def calls(self) -> list[list[str]]:
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines() if line.strip()]

    def test_lists_oldest_first_and_quits(self) -> None:
        result = self.run_reviewer("q\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("2 pending approval(s)", result.stdout)
        self.assertLess(result.stdout.index("gate_older000000"), result.stdout.index("gate_newer000000"))
        self.assertEqual(self.calls(), [["approvals", "list", "--json"]])

    def test_approve_by_number_passes_request_id_and_rationale(self) -> None:
        result = self.run_reviewer("approve 2\npr drafts reviewed\nq\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        decisions = [c for c in self.calls() if c[1] in ("approve", "reject")]
        self.assertEqual(decisions, [
            ["approvals", "approve", "--request-id", "gate_newer000000", "--because", "pr drafts reviewed"],
        ])
        # The queue was re-read after the decision.
        self.assertEqual(sum(1 for c in self.calls() if c[:2] == ["approvals", "list"]), 2)

    def test_preselected_request_from_badge_click(self) -> None:
        result = self.run_reviewer("reject\nstale since July\nq\n", "--request-id", "gate_older000000")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Selected gate_older000000", result.stdout)
        decisions = [c for c in self.calls() if c[1] in ("approve", "reject")]
        self.assertEqual(decisions, [
            ["approvals", "reject", "--request-id", "gate_older000000", "--because", "stale since July"],
        ])

    def test_empty_rationale_changes_nothing(self) -> None:
        result = self.run_reviewer("approve 1\n\nq\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("rationale is required", result.stdout)
        self.assertEqual([c for c in self.calls() if c[1] != "list"], [])

    def test_bad_input_is_explained_not_executed(self) -> None:
        result = self.run_reviewer("approve 9\nyes\nq\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Type `approve 2`", result.stdout)
        self.assertEqual([c for c in self.calls() if c[1] != "list"], [])

    def test_custom_queue_path_is_forwarded(self) -> None:
        env_backup = os.environ.get("AFS_APPROVALS_FILE")
        os.environ["AFS_APPROVALS_FILE"] = "/tmp/custom.json"
        try:
            env = dict(os.environ)
            env.update({
                "BARISTA_AFS_REVIEW_CMD": f"{sys.executable} {self.fake}",
                "FAKE_AFS_LOG": str(self.log),
                "FAKE_AFS_FIXTURE": str(self.fixture),
            })
            subprocess.run([sys.executable, str(REVIEWER)], input="q\n", text=True,
                           capture_output=True, env=env, check=False)
        finally:
            if env_backup is None:
                os.environ.pop("AFS_APPROVALS_FILE", None)
            else:
                os.environ["AFS_APPROVALS_FILE"] = env_backup
        self.assertEqual(self.calls()[0], ["approvals", "--approvals-file", "/tmp/custom.json", "list", "--json"])


if __name__ == "__main__":
    unittest.main()
