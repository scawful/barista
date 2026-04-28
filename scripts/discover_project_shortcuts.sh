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
default = "data/interface_extensions.local.json"
try:
    data = json.loads(state_path.read_text(encoding="utf-8"))
except Exception:
    data = {}

menus = data.get("menus") if isinstance(data, dict) else {}
source = menus.get("extensions") if isinstance(menus, dict) else None
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

def terminal_action(command: str) -> str:
    if not command:
        return ""
    escaped = command.replace('\\', '\\\\').replace('"', '\\"')
    return f"osascript -e 'tell app \"Terminal\" to do script \"{escaped}\"'"

def add_entry(item_id: str, label: str, icon: str, icon_color: str, label_color: str, workflow: str, **extra):
    if not workflow:
        return
    item = {
        "id": item_id,
        "pack": "personal",
        "label": label,
        "icon": icon,
        "icon_color": icon_color,
        "label_color": label_color,
        "script": "scripts/open_local_workflow.sh",
        "args": [workflow],
        "surfaces": ["apple_menu", "front_app", "control_center"],
        "section": "extensions",
        "order": len(items) * 10 + 10,
    }
    for key, value in extra.items():
        if value not in (None, ""):
            item[key] = value
    items.append(item)

scawfulbot_build_open = None
scawfulbot_repo = resolve_path([
    code_dir / "lab/scawfulbot/apps/apple",
    Path.home() / "src/lab/scawfulbot/apps/apple",
])
scawfulbot_app = resolve_path([
    scawfulbot_repo / "build-macos/Build/Products/Debug/Scawfulbot.app" if scawfulbot_repo else None,
    Path.home() / "Applications/Scawfulbot.app",
    Path("/Applications/Scawfulbot.app"),
])
if scawfulbot_repo:
    script = scawfulbot_repo / "scripts" / "build_and_open_mac.sh"
    if script.exists():
        scawfulbot_build_open = str(script)

premia_command = resolve_command([
    code_dir / "lab/premia/build-arch-next/bin/premia",
    code_dir / "lab/premia/build/bin/premia",
    code_dir / "lab/premia/build/Release/premia",
    "premia",
])
loom_repo = resolve_path([
    code_dir / "lab/loom-studio",
    Path.home() / "src/lab/loom-studio",
])
loom_command = resolve_command([
    code_dir / "lab/loom-studio/build/bin/loom-studio",
    Path.home() / "src/lab/loom-studio/build/bin/loom-studio",
    "loom-studio",
])

scawfulbot_build_action = ""
if scawfulbot_repo:
    scawfulbot_build_action = terminal_action(
        f"cd {shlex.quote(str(scawfulbot_repo))} && "
        "xcodegen generate >/dev/null && "
        "xcodebuild -project Scawfulbot.xcodeproj -scheme ScawfulbotMac -configuration Debug "
        "-destination platform=macOS "
        f"-derivedDataPath {shlex.quote(str(scawfulbot_repo / 'build-macos'))} "
        "CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= build && "
        f"open {shlex.quote(str(scawfulbot_repo / 'build-macos/Build/Products/Debug/Scawfulbot.app'))}"
    )
add_entry(
    "scawfulbot",
    "Scawfulbot",
    "󰭹",
    "0xffcba6f7",
    "0xffdfc9f7",
    "scawfulbot",
    available=bool(scawfulbot_app),
    build_action=scawfulbot_build_action or (f"/bin/bash {shlex.quote(scawfulbot_build_open)}" if scawfulbot_build_open else ""),
    build_label="Build scawfulbot",
    missing_message="scawfulbot.app is missing. Rebuild the macOS app (unsigned local build)?",
    missing_title="Barista · scawfulbot",
    missing_action=(open_action(scawfulbot_repo) if scawfulbot_repo else ""),
)

loom_build_action = ""
if loom_repo:
    loom_build_action = terminal_action(
        f"cd {shlex.quote(str(loom_repo))} && "
        "cmake -S . -B build && "
        "cmake --build build --target loom-studio -j$(sysctl -n hw.ncpu)"
    )
add_entry(
    "loom_studio",
    "Loom",
    "󰈙",
    "0xff89b4fa",
    "0xffbac2de",
    "loom",
    available=bool(loom_command),
    build_action=loom_build_action,
    build_label="Build Loom Studio",
    missing_message="loom-studio is missing. Rebuild the target?",
    missing_title="Barista · loom-studio",
    missing_action=(open_action(loom_repo) if loom_repo else ""),
)

premia_build_dir = resolve_path([
    code_dir / "lab/premia/build-arch-next",
    code_dir / "lab/premia/build",
    Path.home() / "src/lab/premia/build-arch-next",
])
premia_repo = resolve_path([
    code_dir / "lab/premia",
    Path.home() / "src/lab/premia",
])
premia_build_action = ""
if premia_repo:
    build_name = premia_build_dir.name if premia_build_dir else "build-arch-next"
    premia_build_action = (
        "osascript -e 'tell app \"Terminal\" to do script \"cd %s && cmake -S . -B %s && cmake --build %s --target premia -j$(sysctl -n hw.ncpu)\"'"
        % (str(premia_repo).replace('"', '\\"'), build_name, build_name)
    )
add_entry(
    "premia_v2",
    "premia v2",
    "󰃬",
    "0xff94e2d5",
    "0xffc7eee8",
    "premia",
    available=bool(premia_command),
    build_action=premia_build_action,
    build_label="Build premia desktop",
    missing_message="premia desktop is missing. Rebuild the desktop target?",
    missing_title="Barista · premia",
    missing_action=(open_action(premia_repo) if premia_repo else ""),
)

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(json.dumps(items, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(output_path)
PY
