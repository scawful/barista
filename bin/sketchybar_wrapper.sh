#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
CONFIG_FILE="${SKETCHYBAR_CONFIG:-$CONFIG_DIR/sketchybarrc}"
FORK_BIN="${BARISTA_SKETCHYBAR_FORK_BIN:-$HOME/.local/libexec/sketchybar-barista/sketchybar}"
if [[ -z "${SKETCHYBAR_BIN:-}" && -x "$FORK_BIN" ]]; then
  SKETCHYBAR_BIN="$FORK_BIN"
fi
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-/opt/homebrew/opt/sketchybar/bin/sketchybar}"
LOG_FILE="${SKETCHYBAR_ERR_LOG:-/opt/homebrew/var/log/sketchybar/sketchybar.err.log}"

if [[ ! -x "$SKETCHYBAR_BIN" ]]; then
  SKETCHYBAR_BIN="$(command -v sketchybar || true)"
fi

if [[ -z "$SKETCHYBAR_BIN" ]]; then
  echo "sketchybar not found" >&2
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "sketchybarrc not found: $CONFIG_FILE" >&2
  exit 1
fi

export BARISTA_CONFIG_DIR="$CONFIG_DIR"

ARGS=("$@")
if [[ ${#ARGS[@]} -eq 0 ]]; then
  ARGS=(--config "$CONFIG_FILE")
fi

exec "$SKETCHYBAR_BIN" "${ARGS[@]}"
