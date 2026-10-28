#!/usr/bin/env python3

import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "dock_oracle.py"
REAL_RECEIPT = Path.home() / "src/hobby/oracle-of-secrets/Scripts/Build/build_receipt.py"

STATUS = {
    "git": {"available": True, "branch": "master", "ahead": 0, "behind": 0,
            "modified": 2, "added": 1, "deleted": 0, "renamed": 0, "untracked": 0},
    "tracker": {"path": "/repo/Docs/oracle.org", "active": [
        {"priority": "B", "title": "Minecarts"}, {"priority": "A", "title": "Zora Temple"}]},
    "paths": {"tracker": "/repo/Docs/oracle.org", "runbook": "/repo/Docs/RUNBOOK.md"},
    "finish_line": {"focus": {"label": "Build", "title": "Build the patched ROM", "action": "quick-build"}},
    "alerts": ["Patched ROM is missing.", "flips is not on PATH.", "Registry has many stale active instances."],
}
PLAY_CLOSED = {"play_window": {"open": False}, "latest": "v0.9.0-b46", "heavy_lock": None}


def load_module():
    spec = importlib.util.spec_from_file_location("dock_oracle", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["dock_oracle"] = module
    spec.loader.exec_module(module)
    return module


def stub(path: Path, body: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("#!/bin/bash\n" + body + "\n")
    path.chmod(0o755)


@unittest.skipUnless(REAL_RECEIPT.is_file(), "needs Oracle's build_receipt.py")
class DockOracleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        base = Path(self.temp.name)
        self.repo = base / "repo"
        self.roms = self.repo / "Roms"
        self.roms.mkdir(parents=True)
        (self.repo / "Oracle_main.asm").write_text("incsrc Core/a.asm\n")
        (self.repo / "Core").mkdir()
        (self.repo / "Core/a.asm").write_text("lda #$01\n")
        (self.repo / "Scripts/Build").mkdir(parents=True)
        shutil.copy(REAL_RECEIPT, self.repo / "Scripts/Build/build_receipt.py")
        (self.roms / "oos168.sfc").write_bytes(b"base-168")
        self.reports = base / "reports"
        # Unix socket paths are limited to ~104 bytes; macOS temp dirs are long.
        self.sockets = Path(tempfile.mkdtemp(dir="/tmp", prefix="dock-oracle-"))
        self.listeners = []
        self.binding_path = base / "oracle.json"
        self.bind()

    def tearDown(self):
        for listener in self.listeners:
            listener.close()
        shutil.rmtree(self.sockets, ignore_errors=True)
        self.temp.cleanup()

    def bind(self, **extra):
        data = {"repo": str(self.repo), "version": 168, **extra}
        self.binding_path.write_text(json.dumps(data))

    def env(self):
        return {**os.environ, "BARISTA_ORACLE_BINDING": str(self.binding_path),
                "BARISTA_MESEN_SOCKET_DIR": str(self.sockets), "BARISTA_ORACLE_REPORTS": str(self.reports)}

    def cli(self, *args, check=False):
        return subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, text=True,
                              env=self.env(), check=check)

    def rows(self, status=STATUS, play=PLAY_CLOSED):
        files = []
        for name, payload in (("status", status), ("play", play)):
            path = self.repo / f"{name}.json"
            path.write_text(json.dumps(payload))
            files += [f"--{name}", str(path)]
        return json.loads(self.cli("info", *files, check=True).stdout)["rows"]

    def receipt(self, exit_code=0, smoke="unavailable"):
        receipt = self.roms / "oos168x.build.json"
        receipt.unlink(missing_ok=True)
        (self.roms / "oos168x.sfc").write_bytes(b"built-168")
        tool = [sys.executable, str(self.repo / "Scripts/Build/build_receipt.py")]
        steps = [["init", "--root", str(self.repo), "--base-rom", str(self.roms / "oos168.sfc"),
                  "--version", "168", "--requested-profile", "defaults", "--assembler", "asar"],
                 ["snapshot", "--phase", "pre_assembly"],
                 ["artifact", "--name", "output_rom", "--path", str(self.roms / "oos168x.sfc")],
                 ["check", "--name", "smoke", "--status", smoke, "--required", "0", "--detail", "x"],
                 ["finish", "--exit-code", str(exit_code), "--stage", "complete"]]
        for step in steps:
            subprocess.run(tool + [step[0], "--receipt", str(receipt), *step[1:]], check=step[0] != "finish",
                           capture_output=True, text=True)

    def built(self):
        return next(row for row in self.rows() if row.get("action") == "Build ROM")

    # Built: the receipt, not file dates, decides.

    def test_a_verified_build_is_green_and_says_runtime_is_untested(self):
        self.receipt()
        row = self.built()
        self.assertEqual((row["title"], row["tone"]), ("Built 168 · passed with gaps", "ok"))
        self.assertIn("runtime untested", row["detail"])

    def test_partial_output_or_missing_receipt_is_never_green(self):
        self.receipt()
        (self.roms / "oos168x.sfc").write_bytes(b"failed assembly partial output")
        row = self.built()
        self.assertEqual(row["tone"], "error")
        self.assertIn("doesn't match its receipt", row["title"])
        (self.roms / "oos168x.build.json").unlink()
        row = self.built()
        self.assertEqual((row["title"], row["tone"]), ("Built 168 · no receipt", "warn"))

    def test_failed_builds_and_changed_inputs_are_reported(self):
        self.receipt(exit_code=1)
        row = self.built()
        self.assertEqual(row["tone"], "error")
        self.assertIn("failed", row["title"])
        self.receipt()
        (self.repo / "Core/a.asm").write_text("lda #$02\n")
        self.assertEqual(self.built()["title"], "Built 168 · 1 source files changed since")
        self.receipt()
        (self.roms / "oos168.sfc").write_bytes(b"restored older base")
        self.assertEqual(self.built()["title"], "Built 168 · base ROM changed since")

    def test_another_base_never_changes_the_bound_version(self):
        self.receipt()
        (self.roms / "oos169.sfc").write_bytes(b"newer base")
        self.assertEqual(self.cli("version", check=True).stdout.strip(), "168")
        self.assertEqual(self.built()["title"], "Built 168 · passed with gaps")

    def test_malformed_status_keeps_the_rows_it_can_and_never_loses_them_all(self):
        status = json.loads(json.dumps(STATUS))
        status["git"].update(modified=None, untracked="2", behind=1)
        status["alerts"] = [7, "flips is not on PATH."]
        rows = self.rows(status=status)
        self.assertIn({"title": "master", "detail": "1 changed · 1 behind", "tone": "warn"}, rows)
        self.assertIn("flips is not on PATH.", [row["title"] for row in rows])
        for payload in (["not", "an object"], None):
            rows = self.rows(status=payload)
            self.assertEqual([row["tone"] for row in rows], ["error"])
        rows = self.rows(status={**STATUS, "paths": {}, "tracker": "not an object"})
        self.assertEqual([(row["title"], row["tone"]) for row in rows], [("Oracle status error", "error")])
        self.assertIsNone(load_module().timestamp(1_700_000_000))

    def test_a_hung_status_query_is_killed_with_everything_it_started(self):
        script = self.repo / "hung-status.sh"
        stub(script, "sleep 30 &\nwait")
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            load_module().query([str(script)], self.repo, timeout=0.5)
        # A grandchild left alive holds stdout open, so this also proves it died.
        self.assertLess(time.monotonic() - started, 5)

    def test_a_missing_binding_is_one_error_row(self):
        self.binding_path.unlink()
        rows = json.loads(self.cli("info").stdout)["rows"]
        self.assertEqual([row["tone"] for row in rows], ["error"])
        self.assertEqual(self.cli("version").returncode, 1)

    # Editing and Testing rows.

    def test_editing_row_says_whether_project_edits_are_in_the_build_base(self):
        project = self.repo.parent / "Oracle.yazeproj"
        project.mkdir()
        (project / "rom").write_bytes(b"base-168")
        sha1 = hashlib.sha1(b"base-168").hexdigest()
        (project / "project.yaze").write_text(
            f"[files]\nrom_filename=rom\nlyra_build_request_file=\n[rom]\nexpected_hash={sha1}\n")
        (project / "manifest.json").write_text(json.dumps({"name": "Oracle", "lastModifiedAt": "2026-01-01T00:00:00+00:00"}))
        self.bind(project=str(project))
        row = self.rows()[0]
        self.assertEqual((row["title"], row["tone"]), ("Editing · Oracle · in build base 168", "ok"))
        self.assertIn("Lyra unbound", row["detail"])
        (project / "rom").write_bytes(b"edited")
        (project / "project.yaze").write_text(
            f"[files]\nrom_filename=rom\n[rom]\nexpected_hash={hashlib.sha1(b'edited').hexdigest()}\n")
        self.assertEqual(self.rows()[0]["title"], "Editing · Oracle · not in build base 168")
        (project / "rom").write_bytes(b"changed outside the editor")
        self.assertEqual(self.rows()[0]["tone"], "error")

    def test_testing_row_shows_counts_and_flags_an_older_candidate(self):
        self.receipt()
        self.reports.mkdir()
        report = {"status": "passed", "counts": {"selected": 5, "passed": 3, "failed": 0, "skipped": 2},
                  "candidate": {"sha256": hashlib.sha256(b"built-168").hexdigest()},
                  "finished_at": "2026-01-01T00:00:00+00:00", "path": "/r/transition.json"}
        (self.reports / "last.json").write_text(json.dumps(report))
        row = next(row for row in self.rows() if row["title"].startswith("Tested"))
        self.assertEqual(row["title"], "Tested · 5 selected · 3 passed · 0 failed · 2 skipped")
        self.assertEqual((row["tone"], row["open"]), ("warn", "/r/transition.json"))
        (self.roms / "oos168x.sfc").write_bytes(b"rebuilt")
        row = next(row for row in self.rows() if row["title"].startswith("Tested"))
        self.assertEqual(row["detail"], "older build")

    def test_mesen_rows_name_the_dev_build_and_owned_instances(self):
        for name in ("oos-rc-play", "oos-dock-tests", "claude-104"):
            listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            listener.bind(str(self.sockets / f"mesen2-{name}.sock"))
            listener.listen(4)
            self.listeners.append(listener)
        (self.sockets / "mesen2-gone.sock").write_text("")
        play = {"play_window": {"open": True, "current": False, "rom": "oos168x.sfc"}, "latest": "v0.9.0-b46"}
        rows = self.rows(play=play)
        titles = [row["title"] for row in rows]
        self.assertIn("Play window · dev build oos168x.sfc", titles)
        self.assertIn({"title": "oos-dock-tests", "detail": "dock tests", "tone": "ok"}, rows)
        self.assertIn({"title": "claude-104", "detail": "agent emulator", "tone": "ok"}, rows)
        prune = next(row for row in rows if row["title"] == "1 dead emulator socket")
        self.assertTrue(prune["run"].endswith("dock_oracle.py prune"))
        self.assertNotIn("Build the patched ROM", titles)
        self.assertNotIn("Registry has many stale active instances.", titles)

    # Actions.

    def test_build_reports_its_result_separately_from_the_mesen_offer(self):
        stub(self.repo / "Scripts/Build/dev_loop.sh", 'echo "dev_loop $*" > "$(dirname "$0")/ran"')
        (self.repo / "Scripts/Mesen2").mkdir(parents=True)
        (self.repo / "Scripts/Mesen2/oos_play.py").write_text("import sys; sys.exit(3)\n")
        self.receipt()
        result = self.cli("build")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.repo / "Scripts/Build/ran").read_text().strip(), "dev_loop 168 --mesen-sync")
        self.assertIn("Mesen offer failed (exit 3)", result.stdout)
        stub(self.repo / "Scripts/Build/dev_loop.sh", "exit 4")
        result = self.cli("build", "--validate")
        self.assertEqual(result.returncode, 4)
        self.assertNotIn("Mesen offer", result.stdout)

    def test_a_second_build_variant_is_refused_while_the_lock_is_held(self):
        stub(self.repo / "Scripts/Build/dev_loop.sh", 'touch "$(dirname "$0")/ran"')
        module = load_module()
        binding = module.load_binding(self.binding_path)
        with module.build_lock(binding):
            result = self.cli("build", "--validate")
            tests = self.cli("test", "transitions")
        self.assertEqual(result.returncode, module.BUSY)
        self.assertIn("in use by pid", result.stdout)
        self.assertEqual(tests.returncode, module.BUSY)
        self.assertFalse((self.repo / "Scripts/Build/ran").exists())

    def test_the_build_inherits_the_held_lock_descriptor(self):
        probe = self.repo / "Scripts/Build/probe.py"
        probe.write_text(
            "import errno,fcntl,os,sys\n"
            "lock=sys.argv[1]; fd=int(os.environ['OOS_BUILD_LOCK_FD'])\n"
            "same=os.fstat(fd).st_ino==os.stat(lock).st_ino\n"
            "fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)\n"
            "other=open(lock,'a')\n"
            "try: fcntl.flock(other,fcntl.LOCK_EX|fcntl.LOCK_NB); print('other-locked')\n"
            "except OSError as e: print('held' if same and e.errno in (errno.EAGAIN,errno.EWOULDBLOCK) else e)\n")
        stub(self.repo / "Scripts/Build/dev_loop.sh",
             f'{shutil.which("python3")} "$(dirname "$0")/probe.py" "$(dirname "$0")/../../Roms/.oos-build.lock" '
             '> "$(dirname "$0")/ran"')
        self.receipt()
        result = self.cli("build")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.repo / "Scripts/Build/ran").read_text().strip(), "held")

    def test_a_test_instance_running_another_rom_is_refused_not_closed(self):
        self.receipt()
        module = load_module()
        module.SOCKET_DIR = self.sockets
        binding = module.load_binding(self.binding_path)
        socket_path = self.sockets / f"mesen2-{binding.test_instance}.sock"
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(str(socket_path))
        listener.listen(4)
        self.listeners.append(listener)
        calls = []

        def runner(args, **kwargs):
            calls.append(args)
            return SimpleNamespace(returncode=1, stdout=json.dumps({"status": "failed", "error": "sha mismatch"}),
                                   stderr="")

        with self.assertRaisesRegex(module.BindingError, "different ROM .*Nothing was closed"):
            module.prepare_endpoint(binding, socket_path, runner, wait=lambda _: None)
        self.assertEqual(len(calls), 1)
        self.assertIn("--verify-only", calls[0])

    def test_presets_without_a_seed_are_refused_before_launch(self):
        seeds = self.repo / "Data/debug/trusted_state_seeds.json"
        seeds.parent.mkdir(parents=True)
        seeds.write_text(json.dumps({"tasks": {"maku": None, "d4": "zora_outside", "d6": None}}))
        stub(self.repo / "Scripts/Build/oos-session.sh", 'echo "$*" > "$(dirname "$0")/launched"')
        result = self.cli("session", "maku", "--crystals", "3")
        self.assertEqual(result.returncode, 2)
        self.assertIn("no trusted seed for maku", result.stdout)
        self.assertFalse((self.repo / "Scripts/Build/launched").exists())
        self.assertEqual(self.cli("session", "zora").returncode, 0)
        self.assertEqual((self.repo / "Scripts/Build/launched").read_text().strip(), "zora --version 168")
        menu = json.loads(self.cli("sessions-menu", check=True).stdout)["menu"][0]["items"]
        disabled = {item["title"]: item.get("disabled") for item in menu}
        self.assertIsNone(disabled["Free Instance"])
        self.assertIsNone(disabled["D4 Zora Temple"])
        self.assertEqual(disabled["D6 Entrance"], "no trusted seed for d6")
        self.assertEqual(disabled["Menu Slot"], "unknown task menu")

    def test_transition_tests_bind_the_candidate_and_count_results(self):
        self.receipt()
        module = load_module()
        module.REPORTS = self.reports
        module.SOCKET_DIR = self.sockets
        binding = module.load_binding(self.binding_path)
        calls = []
        runner_output = "progress\n" + json.dumps({"summary": {"passed": 3, "failed": 0, "skipped": 2, "total": 5},
                                                   "tests": [{"name": "t", "status": "skipped"}]}, indent=2)

        def runner(args, **kwargs):
            calls.append((args, kwargs.get("env", {})))
            if "--verify-only" in args:
                return SimpleNamespace(returncode=0, stdout=json.dumps({"status": "passed"}), stderr="")
            if "test_runner.py" in " ".join(args):
                return SimpleNamespace(returncode=0, stdout=runner_output, stderr="")
            return SimpleNamespace(returncode=0, stdout="", stderr="")

        with contextlib.redirect_stdout(io.StringIO()):
            code, report = module.run_transition_tests(binding, runner=runner, wait=lambda _: None)
        self.assertEqual(code, 0)
        self.assertEqual(report["counts"], {"selected": 5, "passed": 3, "failed": 0, "skipped": 2})
        test_call = next((args, env) for args, env in calls if "test_runner.py" in " ".join(args))
        self.assertIn("--tag", test_call[0])
        self.assertNotIn("--suite", test_call[0])
        self.assertEqual(test_call[0][test_call[0].index("--rom") + 1], str(binding.output))
        self.assertEqual(test_call[1]["MESEN2_SOCKET_PATH"], str(self.sockets / "mesen2-oos-dock-tests.sock"))
        launch = next(args for args, _ in calls if "mesen2_launch_instance.sh" in args[0])
        self.assertEqual(launch[launch.index("--instance") + 1], "oos-dock-tests")
        self.assertEqual(json.loads((self.reports / "last.json").read_text())["status"], "passed")

    def test_transition_tests_refuse_an_unverified_candidate_without_launching(self):
        (self.roms / "oos168x.sfc").write_bytes(b"no receipt")
        module = load_module()
        module.REPORTS = self.reports
        calls = []
        with contextlib.redirect_stdout(io.StringIO()):
            code, report = module.run_transition_tests(module.load_binding(self.binding_path),
                                                       runner=lambda *a, **k: calls.append(a), wait=lambda _: None)
        self.assertEqual(code, 2)
        self.assertEqual(report["status"], "unavailable")
        self.assertIn("candidate not verified", report["error"])
        self.assertEqual(calls, [])

    def test_the_test_instance_can_never_be_the_play_window(self):
        self.bind(test_instance="oos-rc-play")
        self.assertEqual(self.cli("test", "transitions").returncode, 1)


if __name__ == "__main__":
    unittest.main()
