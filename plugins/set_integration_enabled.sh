#!/bin/bash
set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
INTEGRATION="${1:-}"
STATE_VALUE="${2:-on}"

if [ -z "$INTEGRATION" ]; then
  echo "Usage: set_integration_enabled.sh <integration> <on|off>" >&2
  exit 1
fi

ENABLED=true
case "$STATE_VALUE" in
  on|enable|enabled|true)
    ENABLED=true
    ;;
  off|disable|disabled|false)
    ENABLED=false
    ;;
  *)
    echo "Unknown state '$STATE_VALUE'" >&2
    exit 1
    ;;
esac

python3 - "$STATE_FILE" "$INTEGRATION" "$ENABLED" <<'PY'
import json, os, sys
state_path, integration, enabled = sys.argv[1:4]
if enabled.lower() in {"false", "0"}:
    enabled = False
else:
    enabled = True
try:
    with open(state_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
integrations = data.get("integrations")
if not isinstance(integrations, dict):
    integrations = {}
entry = integrations.get(integration)
if not isinstance(entry, dict):
    entry = {}
integrations[integration] = entry
entry["enabled"] = enabled
data["integrations"] = integrations
os.makedirs(os.path.dirname(state_path), exist_ok=True)
with open(state_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False)
PY

sketchybar --trigger yabai_status_refresh >/dev/null 2>&1 || true
sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
