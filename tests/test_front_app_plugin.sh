#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/front_app.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
POISON_BIN_DIR="$TMP_DIR/poison-bin"
SCRIPTS_DIR="$TMP_DIR/scripts"
LOG_FILE="$TMP_DIR/sketchybar.log"
ARGV_LOG="$TMP_DIR/sketchybar-argv.log"
RUNTIME_LOG="$TMP_DIR/runtime-context.log"
HELPER_LOG="$TMP_DIR/runtime-context-helper.log"
CONTEXT_LOG="$TMP_DIR/front-app-context.log"
CONTEXT_MODE_FILE="$TMP_DIR/context-mode"
POISON_LOG="$TMP_DIR/poison-sketchybar.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR" "$POISON_BIN_DIR" "$SCRIPTS_DIR"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$LOG_FILE"
{
  printf 'CALL\n'
  for argument in "\$@"; do
    printf 'ARG\t%s\n' "\$argument"
  done
  printf 'END\n'
} >> "$ARGV_LOG"
case "\${BARISTA_TEST_SKETCHYBAR_FAILURE:-none}" in
  all) exit 1 ;;
  animate) [ "\${1:-}" = "--animate" ] && exit 1 ;;
esac
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$BIN_DIR/yabai"

cat > "$POISON_BIN_DIR/sketchybar" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$POISON_LOG"
exit 91
EOF
chmod +x "$POISON_BIN_DIR/sketchybar"
: > "$POISON_LOG"

cat > "$SCRIPTS_DIR/app_icon.sh" <<'EOF'
#!/bin/bash
printf '󰊠\n'
EOF
chmod +x "$SCRIPTS_DIR/app_icon.sh"

cat > "$SCRIPTS_DIR/front_app_context.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ -n "${BARISTA_TEST_CONTEXT_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$BARISTA_TEST_CONTEXT_LOG"
fi
mode="${FRONT_APP_PLUGIN_CONTEXT_MODE:-floating_above}"
if [ -s "${BARISTA_TEST_CONTEXT_MODE_FILE:-}" ]; then
  mode="$(cat "$BARISTA_TEST_CONTEXT_MODE_FILE")"
fi
case "$mode" in
  floating_above)
    printf 'app_name\tGhostty\n'
    printf 'window_available\ttrue\n'
    printf 'state_icon\t󰒄\n'
    printf 'state_label\tFloating · Above\n'
    printf 'location_label\tSpace 1 · Display 1\n'
    ;;
  fullscreen)
    printf 'app_name\tGhostty\n'
    printf 'window_available\ttrue\n'
    printf 'state_icon\t󰊓\n'
    printf 'state_label\tFullscreen\n'
    printf 'location_label\tSpace 1 · Display 1\n'
    ;;
  none)
    printf 'app_name\tGhostty\n'
    printf 'window_available\tfalse\n'
    printf 'state_icon\t󰋽\n'
    printf 'state_label\tNo managed window\n'
    printf 'location_label\tSpace 1 · Display 1\n'
    ;;
  quoted)
    printf 'app_name\tO\x27Reilly "日本" 🌟\n'
    printf 'window_available\ttrue\n'
    printf 'state_icon\t󰒄\n'
    printf 'state_label\tFloating · Above · 日本\n'
    printf 'location_label\tSpace 2 · Display "Studio" 🌟\n'
    ;;
esac
EOF
chmod +x "$SCRIPTS_DIR/front_app_context.sh"

cat > "$SCRIPTS_DIR/runtime_context.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\tlua_only=%s\n' "$*" "${BARISTA_LUA_ONLY:-0}" >> "${BARISTA_TEST_RUNTIME_LOG:?}"
if [ "$*" = "fresh-front-app" ]; then
  case "${BARISTA_TEST_FRESH_MODE:-success}" in
    empty) exit 0 ;;
    fail) exit 1 ;;
  esac
  printf 'app_name\tGhostty\n'
  printf 'window_available\ttrue\n'
  printf 'state_icon\t󰊓\n'
  printf 'state_label\tFullscreen\n'
  printf 'location_label\tSpace 1 · Display 1\n'
fi
EOF
chmod +x "$SCRIPTS_DIR/runtime_context.sh"

cat > "$SCRIPTS_DIR/runtime_context_helper" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\tyabai=%s\n' "$*" "${BARISTA_YABAI_BIN:-}" >> "${BARISTA_TEST_HELPER_LOG:?}"
if [ "$*" = "fresh-front-app" ]; then
  case "${BARISTA_TEST_HELPER_MODE:-success}" in
    empty) exit 0 ;;
    fail) exit 1 ;;
  esac
  printf 'app_name\tGhostty\n'
  printf 'window_available\ttrue\n'
  printf 'state_icon\t󰊓\n'
  printf 'state_label\tFullscreen\n'
  printf 'location_label\tSpace 1 · Display 1\n'
fi
EOF
chmod +x "$SCRIPTS_DIR/runtime_context_helper"

run_front_app() {
  : > "$LOG_FILE"
  : > "$ARGV_LOG"
  PATH="$POISON_BIN_DIR:$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_CONFIG_DIR="$TMP_DIR/config" \
    BARISTA_SCRIPTS_DIR="$SCRIPTS_DIR" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_FRONT_APP_CONTEXT_SCRIPT="$SCRIPTS_DIR/front_app_context.sh" \
    BARISTA_RUNTIME_CONTEXT_SCRIPT="$SCRIPTS_DIR/runtime_context.sh" \
    BARISTA_APP_ICON_SCRIPT="$SCRIPTS_DIR/app_icon.sh" \
    BARISTA_TEST_RUNTIME_LOG="$RUNTIME_LOG" \
    BARISTA_TEST_CONTEXT_LOG="$CONTEXT_LOG" \
    BARISTA_TEST_CONTEXT_MODE_FILE="$CONTEXT_MODE_FILE" \
    BARISTA_TEST_SKETCHYBAR_FAILURE="${2:-none}" \
    BARISTA_FRONT_APP_ACTION_ROWS="${3:-1}" \
    NAME=front_app \
    SENDER=routine \
    INFO="" \
    FRONT_APP_PLUGIN_CONTEXT_MODE="$1" \
    "$SCRIPT"
}

run_front_app_popup_refresh() {
  : > "$LOG_FILE"
  : > "$ARGV_LOG"
  : > "$RUNTIME_LOG"
  : > "$HELPER_LOG"
  : > "$CONTEXT_LOG"
  printf 'floating_above\n' > "$CONTEXT_MODE_FILE"
  PATH="$POISON_BIN_DIR:$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_CONFIG_DIR="$TMP_DIR/config" \
    BARISTA_SCRIPTS_DIR="$SCRIPTS_DIR" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_FRONT_APP_CONTEXT_SCRIPT="$SCRIPTS_DIR/front_app_context.sh" \
    BARISTA_RUNTIME_CONTEXT_SCRIPT="$SCRIPTS_DIR/runtime_context.sh" \
    BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$SCRIPTS_DIR/runtime_context_helper" \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_APP_ICON_SCRIPT="$SCRIPTS_DIR/app_icon.sh" \
    BARISTA_TEST_RUNTIME_LOG="$RUNTIME_LOG" \
    BARISTA_TEST_HELPER_LOG="$HELPER_LOG" \
    BARISTA_TEST_CONTEXT_LOG="$CONTEXT_LOG" \
    BARISTA_TEST_CONTEXT_MODE_FILE="$CONTEXT_MODE_FILE" \
    BARISTA_TEST_FRESH_MODE="${1:-success}" \
    BARISTA_TEST_HELPER_MODE="${2:-success}" \
    BARISTA_LUA_ONLY="${3:-0}" \
    NAME=front_app \
    SENDER=popup_refresh \
    INFO="Ghostty" \
    "$SCRIPT"
}

run_front_app_event() {
  : > "$LOG_FILE"
  : > "$ARGV_LOG"
  PATH="$POISON_BIN_DIR:$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_CONFIG_DIR="$TMP_DIR/config" \
    BARISTA_SCRIPTS_DIR="$SCRIPTS_DIR" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_FRONT_APP_ACTION_ROWS="${2:-1}" \
    NAME=front_app \
    SENDER="$1" \
    INFO="" \
    "$SCRIPT"
}

assert_log_contains() {
  local expected="$1"
  grep -Fq -- "$expected" "$LOG_FILE" || {
    echo "FAIL: expected log line containing '$expected'" >&2
    cat "$LOG_FILE" >&2
    exit 1
  }
}

assert_call_count() {
  local expected="$1"
  local actual
  actual="$(grep -c '^CALL$' "$ARGV_LOG" || true)"
  [ "$actual" = "$expected" ] || {
    echo "FAIL: expected $expected SketchyBar calls, got $actual" >&2
    cat "$ARGV_LOG" >&2
    exit 1
  }
}

assert_set_count() {
  local expected="$1"
  local actual
  actual="$(grep -Fxc $'ARG\t--set' "$ARGV_LOG" || true)"
  [ "$actual" = "$expected" ] || {
    echo "FAIL: expected $expected batched --set arguments, got $actual" >&2
    cat "$ARGV_LOG" >&2
    exit 1
  }
}

assert_argv_contains() {
  local expected="$1"
  grep -Fxq -- "ARG"$'\t'"$expected" "$ARGV_LOG" || {
    echo "FAIL: expected one argument '$expected'" >&2
    cat "$ARGV_LOG" >&2
    exit 1
  }
}

assert_single_animated_batch() {
  local app_name="$1"
  local state_icon="$2"
  local state_label="$3"
  local location_label="$4"
  local float_label="$5"
  local fullscreen_label="$6"
  local topmost_label="$7"
  local tile_label="$8"
  local action_rows="${9:-1}"
  python3 - "$ARGV_LOG" "$app_name" "$state_icon" "$state_label" \
    "$location_label" "$float_label" "$fullscreen_label" "$topmost_label" \
    "$tile_label" "$action_rows" <<'PY'
from pathlib import Path
import sys

(
    log_path,
    app_name,
    state_icon,
    state_label,
    location_label,
    float_label,
    fullscreen_label,
    topmost_label,
    tile_label,
    action_rows,
) = sys.argv[1:]
rows = Path(log_path).read_text(encoding="utf-8").splitlines()
calls = []
current = None
for row in rows:
    if row == "CALL":
        assert current is None, rows
        current = []
    elif row == "END":
        assert current is not None, rows
        calls.append(current)
        current = None
    else:
        prefix, value = row.split("\t", 1)
        assert prefix == "ARG" and current is not None, rows
        current.append(value)
assert current is None and len(calls) == 1, calls
assert calls[0][:3] == ["--animate", "sin", "12"], calls[0]
expected_payload = [
    "--set", "front_app",
    "icon=󰊠",
    "icon.drawing=on",
    "icon.color=0xFFcad3f5",
    "icon.padding_left=8",
    "icon.padding_right=8",
    "label=",
    "label.drawing=off",
    "background.drawing=on",
    "background.color=0x18313a46",
    "background.border_width=0",
    "background.border_color=0x00000000",
    "--set", "front_app.header", f"label=App · {app_name}",
    "--set", "front_app.state", f"icon={state_icon}", f"label={state_label}",
    "--set", "front_app.location", f"label={location_label}",
]
if action_rows == "1":
    expected_payload.extend([
        "--set", "front_app.window.float", f"label={float_label}",
        "--set", "front_app.window.fullscreen", f"label={fullscreen_label}",
        "--set", "front_app.window.topmost", f"label={topmost_label}",
        "--set", "front_app.preset.tile_here", f"label={tile_label}",
    ])
assert calls[0][3:] == expected_payload, (calls[0][3:], expected_payload)
PY
}

assert_animation_fallback_payload() {
  python3 - "$ARGV_LOG" <<'PY'
from pathlib import Path
import sys

rows = Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
calls = []
current = None
for row in rows:
    if row == "CALL":
        current = []
    elif row == "END":
        calls.append(current)
        current = None
    else:
        current.append(row.split("\t", 1)[1])
assert len(calls) == 2, calls
assert calls[0][:3] == ["--animate", "sin", "12"], calls[0]
assert calls[0][3:] == calls[1], calls
PY
}

run_front_app_event mouse.clicked 1
assert_call_count 1
assert_set_count 2
assert_log_contains "--set front_app.more popup.drawing=off --set front_app popup.drawing=toggle"

run_front_app_event mouse.clicked 0
assert_call_count 1
assert_set_count 1
assert_log_contains "--set front_app popup.drawing=toggle"

run_front_app floating_above
assert_call_count 1
assert_set_count 8
assert_single_animated_batch Ghostty "󰒄" "Floating · Above" "Space 1 · Display 1" \
  "Tile Window" "Enter Fullscreen" "Normal Layer" "Tile Here"
assert_log_contains "--set front_app.window.float label=Tile Window"
assert_log_contains "--set front_app.window.fullscreen label=Enter Fullscreen"
assert_log_contains "--set front_app.window.topmost label=Normal Layer"
assert_log_contains "--set front_app.preset.tile_here label=Tile Here"

run_front_app fullscreen
assert_call_count 1
assert_set_count 8
assert_single_animated_batch Ghostty "󰊓" Fullscreen "Space 1 · Display 1" \
  "Float Window" "Exit Fullscreen" "Make Topmost" "Tile Here"
assert_log_contains "--set front_app.window.float label=Float Window"
assert_log_contains "--set front_app.window.fullscreen label=Exit Fullscreen"
assert_log_contains "--set front_app.window.topmost label=Make Topmost"

run_front_app none
assert_call_count 1
assert_set_count 8
assert_single_animated_batch Ghostty "󰋽" "No managed window" "Space 1 · Display 1" \
  "No Window to Float" "No Window to Fullscreen" "No Window to Layer" "No Window to Tile"
assert_log_contains "--set front_app.window.float label=No Window to Float"
assert_log_contains "--set front_app.preset.tile_here label=No Window to Tile"

run_front_app quoted
assert_call_count 1
assert_set_count 8
assert_single_animated_batch $'O\x27Reilly "日本" 🌟' "󰒄" "Floating · Above · 日本" \
  'Space 2 · Display "Studio" 🌟' "Tile Window" "Enter Fullscreen" "Normal Layer" "Tile Here"
assert_argv_contains $'label=App · O\x27Reilly "日本" 🌟'
assert_argv_contains "label=Floating · Above · 日本"
assert_argv_contains 'label=Space 2 · Display "Studio" 🌟'

run_front_app floating_above animate
assert_call_count 2
assert_set_count 16
assert_argv_contains "--animate"
assert_animation_fallback_payload

run_front_app floating_above all
assert_call_count 2
assert_set_count 16

run_front_app floating_above none 0
assert_call_count 1
assert_set_count 4
assert_single_animated_batch Ghostty "󰒄" "Floating · Above" "Space 1 · Display 1" \
  "Tile Window" "Enter Fullscreen" "Normal Layer" "Tile Here" 0

run_front_app_popup_refresh
assert_call_count 1
assert_set_count 8
assert_single_animated_batch Ghostty "󰊓" Fullscreen "Space 1 · Display 1" \
  "Float Window" "Exit Fullscreen" "Make Topmost" "Tile Here"
grep -Fxq $'fresh-front-app\tyabai='"$BIN_DIR/yabai" "$HELPER_LOG" || {
  echo "FAIL: compiled popup refresh should call the native helper directly" >&2
  cat "$HELPER_LOG" >&2
  exit 1
}
[ ! -s "$RUNTIME_LOG" ] || {
  echo "FAIL: a successful native snapshot should bypass the shell wrapper" >&2
  cat "$RUNTIME_LOG" >&2
  exit 1
}
[ ! -s "$CONTEXT_LOG" ] || {
  echo "FAIL: a successful fresh snapshot should bypass front_app_context fallback" >&2
  cat "$CONTEXT_LOG" >&2
  exit 1
}
assert_log_contains "--set front_app.window.fullscreen label=Exit Fullscreen"

run_front_app_popup_refresh success empty
assert_call_count 1
assert_set_count 8
assert_single_animated_batch Ghostty "󰊓" Fullscreen "Space 1 · Display 1" \
  "Float Window" "Exit Fullscreen" "Make Topmost" "Tile Here"
grep -Fxq $'fresh-front-app\tyabai='"$BIN_DIR/yabai" "$HELPER_LOG" || {
  echo "FAIL: popup refresh should attempt the native helper" >&2
  cat "$HELPER_LOG" >&2
  exit 1
}
grep -Fxq $'fresh-front-app\tlua_only=1' "$RUNTIME_LOG" || {
  echo "FAIL: an empty native snapshot should use the portable wrapper without retrying the helper" >&2
  cat "$RUNTIME_LOG" >&2
  exit 1
}
[ ! -s "$CONTEXT_LOG" ] || {
  echo "FAIL: a successful portable snapshot should bypass front_app_context fallback" >&2
  cat "$CONTEXT_LOG" >&2
  exit 1
}

run_front_app_popup_refresh success success 1
assert_call_count 1
assert_set_count 8
[ ! -s "$HELPER_LOG" ] || {
  echo "FAIL: Lua-only popup refresh should not call the native helper" >&2
  cat "$HELPER_LOG" >&2
  exit 1
}
grep -Fxq $'fresh-front-app\tlua_only=1' "$RUNTIME_LOG" || {
  echo "FAIL: Lua-only popup refresh should retain the portable wrapper" >&2
  cat "$RUNTIME_LOG" >&2
  exit 1
}

run_front_app_popup_refresh empty empty
assert_call_count 1
assert_set_count 8
assert_single_animated_batch Ghostty "󰒄" "Floating · Above" "Space 1 · Display 1" \
  "Tile Window" "Enter Fullscreen" "Normal Layer" "Tile Here"
grep -Fxq -- '--app Ghostty' "$CONTEXT_LOG" || {
  echo "FAIL: an empty fresh snapshot should use the front-app context fallback" >&2
  cat "$CONTEXT_LOG" >&2
  exit 1
}
assert_log_contains "--set front_app.window.float label=Tile Window"

[ ! -s "$POISON_LOG" ] || {
  echo "FAIL: front_app should use BARISTA_SKETCHYBAR_BIN instead of the PATH poison" >&2
  cat "$POISON_LOG" >&2
  exit 1
}

printf 'test_front_app_plugin.sh: ok\n'
