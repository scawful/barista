#!/usr/bin/env python3

import datetime as dt
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "agent_sessions.py"


def write_jsonl(path, *records):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("".join(json.dumps(record) + "\n" for record in records), encoding="utf-8")


class AgentSessionsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.config = self.home / "barista-config"
        today = dt.date.today()
        self.codex_day = codex_day = (self.home / ".codex" / "sessions"
                                      / f"{today:%Y}" / f"{today:%m}" / f"{today:%d}")
        resets = int(time.time()) + 3 * 86400
        write_jsonl(
            codex_day / "rollout-main.jsonl",
            {"type": "session_meta", "payload": {"cwd": "/work/oracle-of-secrets", "thread_source": "user"}},
            {"type": "event_msg", "payload": {"rate_limits": {
                "primary": {"used_percent": 88.0, "window_minutes": 10080, "resets_at": resets},
                "secondary": None,
            }}},
        )
        write_jsonl(
            codex_day / "rollout-sub.jsonl",
            {"type": "session_meta", "payload": {"cwd": "/work/oracle-of-secrets", "thread_source": "subagent"}},
        )
        stale = codex_day / "rollout-stale.jsonl"
        write_jsonl(stale, {"type": "session_meta", "payload": {"cwd": "/work/old"}})
        old = time.time() - 3600
        os.utime(stale, (old, old))

        sessions = self.home / ".claude" / "sessions"
        sessions.mkdir(parents=True)
        (sessions / "live.json").write_text(json.dumps({
            "pid": os.getpid(), "sessionId": "cli-live", "name": "Oracle review", "cwd": "/work/oracle",
            "entrypoint": "cli", "status": "busy", "updatedAt": int(time.time() * 1000),
        }), encoding="utf-8")
        (sessions / "dead.json").write_text(json.dumps({
            "pid": 999999, "name": "Gone", "entrypoint": "claude-desktop", "status": "idle",
        }), encoding="utf-8")

        self.transcripts = self.home / ".cursor" / "projects" / "tmp-project" / "agent-transcripts"
        write_jsonl(self.transcripts / "abc" / "abc.jsonl", {"role": "user", "message": {"content": [
            {"type": "text", "text": "<timestamp>x</timestamp>\n<user_query>\nfix the popup lag please\n</user_query>"},
        ]}})

    def tearDown(self):
        self.temp.cleanup()

    def run_script(self, *arguments, extra_env=None):
        env = dict(os.environ, BARISTA_AGENTS_HOME=str(self.home), BARISTA_CONFIG_DIR=str(self.config),
                   BARISTA_AGENT_BADGES_FILE=str(self.home / "badges.json"))
        env.update(extra_env or {})
        result = subprocess.run([sys.executable, str(SCRIPT), *arguments], capture_output=True,
                                text=True, env=env, check=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_snapshot_counts_live_sessions_only(self):
        snap = json.loads(self.run_script("json").stdout)
        counts = snap["counts"]
        self.assertEqual(counts["codex"], 1, "subagent and stale rollouts are not sessions")
        self.assertEqual(counts["claude"], 1, "dead pids are not sessions")
        self.assertEqual(counts["cursor"], 1)
        titles = {s["tool"]: s for s in snap["sessions"]}
        self.assertEqual(titles["codex"]["title"], "oracle-of-secrets")
        self.assertEqual(titles["claude"]["target"], f"pid:{os.getpid()}")
        self.assertEqual(titles["cursor"]["title"], "fix the popup lag please")
        self.assertEqual(snap["usage"]["codex"], "88% wk")

    def test_resumed_codex_sessions_in_older_day_folders_are_listed(self):
        started = dt.date.today() - dt.timedelta(days=5)
        write_jsonl(
            self.home / ".codex" / "sessions" / f"{started:%Y}" / f"{started:%m}" / f"{started:%d}"
            / "rollout-resumed.jsonl",
            {"type": "session_meta", "payload": {"cwd": "/work/yaze", "thread_source": "user"}},
        )
        snap = json.loads(self.run_script("json").stdout)
        ids = {s["id"] for s in snap["sessions"]}
        self.assertIn("codex:rollout-resumed", ids, "a resumed session writes into its start-day folder")

    def test_archived_chats_are_hidden_and_app_names_win(self):
        archived_rollout = self.codex_day / "rollout-archived.jsonl"
        write_jsonl(archived_rollout, {"type": "session_meta", "payload": {"cwd": "/work/done"}})
        with sqlite3.connect(self.home / ".codex" / "state_5.sqlite") as db:
            db.execute("create table threads (rollout_path text, archived integer, name text)")
            db.executemany("insert into threads values (?, ?, ?)", [
                (str(self.codex_day / "rollout-main.jsonl"), 0, "Oracle Coordinator"),
                (str(archived_rollout), 1, "Finished"),
            ])

        (self.home / ".claude" / "sessions" / "archived.json").write_text(json.dumps({
            "pid": os.getpid(), "sessionId": "cli-archived", "entrypoint": "claude-desktop",
            "status": "idle", "updatedAt": int(time.time() * 1000),
        }), encoding="utf-8")
        desktop = (self.home / "Library" / "Application Support" / "Claude"
                   / "claude-code-sessions" / "account" / "org")
        desktop.mkdir(parents=True)
        (desktop / "local_a.json").write_text(json.dumps(
            {"cliSessionId": "cli-live", "title": "Desktop title", "isArchived": False}), encoding="utf-8")
        (desktop / "local_b.json").write_text(json.dumps(
            {"cliSessionId": "cli-archived", "title": "Archived", "isArchived": True}), encoding="utf-8")

        write_jsonl(self.transcripts / "def" / "def.jsonl", {"role": "user", "message": {"content": []}})
        cursor_db = self.home / "Library" / "Application Support" / "Cursor" / "User" / "globalStorage"
        cursor_db.mkdir(parents=True)
        with sqlite3.connect(cursor_db / "state.vscdb") as db:
            db.execute("create table cursorDiskKV (key text unique, value blob)")
            db.executemany("insert into cursorDiskKV values (?, ?)", [
                ("composerData:abc", json.dumps({"name": "Popup lag"})),
                ("composerData:def", json.dumps({"name": "Done", "isArchived": True})),
            ])

        snap = json.loads(self.run_script("json").stdout)
        self.assertEqual(snap["counts"], {"codex": 1, "claude": 1, "cursor": 1, "gemini": 0})
        titles = {s["tool"]: s["title"] for s in snap["sessions"]}
        self.assertEqual(titles, {"codex": "Oracle Coordinator", "claude": "Desktop title",
                                  "cursor": "Popup lag"})

    def test_apply_sets_bar_rows_and_slots_in_one_call(self):
        log = self.home / "sketchybar.log"
        fake = self.home / "sketchybar"
        fake.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$@\" >> {log}\n", encoding="utf-8")
        fake.chmod(0o755)
        self.run_script("apply", extra_env={"BARISTA_SKETCHYBAR_BIN": str(fake), "BARISTA_AGENTS_ROWS": "4"})
        args = log.read_text(encoding="utf-8").splitlines()
        self.assertEqual(args[:3], ["--set", "agents", "label="], "no number while nothing needs you")
        self.assertEqual(args[args.index("agents.tool.codex") + 1], "label=Codex 1 · 88% wk")
        self.assertEqual(args[args.index("agents.tool.gemini") + 1], "label=Gemini")
        self.assertIn("agents.session.4", args)
        session_clicks = [a for a in args if a.startswith("click_script=")]
        self.assertTrue(any("focus 'pid:" in a or f"focus pid:{os.getpid()}" in a for a in session_clicks))
        self.assertTrue(all("popup.drawing=off" in a for a in session_clicks))

        badges = json.loads((self.home / "badges.json").read_text(encoding="utf-8"))
        self.assertEqual(badges["needs"], {}, "running sessions alone badge nothing")
        self.assertLessEqual(abs(badges["updated"] - time.time()), 60)

        dock = {s["id"]: s for s in badges["sessions"]}
        claude = dock["claude:cli-live"]
        self.assertEqual(claude["app"], "com.anthropic.claudefordesktop")
        self.assertTrue(claude["working"], "a busy Claude session is working")
        self.assertIn("focus", claude["focus"])
        self.assertIn(f"pid:{os.getpid()}", claude["focus"])
        self.assertTrue(dock["codex:rollout-main"]["working"], "a rollout written just now is working")
        self.assertEqual(dock["cursor:abc"]["app"], "com.todesktop.230313mzl4w4u92")
        self.assertEqual(badges["usage"], {"com.openai.codex": "88% wk"})

    def test_sessions_waiting_on_you_are_flagged_listed_first_and_badged(self):
        hours_ago = time.time() - 7200
        (self.home / ".claude" / "sessions" / "live.json").write_text(json.dumps({
            "pid": os.getpid(), "sessionId": "cli-live", "name": "Oracle review", "entrypoint": "claude-desktop",
            "status": "waiting", "waitingFor": "permission dialog", "updatedAt": int(hours_ago * 1000),
        }), encoding="utf-8")

        def codex_rollout(name, *records):
            path = self.codex_day / name
            write_jsonl(path, {"type": "session_meta", "payload": {"cwd": f"/work/{name}"}}, *records)
            os.utime(path, (hours_ago, hours_ago))

        ask = {"type": "response_item", "payload": {
            "type": "function_call", "name": "request_user_input_async",
            "arguments": json.dumps({"questions": [{"title": "Which ROM should I test?"}]})}}
        reply = {"type": "response_item", "payload": {"type": "message", "role": "user", "content": []}}
        codex_rollout("rollout-asking.jsonl", ask)
        codex_rollout("rollout-answered.jsonl", ask, reply)

        write_jsonl(self.transcripts / "plan" / "plan.jsonl", {"role": "assistant", "message": {"content": [
            {"type": "tool_use", "name": "CreatePlan", "input": {"name": "Dock modes"}},
        ]}})
        os.utime(self.transcripts / "plan" / "plan.jsonl", (hours_ago, hours_ago))

        snap = json.loads(self.run_script("json").stdout)
        needs = {s["id"]: s["needs"] for s in snap["sessions"] if s["needs"]}
        self.assertEqual(needs, {
            "codex:rollout-asking": "Which ROM should I test?",
            "claude:cli-live": "Permission dialog",
            "cursor:plan": "Plan ready: Dock modes",
        })
        ids = [s["id"] for s in snap["sessions"]]
        self.assertNotIn("codex:rollout-answered", ids, "an answered question in a quiet rollout drops out")
        self.assertEqual(set(ids[:3]), set(needs), "sessions that need you come first")
        self.assertEqual(snap["needs"], {"codex": 1, "claude": 1, "cursor": 1, "gemini": 0})

        log = self.home / "sketchybar.log"
        fake = self.home / "sketchybar"
        fake.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$@\" >> {log}\n", encoding="utf-8")
        fake.chmod(0o755)
        self.run_script("apply", extra_env={"BARISTA_SKETCHYBAR_BIN": str(fake)})
        args = log.read_text(encoding="utf-8").splitlines()
        self.assertEqual(args[2], "label=3")
        self.assertIn("label=Cursor 2 · 1 need you", args)
        badges = json.loads((self.home / "badges.json").read_text(encoding="utf-8"))
        self.assertEqual(badges["needs"], {"com.openai.codex": 1, "com.anthropic.claudefordesktop": 1,
                                           "com.todesktop.230313mzl4w4u92": 1})
        dock = {s["id"]: s for s in badges["sessions"]}
        self.assertEqual(dock["cursor:plan"]["needs"], "Plan ready: Dock modes")

    def test_a_broken_source_or_missing_bar_still_writes_the_dock_feed(self):
        (self.home / ".claude" / "sessions" / "live.json").write_text(json.dumps({
            "pid": os.getpid(), "sessionId": "cli-live", "updatedAt": "soon",
        }), encoding="utf-8")
        result = self.run_script("apply", extra_env={"BARISTA_SKETCHYBAR_BIN": str(self.home / "missing")})
        self.assertIn("claude_sessions failed", result.stderr)
        self.assertIn("could not update the bar", result.stderr)
        badges = json.loads((self.home / "badges.json").read_text(encoding="utf-8"))
        tools = {s["id"].split(":")[0] for s in badges["sessions"]}
        self.assertEqual(tools, {"codex", "cursor"}, "only the broken source drops out")

    def test_quiet_transcripts_are_not_working(self):
        quiet = time.time() - 300
        os.utime(self.codex_day / "rollout-main.jsonl", (quiet, quiet))
        snap = json.loads(self.run_script("json").stdout)
        codex = next(s for s in snap["sessions"] if s["tool"] == "codex")
        self.assertFalse(codex["working"])
        self.assertEqual(codex["detail"], "5m")


if __name__ == "__main__":
    unittest.main()
