#!/usr/bin/env python3
"""Oracle of Secrets status and actions for the Barista dock's Oracle group.

Everything reads one explicit binding, ~/.config/barista/oracle.json
(BARISTA_ORACLE_BINDING overrides the path):

  {"repo": "~/src/hobby/oracle-of-secrets", "version": 168,
   "project": "~/Zelda/Projects/Oracle-of-Secrets/Oracle-of-Secrets.yazeproj",
   "project_launcher": "~/Zelda/Projects/Oracle-of-Secrets/Open Oracle.command",
   "evidence": "~/.context/projects/oracle-of-secrets/scratchpad",
   "test_instance": "oos-dock-tests"}

Usage:
  dock_oracle.py info [--status FILE] [--play FILE]   status rows for the group's info_command
  dock_oracle.py version                             the bound ROM version
  dock_oracle.py build [--validate]                  build the bound version, then offer it to Mesen
  dock_oracle.py play dev|beta [--now]               open or offer the dev build or the last staged beta
  dock_oracle.py session TASK [ARGS...]              oos-session.sh, refusing presets without a seed
  dock_oracle.py sessions-menu                       debug-session menu entries for a menu_command
  dock_oracle.py test transitions                    transition tests on the dev build in an owned emulator
  dock_oracle.py edit                                open the bound Oracle project in its Yaze
  dock_oracle.py prune                               remove dead Mesen2 sockets

Builds and tests hold Roms/.oos-build.lock for the bound repo, so two dock
actions never write or read half-written build outputs at the same time.
Build success and the optional Mesen offer are reported separately.
"""

from __future__ import annotations

import configparser
import contextlib
import datetime as dt
import errno
import fcntl
import hashlib
import importlib.util
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

BINDING = Path(os.environ.get("BARISTA_ORACLE_BINDING") or "~/.config/barista/oracle.json").expanduser()
BUILD_ACTION = "Build ROM"
EDIT_ACTION = "Edit Oracle Project"
SOCKET_DIR = Path(os.environ.get("BARISTA_MESEN_SOCKET_DIR", "/tmp"))
REPORTS = Path(os.environ.get("BARISTA_ORACLE_REPORTS")
               or "~/Library/Logs/sketchybar-barista/oracle-tests").expanduser()
PLAY_INSTANCE = "oos-rc-play"
SESSION_TASKS = [("maku", "Maku Tree (0 crystals)", ["--crystals", "0"]),
                 ("maku", "Maku Tree (3 crystals)", ["--crystals", "3"]),
                 ("maku", "Maku Tree (7 crystals)", ["--crystals", "7"]),
                 ("d4", "D4 Zora Temple", []), ("d6", "D6 Entrance", []),
                 ("d6inside", "D6 Inside", []), ("d6cart", "D6 Minecart", []),
                 ("menu", "Menu Slot", [])]
TIMEOUT = 4
TEST_TIMEOUT = 600
MAX_EMULATORS = 3
BUSY = 75


class BindingError(Exception):
    pass


@dataclass
class Binding:
    repo: Path
    version: int
    project: Path | None
    launcher: Path | None
    evidence: Path | None
    test_instance: str

    @property
    def roms(self) -> Path:
        return self.repo / "Roms"

    @property
    def base(self) -> Path:
        return self.roms / f"oos{self.version}.sfc"

    @property
    def output(self) -> Path:
        return self.roms / f"oos{self.version}x.sfc"

    @property
    def receipt(self) -> Path:
        return self.roms / f"oos{self.version}x.build.json"

    @property
    def lock(self) -> Path:
        return self.roms / ".oos-build.lock"


def load_binding(path: Path = BINDING) -> Binding:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise BindingError(f"No Oracle binding at {path}") from None
    except (OSError, ValueError) as error:
        raise BindingError(f"Unreadable Oracle binding {path}: {error}") from None

    def optional(key: str) -> Path | None:
        return Path(data[key]).expanduser() if data.get(key) else None

    try:
        binding = Binding(repo=Path(data["repo"]).expanduser(), version=int(data["version"]),
                          project=optional("project"), launcher=optional("project_launcher"),
                          evidence=optional("evidence"),
                          test_instance=data.get("test_instance") or "oos-dock-tests")
    except (KeyError, TypeError, ValueError) as error:
        raise BindingError(f"Oracle binding {path} needs repo and a numeric version ({error})") from None
    if binding.test_instance == PLAY_INSTANCE:
        raise BindingError("test_instance must not be the play window")
    return binding


# MARK: Shared helpers


def sha(path: Path, kind: str = "sha256") -> str:
    digest = hashlib.new(kind)
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def age(seconds: float) -> str:
    minutes = max(0, int(seconds // 60))
    if minutes < 60:
        return f"{minutes}m ago"
    if minutes < 48 * 60:
        return f"{minutes // 60}h ago"
    return f"{minutes // (24 * 60)}d ago"


def timestamp(text: str | None) -> float | None:
    try:
        return dt.datetime.fromisoformat(text).timestamp() if text else None
    except ValueError:
        return None


def receipt_module(repo: Path):
    """Oracle's own receipt verifier, so the dock never reimplements it."""
    path = repo / "Scripts" / "Build" / "build_receipt.py"
    spec = importlib.util.spec_from_file_location("oracle_build_receipt", path)
    if spec is None or spec.loader is None or not path.is_file():
        raise BindingError(f"No receipt verifier at {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def socket_alive(path: Path) -> bool:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(0.3)
    try:
        client.connect(str(path))
        return True
    except OSError:
        return False
    finally:
        client.close()


@contextlib.contextmanager
def build_lock(binding: Binding):
    """Exclusive for the whole build or test; a second holder fails at once."""
    binding.roms.mkdir(parents=True, exist_ok=True)
    handle = binding.lock.open("a+")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as error:
        handle.seek(0)
        holder = handle.read().strip() or "another process"
        handle.close()
        if error.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
            raise BindingError(f"Build outputs are in use by {holder}; try again when it finishes") from None
        raise
    try:
        handle.seek(0)
        handle.truncate()
        handle.write(f"pid {os.getpid()}: {' '.join(sys.argv[1:])}\n")
        handle.flush()
        yield handle
    finally:
        handle.seek(0)
        handle.truncate()
        fcntl.flock(handle, fcntl.LOCK_UN)
        handle.close()


def run(args: list[str], cwd: Path, **kwargs) -> int:
    print("$ " + shlex.join(args), flush=True)
    return subprocess.run(args, cwd=cwd, **kwargs).returncode


# MARK: Build state


@dataclass
class BuildState:
    """What the receipt proves about the bound output, in one word plus detail."""
    status: str  # passed, stale, failed, building, unknown, missing
    title: str
    detail: str = ""


def build_state(binding: Binding, now: float) -> BuildState:
    version = binding.version
    if not binding.receipt.exists():
        if binding.output.exists():
            return BuildState("unknown", f"Built {version} · no receipt", "unverified")
        return BuildState("missing", f"ROM {version} · not built", "Build")
    try:
        receipt = json.loads(binding.receipt.read_text(encoding="utf-8"))
        verifier = receipt_module(binding.repo)
    except (OSError, ValueError, BindingError) as error:
        return BuildState("unknown", f"Built {version} · unreadable receipt", type(error).__name__)
    if str(receipt.get("version")) != str(version):
        return BuildState("unknown", f"Built {version} · receipt names {receipt.get('version')}", "unverified")
    finish = receipt.get("finish") or {}
    stage = finish.get("stage") or receipt.get("last_stage") or "?"
    if receipt.get("state") == "in_progress":
        return BuildState("building", f"Build {version} running or interrupted", f"at {stage}")
    if receipt.get("state") == "failed" or finish.get("exit_code"):
        gaps = finish.get("required_gaps") or []
        return BuildState("failed", f"Build {version} failed at {stage}", ", ".join(gaps[:2]))
    output = (receipt.get("artifacts") or {}).get("output_rom")
    if not output or Path(output.get("path", "")).resolve() != binding.output.resolve() \
            or verifier.verify_identity(output):
        return BuildState("failed", f"Built {version} · output doesn't match its receipt", "rebuild")
    base = receipt.get("base_rom") or {}
    if Path(base.get("path", "")).resolve() != binding.base.resolve():
        return BuildState("stale", f"Built {version} from another base", Path(base.get("path", "?")).name)
    if verifier.verify_identity(base):
        return BuildState("stale", f"Built {version} · base ROM changed since", "Build")
    changed = verifier.verify_source_identity(receipt, binding.receipt)
    if changed:
        count = re.search(r"\((\d+)\)", changed)
        files = f"{count.group(1)} source files" if count else "Sources"
        return BuildState("stale", f"Built {version} · {files} changed since", "Build")
    finished = timestamp(receipt.get("finished_at"))
    checks = {check.get("name"): check.get("status") for check in receipt.get("checks") or []}
    runtime = "smoke passed" if checks.get("smoke") == "passed" else "runtime untested"
    gaps = " with gaps" if receipt.get("state") == "completed_with_gaps" else ""
    when = age(now - finished) if finished else ""
    return BuildState("passed", f"Built {version} · passed{gaps}", " · ".join(filter(None, [when, runtime])))


# MARK: Info rows


def editing_row(binding: Binding, now: float) -> dict | None:
    project = binding.project
    if project is None:
        return None
    config = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        config.read_string((project / "project.yaze").read_text(encoding="utf-8"))
        rom = project / config.get("files", "rom_filename", fallback="rom")
        rom_sha1 = sha(rom, "sha1")
    except (OSError, configparser.Error):
        return {"title": f"Editing · no project at {project.name}", "tone": "error", "open": str(project.parent)}
    expected = config.get("rom", "expected_hash", fallback="").lower()
    manifest = {}
    with contextlib.suppress(OSError, ValueError):
        manifest = json.loads((project / "manifest.json").read_text(encoding="utf-8"))
    saved = timestamp(manifest.get("lastModifiedAt"))
    name = manifest.get("name") or project.stem
    lyra = "" if config.get("files", "lyra_build_request_file", fallback="") else "Lyra unbound"
    detail = " · ".join(filter(None, [f"saved {age(now - saved)}" if saved else "", lyra]))
    if expected and rom_sha1 != expected:
        return {"title": f"Editing · {name} ROM differs from its project hash", "detail": detail,
                "tone": "error", "action": EDIT_ACTION}
    in_build = binding.base.exists() and sha(binding.base, "sha1") == rom_sha1
    return {"title": f"Editing · {name} · {'in' if in_build else 'not in'} build base {binding.version}",
            "detail": detail, "tone": "ok" if in_build else "warn", "action": EDIT_ACTION}


def built_row(binding: Binding, now: float) -> dict:
    state = build_state(binding, now)
    tone = {"passed": "ok", "failed": "error"}.get(state.status, "warn")
    return {"title": state.title, "detail": state.detail, "tone": tone, "action": BUILD_ACTION}


def testing_row(binding: Binding, now: float) -> dict | None:
    report_path = REPORTS / "last.json"
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    counts = report.get("counts") or {}
    selected = counts.get("selected", 0)
    title = (f"Tested · {selected} selected · {counts.get('passed', 0)} passed · "
             f"{counts.get('failed', 0)} failed · {counts.get('skipped', 0)} skipped")
    if report.get("status") == "unavailable":
        title = f"Tests unavailable · {report.get('error', '')}"
    tone = ("error" if report.get("status") == "failed" or counts.get("failed")
            else "warn" if report.get("status") != "passed" or counts.get("skipped") or not selected else "ok")
    finished = timestamp(report.get("finished_at"))
    candidate = (report.get("candidate") or {}).get("sha256")
    current = sha(binding.output) if binding.output.exists() else None
    detail = "older build" if candidate and candidate != current else (age(now - finished) if finished else "")
    if detail == "older build" and tone == "ok":
        tone = "warn"
    return {"title": title, "detail": detail, "tone": tone, "open": report.get("path") or str(report_path)}


def mesen_rows(binding: Binding, play: dict) -> list[dict]:
    window = play.get("play_window") or {}
    beta = (play.get("latest") or "").rsplit("-", 1)[-1] or "staged beta"
    dev = binding.output.name
    script = shlex.quote(str(Path(__file__).resolve()))
    play_dev = f"{script} play dev"
    if not window.get("open"):
        rows = [{"title": "Play window closed", "detail": "open dev build", "tone": "none", "run": play_dev}]
    elif window.get("rom") == dev:
        rows = [{"title": f"Play window · dev build {dev}", "detail": "show", "tone": "ok", "run": play_dev}]
    elif window.get("current"):
        rows = [{"title": f"Play window · staged beta {beta}", "detail": "offer dev build", "tone": "none",
                 "run": play_dev}]
    else:
        rows = [{"title": f"Play window · {window.get('rom') or 'unknown ROM'}", "detail": "offer dev build",
                 "tone": "warn", "run": play_dev}]
    if play.get("heavy_lock"):
        rows[0]["detail"] = f"lock: {play['heavy_lock']}"

    sockets = sorted(SOCKET_DIR.glob("mesen2-*.sock"))
    alive = {path.name[len("mesen2-"):-len(".sock")] for path in sockets if socket_alive(path)}
    agents = sorted(alive - {PLAY_INSTANCE})
    for name in agents[:MAX_EMULATORS]:
        owner = "dock tests" if name == binding.test_instance else "agent emulator"
        rows.append({"title": name, "detail": owner, "tone": "ok"})
    if len(agents) > MAX_EMULATORS:
        rows.append({"title": f"{len(agents) - MAX_EMULATORS} more emulators", "tone": "ok"})
    stale = len(sockets) - len(alive)
    if stale:
        rows.append({"title": f"{stale} dead emulator socket{'s' if stale != 1 else ''}", "detail": "Prune",
                     "tone": "none", "run": f"{script} prune"})
    return rows


def status_rows(binding: Binding, status: dict, play: dict | None, now: float) -> list[dict]:
    paths = status.get("paths") or {}
    tracker = paths.get("tracker") or (status.get("tracker") or {}).get("path")
    out = [row for row in (editing_row(binding, now), built_row(binding, now), testing_row(binding, now)) if row]
    if play is not None:
        out += mesen_rows(binding, play)

    git = status.get("git") or {}
    if git.get("available"):
        counts = [(git.get("modified", 0) + git.get("added", 0) + git.get("deleted", 0)
                   + git.get("renamed", 0), "changed"),
                  (git.get("untracked", 0), "new"),
                  (git.get("ahead", 0), "ahead"),
                  (git.get("behind", 0), "behind")]
        detail = " · ".join(f"{count} {word}" for count, word in counts if count) or "clean"
        tone = "warn" if git.get("behind") else ("ok" if detail == "clean" else "none")
        out.append({"title": git.get("branch") or "detached", "detail": detail, "tone": tone})

    # status-json derives its build focus from its own version guess; the Built row owns building.
    focus = (status.get("finish_line") or {}).get("focus") or {}
    if focus.get("title") and focus.get("action") not in ("quick-build", "verify-build"):
        out.append({"title": focus["title"], "detail": focus.get("label") or "Focus",
                    "tone": "none", "open": tracker})

    active = (status.get("tracker") or {}).get("active") or []
    if active:
        top = next((quest for quest in active if quest.get("priority") == "A"), active[0])
        out.append({"title": top.get("title", "Quest"), "detail": f"{len(active)} active",
                    "tone": "none", "open": tracker})

    alerts = [alert for alert in status.get("alerts") or []
              if not alert.startswith(("Patched ROM is missing", "Registry has many stale"))]
    if alerts:
        out.append({"title": alerts[0], "detail": f"+{len(alerts) - 1}" if len(alerts) > 1 else "",
                    "tone": "none", "open": paths.get("runbook")})
    return [{key: value for key, value in row.items() if value} for row in out]


def query(args: list[str], cwd: Path, timeout: float = TIMEOUT) -> dict:
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=True)
    return json.loads(result.stdout)


def read_json(path: str) -> dict:
    source = sys.stdin if path == "-" else open(path, encoding="utf-8")
    with source:
        return json.load(source)


def option(argv: list[str], name: str) -> str | None:
    return argv[argv.index(name) + 1] if name in argv[:-1] else None


def cmd_info(argv: list[str]) -> int:
    def fail(title: str, detail: str = "", open_path: str | None = None) -> int:
        row = {"title": title, "detail": detail, "tone": "error", "open": open_path}
        print(json.dumps({"rows": [{key: value for key, value in row.items() if value}]}))
        return 0

    # The dock kills info commands after 5 s, so both queries share one budget
    # and the optional play status gets whatever the build status leaves.
    deadline = time.monotonic() + TIMEOUT
    try:
        binding = load_binding()
    except BindingError as error:
        return fail("Oracle binding missing", str(error), str(BINDING.parent))
    try:
        path = option(argv, "--status")
        status = read_json(path) if path else query(
            [str(binding.repo / "Scripts/Build/oos-triforce.sh"), "status-json"], binding.repo)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        return fail("Oracle status unavailable", type(error).__name__)
    play = None
    path = option(argv, "--play")
    remaining = deadline - time.monotonic()
    if path or remaining > 0.5:
        try:
            play = read_json(path) if path else query(
                [sys.executable, str(binding.repo / "Scripts/Mesen2/oos_play.py"), "--status", "--json"],
                binding.repo, timeout=remaining)
        except (OSError, ValueError, subprocess.SubprocessError):
            play = None
    print(json.dumps({"rows": status_rows(binding, status, play, time.time())}))
    return 0


# MARK: Actions


def cmd_build(binding: Binding, argv: list[str]) -> int:
    args = ["Scripts/Build/dev_loop.sh", str(binding.version), "--mesen-sync"]
    if "--validate" in argv:
        args.append("--validate")
    with build_lock(binding) as lock:
        # build_rom.sh takes this same lock; it accepts the held descriptor
        # instead of refusing its own parent.
        fd = lock.fileno()
        code = run(args, binding.repo, pass_fds=(fd,), env={**os.environ, "OOS_BUILD_LOCK_FD": str(fd)})
        if code != 0:
            print(f"[dock] Build {binding.version} failed (exit {code}).")
            return code
        state = build_state(binding, time.time())
        print(f"[dock] Build {binding.version}: {state.title} ({state.detail}).")
    offer = run([sys.executable, "Scripts/Mesen2/oos_play.py", "--rom", str(binding.output), "--offer-only"],
                binding.repo)
    print(f"[dock] Mesen offer {'sent (or window closed)' if offer == 0 else f'failed (exit {offer})'}; "
          "the build result above stands either way.")
    return 0


def cmd_play(binding: Binding, argv: list[str]) -> int:
    which = argv[0] if argv else ""
    args = [sys.executable, "Scripts/Mesen2/oos_play.py"]
    if which == "dev":
        if not binding.output.exists():
            print(f"[dock] {binding.output.name} is not built yet.")
            return 1
        state = build_state(binding, time.time())
        print(f"[dock] Development build {binding.output.name}: {state.title} ({state.detail}).")
        args += ["--rom", str(binding.output)]
    elif which != "beta":
        print("usage: dock_oracle.py play dev|beta [--now]")
        return 2
    else:
        print("[dock] Last staged beta: Roms/Playtest/oos-play.sfc.")
    if "--now" in argv:
        args.append("--now")
    return run(args, binding.repo)


def seed_problem(binding: Binding, task: str) -> str | None:
    """Why a named preset can't reach its start, checked before any launch."""
    if task in ("free", "list"):
        return None
    seeds = binding.repo / "Data/debug/trusted_state_seeds.json"
    try:
        tasks = json.loads(seeds.read_text(encoding="utf-8")).get("tasks", {})
    except (OSError, ValueError) as error:
        return f"unreadable {seeds.name} ({type(error).__name__})"
    key = "d4" if task == "zora" else task
    if key not in tasks:
        return f"unknown task {task}"
    if not tasks[key]:
        return f"no trusted seed for {key}"
    return None


def cmd_session(binding: Binding, argv: list[str]) -> int:
    if not argv:
        print("usage: dock_oracle.py session TASK [ARGS...]")
        return 2
    problem = seed_problem(binding, argv[0])
    if problem:
        print(f"[dock] {argv[0]} unavailable: {problem}. Nothing was launched.")
        return 2
    return run(["Scripts/Build/oos-session.sh", *argv, "--version", str(binding.version)], binding.repo)


def cmd_sessions_menu(binding: Binding) -> int:
    script = shlex.quote(str(Path(__file__).resolve()))
    items = [{"kind": "action", "title": "Free Instance", "command": f"{script} session free"}]
    for task, title, extra in SESSION_TASKS:
        entry = {"kind": "action", "title": title, "command": shlex.join([str(Path(__file__).resolve()),
                                                                          "session", task, *extra])}
        problem = seed_problem(binding, task)
        if problem:
            entry["disabled"] = problem
        items.append(entry)
    print(json.dumps({"menu": [{"kind": "group", "title": "Debug Sessions", "items": items}]}))
    return 0


def cmd_edit(binding: Binding) -> int:
    launcher = binding.launcher
    if launcher is None or not launcher.exists():
        print(f"[dock] No project launcher in the binding ({launcher}).")
        return 1
    log = Path("~/Library/Logs/sketchybar-barista/oracle-project.log").expanduser()
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as output:
        # Its own session: the editor outlives this action and its Stop.
        process = subprocess.Popen([str(launcher)], stdout=output, stderr=subprocess.STDOUT,
                                   stdin=subprocess.DEVNULL, start_new_session=True)
    try:
        code = process.wait(timeout=3)
    except subprocess.TimeoutExpired:
        print(f"[dock] Opened {binding.project} (pid {process.pid}).")
        return 0
    print(log.read_text(errors="replace"))
    print(f"[dock] The project launcher exited with {code}.")
    return code or 1


def cmd_prune(binding: Binding) -> int:
    return run([sys.executable, "Scripts/Mesen2/mesen2_registry.py", "prune"], binding.repo)


# MARK: Tests


def last_json(text: str) -> dict:
    """The runner prints progress, then one JSON object last."""
    start = text.rfind("\n{")
    return json.loads(text[start + 1 if start >= 0 else text.find("{"):])


def verify_endpoint(binding: Binding, socket_path: Path, runner=subprocess.run) -> tuple[bool, dict]:
    result = runner([sys.executable, "Scripts/Build/run_build_smoke.py", "--verify-only",
                     "--rom", str(binding.output), "--socket", str(socket_path)],
                    cwd=binding.repo, capture_output=True, text=True, timeout=60)
    try:
        receipt = json.loads(result.stdout)
    except ValueError:
        receipt = {"status": "failed", "error": (result.stderr or result.stdout).strip()[-400:]}
    return result.returncode == 0, receipt


def prepare_endpoint(binding: Binding, socket_path: Path, runner=subprocess.run,
                     wait=time.sleep, attempts: int = 30) -> dict:
    """The owned test instance running exactly the candidate, or an error.

    An instance already running something else is never closed from here: a
    name alone doesn't prove the dock still owns that process or that no
    native test holds it.
    """
    instance = binding.test_instance
    if socket_alive(socket_path):
        ok, receipt = verify_endpoint(binding, socket_path, runner)
        if ok:
            return receipt
        raise BindingError(f"{instance} is running a different ROM ({receipt.get('error', 'identity mismatch')}); "
                           "close it, then run the tests again. Nothing was closed or launched")
    launch = runner(["Scripts/Mesen2/mesen2_launch_instance.sh", "--reuse", "--instance", instance,
                     "--owner", os.environ.get("USER", "dock"), "--source", "manual",
                     "--rom", str(binding.output)],
                    cwd=binding.repo, capture_output=True, text=True, timeout=90)
    if launch.returncode != 0:
        raise BindingError(f"could not launch {instance}: {(launch.stderr or launch.stdout).strip()[-300:]}")
    receipt: dict = {}
    for _ in range(attempts):
        ok, receipt = verify_endpoint(binding, socket_path, runner)
        if ok:
            return receipt
        wait(1)
    raise BindingError(f"{instance} never ran the candidate: {receipt.get('error', 'no identity')}")


def run_transition_tests(binding: Binding, runner=subprocess.run, wait=time.sleep) -> tuple[int, dict]:
    started = dt.datetime.now(dt.timezone.utc)
    socket_path = SOCKET_DIR / f"mesen2-{binding.test_instance}.sock"
    report: dict = {"kind": "transition", "status": "unavailable", "started_at": started.isoformat(),
                    "instance": binding.test_instance, "socket": str(socket_path),
                    "counts": {"selected": 0, "passed": 0, "failed": 0, "skipped": 0}}
    try:
        state = build_state(binding, time.time())
        report["candidate"] = {"path": str(binding.output), "build": state.title}
        if state.status not in ("passed", "stale"):
            raise BindingError(f"candidate not verified: {state.title}")
        report["candidate"]["sha256"] = sha(binding.output)
        report["preflight"] = prepare_endpoint(binding, socket_path, runner, wait)
        env = {**os.environ, "MESEN2_SOCKET_PATH": str(socket_path), "OOS_TEST_BACKEND": "socket",
               "OOS_TEST_REQUIRE_EMULATOR": "1", "OOS_TEST_REQUIRE_ARTIFACTS": "1",
               "MESEN_AUTO_FOCUS": "0", "MESEN_AUTO_UNSTASH": "0", "MESEN_AUTO_STASH": "0",
               "MESEN_STASH_ON_FAIL": "0", "MESEN2_HANDHELD": "0"}
        command = [sys.executable, "Scripts/Validate/test_runner.py", "--manifest", "Tests/manifest.json",
                   "--tag", "transition", "--rom", str(binding.output), "--output-format", "json"]
        report["command"] = command
        report["status"] = "failed"
        result = runner(command, cwd=binding.repo, env=env, capture_output=True, text=True,
                        timeout=TEST_TIMEOUT)
        report["runner_exit"] = result.returncode
        try:
            output = last_json(result.stdout)
        except ValueError:
            raise BindingError(f"runner printed no results (exit {result.returncode})") from None
        summary = output.get("summary") or {}
        report["tests"] = output.get("tests") or []
        report["counts"] = {"selected": summary.get("total", len(report["tests"])),
                            "passed": summary.get("passed", 0), "failed": summary.get("failed", 0),
                            "skipped": summary.get("skipped", 0)}
        ok, report["postflight"] = verify_endpoint(binding, socket_path, runner)
        if not ok:
            raise BindingError("the test instance stopped running the candidate")
        if sha(binding.output) != report["candidate"]["sha256"]:
            raise BindingError("the candidate changed while the tests ran")
        counts = report["counts"]
        report["status"] = "passed" if not counts["failed"] and result.returncode == 0 else "failed"
    except BindingError as error:
        report["error"] = str(error)
    except (OSError, subprocess.SubprocessError) as error:
        report["error"] = f"{type(error).__name__}: {error}"
    report["finished_at"] = dt.datetime.now(dt.timezone.utc).isoformat()
    REPORTS.mkdir(parents=True, exist_ok=True)
    path = REPORTS / f"transition-{started:%Y%m%d-%H%M%S}.json"
    report["path"] = str(path)
    text = json.dumps(report, indent=2)
    path.write_text(text, encoding="utf-8")
    (REPORTS / "last.json").write_text(text, encoding="utf-8")
    counts = report["counts"]
    print(f"[dock] Transitions: {report['status']} · {counts['selected']} selected · {counts['passed']} passed · "
          f"{counts['failed']} failed · {counts['skipped']} skipped" + (f" ({report['error']})" if report.get("error") else ""))
    print(f"[dock] Report: {path}")
    return {"passed": 0, "failed": 1}.get(report["status"], 2), report


def cmd_test(binding: Binding, argv: list[str]) -> int:
    if argv[:1] != ["transitions"]:
        print("usage: dock_oracle.py test transitions")
        return 2
    with build_lock(binding):
        return run_transition_tests(binding)[0]


def main(argv: list[str]) -> int:
    command, rest = (argv[0], argv[1:]) if argv else ("info", [])
    if command == "info":
        return cmd_info(rest)
    try:
        binding = load_binding()
        if command == "version":
            print(binding.version)
            return 0
        handlers = {"build": lambda: cmd_build(binding, rest), "play": lambda: cmd_play(binding, rest),
                    "session": lambda: cmd_session(binding, rest),
                    "sessions-menu": lambda: cmd_sessions_menu(binding),
                    "test": lambda: cmd_test(binding, rest), "edit": lambda: cmd_edit(binding),
                    "prune": lambda: cmd_prune(binding)}
        if command not in handlers:
            print(__doc__)
            return 2
        return handlers[command]()
    except BindingError as error:
        print(f"[dock] {error}")
        return BUSY if "in use by" in str(error) else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
