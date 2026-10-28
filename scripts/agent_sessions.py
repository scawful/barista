#!/usr/bin/env python3
"""Running coding-agent sessions for the Barista `agents` widget.

Sources (all local, no network; archived chats are skipped):
  Codex   ~/.codex/sessions/YYYY/MM/DD/*.jsonl written recently (Codex Desktop
          and CLI); names and the archived flag come from the `threads` table
          in ~/.codex/state_*.sqlite, and the newest rollout's `rate_limits`
          gives usage.
  Claude  ~/.claude/sessions/<pid>.json whose pid is alive (desktop and CLI);
          Claude Desktop's claude-code-sessions records give title/isArchived.
  Cursor  ~/.cursor/projects/*/agent-transcripts/**/*.jsonl written recently;
          Cursor's state.vscdb `composerData:<id>` gives name/isArchived.
  Gemini  running `gemini` CLI processes.

A session needs you when it is blocked on an answer: Claude's session status is
`waiting` (a permission dialog or a question), a Codex request_user_input call
has no later user message, or a Cursor transcript ends in CreatePlan. A
pending Cursor AskQuestion cannot be seen: Cursor saves transcripts and chat
state only now and then, and runs no hooks for it. Those sessions stay listed for BARISTA_AGENTS_NEEDS_SECONDS (a day)
instead of dropping out when quiet.

Usage:
  agent_sessions.py json            print the snapshot
  agent_sessions.py apply           render into SketchyBar in one call, and write
                                    the sessions and per-app counts of those
                                    that need you for the Barista dock
                                    (BARISTA_AGENT_BADGES_FILE)
  agent_sessions.py focus <target>  jump to a session (app:<bundle>,
                                    pid:<pid>, cursor:<path>)
"""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import shlex
import sqlite3
import subprocess
import sys
import tempfile
import time
from contextlib import closing
from pathlib import Path

ACTIVE_SECONDS = int(os.environ.get("BARISTA_AGENTS_ACTIVE_SECONDS", "600"))
# A transcript written this recently means the agent is still producing output.
WORKING_SECONDS = int(os.environ.get("BARISTA_AGENTS_WORKING_SECONDS", "90"))
NEEDS_SECONDS = int(os.environ.get("BARISTA_AGENTS_NEEDS_SECONDS", "86400"))
# Codex files a rollout under the day the session started, so a resumed
# session keeps writing into an older day folder.
CODEX_SCAN_DAYS = int(os.environ.get("BARISTA_AGENTS_CODEX_SCAN_DAYS", "14"))
MAX_ROWS = int(os.environ.get("BARISTA_AGENTS_ROWS", "8"))
HOME = Path(os.environ.get("BARISTA_AGENTS_HOME", str(Path.home())))
SKETCHYBAR = os.environ.get("BARISTA_SKETCHYBAR_BIN") or "sketchybar"
YABAI = os.environ.get("BARISTA_YABAI_BIN") or "yabai"
ITEM = "agents"
APP_SUPPORT = HOME / "Library" / "Application Support"
CURSOR_DB = APP_SUPPORT / "Cursor" / "User" / "globalStorage" / "state.vscdb"
CLAUDE_DESKTOP_SESSIONS = APP_SUPPORT / "Claude" / "claude-code-sessions"
BADGES_FILE = Path(os.environ.get("BARISTA_AGENT_BADGES_FILE") or (
    Path(os.environ.get("BARISTA_CONFIG_DIR") or HOME / ".config" / "sketchybar")
    / "cache" / "agent_sessions.json"))

TOOLS = {
    "codex": {"label": "Codex", "color": "0xffa6e3a1", "open": "app:com.openai.codex"},
    "claude": {"label": "Claude", "color": "0xfffab387", "open": "app:com.anthropic.claudefordesktop"},
    "cursor": {"label": "Cursor", "color": "0xff89b4fa", "open": "app:com.todesktop.230313mzl4w4u92"},
    "gemini": {"label": "Gemini", "color": "0xffcba6f7", "open": ""},
}
MUTED = "0xff6c7086"
TEXT = "0xffcdd6f4"
NEEDS = "0xfff38ba8"
CODEX_QUESTION = b'"request_user_input_async"'
USER_QUERY = re.compile(r"<user_query>\s*(.*?)\s*(?:</user_query>|$)", re.S)
RATE_LIMITS = re.compile(r'"rate_limits":\s*(?=\{)')


def age(seconds: float) -> str:
    seconds = max(0, int(seconds))
    if seconds < 60:
        return "now"
    if seconds < 3600:
        return f"{seconds // 60}m"
    return f"{seconds // 3600}h"


def clip(text: str, limit: int = 40) -> str:
    text = " ".join(text.split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def first_json_line(path: Path, limit: int = 65536) -> dict:
    try:
        with path.open("rb") as handle:
            return json_record(handle.readline(limit))
    except OSError:
        return {}


def as_dict(value) -> dict:
    return value if isinstance(value, dict) else {}


def tail_lines(path: Path, size: int) -> list[bytes]:
    """Whole lines from the last `size` bytes of a transcript."""
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            start = max(0, handle.tell() - size)
            handle.seek(start)
            lines = handle.read().splitlines()
    except OSError:
        return []
    return lines[1:] if start else lines


def json_record(line: bytes) -> dict:
    try:
        record = json.loads(line)
    except ValueError:
        return {}
    return record if isinstance(record, dict) else {}


def codex_question(path: Path) -> str:
    """A request_user_input question that no later user message answered.
    The call returns at once and the agent may keep working, so the question
    stays open until you write back."""
    lines = tail_lines(path, 1 << 20)
    asked = next((i for i in range(len(lines) - 1, -1, -1) if CODEX_QUESTION in lines[i]), None)
    if asked is None:
        return ""
    question = ""
    for line in lines[asked:]:
        payload = json_record(line).get("payload") or {}
        if payload.get("type") == "message" and payload.get("role") == "user":
            question = ""
        elif payload.get("type") == "function_call" and payload.get("name") == "request_user_input_async":
            try:
                questions = json.loads(payload.get("arguments") or "{}").get("questions") or [{}]
            except (ValueError, AttributeError):
                questions = [{}]
            first = questions[0] if isinstance(questions[0], dict) else {}
            question = first.get("title") or "Question"
    return question


def cursor_plan(path: Path) -> str:
    """A plan a Cursor chat ended its turn on, from its transcript."""
    lines = [line for line in tail_lines(path, 1 << 18) if line.strip()]
    record = json_record(lines[-1]) if lines else {}
    if record.get("role") != "assistant":
        return ""
    content = as_dict(record.get("message")).get("content")
    blocks = [block for block in (content if isinstance(content, list) else []) if isinstance(block, dict)]
    if not blocks or blocks[-1].get("type") != "tool_use" or blocks[-1].get("name") != "CreatePlan":
        return ""
    return f"Plan ready: {as_dict(blocks[-1].get('input')).get('name') or 'review'}"


def sqlite_rows(path: Path, query: str, params: list[str]) -> list[tuple]:
    if not params or not path.is_file():
        return []
    try:
        with closing(sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True, timeout=0.5)) as db:
            return db.execute(query, params).fetchall()
    except sqlite3.Error:
        return []


def placeholders(values: list[str]) -> str:
    return ",".join("?" * len(values))


def recent_day_dirs(root: Path, now: float, days: int) -> list[Path]:
    today = dt.date.fromtimestamp(now)
    dirs = []
    for offset in range(days):
        day = today - dt.timedelta(days=offset)
        path = root / f"{day:%Y}" / f"{day:%m}" / f"{day:%d}"
        if path.is_dir():
            dirs.append(path)
    return dirs


def codex_threads(paths: list[str]) -> dict[str, tuple[bool, str]]:
    def version(path: Path) -> int:
        suffix = path.stem.removeprefix("state_")
        return int(suffix) if suffix.isdigit() else -1
    databases = sorted((HOME / ".codex").glob("state_*.sqlite"), key=version)
    if not databases:
        return {}
    rows = sqlite_rows(databases[-1],
                       "select rollout_path, archived, coalesce(name, '') from threads "
                       f"where rollout_path in ({placeholders(paths)})", paths)
    return {path: (bool(archived), name) for path, archived, name in rows}


def codex_sessions(now: float) -> list[dict]:
    recent = []
    for day in recent_day_dirs(HOME / ".codex" / "sessions", now, CODEX_SCAN_DAYS):
        for path in day.glob("*.jsonl"):
            try:
                idle = now - path.stat().st_mtime
            except OSError:
                continue
            if idle <= NEEDS_SECONDS:
                question = codex_question(path)
                if idle <= ACTIVE_SECONDS or question:
                    recent.append((path, idle, question))
    threads = codex_threads([str(path) for path, _, _ in recent])
    sessions = []
    for path, idle, question in recent:
        archived, name = threads.get(str(path), (False, ""))
        if archived:
            continue
        meta = first_json_line(path).get("payload") or {}
        if meta.get("thread_source") == "subagent":
            continue
        sessions.append({
            "id": f"codex:{path.stem}",
            "tool": "codex",
            "title": name or Path(meta.get("cwd") or "").name or "session",
            "detail": age(idle),
            "target": TOOLS["codex"]["open"],
            "idle": idle,
            "working": idle <= WORKING_SECONDS,
            "needs": question,
        })
    return sessions


def codex_usage(now: float) -> str:
    rollouts = []
    for day in recent_day_dirs(HOME / ".codex" / "sessions", now, 7):
        rollouts.extend(day.glob("*.jsonl"))
    rollouts.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    decoder = json.JSONDecoder()
    for path in rollouts[:3]:
        try:
            with path.open("rb") as handle:
                handle.seek(0, os.SEEK_END)
                handle.seek(max(0, handle.tell() - 262144))
                tail = handle.read().decode("utf-8", errors="replace")
        except OSError:
            continue
        match = None
        for match in RATE_LIMITS.finditer(tail):
            pass
        if match is None:
            continue
        try:
            limits, _ = decoder.raw_decode(tail, match.end())
        except ValueError:
            continue
        parts = []
        for window in (limits.get("primary"), limits.get("secondary")):
            if not isinstance(window, dict) or window.get("used_percent") is None:
                continue
            minutes = window.get("window_minutes") or 0
            span = "wk" if minutes >= 7 * 1440 else f"{max(1, minutes // 60)}h"
            parts.append(f"{window['used_percent']:.0f}% {span}")
        if parts:
            return " ".join(parts)
    return ""


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def read_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0


def claude_desktop_records(session_ids: set[str]) -> dict[str, dict]:
    records: dict[str, dict] = {}
    paths = sorted(CLAUDE_DESKTOP_SESSIONS.glob("*/*/local_*.json"), key=mtime, reverse=True)
    for path in paths:
        if len(records) == len(session_ids):
            break
        data = read_json(path)
        if data.get("cliSessionId") in session_ids:
            records[data["cliSessionId"]] = data
    return records


def claude_sessions(now: float) -> list[dict]:
    live = []
    for path in (HOME / ".claude" / "sessions").glob("*.json"):
        data = read_json(path)
        pid = data.get("pid")
        # os.kill(0) and os.kill(-1) succeed, and bool is an int.
        if type(pid) is int and pid > 0 and pid_alive(pid):
            if not isinstance(data.get("sessionId"), str):
                data["sessionId"] = None
            live.append(data)
    records = claude_desktop_records({data["sessionId"] for data in live} - {None})
    sessions = []
    for data in live:
        pid = data["pid"]
        record = records.get(data.get("sessionId")) or {}
        if record.get("isArchived"):
            continue
        desktop = data.get("entrypoint") == "claude-desktop"
        updated_ms = data.get("updatedAt")
        updated = updated_ms / 1000 if isinstance(updated_ms, (int, float)) else 0
        status = data.get("status") or ""
        waiting = status == "waiting"
        sessions.append({
            "id": f"claude:{data.get('sessionId') or pid}",
            "tool": "claude",
            "title": (record.get("title") or data.get("name")
                      or Path(data.get("cwd") or "").name or "session"),
            "detail": status or age(now - updated),
            "target": TOOLS["claude"]["open"] if desktop else f"pid:{pid}",
            "idle": 0 if status == "busy" else max(0, now - updated),
            "working": status == "busy",
            # Claude names what it waits on: a permission dialog, "input needed", ...
            "needs": (str(data.get("waitingFor") or "") or "Waiting for you").capitalize() if waiting else "",
        })
    return sessions


def decode_project(name: str) -> str:
    parts = name.split("-")
    path, index = "/", 0
    while index < len(parts):
        for end in range(len(parts), index, -1):
            candidate = os.path.join(path, "-".join(parts[index:end]))
            if os.path.isdir(candidate):
                path, index = candidate, end
                break
        else:
            return ""
    return path


def cursor_title(path: Path) -> str:
    content = as_dict(first_json_line(path).get("message")).get("content")
    for block in content if isinstance(content, list) else []:
        if isinstance(block, dict) and block.get("type") == "text":
            match = USER_QUERY.search(block.get("text") or "")
            if match:
                return clip(match.group(1))
    return ""


def cursor_composers(ids: list[str]) -> dict[str, tuple[bool, str]]:
    keys = [f"composerData:{composer}" for composer in ids]
    rows = sqlite_rows(CURSOR_DB,
                       "select substr(key, 14), json_extract(value, '$.isArchived'), "
                       "json_extract(value, '$.name') from cursorDiskKV "
                       f"where key in ({placeholders(keys)})", keys)
    return {composer: (bool(archived), name or "") for composer, archived, name in rows}


def cursor_sessions(now: float) -> list[dict]:
    projects = HOME / ".cursor" / "projects"
    if not projects.is_dir():
        return []
    recent = []
    for project in projects.iterdir():
        transcripts = project / "agent-transcripts"
        if not transcripts.is_dir():
            continue
        for path in list(transcripts.glob("*.jsonl")) + list(transcripts.glob("*/*.jsonl")):
            try:
                idle = now - path.stat().st_mtime
            except OSError:
                continue
            if idle <= NEEDS_SECONDS:
                question = cursor_plan(path)
                if idle <= ACTIVE_SECONDS or question:
                    recent.append((project, path, idle, question))
    composers = cursor_composers([path.stem for _, path, _, _ in recent])
    sessions = []
    for project, path, idle, question in recent:
        archived, name = composers.get(path.stem, (False, ""))
        if archived:
            continue
        root = decode_project(project.name)
        sessions.append({
            "id": f"cursor:{path.stem}",
            "tool": "cursor",
            "title": name or cursor_title(path) or Path(root).name or project.name,
            "detail": age(idle),
            "target": f"cursor:{root}" if root else TOOLS["cursor"]["open"],
            "idle": idle,
            "working": idle <= WORKING_SECONDS and not question,
            "needs": question,
        })
    return sessions


def process_table() -> dict[int, tuple[int, str]]:
    try:
        output = subprocess.run(["ps", "-axo", "pid=,ppid=,args="], capture_output=True,
                                text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    table = {}
    for line in output.splitlines():
        fields = line.split(None, 2)
        if len(fields) == 3 and fields[0].isdigit() and fields[1].isdigit():
            table[int(fields[0])] = (int(fields[1]), fields[2])
    return table


def gemini_sessions(processes: dict[int, tuple[int, str]]) -> list[dict]:
    sessions = []
    for pid, (_, args) in processes.items():
        argv = args.split()
        # The CLI runs as `gemini …` or `node …/gemini …`; `rg gemini` is not a session.
        launcher = Path(argv[0]).name if argv else ""
        script = Path(argv[1]).name if len(argv) > 1 else ""
        if launcher == "gemini" or (launcher in ("node", "bun") and script == "gemini"):
            sessions.append({
                "id": f"gemini:{pid}",
                "tool": "gemini",
                "title": f"gemini {pid}",
                "detail": "cli",
                "target": f"pid:{pid}",
                "idle": 0,
                # A running CLI says nothing about whether it is mid-answer.
                "working": False,
                "needs": "",
            })
    return sessions


def guarded(source, *args, default):
    """Each tool's files change format under us; one bad record should cost
    that tool's sessions, not the whole snapshot."""
    try:
        return source(*args)
    except Exception as error:
        print(f"agent_sessions: {source.__name__} failed: {error!r}", file=sys.stderr)
        return default


def snapshot() -> dict:
    now = time.time()
    sessions = (guarded(codex_sessions, now, default=[]) + guarded(claude_sessions, now, default=[])
                + guarded(cursor_sessions, now, default=[])
                + guarded(lambda: gemini_sessions(process_table()), default=[]))
    sessions.sort(key=lambda s: (not s["needs"], list(TOOLS).index(s["tool"]), s["idle"]))
    counts = {tool: sum(1 for s in sessions if s["tool"] == tool) for tool in TOOLS}
    needs = {tool: sum(1 for s in sessions if s["tool"] == tool and s["needs"]) for tool in TOOLS}
    usage = {"codex": guarded(codex_usage, now, default="")}
    return {"sessions": sessions, "counts": counts, "needs": needs, "usage": usage}


def focus_command(target: str) -> str:
    script = shlex.quote(str(Path(__file__).resolve()))
    return f"{script} focus {shlex.quote(target)}"


def apply(snap: dict) -> None:
    close = f"{shlex.quote(SKETCHYBAR)} --set {ITEM} popup.drawing=off"
    total = len(snap["sessions"])
    waiting = sum(snap["needs"].values())
    # The bar shows a number only when an agent waits on you; counts live in the menu.
    args = [SKETCHYBAR, "--set", ITEM, f"label={waiting or ''}", f"label.color={NEEDS}",
            f"label.padding_right={8 if waiting else 0}",
            f"icon.color={NEEDS if waiting else TEXT if total else MUTED}"]
    for tool, info in TOOLS.items():
        count = snap["counts"][tool]
        label = f"{info['label']} {count}" if count else info["label"]
        if snap["needs"][tool]:
            label += f" · {snap['needs'][tool]} need you"
        usage = snap["usage"].get(tool)
        if usage:
            label += f" · {usage}"
        args += ["--set", f"{ITEM}.tool.{tool}", f"label={label}",
                 f"icon.color={info['color'] if count else MUTED}"]
    rows = snap["sessions"][:MAX_ROWS]
    args += ["--set", f"{ITEM}.sessions.sep", f"drawing={'on' if rows else 'off'}"]
    for slot in range(1, MAX_ROWS + 1):
        name = f"{ITEM}.session.{slot}"
        if slot > len(rows):
            args += ["--set", name, "drawing=off"]
            continue
        session = rows[slot - 1]
        detail = clip(session["needs"], 32) if session["needs"] else session["detail"]
        args += ["--set", name, "drawing=on",
                 f"label={clip(session['title'], 22)} · {detail}",
                 f"label.color={NEEDS if session['needs'] else TEXT}",
                 f"icon.color={TOOLS[session['tool']]['color']}",
                 f"click_script={focus_command(session['target'])}; {close}"]
    subprocess.run(args, capture_output=True, timeout=5)


def write_badges(snap: dict) -> None:
    """By app bundle ID, how many sessions need you (the dock's badges), and
    each session for the dock's group callouts; `updated` lets the dock ignore
    a stale file."""
    needs = {}
    for tool, count in snap["needs"].items():
        target = TOOLS[tool]["open"]
        if count and target.startswith("app:"):
            needs[target[4:]] = count
    sessions = []
    for session in snap["sessions"]:
        info = TOOLS[session["tool"]]
        sessions.append({
            "id": session["id"],
            "app": info["open"][4:] if info["open"].startswith("app:") else "",
            "title": session["title"],
            "detail": session["detail"],
            "working": session["working"],
            "needs": session["needs"],
            "color": info["color"],
            "focus": focus_command(session["target"]),
        })
    usage = {TOOLS[tool]["open"][4:]: text for tool, text in snap["usage"].items()
             if text and TOOLS[tool]["open"].startswith("app:")}
    BADGES_FILE.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps({"updated": int(time.time()), "needs": needs, "sessions": sessions,
                          "usage": usage}) + "\n"
    fd, temp = tempfile.mkstemp(dir=BADGES_FILE.parent, prefix=f".{BADGES_FILE.name}.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(payload)
        os.replace(temp, BADGES_FILE)
    except BaseException:
        Path(temp).unlink(missing_ok=True)
        raise


def window_for_pid(pid: int, processes: dict[int, tuple[int, str]]) -> int | None:
    try:
        windows = json.loads(subprocess.run([YABAI, "-m", "query", "--windows"], capture_output=True,
                                            text=True, timeout=2).stdout or "[]")
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    by_pid: dict[int, int] = {}
    for window in windows:
        by_pid.setdefault(window.get("pid"), window.get("id"))
    seen = set()
    while pid and pid not in seen:
        if pid in by_pid:
            return by_pid[pid]
        seen.add(pid)
        pid = processes.get(pid, (0, ""))[0]
    return None


def focus(target: str) -> int:
    kind, _, value = target.partition(":")
    if kind == "app" and value:
        return subprocess.run(["open", "-b", value]).returncode
    if kind == "cursor" and value:
        return subprocess.run(["open", "-b", TOOLS["cursor"]["open"][4:], value]).returncode
    if kind == "pid" and value.isdigit():
        window = window_for_pid(int(value), process_table())
        if window is not None:
            return subprocess.run([YABAI, "-m", "window", "--focus", str(window)]).returncode
    return 1


def main(argv: list[str]) -> int:
    command = argv[1] if len(argv) > 1 else "apply"
    if command == "json":
        json.dump(snapshot(), sys.stdout, indent=2)
        print()
        return 0
    if command == "apply":
        snap = snapshot()
        # The dock's feed first: a hung or missing sketchybar must not cost it.
        try:
            write_badges(snap)
        except OSError as error:
            print(f"agent_sessions: could not write {BADGES_FILE}: {error}", file=sys.stderr)
        try:
            apply(snap)
        except (OSError, subprocess.SubprocessError) as error:
            print(f"agent_sessions: could not update the bar: {error}", file=sys.stderr)
        return 0
    if command == "focus" and len(argv) > 2:
        return focus(argv[2])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
