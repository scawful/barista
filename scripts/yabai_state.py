#!/usr/bin/env python3
"""Validate and atomically update Barista's saved Yabai choices."""

import fcntl
import hashlib
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


# Barista's app levels and the Yabai sub-layer each one installs.
WINDOW_LEVELS = {"normal": "below", "raised": "normal", "top": "above"}


def object_field(parent, key):
    value = parent.setdefault(key, {})
    # Lua's empty tables may be encoded as [] in existing state.json files.
    if value == []:
        value = parent[key] = {}
    if not isinstance(value, dict):
        raise ValueError(f"{key} must be a JSON object")
    return value


def normalize_locked_spaces(spaces_cfg):
    raw = spaces_cfg.get("locked_spaces", {})
    if isinstance(raw, list):
        normalized = {str(item): True for item in raw if str(item)}
        spaces_cfg["locked_spaces"] = normalized
        return normalized
    if isinstance(raw, dict):
        normalized = {str(k): bool(v) for k, v in raw.items() if str(k) and v}
        spaces_cfg["locked_spaces"] = normalized
        return normalized
    raise ValueError("spaces.locked_spaces must be a JSON object or array")


SPACE_POLICY_VALIDATORS = {
    "max_spaces_per_display": lambda v: int(v) if v.isdecimal() and 0 <= int(v) <= 32 else (_ for _ in ()).throw(ValueError("max_spaces_per_display must be an integer between 0 and 32")),
    "min_spaces_per_display": lambda v: int(v) if v.isdecimal() and 1 <= int(v) <= 16 else (_ for _ in ()).throw(ValueError("min_spaces_per_display must be an integer between 1 and 16")),
    "destroy_non_empty_policy": lambda v: v if v in ("allow", "refuse", "evacuate") else (_ for _ in ()).throw(ValueError("destroy_non_empty_policy must be allow, refuse, or evacuate")),
    "new_space_layout": lambda v: v if v in ("default", "bsp", "stack", "float", "inherit") else (_ for _ in ()).throw(ValueError("new_space_layout must be default, bsp, stack, float, or inherit")),
    "window_move_policy": lambda v: v if v in ("preserve", "adopt_destination") else (_ for _ in ()).throw(ValueError("window_move_policy must be preserve or adopt_destination")),
    "creator_mode": lambda v: v if v in ("per_display", "primary", "active") else (_ for _ in ()).throw(ValueError("creator_mode must be per_display, primary, or active")),
    "right_click_close": lambda v: v if v in ("confirm", "direct", "off") else (_ for _ in ()).throw(ValueError("right_click_close must be confirm, direct, or off")),
    "reorder_mode": lambda v: v if v in ("menu", "modifier_click", "off") else (_ for _ in ()).throw(ValueError("reorder_mode must be menu, modifier_click, or off")),
}

# `yabai_shortcuts` is owned by toggle_shortcuts.sh, which also manages skhd.
FEATURE_TOGGLE_DEFAULTS = {
    "stack_indicator": True,
}

WORKFLOW_POLICY_DEFAULTS = {
    "scratchpad": {
        "width_pct": 75,
        "height_pct": 75,
        "terminal_cmd": "",
        "files_cmd": "yazi",
    },
    "emacs": {
        "client_bin": "emacsclient",
        "app_name": "Emacs",
        "capture_key": "",
    },
    "files": {
        "picker": "auto",
        "default_root": "~/src",
    },
}


def _parse_bool(raw_val, name):
    lowered = str(raw_val).strip().lower()
    if lowered in ("true", "1", "on", "yes", "enable", "enabled"):
        return True
    if lowered in ("false", "0", "off", "no", "disable", "disabled"):
        return False
    raise ValueError(f"{name} must be on/off or true/false")


WORKFLOW_POLICY_VALIDATORS = {
    "scratchpad.width_pct": lambda v: int(v) if str(v).isdecimal() and 25 <= int(v) <= 100 else (_ for _ in ()).throw(ValueError("scratchpad.width_pct must be between 25 and 100")),
    "scratchpad.height_pct": lambda v: int(v) if str(v).isdecimal() and 25 <= int(v) <= 100 else (_ for _ in ()).throw(ValueError("scratchpad.height_pct must be between 25 and 100")),
    "scratchpad.terminal_cmd": lambda v: str(v),
    "scratchpad.files_cmd": lambda v: str(v).strip() or (_ for _ in ()).throw(ValueError("scratchpad.files_cmd cannot be empty")),
    "emacs.client_bin": lambda v: str(v).strip() or (_ for _ in ()).throw(ValueError("emacs.client_bin cannot be empty")),
    "emacs.app_name": lambda v: str(v).strip() or (_ for _ in ()).throw(ValueError("emacs.app_name cannot be empty")),
    "emacs.capture_key": lambda v: str(v).strip(),
    "files.picker": lambda v: str(v).strip() if str(v).strip() in ("auto", "yazi", "fzf", "dired") else (_ for _ in ()).throw(ValueError("files.picker must be auto, yazi, fzf, or dired")),
    "files.default_root": lambda v: str(v).strip() or (_ for _ in ()).throw(ValueError("files.default_root cannot be empty")),
}


def update(path, operation, values):
    path = Path(path).expanduser()
    path.parent.mkdir(parents=True, exist_ok=True)
    # Match tui.config._config_lock without importing its UI dependencies.
    # Canonical paths make symlinked config directories share the same lock.
    lock_root = Path(tempfile.gettempdir()) / f"barista-config-locks-{os.getuid()}"
    lock_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    canonical_path = str(path.resolve(strict=False))
    lock_name = hashlib.sha256(canonical_path.encode("utf-8")).hexdigest()
    result_summary = None
    with (lock_root / f"{lock_name}.lock").open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with path.open(encoding="utf-8") as source:
                data = json.load(source)
        except FileNotFoundError:
            data = {}
        if not isinstance(data, dict):
            raise ValueError("state must be a JSON object")

        if operation in ("space-check", "space-mode", "space-unset"):
            modes = object_field(data, "space_modes")
            modes_by_uuid = object_field(data, "space_modes_by_uuid")
            bindings = object_field(data, "space_mode_uuids")
            if operation == "space-mode":
                space, mode = values[:2]
                space_uuid = values[2] if len(values) > 2 else ""
                if not space.isdecimal() or int(space) < 1 or mode not in ("float", "bsp", "stack"):
                    raise ValueError("invalid space index or layout")
                if space_uuid:
                    # Keep UUID choices even when a newly saved space occupies
                    # another space's old index after a reorder.
                    for old_index, bound_uuid in list(bindings.items()):
                        if bound_uuid == space_uuid and old_index != space:
                            bindings.pop(old_index)
                            modes.pop(old_index, None)
                    modes_by_uuid[space_uuid] = mode
                    bindings[space] = space_uuid
                else:
                    # Legacy callers address positions and have no identity.
                    # Remove only that position's previous canonical choice.
                    previous_uuid = bindings.pop(space, None)
                    if previous_uuid:
                        modes_by_uuid.pop(previous_uuid, None)
                modes[space] = mode
            elif operation == "space-unset":
                space = values[0]
                space_uuid = values[1] if len(values) > 1 else ""
                modes.pop(space, None)
                bound_uuid = bindings.pop(space, None)
                if bound_uuid:
                    modes_by_uuid.pop(bound_uuid, None)
                if space_uuid:
                    modes_by_uuid.pop(space_uuid, None)
                    for old_index, candidate_uuid in list(bindings.items()):
                        if candidate_uuid == space_uuid:
                            bindings.pop(old_index, None)
                            modes.pop(old_index, None)
        elif operation in ("space-prune", "space-prune-check"):
            modes = object_field(data, "space_modes")
            modes_by_uuid = object_field(data, "space_modes_by_uuid")
            bindings = object_field(data, "space_mode_uuids")
            live_spaces = json.loads(values[0]) if values else []
            if not isinstance(live_spaces, list):
                raise ValueError("live spaces payload must be a JSON array")
            live_index_to_uuid = {}
            live_uuid_to_index = {}
            for entry in live_spaces:
                if not isinstance(entry, dict):
                    continue
                idx = entry.get("index")
                uuid = entry.get("uuid")
                if isinstance(idx, int) and idx >= 1:
                    idx_str = str(idx)
                    uuid_str = str(uuid) if isinstance(uuid, str) and uuid else ""
                    live_index_to_uuid[idx_str] = uuid_str
                    if uuid_str:
                        live_uuid_to_index[uuid_str] = idx_str
            pruned_uuids = []
            for saved_uuid in list(modes_by_uuid.keys()):
                if saved_uuid not in live_uuid_to_index:
                    pruned_uuids.append(saved_uuid)
                    modes_by_uuid.pop(saved_uuid, None)
            pruned_indices = []
            for saved_index in list(set(modes.keys()) | set(bindings.keys())):
                bound_uuid = bindings.get(saved_index, "")
                if saved_index not in live_index_to_uuid:
                    pruned_indices.append(saved_index)
                    modes.pop(saved_index, None)
                    bindings.pop(saved_index, None)
                elif bound_uuid and bound_uuid not in live_uuid_to_index:
                    pruned_indices.append(saved_index)
                    modes.pop(saved_index, None)
                    bindings.pop(saved_index, None)
            remapped = {}
            for uuid_str, mode in list(modes_by_uuid.items()):
                live_idx = live_uuid_to_index.get(uuid_str)
                if live_idx:
                    if bindings.get(live_idx) != uuid_str or modes.get(live_idx) != mode:
                        remapped[live_idx] = mode
                    for old_idx, old_uuid in list(bindings.items()):
                        if old_uuid == uuid_str and old_idx != live_idx:
                            bindings.pop(old_idx, None)
                            modes.pop(old_idx, None)
                    bindings[live_idx] = uuid_str
                    modes[live_idx] = mode
            result_summary = {
                "pruned_uuids": sorted(pruned_uuids),
                "pruned_indices": sorted(pruned_indices),
                "remapped_indices": remapped,
                "active_modes": dict(modes),
                "active_uuids": len(modes_by_uuid),
            }
        elif operation in ("space-lock", "space-unlock", "space-policy"):
            spaces_cfg = object_field(data, "spaces")
            if operation in ("space-lock", "space-unlock"):
                target = str(values[0]).strip() if values else ""
                if not target:
                    raise ValueError("space lock target cannot be empty")
                locked = normalize_locked_spaces(spaces_cfg)
                if operation == "space-lock":
                    locked[target] = True
                else:
                    locked.pop(target, None)
                result_summary = {"locked_spaces": sorted(locked.keys())}
            elif operation == "space-policy":
                key, raw_val = values[:2]
                if key not in SPACE_POLICY_VALIDATORS:
                    raise ValueError(f"unsupported space policy key: {key}")
                spaces_cfg[key] = SPACE_POLICY_VALIDATORS[key](raw_val)
                result_summary = {key: spaces_cfg[key]}
        elif operation in ("app-check", "app-default", "app-unset"):
            apps = object_field(object_field(data, "window_defaults"), "apps")
            if operation == "app-default":
                app, mode, app_regex, label = values
                if not app or mode not in ("float", "tile"):
                    raise ValueError("invalid app name or default")
                apps[app] = {
                    "mode": mode,
                    "app_regex": app_regex,
                    "rule_label": label,
                    "manage": "off" if mode == "float" else "on",
                }
            elif operation == "app-unset":
                apps.pop(values[0], None)
        elif operation in ("level-check", "app-level", "level-unset"):
            # Window stacking per app, apart from float/tile: normal shares
            # the tiled windows' layer, raised sits above it, top above all.
            levels = object_field(data, "window_levels")
            if operation == "app-level":
                app, level, app_regex, label = values
                if not app or level not in WINDOW_LEVELS:
                    raise ValueError("invalid app name or level")
                levels[app] = {"level": level, "app_regex": app_regex, "rule_label": label}
            elif operation == "level-unset":
                levels.pop(values[0], None)
        elif operation in ("shortcuts-check", "shortcuts-state"):
            toggles = object_field(data, "toggles")
            if operation == "shortcuts-state":
                if values[0] not in ("true", "false"):
                    raise ValueError("shortcut state must be true or false")
                toggles["yabai_shortcuts"] = values[0] == "true"
        elif operation in ("feature-toggle", "feature-check"):
            toggles = object_field(data, "toggles")
            if operation == "feature-toggle":
                key = str(values[0]).strip() if values else ""
                if key not in FEATURE_TOGGLE_DEFAULTS:
                    raise ValueError(f"unsupported feature toggle: {key}")
                mode = str(values[1]).strip().lower() if len(values) > 1 else "toggle"
                current = bool(toggles.get(key, FEATURE_TOGGLE_DEFAULTS[key]))
                if mode == "toggle":
                    toggles[key] = not current
                else:
                    toggles[key] = _parse_bool(mode, key)
                result_summary = {key: toggles[key]}
            else:
                merged_toggles = {
                    k: bool(toggles.get(k, default))
                    for k, default in FEATURE_TOGGLE_DEFAULTS.items()
                }
                result_summary = {"toggles": merged_toggles}
        elif operation in ("workflow-policy", "workflow-check"):
            workflow_cfg = object_field(data, "workflow")
            if operation == "workflow-policy":
                key = str(values[0]).strip() if values else ""
                if key not in WORKFLOW_POLICY_VALIDATORS or "." not in key:
                    raise ValueError(f"unsupported workflow policy key: {key}")
                raw_val = values[1] if len(values) > 1 else ""
                section, field = key.split(".", 1)
                section_obj = object_field(workflow_cfg, section)
                section_obj[field] = WORKFLOW_POLICY_VALIDATORS[key](raw_val)
                result_summary = {key: section_obj[field]}
            else:
                merged_workflow = {}
                for section, defaults in WORKFLOW_POLICY_DEFAULTS.items():
                    sec_data = workflow_cfg.get(section)
                    if not isinstance(sec_data, dict):
                        sec_data = {}
                    merged_workflow[section] = {
                        field: sec_data.get(field, default)
                        for field, default in defaults.items()
                    }
                result_summary = {"workflow": merged_workflow}
        else:
            raise ValueError(f"unknown operation: {operation}")

        if operation.endswith("-check"):
            return result_summary

        fd, temporary = tempfile.mkstemp(prefix=".barista-state-", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as target:
                if path.exists():
                    os.fchmod(target.fileno(), stat.S_IMODE(path.stat().st_mode))
                json.dump(data, target, ensure_ascii=False)
                target.write("\n")
                target.flush()
                os.fsync(target.fileno())
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        return result_summary


if __name__ == "__main__":
    try:
        summary = update(sys.argv[1], sys.argv[2], sys.argv[3:])
        if summary is not None:
            print(json.dumps(summary))
    except (OSError, ValueError, IndexError) as error:
        print(f"Cannot update saved Yabai state: {error}", file=sys.stderr)
        sys.exit(1)
