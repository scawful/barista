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
[ -n "${BARISTA_TEST_LOG:-}" ] && printf 'yabai\t%s\n' "$*" >> "$BARISTA_TEST_LOG"
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

# Space policy enforcement & agent CLI checks
REAL_JQ="$(command -v jq)"
cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
[ -n "${BARISTA_TEST_LOG:-}" ] && printf 'yabai\t%s\n' "$*" >> "$BARISTA_TEST_LOG"
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--spaces" ]; then
  if [ "${BARISTA_TEST_MULTI_DISPLAY:-0}" = "1" ]; then
    if grep -Fq $'yabai\t-m space --create' "$BARISTA_TEST_LOG"; then
      printf '[{"index":1,"uuid":"UUID-1","display":1,"type":"bsp","has-focus":true,"windows":[]},{"index":2,"uuid":"UUID-2","display":1,"type":"bsp","has-focus":false,"windows":[]},{"index":3,"uuid":"UUID-NEW","display":1,"type":"bsp","has-focus":false,"windows":[]},{"index":4,"uuid":"UUID-3","display":2,"type":"bsp","has-focus":false,"windows":[]}]\n'
    else
      printf '[{"index":1,"uuid":"UUID-1","display":1,"type":"bsp","has-focus":true,"windows":[]},{"index":2,"uuid":"UUID-2","display":1,"type":"bsp","has-focus":false,"windows":[]},{"index":3,"uuid":"UUID-3","display":2,"type":"bsp","has-focus":false,"windows":[]}]\n'
    fi
    exit 0
  fi
  if [ "${BARISTA_TEST_DESTROY_REFUSED:-0}" != "1" ] && grep -Fq $'yabai\t-m space 2 --destroy' "$BARISTA_TEST_LOG"; then
    printf '[{"index":1,"id":101,"uuid":"UUID-1","display":1,"type":"bsp","has-focus":true,"is-visible":true,"is-native-fullscreen":false,"windows":[11,12,21]}]\n'
    exit 0
  fi
  printf '[{"index":1,"id":101,"uuid":"UUID-1","display":1,"type":"bsp","has-focus":true,"is-visible":true,"is-native-fullscreen":false,"windows":[11,12]},{"index":2,"id":102,"uuid":"UUID-2","display":1,"type":"float","has-focus":false,"is-visible":false,"is-native-fullscreen":false,"windows":[21]}]\n'
  exit 0
fi
if [ "${1:-}" = "-m" ] && [ "${2:-}" = "query" ] && [ "${3:-}" = "--windows" ]; then
  printf '[{"id":11,"app":"Ghostty","title":"term","space":1,"display":1,"has-focus":true,"is-floating":false,"is-sticky":false,"is-minimized":false,"has-fullscreen-zoom":false,"layer":"normal","sub-layer":"normal"}]\n'
  exit 0
fi
exit 0
EOF
chmod +x "$BIN_DIR/yabai"

printf '{"modes":{"runtime_backend":"lua"},"spaces":{"max_spaces_per_display":2,"min_spaces_per_display":1,"destroy_non_empty_policy":"refuse","locked_spaces":{"1":true}}}\n' > "$CONFIG_DIR/state.json"
: > "$LOG_FILE"
if PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" YABAI_BIN="$BIN_DIR/yabai" JQ_BIN="$REAL_JQ" SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" BARISTA_REFRESH_LOG="$REFRESH_LOG" \
  "$SCRIPT" create --display 1 2>/dev/null; then
  echo "FAIL: max_spaces_per_display=2 should refuse creating a 3rd space on display 1" >&2
  exit 1
fi
if grep -Fq $'yabai\t-m space --create' "$LOG_FILE"; then
  echo "FAIL: refused space create must not call yabai --create" >&2
  exit 1
fi

if PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" YABAI_BIN="$BIN_DIR/yabai" JQ_BIN="$REAL_JQ" SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" BARISTA_REFRESH_LOG="$REFRESH_LOG" \
  "$SCRIPT" destroy --space 1 2>/dev/null; then
  echo "FAIL: locked space 1 must refuse destroy" >&2
  exit 1
fi

if PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" YABAI_BIN="$BIN_DIR/yabai" JQ_BIN="$REAL_JQ" SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" BARISTA_REFRESH_LOG="$REFRESH_LOG" \
  "$SCRIPT" destroy --space 2 2>/dev/null; then
  echo "FAIL: destroy_non_empty_policy=refuse must refuse destroying space 2 with windows" >&2
  exit 1
fi

printf '{"modes":{"runtime_backend":"lua"},"spaces":{"max_spaces_per_display":4,"min_spaces_per_display":1,"destroy_non_empty_policy":"evacuate","locked_spaces":{}}}\n' > "$CONFIG_DIR/state.json"
: > "$LOG_FILE"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" YABAI_BIN="$BIN_DIR/yabai" JQ_BIN="$REAL_JQ" SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" BARISTA_REFRESH_LOG="$REFRESH_LOG" \
  "$SCRIPT" destroy --space 2
grep -Fq $'yabai\t-m window 21 --space 1' "$LOG_FILE" || {
  echo "FAIL: destroy_non_empty_policy=evacuate must evacuate windows before destroying space" >&2
  exit 1
}
grep -Fq $'yabai\t-m space 2 --destroy' "$LOG_FILE" || {
  echo "FAIL: destroy_non_empty_policy=evacuate must destroy the space after evacuating windows" >&2
  exit 1
}

# Verify unified bin/barista CLI JSON endpoints
STATUS_JSON="$(PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" BARISTA_CONFIG_DIR="$CONFIG_DIR" BARISTA_STATE_FILE="$CONFIG_DIR/state.json" BARISTA_YABAI_BIN="$BIN_DIR/yabai" BARISTA_JQ_BIN="$REAL_JQ" "$ROOT_DIR/bin/barista" status --json)"
[ "$(printf '%s' "$STATUS_JSON" | "$REAL_JQ" -r '.current_space.index')" = "1" ] || {
  echo "FAIL: barista status --json should report current_space.index=1" >&2
  exit 1
}
[ "$(printf '%s' "$STATUS_JSON" | "$REAL_JQ" -r '.space_policies.destroy_non_empty_policy')" = "evacuate" ] || {
  echo "FAIL: barista status --json should report configured space_policies" >&2
  exit 1
}

SPACES_JSON="$(PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" BARISTA_CONFIG_DIR="$CONFIG_DIR" BARISTA_STATE_FILE="$CONFIG_DIR/state.json" BARISTA_YABAI_BIN="$BIN_DIR/yabai" BARISTA_JQ_BIN="$REAL_JQ" "$ROOT_DIR/bin/barista" spaces --json)"
[ "$(printf '%s' "$SPACES_JSON" | "$REAL_JQ" -r 'length')" = "2" ] || {
  echo "FAIL: barista spaces --json should return 2 spaces" >&2
  exit 1
}

# Saved layout state survives a destroy that yabai refused, and is cleared
# once the space is really gone.
printf '{"modes":{"runtime_backend":"lua"},"space_modes":{"2":"float"},"space_modes_by_uuid":{"UUID-2":"float"},"space_mode_uuids":{"2":"UUID-2"}}\n' > "$CONFIG_DIR/state.json"
: > "$LOG_FILE"
if PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" YABAI_BIN="$BIN_DIR/yabai" JQ_BIN="$REAL_JQ" SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" BARISTA_REFRESH_LOG="$REFRESH_LOG" BARISTA_TEST_DESTROY_REFUSED=1 \
  "$SCRIPT" destroy --space 2 2>/dev/null; then
  echo "FAIL: a destroy yabai refused should report failure" >&2
  exit 1
fi
[ "$("$REAL_JQ" -r '.space_modes_by_uuid["UUID-2"] // ""' "$CONFIG_DIR/state.json")" = "float" ] || {
  echo "FAIL: a refused destroy must keep the surviving space's saved layout" >&2
  exit 1
}
: > "$LOG_FILE"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" YABAI_BIN="$BIN_DIR/yabai" JQ_BIN="$REAL_JQ" SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" BARISTA_REFRESH_LOG="$REFRESH_LOG" \
  "$SCRIPT" destroy --space 2
[ "$("$REAL_JQ" -r '.space_modes_by_uuid["UUID-2"] // ""' "$CONFIG_DIR/state.json")" = "" ] || {
  echo "FAIL: a confirmed destroy should clear the space's saved layout" >&2
  exit 1
}

# Locks keyed by uuid also guard reorders, which only know the index.
printf '{"modes":{"runtime_backend":"lua"},"spaces":{"locked_spaces":{"UUID-2":true}}}\n' > "$CONFIG_DIR/state.json"
: > "$LOG_FILE"
if PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" YABAI_BIN="$BIN_DIR/yabai" JQ_BIN="$REAL_JQ" SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" BARISTA_REFRESH_LOG="$REFRESH_LOG" \
  "$SCRIPT" move-right --space 1 2>/dev/null; then
  echo "FAIL: moving next to a uuid-locked space should be refused" >&2
  exit 1
fi
if grep -Fq -- '--move' "$LOG_FILE"; then
  echo "FAIL: a refused reorder must not call yabai --move" >&2
  exit 1
fi

# With another display after the target, the new space is found by uuid, not
# by the one index that did not exist before (which belongs to display 2).
printf '{"modes":{"runtime_backend":"lua"},"spaces":{"new_space_layout":"float"}}\n' > "$CONFIG_DIR/state.json"
: > "$LOG_FILE"
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  CONFIG_DIR="$CONFIG_DIR" YABAI_BIN="$BIN_DIR/yabai" JQ_BIN="$REAL_JQ" SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
  BARISTA_TEST_LOG="$LOG_FILE" BARISTA_REFRESH_LOG="$REFRESH_LOG" BARISTA_TEST_MULTI_DISPLAY=1 \
  "$SCRIPT" create --display 1
grep -Fq $'yabai\t-m space 3 --layout float' "$LOG_FILE" || {
  echo "FAIL: new_space_layout should apply to the created space on display 1" >&2
  exit 1
}

printf 'test_space_action_click.sh: ok\n'
