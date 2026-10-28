#!/usr/bin/env python3
"""Restore explicit Barista Yabai preferences after the base yabairc rules."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from yabai_state import WINDOW_LEVELS, object_field


def preferences(path):
    try:
        with Path(path).open(encoding="utf-8") as source:
            state = json.load(source)
    except FileNotFoundError:
        state = {}
    if not isinstance(state, dict):
        raise ValueError("saved state must be a JSON object")
    modes = object_field(state, "space_modes")
    modes_by_uuid = object_field(state, "space_modes_by_uuid")
    bindings = object_field(state, "space_mode_uuids")
    apps = object_field(object_field(state, "window_defaults"), "apps")
    for index, mode in modes.items():
        if not index.isdecimal() or int(index) < 1 or mode not in ("bsp", "stack", "float"):
            raise ValueError(f"invalid saved space layout: {index}")
    for uuid, mode in modes_by_uuid.items():
        if not uuid or mode not in ("bsp", "stack", "float"):
            raise ValueError(f"invalid saved space UUID layout: {uuid}")
    for index, uuid in bindings.items():
        if not index.isdecimal() or int(index) < 1 or not isinstance(uuid, str) or uuid not in modes_by_uuid:
            raise ValueError(f"invalid saved space UUID binding: {index}")
    levels = object_field(state, "window_levels")
    rules = []
    labels = set()

    def rule_identity(app, record, prefix):
        slug = re.sub(r"[^a-z0-9]+", "-", app.lower()).strip("-") or "app"
        label = record.get("rule_label") or prefix + slug
        app_regex = record.get("app_regex") or "^" + re.escape(app) + "$"
        if not isinstance(label, str) or not label.startswith(prefix) or label in labels:
            raise ValueError(f"invalid or duplicate app rule label: {label}")
        if not isinstance(app_regex, str):
            raise ValueError(f"invalid saved app rule: {app}")
        labels.add(label)
        return label, app_regex

    for app, record in apps.items():
        if not app or not isinstance(record, dict) or record.get("mode") not in ("float", "tile"):
            raise ValueError(f"invalid saved app default: {app}")
        label, app_regex = rule_identity(app, record, "barista-default-")
        # Float or tile only; stacking belongs to the app's level.
        rules.append({"name": app, "label": label, "app": app_regex,
                      "manage": record["mode"] == "tile", "sub-layer": ""})
    for app, record in levels.items():
        if not app or not isinstance(record, dict) or record.get("level") not in WINDOW_LEVELS:
            raise ValueError(f"invalid saved app level: {app}")
        label, app_regex = rule_identity(app, record, "barista-level-")
        rules.append({"name": app, "label": label, "app": app_regex,
                      "manage": None, "sub-layer": WINDOW_LEVELS[record["level"]]})
    return modes, modes_by_uuid, bindings, rules


def rule_command(rule):
    command = ["rule", "--add", "label=" + rule["label"], "app=" + rule["app"]]
    if rule["manage"] is not None:
        command.append("manage=" + ("on" if rule["manage"] else "off"))
    if rule["sub-layer"]:
        command.append("sub-layer=" + rule["sub-layer"])
    return command


def rule_matches(live, rule):
    """A live rule as yabai lists it: an unset sub-layer reads as "", and a
    level rule leaves manage unset."""
    if live.get("label") != rule["label"] or live.get("app") != rule["app"]:
        return False
    if (live.get("sub-layer") or "") != rule["sub-layer"]:
        return False
    return rule["manage"] is None or live.get("manage") == rule["manage"]


def pattern_matches(pattern, text):
    try:
        return re.search(pattern, text or "") is not None
    except re.error:
        return False


def rule_sub_layer(window, rules):
    """The sub-layer the rules give a window: the last matching rule that
    sets one, as yabai combines them; "" when none does."""
    layer = ""
    for rule in rules:
        if not rule.get("sub-layer") or not pattern_matches(rule.get("app") or "", window.get("app")):
            continue
        if rule.get("title") and not pattern_matches(rule["title"], window.get("title")):
            continue
        if any(rule.get(key) and rule[key] != window.get(key) for key in ("role", "subrole")):
            continue
        layer = rule["sub-layer"]
    return layer


def restack_plan(windows, rules):
    """Open windows whose sub-layer differs from what the rules give them.
    Rules reach only new windows, so a restarted yabai leaves open ones on
    their old layer. A window raised to `above` by hand stays there."""
    if not isinstance(windows, list) or not isinstance(rules, list):
        raise ValueError("invalid live Yabai windows or rules")
    rules = [rule for rule in rules if isinstance(rule, dict)]
    plan = []
    for window in windows:
        if not isinstance(window, dict) or window.get("subrole") != "AXStandardWindow":
            continue
        layer = rule_sub_layer(window, rules)
        current = window.get("sub-layer")
        if layer and layer != current and (current != "above" or layer == "above"):
            plan.append((window.get("id"), layer))
    return plan


def restack(args):
    """Moves open windows to their rules' layer. Run it after the yabairc sets
    the global layout: tiling an unpinned space moves its windows to below."""
    def query(*command):
        result = subprocess.run([args.yabai_bin, "-m", *command], text=True,
                                capture_output=True, timeout=2, check=False)
        if result.returncode:
            raise ValueError(result.stderr.strip() or f"yabai command failed: {' '.join(command)}")
        return json.loads(result.stdout) if result.stdout.strip() else None

    if not args.yabai_bin:
        raise ValueError("yabai is required to restack open windows")
    plan = restack_plan(query("query", "--windows"), query("rule", "--list"))
    if args.dry_run:
        print(json.dumps({"restack": [{"window": window, "sub-layer": layer} for window, layer in plan]}, indent=2))
        return
    failed = []
    for window_id, layer in plan:
        try:
            query("window", str(window_id), "--sub-layer", layer)
        except (ValueError, subprocess.TimeoutExpired):
            failed.append(str(window_id))  # Closed since the query; the rest still move.
    print(f"Restacked {len(plan) - len(failed)} open window(s) to their rules' layer")
    if failed:
        print(f"Could not restack window(s): {', '.join(failed)}", file=sys.stderr)


def restore(args):
    # Validate all saved preferences before issuing any mutation. The file is
    # written atomically by the menu, and startup never rewrites preferences.
    modes, modes_by_uuid, bindings, rules = preferences(args.state_file)
    startup = getattr(args, "startup", False)
    if args.rules_only:
        modes = {}
        modes_by_uuid = {}
    if not modes and not modes_by_uuid and not rules:
        print("No saved Yabai preferences to restore")
        return
    if not args.yabai_bin:
        raise ValueError("yabai is required to restore saved preferences")

    def run(*command):
        result = subprocess.run([args.yabai_bin, "-m", *command], text=True,
                                capture_output=True, timeout=2, check=False)
        if result.returncode:
            raise ValueError(result.stderr.strip() or f"yabai command failed: {' '.join(command)}")
        return result.stdout

    def query(*command):
        return json.loads(run(*command))

    active_rules = query("rule", "--list") if rules else []
    if not isinstance(active_rules, list) or any(not isinstance(rule, dict) for rule in active_rules):
        raise ValueError("invalid live Yabai rule list")
    for rule in rules:
        if any(active.get("label") == rule["label"] and active.get("app") != rule["app"] for active in active_rules):
            raise ValueError(f"app rule label belongs to another app: {rule['label']}")

    spaces = query("query", "--spaces") if modes or modes_by_uuid else []
    if not isinstance(spaces, list) or any(not isinstance(space, dict) for space in spaces):
        raise ValueError("invalid live Yabai spaces")
    by_index = {str(space.get("index")): space for space in spaces}
    by_uuid = {space.get("uuid"): space for space in spaces if space.get("uuid")}
    actions = []
    skipped = []
    notes = []
    selected = []
    for uuid, mode in modes_by_uuid.items():
        space = by_uuid.get(uuid)
        if not space:
            skipped.append(f"Space UUID {uuid}: unavailable; old index was not used")
            continue
        selected.append((str(space.get("index")), mode, space))
    for index, mode in modes.items():
        if index in bindings:
            continue
        space = by_index.get(index)
        if space and space.get("uuid") in modes_by_uuid:
            skipped.append(f"Space {index}: legacy index choice superseded by UUID preference")
            continue
        notes.append(f"Space {index}: legacy preference follows its index until saved again")
        selected.append((index, mode, space))
    for index, mode, space in selected:
        if not space or space.get("is-native-fullscreen"):
            skipped.append(f"Space {index}: unavailable or native fullscreen")
            continue
        if startup or space.get("type") != mode:
            if not index.isdecimal() or int(index) < 1 or not isinstance(space.get("id"), int) or space["id"] < 1:
                raise ValueError(f"Space {index} has no valid live identity")
            # config --space marks VIEW_LAYOUT even if the current type already
            # matches. The subsequent global startup default skips this space.
            command = ["config", "--space", index, "layout", mode] if startup else ["space", index, "--layout", mode]
            actions.append({"kind": "space", "index": index, "id": space.get("id"),
                            "uuid": space.get("uuid"),
                            "layout": mode, "command": command})
    rule_actions = []
    for rule in rules:
        rule_actions.append({"kind": "rule", "rule": rule, "command": rule_command(rule)})
    actions = rule_actions + actions if startup else actions + rule_actions

    if args.dry_run:
        print(json.dumps({"rules_only": args.rules_only, "startup": startup, "actions": actions, "skipped": skipped, "notes": notes}, indent=2))
        return

    applied = 0
    for action in actions:
        try:
            if action["kind"] == "space":
                current = query("query", "--spaces", "--space", action["index"])
                if not isinstance(current, dict) or current.get("id") != action["id"] or current.get("uuid") != action["uuid"] or str(current.get("index")) != action["index"]:
                    raise ValueError(f"Space {action['index']} changed identity")
            run(*action["command"])
            if action["kind"] == "space":
                current = query("query", "--spaces", "--space", action["index"])
                if not isinstance(current, dict) or current.get("id") != action["id"] or current.get("uuid") != action["uuid"] or current.get("type") != action["layout"]:
                    raise ValueError(f"Space {action['index']} layout could not be verified")
            else:
                rule = action["rule"]
                current_rules = query("rule", "--list")
                if not isinstance(current_rules, list) or not any(isinstance(current, dict) and rule_matches(current, rule)
                                                                  for current in current_rules):
                    raise ValueError(f"App rule {rule['label']} for {rule['name']} could not be verified")
            applied += 1
        except (ValueError, subprocess.TimeoutExpired) as error:
            raise ValueError(f"restore stopped after {applied} verified change(s): {error}") from error
    print(f"Restored {applied} saved Yabai preference(s)")
    for message in notes + skipped:
        print(message, file=sys.stderr)


def main():
    config_dir = os.environ.get("BARISTA_CONFIG_DIR", str(Path.home() / ".config/sketchybar"))
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-file", default=os.environ.get("BARISTA_STATE_FILE", config_dir + "/state.json"))
    parser.add_argument("--yabai-bin", default=os.environ.get("BARISTA_YABAI_BIN") or os.environ.get("YABAI_BIN") or shutil.which("yabai"))
    parser.add_argument("--rules-only", action="store_true", help="restore app rules without changing space layouts")
    parser.add_argument("--startup", action="store_true", help="install app rules first and pin saved layouts before the global default")
    parser.add_argument("--restack", action="store_true", help="only move open windows to their rules' sub-layer")
    parser.add_argument("--dry-run", action="store_true", help="query and print changes without applying them")
    args = parser.parse_args()
    try:
        if args.restack:
            restack(args)
        else:
            restore(args)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Cannot restore saved Yabai preferences: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
