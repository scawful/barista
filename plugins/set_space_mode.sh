#!/bin/bash
set -euo pipefail

CONFIG_DIR="${BARISTA_CONFIG_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar}}"
STATE_FILE="${BARISTA_STATE_FILE:-$CONFIG_DIR/state.json}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_WRITER="$ROOT_DIR/scripts/yabai_state.py"
MODE="${2:-float}"
TARGET="${1:-current}"

YABAI_BIN="${BARISTA_YABAI_BIN:-${YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}}"
JQ_BIN="${BARISTA_JQ_BIN:-${JQ_BIN:-$(command -v jq 2>/dev/null || true)}}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"

normalize_mode() {
  case "$1" in
    float|floating)
      printf 'float'
      ;;
    stack|stacked)
      printf 'stack'
      ;;
    bsp|tile|tiling)
      printf 'bsp'
      ;;
    *)
      echo "Invalid space layout: $1 (expected float, bsp, or stack)" >&2
      return 1
      ;;
  esac
}

MODE=$(normalize_mode "$MODE")

if [[ "$TARGET" != "current" && ! "$TARGET" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid space index: $TARGET" >&2
  exit 1
fi
[ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || { echo "yabai and jq are required to change a space layout" >&2; exit 1; }
python3 "$STATE_WRITER" "$STATE_FILE" space-check

if [ "$TARGET" = "current" ]; then
  SPACE_JSON="$("$YABAI_BIN" -m query --spaces --space)"
else
  SPACE_JSON="$("$YABAI_BIN" -m query --spaces --space "$TARGET")"
fi
RESOLVED_TARGET="$(printf '%s\n' "$SPACE_JSON" | "$JQ_BIN" -er '.index | select(type == "number" and . > 0 and floor == .)')"
if [ "$TARGET" != "current" ] && [ "$RESOLVED_TARGET" != "$TARGET" ]; then
  echo "Space $TARGET is no longer available" >&2
  exit 1
fi
TARGET="$RESOLVED_TARGET"
SPACE_ID="$(printf '%s\n' "$SPACE_JSON" | "$JQ_BIN" -r '.uuid // .id // .index')"
SPACE_UUID="$(printf '%s\n' "$SPACE_JSON" | "$JQ_BIN" -r '.uuid // empty')"
if [ -n "${BARISTA_TARGET_SPACE_ID:-}" ] && \
  [ "$(printf '%s\n' "$SPACE_JSON" | "$JQ_BIN" -r '.id')" != "$BARISTA_TARGET_SPACE_ID" ]; then
  echo "The selected space changed; reopen the space menu" >&2
  exit 1
fi
printf '%s\n' "$SPACE_JSON" | "$JQ_BIN" -e '."is-native-fullscreen" != true' >/dev/null || {
  echo "Space $TARGET is a native fullscreen space" >&2
  exit 1
}
if [ "${BARISTA_SPACE_FORCE:-0}" != "1" ] && [ -f "$STATE_FILE" ]; then
  if "$JQ_BIN" -e --arg idx "$TARGET" --arg uuid "$SPACE_UUID" '
    (.spaces.locked_spaces // {}) as $locked
    | if ($locked | type) == "array" then
        ($locked | map(tostring) | index($idx) != null)
        or (($uuid != "") and ($locked | map(tostring) | index($uuid) != null))
      elif ($locked | type) == "object" then
        (($locked[$idx] // false) == true)
        or (($uuid != "") and (($locked[$uuid] // false) == true))
      else false end
  ' "$STATE_FILE" >/dev/null 2>&1; then
    echo "Space $TARGET is locked (spaces.locked_spaces)" >&2
    exit 1
  fi
fi

"$YABAI_BIN" -m space "$TARGET" --layout "$MODE"
APPLIED_JSON="$("$YABAI_BIN" -m query --spaces --space "$TARGET")"
if ! printf '%s\n' "$APPLIED_JSON" | "$JQ_BIN" -e --arg mode "$MODE" --arg identity "$SPACE_ID" \
  '.type == $mode and ((.uuid // .id // .index) | tostring) == $identity' >/dev/null; then
  echo "Space $TARGET layout could not be verified; saved state was not changed" >&2
  exit 1
fi
if ! python3 "$STATE_WRITER" "$STATE_FILE" space-mode "$TARGET" "$MODE" "$SPACE_UUID"; then
  echo "Space $TARGET is now $MODE, but the choice could not be saved" >&2
  exit 1
fi
if [ -n "$SKETCHYBAR_BIN" ]; then
  "$SKETCHYBAR_BIN" --trigger space_mode_refresh >/dev/null 2>&1 || true
fi
printf 'Space %s layout: %s\n' "$TARGET" "$MODE"
