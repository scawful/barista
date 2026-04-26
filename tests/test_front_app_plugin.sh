#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/front_app.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
SCRIPTS_DIR="$TMP_DIR/scripts"
LOG_FILE="$TMP_DIR/sketchybar.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR" "$SCRIPTS_DIR"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$LOG_FILE"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

cat > "$SCRIPTS_DIR/app_icon.sh" <<'EOF'
#!/bin/bash
printf '󰊠\n'
EOF
chmod +x "$SCRIPTS_DIR/app_icon.sh"

cat > "$SCRIPTS_DIR/front_app_context.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${FRONT_APP_PLUGIN_CONTEXT_MODE:-floating_above}" in
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
esac
EOF
chmod +x "$SCRIPTS_DIR/front_app_context.sh"

run_front_app() {
  : > "$LOG_FILE"
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    BARISTA_CONFIG_DIR="$TMP_DIR/config" \
    BARISTA_SCRIPTS_DIR="$SCRIPTS_DIR" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_FRONT_APP_CONTEXT_SCRIPT="$SCRIPTS_DIR/front_app_context.sh" \
    BARISTA_APP_ICON_SCRIPT="$SCRIPTS_DIR/app_icon.sh" \
    NAME=front_app \
    SENDER=routine \
    INFO="" \
    FRONT_APP_PLUGIN_CONTEXT_MODE="$1" \
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

run_front_app floating_above
assert_log_contains "--set front_app.window.float label=Tile Window"
assert_log_contains "--set front_app.window.fullscreen label=Enter Fullscreen"
assert_log_contains "--set front_app.window.topmost label=Normal Layer"
assert_log_contains "--set front_app.preset.tile_here label=Tile Here"

run_front_app fullscreen
assert_log_contains "--set front_app.window.float label=Float Window"
assert_log_contains "--set front_app.window.fullscreen label=Exit Fullscreen"
assert_log_contains "--set front_app.window.topmost label=Make Topmost"

run_front_app none
assert_log_contains "--set front_app.window.float label=No Window to Float"
assert_log_contains "--set front_app.preset.tile_here label=No Window to Tile"

printf 'test_front_app_plugin.sh: ok\n'
