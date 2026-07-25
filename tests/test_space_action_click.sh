#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/space_action.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN_DIR="$TMP_DIR/bin"
CONFIG_DIR="$TMP_DIR/config"
LOG_FILE="$TMP_DIR/actions.log"
REFRESH_LOG="$TMP_DIR/refresh.log"
mkdir -p "$BIN_DIR" "$CONFIG_DIR/bin" "$CONFIG_DIR/plugins"
printf '{"modes":{"runtime_backend":" Pure-Lua "},"spaces":{"context_menu_on_right_click":true}}\n' > "$CONFIG_DIR/state.json"

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
printf 'yabai\t%s\n' "$*" >> "${BARISTA_TEST_LOG:?}"
EOF
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
printf 'sketchybar\t%s\n' "$*" >> "${BARISTA_TEST_LOG:?}"
if [ "${1:-}" = "--query" ]; then
  exit 1
fi
EOF
chmod +x "$BIN_DIR/sketchybar"

cat > "$CONFIG_DIR/bin/space_manager" <<'EOF'
#!/bin/bash
printf 'space_manager\t%s\n' "$*" >> "${BARISTA_TEST_LOG:?}"
EOF
chmod +x "$CONFIG_DIR/bin/space_manager"

cat > "$CONFIG_DIR/plugins/refresh_spaces.sh" <<'EOF'
#!/bin/bash
printf 'refresh\tlua_only=%s\n' "${BARISTA_LUA_ONLY:-0}" >> "${BARISTA_REFRESH_LOG:?}"
EOF
chmod +x "$CONFIG_DIR/plugins/refresh_spaces.sh"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  YABAI_BIN="$BIN_DIR/yabai" \
  JQ_BIN="" \
  SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" \
  BUTTON=2 \
  "$SCRIPT" click --space 4

grep -Fq $'yabai\t-m space --focus 4' "$LOG_FILE" || {
  echo "FAIL: ambiguous numeric button should focus the clicked space" >&2
  exit 1
}

if grep -Fq 'popup.drawing' "$LOG_FILE"; then
  echo "FAIL: ambiguous numeric button should not open a space context menu" >&2
  exit 1
fi

printf '{"modes":{"runtime_backend":"auto"},"spaces":{"context_menu_on_right_click":true}}\n' > "$CONFIG_DIR/state.json"
printf 'lua\n' > "$CONFIG_DIR/.barista_runtime_backend"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  YABAI_BIN="$BIN_DIR/yabai" \
  JQ_BIN="" \
  SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" \
  BARISTA_REFRESH_LOG="$REFRESH_LOG" \
  "$SCRIPT" create --display active

for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$REFRESH_LOG" ] && break
  sleep 0.05
done

if grep -Fq $'space_manager\t' "$LOG_FILE"; then
  echo "FAIL: dynamically resolved Lua-only actions must ignore a leftover compiled manager" >&2
  exit 1
fi
grep -Fq $'yabai\t-m space --create' "$LOG_FILE" || {
  echo "FAIL: Lua-only create should retain the yabai fallback" >&2
  exit 1
}
grep -Fqx $'refresh\tlua_only=1' "$REFRESH_LOG" || {
  echo "FAIL: dynamically resolved Lua-only actions must propagate the helper gate to refresh" >&2
  exit 1
}
grep -Fq "click_script=/usr/bin/env BARISTA_LUA_ONLY=1 $CONFIG_DIR/scripts/space_action.sh swap-cancel" "$LOG_FILE" || {
  echo "FAIL: Lua-only swap indicator clicks must preserve the helper gate" >&2
  exit 1
}

: > "$CONFIG_DIR/.barista_runtime_backend"
: > "$LOG_FILE"
: > "$REFRESH_LOG"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" \
  YABAI_BIN="$BIN_DIR/yabai" \
  JQ_BIN="" \
  SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" \
  BARISTA_REFRESH_LOG="$REFRESH_LOG" \
  "$SCRIPT" create --display active

for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -s "$REFRESH_LOG" ] && break
  sleep 0.05
done
if grep -Fq $'space_manager\t' "$LOG_FILE"; then
  echo "FAIL: invalid resolved-runtime markers must fail closed" >&2
  exit 1
fi
grep -Fqx $'refresh\tlua_only=1' "$REFRESH_LOG" || {
  echo "FAIL: invalid resolved-runtime markers must preserve the refresh gate" >&2
  exit 1
}

printf 'test_space_action_click.sh: ok\n'
