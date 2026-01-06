#!/usr/bin/env bash
set -euo pipefail

DEST="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
META_FILE="$DEST/.barista_deploy.json"
LOG_FILE="$DEST/.deployments.log"

if [ ! -f "$META_FILE" ]; then
  echo "No deploy metadata found at $META_FILE" >&2
  exit 1
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "$META_FILE" "$LOG_FILE" <<'PY'
import json
import sys

meta_file = sys.argv[1]
log_file = sys.argv[2]

with open(meta_file, "r", encoding="utf-8") as fh:
    meta = json.load(fh)

print("Barista deploy info")
print("Config:", meta.get("source", "unknown"))
print("Timestamp:", meta.get("timestamp", "unknown"))

info = meta.get("git", {})
commit = info.get("commit", "unknown")
branch = info.get("branch", "unknown")
describe = info.get("describe", "unknown")
dirty = info.get("dirty", False)
print("Git:", f"{branch} {commit} ({describe}) dirty={dirty}")

if not log_file:
    sys.exit(0)

try:
    with open(log_file, "r", encoding="utf-8") as fh:
        lines = [line.strip() for line in fh if line.strip()]
except FileNotFoundError:
    lines = []

if lines:
    print("\nRecent deploys:")
    for line in lines[-5:]:
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        timestamp = entry.get("timestamp", "unknown")
        note = entry.get("note", "")
        git = entry.get("git", {})
        label = f"{git.get('branch', 'unknown')} {git.get('commit', 'unknown')}"
        if note:
            print(f"- {timestamp} {label} :: {note}")
        else:
            print(f"- {timestamp} {label}")
PY
else
  echo "python3 not available; raw deploy metadata:" >&2
  cat "$META_FILE"
fi
