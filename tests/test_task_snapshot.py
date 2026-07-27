#!/usr/bin/env python3

import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "task_snapshot.py"


class TaskSnapshotTests(unittest.TestCase):
    def run_snapshot(self, *arguments, env=None):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *map(str, arguments)],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_files_provider_normalizes_markdown_org_and_missing_sources(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            markdown = root / "active.md"
            org = root / "project.org"
            missing = root / "missing.md"
            markdown.write_text(
                """# Tasks

## Active
- [ ] Current task
- [ ] [NEXT] Ship snapshot
- [x] Completed task

## Waiting
- [ ] Await review

## Blocked
- [ ] Need credentials

## Inbox
- [ ] Triage notes
""",
                encoding="utf-8",
            )
            org.write_text(
                """#+title: Project Tasks
* Project
** STARTED Active org task :dev:
** TODO [#A] Follow-up task
** CANCELLED Retired task
""",
                encoding="utf-8",
            )

            first = self.run_snapshot(
                "--source",
                markdown,
                "--sources",
                f"{org}:{missing}",
            )
            snapshot = json.loads(first.stdout)

            self.assertEqual(snapshot["version"], 1)
            self.assertEqual(snapshot["provider"], "files")
            self.assertTrue(snapshot["generated_at"].endswith("Z"))
            self.assertEqual(len(snapshot["sources"]), 3)
            self.assertEqual(snapshot["sources"][2]["error"], "missing")
            self.assertFalse(snapshot["sources"][2]["exists"])

            counts = snapshot["counts"]
            self.assertEqual(counts["total"], 9)
            self.assertEqual(counts["open"], 7)
            self.assertEqual(counts["closed"], 2)
            self.assertEqual(counts["active"], 2)
            self.assertEqual(counts["next"], 1)
            self.assertEqual(counts["waiting"], 1)
            self.assertEqual(counts["blocked"], 1)
            self.assertEqual(counts["todo"], 2)
            self.assertEqual(counts["done"], 1)
            self.assertEqual(counts["cancelled"], 1)

            self.assertEqual(snapshot["focus"]["title"], "Current task")
            self.assertEqual(snapshot["next"]["title"], "Ship snapshot")
            self.assertEqual(snapshot["waiting"]["title"], "Await review")
            self.assertEqual(snapshot["blocked"]["title"], "Need credentials")
            org_active = next(task for task in snapshot["tasks"] if task["title"] == "Active org task")
            self.assertEqual(org_active["state"], "ACTIVE")
            self.assertEqual(org_active["section"], "Project")
            self.assertEqual(len(org_active["id"]), 64)

            second = json.loads(
                self.run_snapshot("--source", markdown, "--source", org).stdout
            )
            first_ids = {task["title"]: task["id"] for task in snapshot["tasks"]}
            second_ids = {task["title"]: task["id"] for task in second["tasks"]}
            for title, identity in second_ids.items():
                self.assertEqual(identity, first_ids[title])

    def test_output_is_atomic_and_stdout_stays_empty(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "tasks.md"
            output = root / "cache" / "snapshot.json"
            source.write_text("## Next\n- [ ] First task\n", encoding="utf-8")

            result = self.run_snapshot("--source", source, "--output", output)
            self.assertEqual(result.stdout, "")
            snapshot = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(snapshot["focus"]["title"], "First task")
            self.assertEqual(snapshot["next"], None)
            self.assertEqual(list(output.parent.glob(f".{output.name}.*.tmp")), [])

            source.write_text("## Active\n- [ ] Replacement task\n", encoding="utf-8")
            self.run_snapshot("--source", source, "--output", output)
            replacement = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(replacement["focus"]["title"], "Replacement task")

    def test_barista_fields_share_snapshot_process_and_render_focus_state(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "tasks.md"
            output = root / "cache" / "snapshot.json"
            state_file = root / "focus-state.json"
            source.write_text(
                """## Active
- [ ] Current task with a title long enough to require compact rendering

## Next
- [ ] Follow-up

## Waiting
- [ ] Await review
""",
                encoding="utf-8",
            )
            started_at = dt.datetime(2000, 1, 1, tzinfo=dt.timezone.utc)
            ends_at = started_at + dt.timedelta(minutes=25)
            state_file.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "state": "active",
                        "duration_minutes": 25,
                        "started_at": started_at.isoformat().replace("+00:00", "Z"),
                        "ends_at": ends_at.isoformat().replace("+00:00", "Z"),
                    }
                ),
                encoding="utf-8",
            )

            result = self.run_snapshot(
                "--source",
                source,
                "--output",
                output,
                "--barista-fields",
                "--focus-state-file",
                state_file,
            )

            self.assertTrue(output.is_file())
            self.assertEqual(
                result.stdout.splitlines(),
                [
                    "bar\t3",
                    "summary\t3 open · 1 active · 1 next",
                    "focus\tFocus: Current task with a title long enough t…",
                    "next\tNext: Follow-up",
                    "waiting\tWaiting: Await review",
                    "blocked\tBlocked: Clear",
                    "timer\tFocus Session complete · start 25m",
                ],
            )
            snapshot = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(
                snapshot["focus"]["title"],
                "Current task with a title long enough to require compact rendering",
            )

    def test_syshelp_is_only_used_when_explicitly_selected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            log = root / "syshelp.log"
            payload_file = root / "payload.json"
            task_file = root / "syshelp-tasks.md"
            task_file.write_text("# fixture\n", encoding="utf-8")
            payload_file.write_text(
                json.dumps(
                    {
                        "file": str(task_file),
                        "sections": [
                            {
                                "name": "Active",
                                "tasks": [
                                    {
                                        "line": 4,
                                        "state": "ACTIVE",
                                        "title": "Provider focus",
                                        "open": True,
                                    },
                                    {
                                        "line": 5,
                                        "state": "NEXT",
                                        "title": "Provider next",
                                        "open": True,
                                    },
                                ],
                            },
                            {
                                "name": "Waiting",
                                "tasks": [
                                    {
                                        "line": 8,
                                        "state": "WAITING",
                                        "title": "Provider wait",
                                        "open": True,
                                    }
                                ],
                            },
                        ],
                    }
                ),
                encoding="utf-8",
            )
            syshelp = bin_dir / "syshelp"
            syshelp.write_text(
                """#!/bin/sh
printf '%s\n' "$*" > "$TASK_SNAPSHOT_SYSHELP_LOG"
cat "$TASK_SNAPSHOT_SYSHELP_PAYLOAD"
""",
                encoding="utf-8",
            )
            syshelp.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
            env["TASK_SNAPSHOT_SYSHELP_LOG"] = str(log)
            env["TASK_SNAPSHOT_SYSHELP_PAYLOAD"] = str(payload_file)

            default_snapshot = json.loads(self.run_snapshot(env=env).stdout)
            self.assertEqual(default_snapshot["provider"], "files")
            self.assertFalse(log.exists())

            explicit = self.run_snapshot("--provider", "syshelp", env=env)
            snapshot = json.loads(explicit.stdout)
            self.assertEqual(log.read_text(encoding="utf-8").strip(), "plan tasks json")
            self.assertEqual(snapshot["provider"], "syshelp")
            self.assertEqual(snapshot["counts"]["total"], 3)
            self.assertEqual(snapshot["focus"]["title"], "Provider focus")
            self.assertEqual(snapshot["next"]["title"], "Provider next")
            self.assertEqual(snapshot["waiting"]["title"], "Provider wait")
            self.assertIsNone(snapshot["blocked"])

            explicit_path = self.run_snapshot(
                "--provider",
                "syshelp",
                "--syshelp-bin",
                syshelp,
                env={**env, "PATH": "/usr/bin:/bin"},
            )
            self.assertEqual(json.loads(explicit_path.stdout)["focus"]["title"], "Provider focus")


if __name__ == "__main__":
    unittest.main()
