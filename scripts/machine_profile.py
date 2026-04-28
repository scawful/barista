#!/usr/bin/env python3
"""Machine-local Barista profile and capability configurator.

This script is intentionally Python standard-library only. It is safe to run on
managed Macs where jq, Homebrew packages, yabai, or compiled Barista helpers may
not be approved.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import sys
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent

sys.path.insert(0, str(SCRIPT_DIR))
import restricted_config  # noqa: E402


VARIANT_ALIASES = {
    "restricted": "restricted-work",
    "work-restricted": "restricted-work",
    "scripts-only": "restricted-work",
    "shared": "minimal",
    "full": "personal",
}


PROFILE_VARIANTS: dict[str, dict[str, Any]] = {
    "minimal": {
        "state_profile": "minimal",
        "restricted": False,
        "menu_packs": ["core", "restricted_safe"],
        "modes": {
            "window_manager": "optional",
            "runtime_backend": "auto",
            "widget_daemon": "auto",
        },
        "control_panel": {"preferred": "tui", "window_mode": "standard"},
        "toggles": {"yabai_shortcuts": False},
    },
    "cozy": {
        "state_profile": "cozy",
        "restricted": False,
        "menu_packs": ["core", "restricted_safe"],
        "modes": {
            "window_manager": "disabled",
            "runtime_backend": "auto",
            "widget_daemon": "auto",
        },
        "control_panel": {"preferred": "tui", "window_mode": "standard"},
        "toggles": {"yabai_shortcuts": False},
    },
    "personal": {
        "state_profile": "personal",
        "restricted": False,
        "menu_packs": ["core", "dev_tools", "personal"],
        "modes": {
            "window_manager": "required",
            "runtime_backend": "auto",
            "widget_daemon": "auto",
        },
        "control_panel": {"preferred": "native", "window_mode": "standard"},
        "toggles": {"yabai_shortcuts": True},
    },
    "work": {
        "state_profile": "work",
        "restricted": False,
        "menu_packs": ["core", "work", "dev_tools"],
        "modes": {
            "window_manager": "required",
            "runtime_backend": "auto",
            "widget_daemon": "auto",
        },
        "control_panel": {"preferred": "tui", "window_mode": "standard"},
        "toggles": {"yabai_shortcuts": True},
    },
    "restricted-work": {
        "state_profile": "work",
        "restricted": True,
        "menu_packs": ["core", "work", "restricted_safe"],
        "modes": {
            "window_manager": "disabled",
            "runtime_backend": "lua",
            "widget_daemon": "disabled",
        },
        "control_panel": {"preferred": "tui", "window_mode": "standard"},
        "toggles": {"yabai_shortcuts": False},
    },
}


COMMAND_CAPABILITIES = {
    "sketchybar": "sketchybar",
    "yabai": "yabai",
    "skhd": "skhd",
    "jq": "jq",
    "python3": "python3",
    "swift": "swift",
    "xcodebuild": "xcodebuild",
    "open": "open",
    "brew": "brew",
}


def expand_path(raw: str | None, state_file: Path | None = None) -> Path | None:
    return restricted_config.expand_path(raw, state_file)


def load_json_object(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"JSON file is invalid: {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"JSON file must contain an object: {path}")
    return data


def atomic_write_json(path: Path, data: Any, dry_run: bool = False) -> None:
    restricted_config.atomic_write_json(path, data, dry_run=dry_run)


def ensure_dict(parent: dict[str, Any], key: str) -> dict[str, Any]:
    return restricted_config.ensure_dict(parent, key)


def normalize_variant(raw: str) -> str:
    value = (raw or "minimal").strip().lower().replace("_", "-")
    value = VARIANT_ALIASES.get(value, value)
    if value not in PROFILE_VARIANTS:
        valid = ", ".join(sorted(PROFILE_VARIANTS))
        raise SystemExit(f"Unsupported profile variant '{raw}'. Valid variants: {valid}")
    return value


def normalize_runtime_backend(raw: str) -> str:
    value = (raw or "").strip().lower()
    if value in {"auto", "lua", "compiled"}:
        return value
    raise SystemExit(f"Unsupported runtime backend '{raw}'. Valid values: auto, lua, compiled")


def normalize_window_manager(raw: str) -> str:
    value = (raw or "").strip().lower()
    aliases = {
        "off": "disabled",
        "disable": "disabled",
        "disabled": "disabled",
        "opt": "optional",
        "optional": "optional",
        "on": "required",
        "enable": "required",
        "required": "required",
        "auto": "auto",
    }
    if value in aliases:
        return aliases[value]
    raise SystemExit(f"Unsupported window manager mode '{raw}'. Valid values: auto, optional, required, disabled")


def normalize_panel_mode(raw: str) -> str:
    value = (raw or "").strip().lower()
    if value in {"native", "tui", "imgui", "custom"}:
        return value
    raise SystemExit(f"Unsupported panel mode '{raw}'. Valid values: native, tui, imgui, custom")


def command_path(command: str) -> str:
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = Path(directory) / command
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return ""


def executable(path: Path) -> bool:
    return path.exists() and os.access(path, os.X_OK)


def detect_capabilities(root_dir: Path = ROOT_DIR) -> dict[str, Any]:
    commands = {name: command_path(command) for name, command in COMMAND_CAPABILITIES.items()}
    paths = {
        "barista_app": [
            "/Applications/Barista.app",
            str(root_dir / "bin" / "Barista.app"),
            str(root_dir / "build" / "bin" / "Barista.app"),
        ],
        "config_menu": [
            str(root_dir / "bin" / "config_menu"),
            str(root_dir / "gui" / "bin" / "config_menu"),
            str(root_dir / "build" / "bin" / "config_menu"),
        ],
        "runtime_context_helper": [
            str(root_dir / "bin" / "runtime_context_helper"),
            str(root_dir / "build" / "bin" / "runtime_context_helper"),
        ],
        "widget_manager": [
            str(root_dir / "bin" / "widget_manager"),
            str(root_dir / "helpers" / "widget_manager"),
            str(root_dir / "build" / "bin" / "widget_manager"),
        ],
    }
    resolved_paths: dict[str, str] = {}
    for name, candidates in paths.items():
        resolved_paths[name] = next((candidate for candidate in candidates if Path(candidate).exists()), "")

    has_native_panel = bool(resolved_paths["barista_app"] or resolved_paths["config_menu"])
    has_compiled_helpers = bool(
        executable(Path(resolved_paths["runtime_context_helper"]))
        or executable(Path(resolved_paths["widget_manager"]))
    )
    return {
        "commands": commands,
        "paths": resolved_paths,
        "sketchybar": bool(commands["sketchybar"]),
        "yabai": bool(commands["yabai"]),
        "skhd": bool(commands["skhd"]),
        "jq": bool(commands["jq"]),
        "python3": bool(commands["python3"]),
        "swift": bool(commands["swift"]),
        "xcodebuild": bool(commands["xcodebuild"]),
        "open": bool(commands["open"]),
        "brew": bool(commands["brew"]),
        "native_panel": has_native_panel,
        "compiled_helpers": has_compiled_helpers,
        "window_manager_stack": bool(commands["yabai"] and commands["skhd"]),
    }


def allowed_features(
    variant: str,
    capabilities: dict[str, Any],
    modes: dict[str, Any] | None = None,
) -> dict[str, bool]:
    spec = PROFILE_VARIANTS[variant]
    restricted = bool(spec["restricted"])
    resolved_modes = dict(spec["modes"])
    if modes:
        resolved_modes.update(modes)
    window_manager_mode = resolved_modes["window_manager"]
    runtime_backend = resolved_modes["runtime_backend"]
    return {
        "script_menus": True,
        "work_apps": "work" in spec["menu_packs"],
        "shell_actions": bool(capabilities.get("open", False)),
        "python_config": bool(capabilities.get("python3", False)),
        "native_panel": bool(capabilities.get("native_panel", False)) and not restricted,
        "compiled_helpers": bool(capabilities.get("compiled_helpers", False))
        and not restricted
        and runtime_backend != "lua",
        "window_manager": bool(capabilities.get("window_manager_stack", False))
        and not restricted
        and window_manager_mode != "disabled",
        "shortcut_daemon": bool(capabilities.get("skhd", False))
        and not restricted
        and window_manager_mode != "disabled",
        "homebrew_setup": bool(capabilities.get("brew", False)) and not restricted,
    }


def machine_profile_payload(
    variant: str,
    capabilities: dict[str, Any],
    machine_name: str = "",
    mode_overrides: dict[str, str] | None = None,
    panel_mode: str = "",
) -> dict[str, Any]:
    spec = PROFILE_VARIANTS[variant]
    modes = dict(spec["modes"])
    if mode_overrides:
        modes.update(mode_overrides)
    control_panel = dict(spec["control_panel"])
    if panel_mode:
        control_panel["preferred"] = panel_mode
    return {
        "_version": 1,
        "computer_name": machine_name or platform.node() or "unknown",
        "profile_variant": variant,
        "state_profile": spec["state_profile"],
        "restricted": bool(spec["restricted"]),
        "menu_packs": list(spec["menu_packs"]),
        "modes": modes,
        "control_panel": control_panel,
        "toggles": dict(spec["toggles"]),
        "allowed_features": allowed_features(variant, capabilities, modes),
        "capabilities": capabilities,
    }


def apply_basic_variant_state(state: dict[str, Any], variant: str, payload: dict[str, Any]) -> None:
    state["_version"] = state.get("_version", 1)
    state["profile"] = payload["state_profile"]

    modes = ensure_dict(state, "modes")
    for key, value in payload["modes"].items():
        modes[key] = value

    control_panel = ensure_dict(state, "control_panel")
    for key, value in payload["control_panel"].items():
        control_panel[key] = value

    toggles = ensure_dict(state, "toggles")
    for key, value in payload["toggles"].items():
        toggles[key] = value

    widgets = ensure_dict(state, "widgets")
    widgets["lmstudio"] = variant == "personal"

    machine = ensure_dict(state, "machine")
    machine["profile_variant"] = payload["profile_variant"]
    machine["restricted"] = payload["restricted"]
    machine["menu_packs"] = payload["menu_packs"]
    machine["allowed_features"] = payload["allowed_features"]


def apply_work_apps_if_requested(
    state: dict[str, Any],
    state_file: Path,
    args: argparse.Namespace,
    write_defaults: bool,
) -> Path | None:
    if args.skip_work_apps or not write_defaults:
        return None
    if args.from_file:
        apps_path = expand_path(args.from_file, state_file)
        if apps_path is None:
            raise SystemExit("work apps input path could not be resolved")
        apps = restricted_config.load_apps_file(apps_path)
    else:
        apps = restricted_config.default_work_apps(args.domain)
    return restricted_config.apply_work_apps(
        state,
        state_file,
        apps,
        args.work_apps_out_file,
        args.domain,
        args.replace,
        args.dry_run,
    )


def maybe_reload(enabled: bool) -> None:
    restricted_config.maybe_reload(enabled)


def run_apply(args: argparse.Namespace) -> int:
    variant = normalize_variant(args.variant)
    state_file = expand_path(args.state)
    machine_file = expand_path(args.machine_file, state_file)
    if state_file is None or machine_file is None:
        raise SystemExit("state or machine profile path could not be resolved")

    mode_overrides: dict[str, str] = {}
    if variant != "restricted-work":
        if args.runtime_backend:
            mode_overrides["runtime_backend"] = normalize_runtime_backend(args.runtime_backend)
        if args.window_manager:
            mode_overrides["window_manager"] = normalize_window_manager(args.window_manager)
        panel_mode = normalize_panel_mode(args.panel_mode) if args.panel_mode else ""
    else:
        panel_mode = ""

    capabilities = detect_capabilities(ROOT_DIR)
    payload = machine_profile_payload(variant, capabilities, args.computer_name, mode_overrides, panel_mode)
    state = restricted_config.load_state(state_file)

    if variant == "restricted-work":
        restricted_args = argparse.Namespace(profile=PROFILE_VARIANTS[variant]["state_profile"])
        restricted_config.apply_restricted_defaults(state, restricted_args)
    else:
        apply_basic_variant_state(state, variant, payload)

    apps_file = apply_work_apps_if_requested(
        state,
        state_file,
        args,
        write_defaults=("work" in PROFILE_VARIANTS[variant]["menu_packs"] and bool(args.domain or args.from_file or args.write_work_apps)),
    )
    if variant == "restricted-work" and apps_file is None and not args.skip_work_apps:
        apps_file = apply_work_apps_if_requested(state, state_file, args, write_defaults=True)

    atomic_write_json(machine_file, payload, dry_run=args.dry_run)
    atomic_write_json(state_file, state, dry_run=args.dry_run)
    maybe_reload(args.reload and not args.no_reload and not args.dry_run)

    if args.report:
        print("machine_profile.report.status=ok")
        print(f"machine_profile.report.variant={variant}")
        print(f"machine_profile.report.restricted={int(payload['restricted'])}")
        print(f"machine_profile.report.state_profile={payload['state_profile']}")
        print(f"machine_profile.report.state_file={state_file}")
        print(f"machine_profile.report.machine_file={machine_file}")
        print(f"machine_profile.report.dry_run={int(args.dry_run)}")
        if apps_file:
            print(f"machine_profile.report.work_apps_file={apps_file}")
    return 0


def print_capabilities(args: argparse.Namespace) -> int:
    capabilities = detect_capabilities(ROOT_DIR)
    if args.format == "json":
        print(json.dumps(capabilities, indent=2, sort_keys=True))
    else:
        for key in sorted(k for k, v in capabilities.items() if isinstance(v, bool)):
            print(f"capability.{key}={int(bool(capabilities[key]))}")
        for key, value in sorted(capabilities["paths"].items()):
            print(f"path.{key}={value}")
    return 0


def print_report(args: argparse.Namespace) -> int:
    state_file = expand_path(args.state)
    machine_file = expand_path(args.machine_file, state_file)
    if state_file is None or machine_file is None:
        raise SystemExit("state or machine profile path could not be resolved")
    state = restricted_config.load_state(state_file)
    machine = load_json_object(machine_file)
    capabilities = detect_capabilities(ROOT_DIR)
    variant = machine.get("profile_variant") or state.get("profile") or "minimal"
    try:
        variant = normalize_variant(str(variant))
    except SystemExit:
        variant = "minimal"

    features = machine.get("allowed_features")
    if not isinstance(features, dict):
        features = allowed_features(variant, capabilities)

    print(f"profile={state.get('profile', '')}")
    print(f"profile_variant={machine.get('profile_variant', '')}")
    print(f"restricted={int(bool(machine.get('restricted', False)))}")
    print(f"machine_file={machine_file}")
    print(f"state_file={state_file}")
    for key in sorted(features):
        print(f"feature.{key}={int(bool(features[key]))}")
    return 0


def add_common_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--state", default="~/.config/sketchybar/state.json", help="state.json path")
    parser.add_argument(
        "--machine-file",
        default="data/machine.local.json",
        help="machine-local profile JSON path, relative to state.json by default",
    )
    parser.add_argument("--dry-run", action="store_true", help="validate and report without writing")
    parser.add_argument("--report", action="store_true", help="print machine-readable report")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Barista machine profile configurator")
    subparsers = parser.add_subparsers(dest="subcommand", required=True)

    capabilities_parser = subparsers.add_parser("capabilities", help="probe available local tools")
    capabilities_parser.add_argument("--format", choices=("env", "json"), default="env")

    apply_parser = subparsers.add_parser("apply", help="apply a machine profile variant")
    add_common_args(apply_parser)
    apply_parser.add_argument(
        "--variant",
        default="minimal",
        help="profile variant: minimal, cozy, personal, work, restricted-work",
    )
    apply_parser.add_argument("--computer-name", default="", help="name to store in machine profile")
    apply_parser.add_argument("--runtime-backend", default="", help="override runtime backend for this machine")
    apply_parser.add_argument("--window-manager", default="", help="override window-manager mode for this machine")
    apply_parser.add_argument("--panel-mode", default="", help="override preferred control panel mode")
    apply_parser.add_argument("--domain", "--work-domain", default="", help="Google Workspace domain")
    apply_parser.add_argument("--from-file", "--work-apps-file", default="", help="JSON array of work app rows")
    apply_parser.add_argument("--work-apps-out-file", "--apps-out-file", default="data/work_apps.local.json")
    apply_parser.add_argument("--write-work-apps", action="store_true", help="write work app rows even without a domain")
    apply_parser.add_argument("--skip-work-apps", action="store_true", help="do not write work app rows")
    apply_parser.add_argument("--replace", action="store_true", help="remove stale work custom duplicates")
    apply_parser.add_argument("--reload", action="store_true", help="reload SketchyBar after writing")
    apply_parser.add_argument("--no-reload", action="store_true", help=argparse.SUPPRESS)
    apply_parser.add_argument("--yes", "-y", action="store_true", help=argparse.SUPPRESS)

    report_parser = subparsers.add_parser("report", help="print current machine profile summary")
    add_common_args(report_parser)

    args = parser.parse_args(argv)
    if args.subcommand == "capabilities":
        return print_capabilities(args)
    if args.subcommand == "apply":
        return run_apply(args)
    if args.subcommand == "report":
        return print_report(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
