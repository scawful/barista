#!/usr/bin/env bash
# display_density.sh must produce the fingerprint main.lua writes for the same
# topology; any mismatch reloads the bar, and the reload writes it back again.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_DIR="$TMP_DIR/config"
RELOAD_LOG="$TMP_DIR/reloads"
mkdir -p "$CONFIG_DIR/plugins" "$CONFIG_DIR/cache"

cat > "$CONFIG_DIR/plugins/reload_sketchybar.sh" <<EOF
#!/bin/bash
echo reload >> "$RELOAD_LOG"
EOF
chmod +x "$CONFIG_DIR/plugins/reload_sketchybar.sh"

cat > "$TMP_DIR/sketchybar" <<'EOF'
#!/bin/bash
[ "$*" = "--query displays" ] && cat "$DISPLAYS_JSON"
EOF
chmod +x "$TMP_DIR/sketchybar"

lua_fingerprint() {
  lua -e "
    package.path = '$ROOT_DIR/modules/?.lua;$ROOT_DIR/helpers/lib/?.lua;' .. package.path
    local json = require('json')
    local frames = {}
    for _, d in ipairs(json.decode(io.read('a'))) do
      table.insert(frames, { id = d['arrangement-id'], width = d.frame.w, height = d.frame.h })
    end
    io.write(require('display_profile').classify_displays(frames).fingerprint)
  " < "$1"
}

check_layout() {
  local name="$1" displays="$2" expected
  printf '%s\n' "$displays" > "$TMP_DIR/$name.json"
  expected="$(lua_fingerprint "$TMP_DIR/$name.json")"
  printf '%s\n' "$expected" > "$CONFIG_DIR/cache/display_density_fingerprint"
  rm -f "$RELOAD_LOG"
  DISPLAYS_JSON="$TMP_DIR/$name.json" CONFIG_DIR="$CONFIG_DIR" BARISTA_SKETCHYBAR_BIN="$TMP_DIR/sketchybar" \
    bash "$ROOT_DIR/plugins/display_density.sh"
  sleep 0.3
  if [ -e "$RELOAD_LOG" ]; then
    echo "FAIL: $name: shell fingerprint '$(cat "$CONFIG_DIR/cache/display_density_fingerprint")' != Lua '$expected'" >&2
    exit 1
  fi
}

check_layout wide_only '[{"arrangement-id":1,"frame":{"w":1800,"h":1169}}]'
check_layout split '[{"arrangement-id":1,"frame":{"w":1800,"h":1169}},{"arrangement-id":2,"frame":{"w":800,"h":1280}}]'
check_layout all_narrow '[{"arrangement-id":1,"frame":{"w":900,"h":1600}}]'
check_layout fractional '[{"arrangement-id":1,"frame":{"w":1511.6,"h":982}}]'

# A real topology change still reloads.
printf '%s\n' "$(lua_fingerprint "$TMP_DIR/wide_only.json")" > "$CONFIG_DIR/cache/display_density_fingerprint"
rm -f "$RELOAD_LOG"
DISPLAYS_JSON="$TMP_DIR/split.json" CONFIG_DIR="$CONFIG_DIR" BARISTA_SKETCHYBAR_BIN="$TMP_DIR/sketchybar" \
  bash "$ROOT_DIR/plugins/display_density.sh"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$RELOAD_LOG" ] && break; sleep 0.1; done
[ -e "$RELOAD_LOG" ] || { echo "FAIL: adding a narrow display should reload" >&2; exit 1; }

echo "test_display_density.sh: ok"
