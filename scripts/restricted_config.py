#!/usr/bin/env python3
"""Configure Barista on managed Macs without compiled helpers or yabai.

This intentionally uses only the Python standard library so it can run on
locked-down work laptops where jq, Homebrew packages, or native GUI builds are
not available.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


DEFAULT_WORK_APPS = [
    ("gmail", "Gmail", "mail.google.com", 1),
    ("calendar", "Calendar", "calendar.google.com", 2),
    ("drive", "Drive", "drive.google.com", 3),
    ("docs", "Docs", "https://docs.google.com/document/u/0/", 4),
    ("sheets", "Sheets", "https://docs.google.com/spreadsheets/u/0/", 5),
    ("meet", "Meet", "https://meet.google.com/", 6),
]


def expand_path(raw: str | None, state_file: Path | None = None) -> Path | None:
    if not raw:
        return None
    expanded = os.path.expandvars(os.path.expanduser(raw))
    path = Path(expanded)
    if path.is_absolute():
        return path
    if state_file is not None:
        return state_file.parent / path
    return path


def load_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"state.json is not valid JSON: {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"state.json must contain an object: {path}")
    return data


def atomic_write_json(path: Path, data: Any, dry_run: bool = False) -> None:
    if dry_run:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(data, indent=2, sort_keys=False) + "\n"
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=str(path.parent),
        delete=False,
    ) as handle:
        handle.write(payload)
        temp_name = handle.name
    os.replace(temp_name, path)


def ensure_dict(parent: dict[str, Any], key: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        value = {}
        parent[key] = value
    return value


def sanitize_id(raw: str | None, fallback: str = "item") -> str:
    value = (raw or fallback).lower()
    cleaned = []
    last_underscore = False
    for char in value:
        if char.isalnum():
            cleaned.append(char)
            last_underscore = False
        elif not last_underscore:
            cleaned.append("_")
            last_underscore = True
    result = "".join(cleaned).strip("_")
    return result or fallback


def google_url(host_or_url: str, domain: str = "") -> str:
    if host_or_url.startswith("http://") or host_or_url.startswith("https://"):
        return host_or_url
    if domain:
        return f"https://{host_or_url}/a/{domain}/"
    return f"https://{host_or_url}/"


def default_work_apps(domain: str = "") -> list[dict[str, Any]]:
    apps = []
    for app_id, label, host_or_url, order in DEFAULT_WORK_APPS:
        apps.append(
            {
                "id": f"work_google_{sanitize_id(app_id)}",
                "label": label,
                "url": google_url(host_or_url, domain),
                "section": "work",
                "order": order,
                "enabled": True,
            }
        )
    return apps


def load_apps_file(path: Path) -> list[dict[str, Any]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"work apps file is not valid JSON: {path}: {exc}") from exc
    if not isinstance(data, list):
        raise SystemExit(f"work apps file must contain a JSON array: {path}")
    return [item for item in data if isinstance(item, dict)]


def normalize_work_apps(apps: list[dict[str, Any]]) -> list[dict[str, Any]]:
    normalized = []
    for index, item in enumerate(apps, start=1):
        label = str(item.get("label") or item.get("title") or item.get("name") or f"Work App {index}")
        raw_id = str(item.get("id") or label)
        item_id = sanitize_id(raw_id, f"work_google_{index}")
        if not item_id.startswith("work_google_"):
            item_id = f"work_google_{item_id}"

        url = str(item.get("url") or "")
        command = str(item.get("command") or item.get("action") or "")
        entry: dict[str, Any] = {
            "id": item_id,
            "label": label,
            "section": str(item.get("section") or "work"),
            "order": item.get("order", index),
            "enabled": item.get("enabled", True),
        }
        for key in ("icon", "color", "icon_color", "label_color", "shortcut"):
            if item.get(key):
                entry[key] = item[key]
        if command:
            entry["command"] = command
        elif url:
            entry["url"] = url
        else:
            continue
        normalized.append(entry)
    return normalized


def strip_work_custom_duplicates(state: dict[str, Any], incoming_ids: set[str]) -> None:
    menus = ensure_dict(state, "menus")
    apple = ensure_dict(menus, "apple")
    custom = apple.get("custom")
    if not isinstance(custom, list):
        return
    filtered = []
    for item in custom:
        if not isinstance(item, dict):
            filtered.append(item)
            continue
        item_id = str(item.get("id") or "")
        section = str(item.get("section") or "").lower()
        if item_id in incoming_ids or (section == "work" and item_id.startswith("work_google_")):
            continue
        filtered.append(item)
    apple["custom"] = filtered


def apply_work_apps(
    state: dict[str, Any],
    state_file: Path,
    apps: list[dict[str, Any]],
    apps_file_raw: str,
    domain: str,
    replace: bool,
    dry_run: bool,
) -> Path:
    normalized = normalize_work_apps(apps)
    apps_file = expand_path(apps_file_raw, state_file)
    if apps_file is None:
        raise SystemExit("apps output file could not be resolved")

    menus = ensure_dict(state, "menus")
    apple = ensure_dict(menus, "apple")
    sections = ensure_dict(apple, "sections")
    sections.setdefault("work", {"label": "Work Apps", "order": 3})
    work = ensure_dict(menus, "work")
    work["apps_file"] = apps_file_raw
    work["workspace_domain"] = domain
    work["google_apps"] = normalized
    if replace:
        strip_work_custom_duplicates(state, {str(item.get("id")) for item in normalized})

    atomic_write_json(apps_file, normalized, dry_run=dry_run)
    return apps_file


def apply_restricted_defaults(state: dict[str, Any], args: argparse.Namespace) -> None:
    state["_version"] = state.get("_version", 1)
    state["profile"] = args.profile

    modes = ensure_dict(state, "modes")
    modes["window_manager"] = "disabled"
    modes["runtime_backend"] = "lua"
    modes["widget_daemon"] = "disabled"

    control_panel = ensure_dict(state, "control_panel")
    control_panel["preferred"] = "tui"
    control_panel.setdefault("window_mode", "standard")

    toggles = ensure_dict(state, "toggles")
    toggles["yabai_shortcuts"] = False

    widgets = ensure_dict(state, "widgets")
    for key in ("clock", "battery", "volume", "network", "system_info"):
        widgets.setdefault(key, True)
    widgets.setdefault("lmstudio", False)

    system_info = ensure_dict(state, "system_info_items")
    for key in ("cpu", "mem", "disk", "net"):
        system_info.setdefault(key, True)

    appearance = ensure_dict(state, "appearance")
    appearance.setdefault("menu_item_height", 24)
    appearance.setdefault("menu_font_style", "Semibold")
    appearance.setdefault("menu_header_font_style", "Bold")
    appearance.setdefault("menu_font_size_offset", 2)
    appearance.setdefault("menu_popup_bg_color", "0xF021162F")
    appearance.setdefault("popup_border_color", "0xB0cdd6f4")
    appearance.setdefault("font_text", "SF Pro Text")
    appearance.setdefault("font_numbers", "SF Mono")

    menus = ensure_dict(state, "menus")
    apple = ensure_dict(menus, "apple")
    apple.setdefault("show_missing", False)
    apple.setdefault("terminal", False)
    apple.setdefault("custom", [])
    sections = ensure_dict(apple, "sections")
    sections.setdefault("work", {"label": "Work Apps", "order": 3})
    sections.setdefault("custom", {"label": "Custom", "order": 8})


def menu_item_from_args(args: argparse.Namespace) -> dict[str, Any]:
    if not args.label:
        raise SystemExit("--label is required")
    command = args.command
    if not command and args.url:
        url = args.url
    else:
        url = ""
    if not command and not url and args.path:
        command = "open " + shlex.quote(args.path)
    if not command and not url:
        raise SystemExit("one of --url, --command, or --path is required")

    item = {
        "id": args.id or sanitize_id(args.label),
        "label": args.label,
        "section": args.section,
        "enabled": not args.disabled,
    }
    if command:
        item["command"] = command
    if url:
        item["url"] = url
    if args.icon:
        item["icon"] = args.icon
    if args.order is not None:
        item["order"] = args.order
    if args.shortcut:
        item["shortcut"] = args.shortcut
    return item


def upsert_custom_item(state: dict[str, Any], item: dict[str, Any]) -> None:
    menus = ensure_dict(state, "menus")
    apple = ensure_dict(menus, "apple")
    custom = apple.get("custom")
    if not isinstance(custom, list):
        custom = []
        apple["custom"] = custom

    item_id = str(item.get("id") or "")
    replaced = False
    for index, existing in enumerate(custom):
        if isinstance(existing, dict) and str(existing.get("id") or "") == item_id:
            custom[index] = item
            replaced = True
            break
    if not replaced:
        custom.append(item)

    sections = ensure_dict(apple, "sections")
    sections.setdefault(str(item.get("section") or "custom"), {"label": str(item.get("section") or "Custom").title(), "order": 8})


def maybe_reload(enabled: bool) -> None:
    if not enabled:
        return
    if not shutil_which("sketchybar"):
        return
    subprocess.run(["sketchybar", "--reload"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def shutil_which(command: str) -> str | None:
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / command
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def print_report(state_file: Path, action: str, dry_run: bool, apps_file: Path | None = None) -> None:
    print("restricted_config.report.status=ok")
    print(f"restricted_config.report.action={action}")
    print(f"restricted_config.report.dry_run={int(dry_run)}")
    print(f"restricted_config.report.state_file={state_file}")
    if apps_file:
        print(f"restricted_config.report.work_apps_file={apps_file}")


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--state", default="~/.config/sketchybar/state.json", help="state.json path")
    parser.add_argument("--dry-run", action="store_true", help="validate and report without writing")
    parser.add_argument("--report", action="store_true", help="print machine-readable report")
    parser.add_argument("--reload", action="store_true", help="reload SketchyBar after writing")
    parser.add_argument("--no-reload", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--yes", "-y", action="store_true", help=argparse.SUPPRESS)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Restricted Barista state/menu configurator")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    apply_parser = subparsers.add_parser("apply", help="apply restricted work-laptop defaults")
    add_common_args(apply_parser)
    apply_parser.add_argument("--profile", default="work", help="profile name to persist")
    apply_parser.add_argument("--domain", "--work-domain", default="", help="Google Workspace domain")
    apply_parser.add_argument("--from-file", "--work-apps-file", default="", help="JSON array of work app rows")
    apply_parser.add_argument("--work-apps-out-file", "--apps-out-file", default="data/work_apps.local.json")
    apply_parser.add_argument("--skip-work-apps", action="store_true", help="do not write default work app rows")
    apply_parser.add_argument("--replace", action="store_true", help="remove stale work custom duplicates")

    apps_parser = subparsers.add_parser("work-apps", help="write/update work web-app menu rows")
    add_common_args(apps_parser)
    apps_parser.add_argument("--domain", "--work-domain", default="", help="Google Workspace domain")
    apps_parser.add_argument("--from-file", "--work-apps-file", default="", help="JSON array of work app rows")
    apps_parser.add_argument("--work-apps-out-file", "--apps-out-file", default="data/work_apps.local.json")
    apps_parser.add_argument("--replace", action="store_true", help="remove stale work custom duplicates")

    item_parser = subparsers.add_parser("menu-item", help="add or replace a custom Apple-menu row")
    add_common_args(item_parser)
    item_parser.add_argument("--id", default="", help="stable item id")
    item_parser.add_argument("--label", required=True, help="menu row label")
    item_parser.add_argument("--url", default="", help="URL to open")
    item_parser.add_argument("--command", default="", help="shell command to run")
    item_parser.add_argument("--path", default="", help="file/folder path to open")
    item_parser.add_argument("--section", default="custom", help="popup section id")
    item_parser.add_argument("--icon", default="", help="optional icon glyph")
    item_parser.add_argument("--order", type=int, default=None, help="sort order")
    item_parser.add_argument("--shortcut", default="", help="display shortcut hint")
    item_parser.add_argument("--disabled", action="store_true", help="write the row disabled")

    summary_parser = subparsers.add_parser("summary", help="print restricted-mode summary")
    add_common_args(summary_parser)

    args = parser.parse_args(argv)
    state_file = expand_path(args.state)
    if state_file is None:
        raise SystemExit("state path could not be resolved")
    state = load_state(state_file)
    apps_file: Path | None = None

    if args.subcommand == "apply":
        apply_restricted_defaults(state, args)
        if not args.skip_work_apps:
            apps = load_apps_file(expand_path(args.from_file, state_file)) if args.from_file else default_work_apps(args.domain)
            apps_file = apply_work_apps(
                state,
                state_file,
                apps,
                args.work_apps_out_file,
                args.domain,
                args.replace,
                args.dry_run,
            )
        atomic_write_json(state_file, state, dry_run=args.dry_run)
        maybe_reload(args.reload and not args.no_reload and not args.dry_run)
    elif args.subcommand == "work-apps":
        apps = load_apps_file(expand_path(args.from_file, state_file)) if args.from_file else default_work_apps(args.domain)
        apps_file = apply_work_apps(
            state,
            state_file,
            apps,
            args.work_apps_out_file,
            args.domain,
            args.replace,
            args.dry_run,
        )
        atomic_write_json(state_file, state, dry_run=args.dry_run)
        maybe_reload(args.reload and not args.no_reload and not args.dry_run)
    elif args.subcommand == "menu-item":
        upsert_custom_item(state, menu_item_from_args(args))
        atomic_write_json(state_file, state, dry_run=args.dry_run)
        maybe_reload(args.reload and not args.no_reload and not args.dry_run)
    elif args.subcommand == "summary":
        modes = state.get("modes") if isinstance(state.get("modes"), dict) else {}
        control_panel = state.get("control_panel") if isinstance(state.get("control_panel"), dict) else {}
        menus = state.get("menus") if isinstance(state.get("menus"), dict) else {}
        work = menus.get("work") if isinstance(menus.get("work"), dict) else {}
        print(f"profile={state.get('profile', '')}")
        print(f"window_manager={modes.get('window_manager', '')}")
        print(f"runtime_backend={modes.get('runtime_backend', '')}")
        print(f"widget_daemon={modes.get('widget_daemon', '')}")
        print(f"control_panel={control_panel.get('preferred', '')}")
        print(f"work_apps_file={work.get('apps_file', '')}")

    if args.report:
        print_report(state_file, args.subcommand, args.dry_run, apps_file)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
