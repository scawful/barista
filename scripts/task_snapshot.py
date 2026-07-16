#!/usr/bin/env python3
"""Build a normalized, portable task snapshot for Barista surfaces."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Any, Iterable


SNAPSHOT_VERSION = 1
OPEN_STATES = ("ACTIVE", "NEXT", "WAITING", "BLOCKED", "TODO")
CLOSED_STATES = ("DONE", "CANCELLED")
ALL_STATES = OPEN_STATES + CLOSED_STATES
STATE_ALIASES = {
    "DOING": "ACTIVE",
    "STARTED": "ACTIVE",
    "CANCELED": "CANCELLED",
}

MARKDOWN_HEADING_RE = re.compile(r"^\s*#{1,6}\s+(.+?)\s*#*\s*$")
MARKDOWN_TASK_RE = re.compile(r"^\s*[-*+]\s+\[([ xX-])\]\s+(.+?)\s*$")
EXPLICIT_STATE_RE = re.compile(
    r"^\[(TODO|NEXT|ACTIVE|DOING|STARTED|WAITING|BLOCKED|DONE|CANCELLED|CANCELED)\]\s+(.+?)\s*$",
    re.IGNORECASE,
)
ORG_HEADING_RE = re.compile(r"^(\*+)\s+(.+?)\s*$")
ORG_TASK_RE = re.compile(
    r"^(TODO|NEXT|ACTIVE|DOING|STARTED|WAITING|BLOCKED|DONE|CANCELLED|CANCELED)\s+(.+?)\s*$",
    re.IGNORECASE,
)
ORG_TAGS_RE = re.compile(r"\s+:[\w@#%:]+:\s*$")
ORG_PRIORITY_RE = re.compile(r"^\[#[A-Za-z0-9]\]\s*")


class SnapshotError(RuntimeError):
    """Raised when an explicitly selected provider cannot produce a snapshot."""


def normalize_state(value: Any) -> str:
    state = str(value or "TODO").strip().upper()
    state = STATE_ALIASES.get(state, state)
    return state if state in ALL_STATES else "TODO"


def clean_title(value: Any) -> str:
    title = str(value or "").strip()
    title = ORG_TAGS_RE.sub("", title).strip()
    title = ORG_PRIORITY_RE.sub("", title).strip()
    return title


def canonical_path(value: str) -> str:
    path = Path(value).expanduser()
    try:
        return str(path.resolve(strict=False))
    except OSError:
        return str(path.absolute())


def source_format(path: str, text: str | None = None) -> str:
    suffix = Path(path).suffix.lower()
    if suffix == ".org":
        return "org"
    if suffix in {".md", ".markdown"}:
        return "markdown"
    if text is not None:
        for line in text.splitlines():
            if line.startswith("#+") or ORG_HEADING_RE.match(line):
                return "org"
            if MARKDOWN_HEADING_RE.match(line) or MARKDOWN_TASK_RE.match(line):
                return "markdown"
    return "markdown"


def task_id(source: str, line: int, title: str) -> str:
    identity = f"{source}\0{line}\0{title}".encode("utf-8")
    return hashlib.sha256(identity).hexdigest()


def make_task(
    source: str,
    line: int,
    section: str,
    state: str,
    title: str,
) -> dict[str, Any] | None:
    title = clean_title(title)
    if not title:
        return None
    normalized_state = normalize_state(state)
    return {
        "id": task_id(source, line, title),
        "source": source,
        "line": line,
        "section": section.strip(),
        "state": normalized_state,
        "title": title,
        "open": normalized_state in OPEN_STATES,
    }


def markdown_default_state(section: str) -> str:
    normalized = section.strip().lower()
    if normalized in {"active", "doing", "in progress", "current", "today"}:
        return "ACTIVE"
    if normalized in {"next", "up next"}:
        return "NEXT"
    if normalized in {"waiting", "wait"}:
        return "WAITING"
    if normalized == "blocked":
        return "BLOCKED"
    if normalized in {"done", "completed", "archive"}:
        return "DONE"
    if normalized in {"cancelled", "canceled"}:
        return "CANCELLED"
    return "TODO"


def parse_markdown(source: str, text: str) -> list[dict[str, Any]]:
    tasks: list[dict[str, Any]] = []
    section = ""
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        heading = MARKDOWN_HEADING_RE.match(raw_line)
        if heading:
            section = heading.group(1).strip()
            continue

        match = MARKDOWN_TASK_RE.match(raw_line)
        if not match:
            continue
        marker, title = match.groups()
        state = markdown_default_state(section)
        explicit = EXPLICIT_STATE_RE.match(title)
        if explicit:
            state = normalize_state(explicit.group(1))
            title = explicit.group(2)
        if marker in {"x", "X"}:
            state = "DONE"
        elif marker == "-":
            state = "CANCELLED"

        task = make_task(source, line_number, section, state, title)
        if task:
            tasks.append(task)
    return tasks


def parse_org(source: str, text: str) -> list[dict[str, Any]]:
    tasks: list[dict[str, Any]] = []
    headings: dict[int, str] = {}

    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        heading = ORG_HEADING_RE.match(raw_line)
        if not heading:
            continue
        stars, body = heading.groups()
        level = len(stars)
        parent_levels = [candidate for candidate in headings if candidate < level]
        section = headings[max(parent_levels)] if parent_levels else ""

        match = ORG_TASK_RE.match(body)
        if match:
            state, title = match.groups()
            task = make_task(source, line_number, section, state, title)
            if task:
                tasks.append(task)
                heading_title = task["title"]
            else:
                heading_title = clean_title(title)
        else:
            heading_title = clean_title(body)

        for old_level in [candidate for candidate in headings if candidate >= level]:
            del headings[old_level]
        headings[level] = heading_title
    return tasks


def collect_source_values(repeated: Iterable[str], combined: Iterable[str]) -> list[str]:
    values: list[str] = []
    for value in repeated:
        if value and value.strip():
            values.append(value.strip())
    for group in combined:
        for value in group.split(":"):
            if value.strip():
                values.append(value.strip())

    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        path = canonical_path(value)
        if path not in seen:
            seen.add(path)
            result.append(path)
    return result


def load_files(source_paths: list[str]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    tasks: list[dict[str, Any]] = []
    sources: list[dict[str, Any]] = []
    for source in source_paths:
        path = Path(source)
        entry: dict[str, Any] = {
            "path": source,
            "exists": path.is_file(),
            "format": source_format(source),
            "task_count": 0,
        }
        if not path.is_file():
            entry["error"] = "missing"
            sources.append(entry)
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as error:
            entry["exists"] = True
            entry["error"] = str(error)
            sources.append(entry)
            continue

        file_format = source_format(source, text)
        parsed = parse_org(source, text) if file_format == "org" else parse_markdown(source, text)
        entry["format"] = file_format
        entry["task_count"] = len(parsed)
        sources.append(entry)
        tasks.extend(parsed)
    return tasks, sources


def load_syshelp(binary: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    try:
        result = subprocess.run(
            [binary, "plan", "tasks", "json"],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
    except FileNotFoundError as error:
        raise SnapshotError("syshelp provider selected, but syshelp was not found") from error
    except subprocess.TimeoutExpired as error:
        raise SnapshotError("syshelp plan tasks json timed out") from error

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}"
        raise SnapshotError(f"syshelp plan tasks json failed: {detail}")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise SnapshotError("syshelp plan tasks json returned invalid JSON") from error
    if not isinstance(payload, dict):
        raise SnapshotError("syshelp plan tasks json returned a non-object payload")

    root_source_value = payload.get("file")
    root_source = canonical_path(root_source_value) if isinstance(root_source_value, str) and root_source_value else "syshelp"
    tasks: list[dict[str, Any]] = []
    ordinal = 0

    sections = payload.get("sections")
    if not isinstance(sections, list):
        sections = [{"name": "", "tasks": payload.get("tasks", [])}]
    for section_entry in sections:
        if not isinstance(section_entry, dict):
            continue
        section = str(section_entry.get("name") or "")
        section_tasks = section_entry.get("tasks")
        if not isinstance(section_tasks, list):
            continue
        for raw_task in section_tasks:
            if not isinstance(raw_task, dict):
                continue
            ordinal += 1
            raw_source = raw_task.get("source")
            source = canonical_path(raw_source) if isinstance(raw_source, str) and raw_source else root_source
            raw_line = raw_task.get("line")
            try:
                line_number = int(raw_line)
            except (TypeError, ValueError):
                line_number = ordinal
            task = make_task(
                source,
                line_number,
                str(raw_task.get("section") or section),
                str(raw_task.get("state") or "TODO"),
                str(raw_task.get("title") or ""),
            )
            if task:
                tasks.append(task)

    source_order: list[str] = []
    source_counts: dict[str, int] = {}
    if root_source not in source_order:
        source_order.append(root_source)
    for task in tasks:
        source = task["source"]
        if source not in source_order:
            source_order.append(source)
        source_counts[source] = source_counts.get(source, 0) + 1

    sources: list[dict[str, Any]] = []
    for source in source_order:
        if source == "syshelp":
            sources.append({
                "path": source,
                "exists": True,
                "format": "syshelp",
                "task_count": source_counts.get(source, 0),
            })
            continue
        path = Path(source)
        entry = {
            "path": source,
            "exists": path.is_file(),
            "format": source_format(source),
            "task_count": source_counts.get(source, 0),
        }
        if not path.is_file():
            entry["error"] = "missing"
        sources.append(entry)
    return tasks, sources


def count_tasks(tasks: list[dict[str, Any]]) -> dict[str, int]:
    counts = {
        "total": len(tasks),
        "open": 0,
        "closed": 0,
        **{state.lower(): 0 for state in ALL_STATES},
    }
    for task in tasks:
        state = task["state"]
        counts[state.lower()] += 1
        if task["open"]:
            counts["open"] += 1
        else:
            counts["closed"] += 1
    return counts


def first_task(
    tasks: list[dict[str, Any]],
    states: Iterable[str],
    excluded: set[str] | None = None,
) -> dict[str, Any] | None:
    excluded = excluded or set()
    for state in states:
        for task in tasks:
            if task["state"] == state and task["open"] and task["id"] not in excluded:
                return task
    return None


def build_snapshot(
    provider: str,
    tasks: list[dict[str, Any]],
    sources: list[dict[str, Any]],
) -> dict[str, Any]:
    focus = first_task(tasks, ("ACTIVE", "NEXT", "TODO"))
    excluded = {focus["id"]} if focus else set()
    next_task = first_task(tasks, ("NEXT", "TODO"), excluded)
    return {
        "version": SNAPSHOT_VERSION,
        "provider": provider,
        "generated_at": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "sources": sources,
        "counts": count_tasks(tasks),
        "tasks": tasks,
        "focus": focus,
        "next": next_task,
        "waiting": first_task(tasks, ("WAITING",)),
        "blocked": first_task(tasks, ("BLOCKED",)),
    }


def encode_snapshot(snapshot: dict[str, Any]) -> str:
    return json.dumps(snapshot, ensure_ascii=False, indent=2, sort_keys=False) + "\n"


def atomic_write(path_value: str, content: str) -> None:
    path = Path(path_value).expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=str(path.parent),
    )
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


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        action="append",
        default=[],
        help="Task source path; may be repeated (files provider)",
    )
    parser.add_argument(
        "--sources",
        action="append",
        default=[],
        help="Colon-separated task source paths (files provider)",
    )
    parser.add_argument(
        "--provider",
        choices=("files", "syshelp"),
        default="files",
        help="Snapshot provider; syshelp is never selected automatically",
    )
    parser.add_argument(
        "--output",
        help="Atomically write JSON to this path instead of stdout; use - for stdout",
    )
    parser.add_argument(
        "--syshelp-bin",
        default=os.environ.get("BARISTA_SYSHELP_BIN") or "syshelp",
        help="syshelp executable path for the explicit syshelp provider",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    source_paths = collect_source_values(args.source, args.sources)
    try:
        if args.provider == "syshelp":
            tasks, sources = load_syshelp(args.syshelp_bin)
        else:
            tasks, sources = load_files(source_paths)
        snapshot = build_snapshot(args.provider, tasks, sources)
        content = encode_snapshot(snapshot)
        if args.output and args.output != "-":
            atomic_write(args.output, content)
        else:
            sys.stdout.write(content)
    except (OSError, SnapshotError) as error:
        print(f"task_snapshot: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
