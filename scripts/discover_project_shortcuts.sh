#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="${CONFIG_DIR}/state.json"
CODE_DIR="${BARISTA_CODE_DIR:-${HOME}/src}"
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-dir)
      CONFIG_DIR="${2:-}"
      shift 2
      ;;
    --code-dir)
      CODE_DIR="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    --state)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="$(python3 - "$STATE_FILE" <<'PY'
import json
import sys
from pathlib import Path

state_path = Path(sys.argv[1])
default = "data/project_shortcuts.json"
try:
    data = json.loads(state_path.read_text(encoding="utf-8"))
except Exception:
    data = {}

menus = data.get("menus") if isinstance(data, dict) else {}
apps = menus.get("apps") if isinstance(menus, dict) else None
projects = menus.get("projects") if isinstance(menus, dict) else None
source = apps if isinstance(apps, dict) else projects if isinstance(projects, dict) else None
value = source.get("file") if isinstance(source, dict) else None
print(value or default)
PY
)"
fi

python3 - "$CONFIG_DIR" "$CODE_DIR" "$OUTPUT_FILE" <<'PY'
import json
import shlex
import shutil
import sys
from pathlib import Path

config_dir = Path(sys.argv[1]).expanduser()
code_dir = Path(sys.argv[2]).expanduser()
output_value = sys.argv[3]

if output_value.startswith("~"):
    output_path = Path(output_value).expanduser()
elif output_value.startswith("/"):
    output_path = Path(output_value)
else:
    output_path = config_dir / output_value

items = []

def resolve_path(candidates):
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate).expanduser()
        if path.exists():
            return path
    return None

def resolve_command(candidates):
    for candidate in candidates:
        if not candidate:
            continue
        path = Path(candidate).expanduser()
        if path.exists():
            return str(path)
        resolved = shutil.which(candidate)
        if resolved:
            return resolved
    return None

def open_action(path: Path) -> str:
    return f"open {shlex.quote(str(path))}"

def command_action(command: str, *args: str) -> str:
    parts = [shlex.quote(command)]
    for arg in args:
        parts.append(shlex.quote(arg))
    return " ".join(parts)

def add_entry(item_id: str, label: str, icon: str, icon_color: str, label_color: str, action: str):
    if not action:
        return
    items.append({
        "id": item_id,
        "label": label,
        "icon": icon,
        "icon_color": icon_color,
        "label_color": label_color,
        "action": action,
        "order": len(items) * 10 + 10,
    })

cortex_cli = resolve_command([
    code_dir / "lab/cortex/bin/cortex-cli",
    Path.home() / "src/lab/cortex/bin/cortex-cli",
    "cortex-cli",
])

premia_command = resolve_command([
    code_dir / "lab/premia/build/bin/premia",
    code_dir / "lab/premia/build/Release/premia",
    "premia",
])

oracle_action = command_action(cortex_cli, "oracle") if cortex_cli else ""

add_entry("oracle", "Oracle", "󰊕", "0xffcba6f7", "0xffdfc9f7",
          oracle_action)
add_entry("premia_v2", "Premia v2", "󰃬", "0xff94e2d5", "0xffc7eee8",
          command_action(premia_command) if premia_command else "")

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(items, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(output_path)
PY
