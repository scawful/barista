#!/usr/bin/env python3
"""Music studio status and menus for the Barista dock's Studio group.

Wraps the Music folder's own `studio` CLI instead of re-deriving its state.
BARISTA_MUSIC_DIR (default ~/Music) and BARISTA_STUDIO_BIN override paths.

Usage:
  dock_studio.py info         status rows for the group's info_command
  dock_studio.py logic-menu   recent Logic projects for Logic's menu_command
"""

from __future__ import annotations

import concurrent.futures
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path

MUSIC = Path(os.environ.get("BARISTA_MUSIC_DIR") or "~/Music").expanduser()
# The dock kills info commands after 5 s; every query shares this budget.
TIMEOUT = 4.0
DOCTOR_ACTION = "Studio Doctor"
SONG_ACTION = "Next Song"
NOW_STALE_DAYS = 14
RECENT_PROJECTS = 8
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def studio_bin() -> str | None:
    override = os.environ.get("BARISTA_STUDIO_BIN")
    if override:
        return override
    # Login shells do not read .zshrc, where the CLI's PATH entry usually lives.
    fallback = MUSIC / "Studio/Tools/studio/bin/studio"
    return shutil.which("studio") or (str(fallback) if fallback.exists() else None)


def run_studio(binary: str, args: list[str], timeout: float) -> str:
    env = dict(os.environ, NO_COLOR="1", COLUMNS="200", TERM="dumb")
    result = subprocess.run([binary, *args], cwd=MUSIC, env=env, capture_output=True,
                            text=True, timeout=max(timeout, 0.1))
    return result.stdout


def logic_projects(limit: int = RECENT_PROJECTS) -> list[tuple[Path, float]]:
    """Newest first. Logic saves inside the bundle, so its ProjectData dates the work."""
    found: dict[Path, float] = {}
    for root in (MUSIC / "Logic", MUSIC / "Projects/Logic Projects"):
        if not root.is_dir():
            continue
        for bundle in [*root.glob("*.logicx"), *root.glob("*/*.logicx")]:
            stamps = [bundle.stat().st_mtime]
            stamps += [data.stat().st_mtime for data in bundle.glob("Alternatives/*/ProjectData")]
            found[bundle] = max(stamps)
    return sorted(found.items(), key=lambda item: item[1], reverse=True)[:limit]


def age(seconds: float) -> str:
    if seconds < 3600:
        return "just now"
    if seconds < 86400:
        return f"{int(seconds // 3600)}h ago"
    return f"{int(seconds // 86400)}d ago"


def song_line(text: str) -> tuple[str, str] | None:
    """`studio song next`'s pick: ("song 01 — untitled", "SPARK")."""
    for raw in ANSI.sub("", text).splitlines():
        line = raw.strip(" │|\t")
        if "▶" not in line:
            continue
        pick = line.split("▶", 1)[1].strip()
        stage = re.search(r"\[([^\]]+)\]\s*$", pick)
        title = pick[:stage.start()].strip() if stage else pick
        return title, stage.group(1) if stage else ""
    return None


def status_rows(devices: dict | None, doctor: dict | None, song: tuple[str, str] | None,
                projects: list[tuple[Path, float]], now_md: float | None, now: float) -> list[dict]:
    rows = []
    if devices is not None:
        connected = [d.get("display_name") or d.get("device_id", "?")
                     for d in devices.get("devices", []) if d.get("connected")]
        inputs = (devices.get("summary") or {}).get("audio_inputs")
        rows.append({
            "title": f"Gear · {len(connected)} connected" if connected else "Gear · nothing connected",
            "detail": ", ".join(connected[:2]) + (f" +{len(connected) - 2}" if len(connected) > 2 else "")
                      if connected else (f"{inputs} audio inputs" if inputs is not None else ""),
            "tone": "ok" if connected else "none",
            "action": DOCTOR_ACTION,
        })
    if doctor is not None:
        status = doctor.get("status") or "unknown"
        advice = (doctor.get("recommended_action") or {}).get("label")
        if status == "ok" or not advice:
            rows.append({"title": "Studio ready", "detail": "doctor", "tone": "ok" if status == "ok" else "none",
                         "action": DOCTOR_ACTION})
        else:
            rows.append({"title": advice, "detail": "doctor", "tone": "error" if status == "error" else "warn",
                         "action": DOCTOR_ACTION})
    if song:
        rows.append({"title": f"Next · {song[0]}", "detail": song[1], "tone": "none", "action": SONG_ACTION})
    if projects:
        path, stamp = projects[0]
        rows.append({"title": f"Last session · {path.stem}", "detail": age(now - stamp), "tone": "none",
                     "open": str(path)})
    if now_md is not None:
        days = (now - now_md) / 86400
        rows.append({"title": f"NOW.md · {age(now - now_md)}",
                     "detail": "stale, refresh it" if days > NOW_STALE_DAYS else "",
                     "tone": "warn" if days > NOW_STALE_DAYS else "none",
                     "open": str(MUSIC / "NOW.md")})
    return [{key: value for key, value in row.items() if value} for row in rows]


def cmd_info() -> int:
    deadline = time.monotonic() + TIMEOUT
    binary = studio_bin()
    devices = doctor = song = None
    if binary is None:
        print(json.dumps({"rows": [{"title": "studio CLI not found", "detail": "Music/Studio/Tools",
                                    "tone": "error", "open": str(MUSIC)}]}))
        return 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        jobs = {name: pool.submit(run_studio, binary, args, deadline - time.monotonic())
                for name, args in (("devices", ["devices", "--json"]), ("doctor", ["doctor", "--json"]),
                                   ("song", ["song", "next"]))}
        results = {}
        for name, job in jobs.items():
            try:
                results[name] = job.result(timeout=max(deadline - time.monotonic(), 0.1))
            except (OSError, subprocess.SubprocessError, concurrent.futures.TimeoutError):
                results[name] = None
    for name in ("devices", "doctor"):
        try:
            value = json.loads(results[name]) if results[name] else None
        except ValueError:
            value = None
        if name == "devices":
            devices = value
        else:
            doctor = value
    song = song_line(results["song"]) if results["song"] else None
    now_md = MUSIC / "NOW.md"
    rows = status_rows(devices, doctor, song, logic_projects(1),
                       now_md.stat().st_mtime if now_md.exists() else None, time.time())
    print(json.dumps({"rows": rows or [{"title": "Studio status unavailable", "tone": "warn"}]}))
    return 0


def cmd_logic_menu() -> int:
    items = [{"kind": "action", "title": path.stem,
              "command": "open -a 'Logic Pro' " + shlex.quote(str(path))}
             for path, _ in logic_projects()]
    menu = [{"kind": "group", "title": "Recent Projects", "items": items}] if items else []
    print(json.dumps({"menu": menu}))
    return 0


def main(argv: list[str]) -> int:
    command = argv[0] if argv else "info"
    if command == "info":
        return cmd_info()
    if command == "logic-menu":
        return cmd_logic_menu()
    print(__doc__.strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
