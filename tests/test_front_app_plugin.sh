#!/bin/bash

set -euo pipefail
export BARISTA_HOVER_ANIMATION_DURATION=12

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

mkdir -p "$BIN_DIR" "$POISON_BIN_DIR" "$SCRIPTS_DIR" "$TMP_DIR/custom config's"
printf '{"window_defaults":{"apps":{}}}\n' > "$TMP_DIR/custom config's/state.json"

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
case "$*" in
  '-m rule --list') printf '%s\n' "${BARISTA_TEST_RULES_JSON:-[]}" ;;
  '-m query --windows --window') printf '%s\n' "${BARISTA_TEST_WINDOW_JSON:-{}}" ;;
esac
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
if [ "$mode" != none ] && [ "$mode" != legacy ]; then
  printf 'window_id\t731\n'
  printf 'window_space_type\tbsp\n'
fi
case "$mode" in
  floating_above|legacy|manual_floating)
    printf 'app_name\tGhostty\n'
    printf 'window_available\ttrue\n'
    printf 'state_icon\t󰒄\n'
    printf 'state_label\tFloating · Above\n'
    printf 'location_label\tSpace 1 · Display 1\n'
    if [ "$mode" = manual_floating ]; then printf 'window_space_type\tfloat\n'; fi
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
  barista_files)
    printf 'app_name\tBarista Files\n'
    printf 'window_available\ttrue\n'
    printf 'state_icon\t󰒄\n'
    printf 'state_label\tFloating · Above\n'
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
  printf 'window_id\t731\n'
  printf 'window_space_type\tbsp\n'
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
  printf 'window_id\t731\n'
  printf 'window_space_type\tbsp\n'
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
    BARISTA_CONFIG_DIR="$TMP_DIR/custom config's" \
    BARISTA_SCRIPTS_DIR="$SCRIPTS_DIR" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
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
    BARISTA_CONFIG_DIR="$TMP_DIR/custom config's" \
    BARISTA_SCRIPTS_DIR="$SCRIPTS_DIR" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_FRONT_APP_CONTEXT_SCRIPT="$SCRIPTS_DIR/front_app_context.sh" \
    BARISTA_RUNTIME_CONTEXT_SCRIPT="$SCRIPTS_DIR/runtime_context.sh" \
    BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$SCRIPTS_DIR/runtime_context_helper" \
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
    BARISTA_CONFIG_DIR="$TMP_DIR/custom config's" \
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
payload = calls[0][3:]
fields = {}
i = 0
while i < len(payload):
    assert payload[i] == "--set", payload[i:]
    name = payload[i + 1]
    props = fields.setdefault(name, {})
    i += 2
    while i < len(payload) and payload[i] != "--set":
        key, value = payload[i].split("=", 1)
        props[key] = value
        i += 1
assert fields["front_app"]["icon"] == "󰊠"
assert fields["front_app.header"]["label"] == app_name
assert fields["front_app.state"]["icon"] == state_icon
assert fields["front_app.state"]["label"] == state_label
assert fields["front_app.location"]["label"] == location_label
if action_rows == "1":
    import shlex
    assert fields["front_app.window.float"]["label"] == float_label
    assert fields["front_app.window.fullscreen"]["label"] == fullscreen_label
    assert fields["front_app.window.topmost"]["label"] == topmost_label
    assert fields["front_app.preset.tile_here"]["label"] == tile_label
    window_names = [name for name in fields if name.startswith(("front_app.window.", "front_app.preset.", "front_app.move."))]
    assert len(window_names) == 15, window_names
    for name in window_names:
        script = fields[name]["click_script"]
        if state_label.startswith("No window"):
            assert script == "", (name, script)
            assert fields[name]["label.color"] == "0xFF6e738d"
        else:
            try:
                args = shlex.split(script)
            except ValueError:
                raise AssertionError(repr(script))
            assert args[-4] == "window" and args[-2:] == ["731", app_name], args
    for name in ("hide", "quit", "force_quit"):
        args = shlex.split(fields["front_app." + name]["click_script"])
        assert args[-4] == "app" and args[-1] == app_name, args
else:
    assert len(fields) == 4, fields

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
assert_set_count 4
assert_log_contains "--set front_app.more popup.drawing=off --set front_app.move popup.drawing=off --set front_app.defaults popup.drawing=off --set front_app popup.drawing=toggle"

run_front_app_event mouse.clicked 0
assert_call_count 1
assert_set_count 1
assert_log_contains "--set front_app popup.drawing=toggle"

run_front_app floating_above
assert_call_count 1
assert_set_count 36
assert_single_animated_batch Ghostty "󰒄" "Floating · Above" "Space 1 · Display 1" \
  "Tile Window" "Enter Fullscreen" "Always on top: On" "Exit Fullscreen + Match Space"
assert_log_contains "--set front_app.window.float label=Tile Window"
assert_log_contains "--set front_app.window.fullscreen label=Enter Fullscreen"
assert_log_contains "--set front_app.window.topmost label=Always on top: On"
assert_log_contains "--set front_app.preset.tile_here label=Exit Fullscreen + Match Space"

run_front_app fullscreen
assert_call_count 1
assert_set_count 36
assert_single_animated_batch Ghostty "󰊓" Fullscreen "Space 1 · Display 1" \
  "Float Window" "Exit Fullscreen" "Always on top: Off" "Exit Fullscreen + Match Space"
assert_log_contains "--set front_app.window.float label=Float Window"
assert_log_contains "--set front_app.window.fullscreen label=Exit Fullscreen"
assert_log_contains "--set front_app.window.topmost label=Always on top: Off"

run_front_app none
assert_call_count 1
assert_set_count 36
assert_single_animated_batch Ghostty "󰋽" "No window available · App defaults still apply" "Space 1 · Display 1" \
  "No Window Available" "No Window Available" "No Window Available" "No Window Available"
assert_log_contains "--set front_app.window.float label=No Window Available"
assert_log_contains "--set front_app.preset.tile_here label=No Window Available"

run_front_app quoted
assert_call_count 1
assert_set_count 36
assert_single_animated_batch $'O\x27Reilly "日本" 🌟' "󰒄" "Floating · Above · 日本" \
  'Space 2 · Display "Studio" 🌟' "Tile Window" "Enter Fullscreen" "Always on top: On" "Exit Fullscreen + Match Space"
assert_argv_contains $'label=O\x27Reilly "日本" 🌟'
assert_argv_contains "label=Floating · Above · 日本"
assert_argv_contains 'label=Space 2 · Display "Studio" 🌟'

run_front_app floating_above animate
assert_call_count 2
assert_set_count 72
assert_argv_contains "--animate"
assert_animation_fallback_payload

run_front_app floating_above all
assert_call_count 2
assert_set_count 72

run_front_app floating_above none 0
assert_call_count 1
assert_set_count 4
assert_single_animated_batch Ghostty "󰒄" "Floating · Above" "Space 1 · Display 1" \
  "Tile Window" "Enter Fullscreen" "Always on top: On" "Exit Fullscreen + Match Space" 0

run_front_app_popup_refresh
assert_call_count 1
assert_set_count 37
assert_single_animated_batch Ghostty "󰊓" Fullscreen "Space 1 · Display 1" \
  "Float Window" "Exit Fullscreen" "Always on top: Off" "Exit Fullscreen + Match Space"
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
assert_set_count 37
assert_single_animated_batch Ghostty "󰊓" Fullscreen "Space 1 · Display 1" \
  "Float Window" "Exit Fullscreen" "Always on top: Off" "Exit Fullscreen + Match Space"
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
assert_set_count 37
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
assert_set_count 37
assert_single_animated_batch Ghostty "󰒄" "Floating · Above" "Space 1 · Display 1" \
  "Tile Window" "Enter Fullscreen" "Always on top: On" "Exit Fullscreen + Match Space"
grep -Fxq -- '--app Ghostty' "$CONTEXT_LOG" || {
  echo "FAIL: an empty fresh snapshot should use the front-app context fallback" >&2
  cat "$CONTEXT_LOG" >&2
  exit 1
}
assert_log_contains "--set front_app.window.float label=Tile Window"

# Saved-state markers are independent of whether the captured app has a window.
: > "$CONTEXT_MODE_FILE"
printf '{"window_defaults":{"apps":{"Ghostty":{"mode":"float","app_regex":"^Ghostty$","rule_label":"barista-default-ghostty"}}}}\n' > "$TMP_DIR/custom config's/state.json"
run_front_app none
assert_log_contains "--set front_app.default.float icon=✓"
assert_log_contains "--set front_app.default.unset icon=○"
assert_log_contains "label=Saved default · Float new windows"

run_front_app_popup_refresh
assert_log_contains "label=Saved default · Float new windows · Not active — choose again"
BARISTA_TEST_RULES_JSON='[{"label":"barista-default-ghostty","app":"^Ghostty$","manage":false}]' run_front_app_popup_refresh
assert_log_contains "label=Saved default · Float new windows · Active"
BARISTA_TEST_RULES_JSON='not json' run_front_app_popup_refresh
assert_log_contains "label=Saved default · Float new windows · Live rule unverified"

: > "$CONTEXT_MODE_FILE"
printf '{"window_defaults":{"apps":[]}}\n' > "$TMP_DIR/custom config's/state.json"
run_front_app floating_above
assert_log_contains "--set front_app.default.unset icon=✓"
printf '{"window_defaults":{"apps":["bad"]}}\n' > "$TMP_DIR/custom config's/state.json"
run_front_app floating_above
assert_log_contains "label=Saved default unavailable"
if grep -Eq 'front_app\.default\.[a-z]+ icon=✓' "$LOG_FILE"; then
  echo 'FAIL: unreadable saved state must not claim a selected default' >&2
  exit 1
fi
assert_log_contains "--set front_app.level.unset icon=✓"

printf '{"window_levels":{"Ghostty":{"level":"raised"}}}\n' > "$TMP_DIR/custom config's/state.json"
run_front_app floating_above
assert_log_contains "--set front_app.level.raised icon=✓"
assert_log_contains "--set front_app.level.unset icon=○"
assert_log_contains "'level' 'top' '731' 'Ghostty'"
printf 'not json\n' > "$TMP_DIR/custom config's/state.json"
run_front_app floating_above
if grep -Eq 'front_app\.level\.[a-z]+ icon=✓' "$LOG_FILE"; then
  echo 'FAIL: an unreadable state file must not claim a window level' >&2
  exit 1
fi

# A legacy helper cannot accidentally bind a different focused application.
BARISTA_TEST_WINDOW_JSON='{"id":999,"app":"Safari","is-minimized":false}' run_front_app legacy
assert_log_contains 'front_app.window.float click_script= label.color=0xFF6e738d'
run_front_app manual_floating
assert_log_contains 'front_app.window.float label=Follow Space Layout'
python3 - "$ARGV_LOG" <<'PYTEST'
import pathlib, shlex, sys
rows = pathlib.Path(sys.argv[1]).read_text().splitlines()
argv = [row.split("\t", 1)[1] for row in rows if row.startswith("ARG\t")]
for index, value in enumerate(argv):
    if value == "front_app.window.float" and argv[index + 1].startswith("click_script="):
        action = shlex.split(argv[index + 1].split("=", 1)[1])
        assert action[-3] == "window-adopt-space-mode", action
        environment = dict(part.split("=", 1) for part in action[1:6])
        assert environment["BARISTA_CONFIG_DIR"].endswith("/custom config's"), environment
        assert environment["BARISTA_STATE_FILE"].endswith("/custom config's/state.json"), environment
        assert environment["BARISTA_SKETCHYBAR_BIN"].endswith("/bin/sketchybar"), environment
        break
else:
    raise AssertionError("missing window float action")
PYTEST
BARISTA_TEST_WINDOW_JSON='{"id":731,"app":"Ghostty","is-minimized":false}' run_front_app legacy
assert_log_contains "'window-adopt-space-mode' '731' 'Ghostty'"

# Barista Files is a window of barista-agent: the menu shows the window name,
# while window actions and saved defaults target the process yabai knows.
printf '{"window_levels":{"barista-agent":{"level":"raised"}}}\n' > "$TMP_DIR/custom config's/state.json"
: > "$CONTEXT_MODE_FILE"
run_front_app barista_files
assert_log_contains "--set front_app.header label=Barista Files"
assert_log_contains "label=App Defaults · Barista Files"
assert_log_contains "'level' 'top' '731' 'barista-agent'"
assert_log_contains "--set front_app.level.raised icon=✓"
if grep -Fq "'Barista Files'" "$LOG_FILE"; then
  echo 'FAIL: window actions must target barista-agent, not the window name' >&2
  exit 1
fi

# Merged mode draws no chip: a focus change renames the header and stops.
: > "$LOG_FILE"
: > "$ARGV_LOG"
: > "$CONTEXT_LOG"
PATH="$POISON_BIN_DIR:$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_CONFIG_DIR="$TMP_DIR/custom config's" \
  BARISTA_SCRIPTS_DIR="$SCRIPTS_DIR" \
  BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_FRONT_APP_CONTEXT_SCRIPT="$SCRIPTS_DIR/front_app_context.sh" \
  BARISTA_TEST_CONTEXT_LOG="$CONTEXT_LOG" \
  BARISTA_FRONT_APP_CHIP=0 \
  NAME=front_app \
  SENDER=front_app_switched \
  INFO="Ghostty" \
  "$SCRIPT"
assert_call_count 1
assert_log_contains "--set front_app.header label=Ghostty"
[ ! -s "$CONTEXT_LOG" ] || {
  echo 'FAIL: merged mode must not query window context on a focus change' >&2
  exit 1
}

[ ! -s "$POISON_LOG" ] || {
  echo "FAIL: front_app should use BARISTA_SKETCHYBAR_BIN instead of the PATH poison" >&2
  cat "$POISON_LOG" >&2
  exit 1
}

printf 'test_front_app_plugin.sh: ok\n'
