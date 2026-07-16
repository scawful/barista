#!/usr/bin/env python3
"""Manage a local, menu-driven focus session without a resident daemon.

The default state file lives under Barista's ignored ``cache/`` directory. A
popup can call ``start 25``, ``start 50``, ``toggle 25``, ``stop``, or
``status`` and render the returned JSON. Expiration is derived when status is
requested; this script does not poll, launch a background process, or invoke
external commands.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import sys
import tempfile
from typing import Any


STATE_VERSION = 1
ALLOWED_DURATIONS = (25, 50)
MAX_STATE_BYTES = 64 * 1024
SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent


class FocusStateError(RuntimeError):
    """Raised when focus state cannot be written."""


def now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def format_timestamp(value: dt.datetime) -> str:
    return (
        value.astimezone(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z")
    )


def parse_timestamp(value: Any) -> dt.datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return parsed.astimezone(dt.timezone.utc)


def default_state_path() -> Path:
    explicit = os.environ.get("BARISTA_FOCUS_STATE_FILE")
    if explicit:
        return Path(explicit).expanduser()
    config_dir = Path(os.environ.get("BARISTA_CONFIG_DIR") or ROOT_DIR).expanduser()
    return config_dir / "cache" / "focus_session" / "state.json"


def read_state(path: Path) -> tuple[dict[str, Any] | None, str]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            content = handle.read(MAX_STATE_BYTES + 1)
    except FileNotFoundError:
        return None, "missing"
    except (OSError, UnicodeError):
        return None, "corrupt"

    if len(content) > MAX_STATE_BYTES:
        return None, "corrupt"
    try:
        payload = json.loads(content)
    except (json.JSONDecodeError, UnicodeError):
        return None, "corrupt"
    if not isinstance(payload, dict) or payload.get("version") != STATE_VERSION:
        return None, "corrupt"

    state = payload.get("state")
    if state == "idle":
        return payload, "ok"
    if state != "active":
        return None, "corrupt"

    duration = payload.get("duration_minutes")
    started_at = parse_timestamp(payload.get("started_at"))
    ends_at = parse_timestamp(payload.get("ends_at"))
    if (
        type(duration) is not int
        or duration not in ALLOWED_DURATIONS
        or started_at is None
        or ends_at is None
        or ends_at <= started_at
        or abs((ends_at - started_at).total_seconds() - duration * 60) > 1
    ):
        return None, "corrupt"
    return payload, "ok"


def atomic_write(path: Path, payload: dict[str, Any]) -> None:
    content = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{path.name}.",
            suffix=".tmp",
            dir=str(path.parent),
        )
    except OSError as error:
        raise FocusStateError(str(error)) from error

    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def empty_status(health: str = "ok") -> dict[str, Any]:
    return {
        "version": STATE_VERSION,
        "state": "idle",
        "active": False,
        "duration_minutes": None,
        "started_at": None,
        "ends_at": None,
        "remaining_seconds": 0,
        "remaining_minutes": 0,
        "health": health,
    }


def derive_status(
    payload: dict[str, Any] | None,
    health: str,
    current_time: dt.datetime,
) -> dict[str, Any]:
    if payload is None or payload.get("state") == "idle":
        return empty_status(health)

    ends_at = parse_timestamp(payload["ends_at"])
    if ends_at is None:  # Defensive; read_state validates active payloads.
        return empty_status("corrupt")
    remaining_seconds = max(0, math.ceil((ends_at - current_time).total_seconds()))
    active = remaining_seconds > 0
    return {
        "version": STATE_VERSION,
        "state": "active" if active else "expired",
        "active": active,
        "duration_minutes": payload["duration_minutes"],
        "started_at": payload["started_at"],
        "ends_at": payload["ends_at"],
        "remaining_seconds": remaining_seconds,
        "remaining_minutes": math.ceil(remaining_seconds / 60),
        "health": health,
    }


def start_session(path: Path, duration: int, current_time: dt.datetime) -> dict[str, Any]:
    ends_at = current_time + dt.timedelta(minutes=duration)
    payload = {
        "version": STATE_VERSION,
        "state": "active",
        "duration_minutes": duration,
        "started_at": format_timestamp(current_time),
        "ends_at": format_timestamp(ends_at),
    }
    atomic_write(path, payload)
    return derive_status(payload, "ok", current_time)


def stop_session(path: Path, current_time: dt.datetime) -> dict[str, Any]:
    payload = {
        "version": STATE_VERSION,
        "state": "idle",
        "stopped_at": format_timestamp(current_time),
    }
    atomic_write(path, payload)
    return empty_status("ok")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument(
        "--state-file",
        type=Path,
        default=default_state_path(),
        help=(
            "State file path (default: BARISTA_FOCUS_STATE_FILE or "
            "BARISTA_CONFIG_DIR/cache/focus_session/state.json)"
        ),
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status", help="Print current status JSON")
    start = commands.add_parser("start", help="Start or replace a focus session")
    start.add_argument("minutes", type=int, choices=ALLOWED_DURATIONS)
    toggle = commands.add_parser("toggle", help="Start a session, or stop the active one")
    toggle.add_argument("minutes", type=int, choices=ALLOWED_DURATIONS, nargs="?", default=25)
    commands.add_parser("stop", help="Stop the current focus session")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    state_path = args.state_file.expanduser()
    current_time = now_utc()
    try:
        if args.command == "start":
            status = start_session(state_path, args.minutes, current_time)
        elif args.command == "toggle":
            payload, health = read_state(state_path)
            current = derive_status(payload, health, current_time)
            if current["active"]:
                status = stop_session(state_path, current_time)
            else:
                status = start_session(state_path, args.minutes, current_time)
        elif args.command == "stop":
            status = stop_session(state_path, current_time)
        else:
            payload, health = read_state(state_path)
            status = derive_status(payload, health, current_time)
    except (OSError, FocusStateError) as error:
        print(f"focus_session: {error}", file=sys.stderr)
        return 2

    sys.stdout.write(json.dumps(status, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
