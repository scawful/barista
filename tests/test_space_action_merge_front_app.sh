#!/bin/bash
# A click on the already-focused space chip opens the front_app menu under it
# when spaces.merge_front_app is on; otherwise it keeps the old refresh path.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/space_action.sh"
JQ="$(command -v jq || true)"
if [ -z "$JQ" ]; then
  echo "SKIP: jq not installed"
  exit 0
fi
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN_DIR="$TMP_DIR/bin"
CONFIG_DIR="$TMP_DIR/config"
LOG_FILE="$TMP_DIR/actions.log"
mkdir -p "$BIN_DIR" "$CONFIG_DIR"

# yabai refuses to focus space 3 the way the real one does.
cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
printf 'yabai\t%s\n' "$*" >> "${BARISTA_TEST_LOG:?}"
if [ "$*" = "-m space --focus 3" ]; then
  echo "cannot focus an already focused space." >&2
  exit 1
fi
EOF
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
printf 'sketchybar\t%s\n' "$*" >> "${BARISTA_TEST_LOG:?}"
if [ "$*" = "--query front_app" ]; then
  printf '{"scripting":{"click_script":"printf \\"menu\\\\topened\\\\n\\" >> \\"$BARISTA_TEST_LOG\\""}}\n'
fi
EOF
chmod +x "$BIN_DIR/sketchybar"

run_click() {
  local space="$1"
  : > "$LOG_FILE"
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    CONFIG_DIR="$CONFIG_DIR" \
    YABAI_BIN="$BIN_DIR/yabai" \
    JQ_BIN="$JQ" \
    SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_TEST_LOG="$LOG_FILE" \
    BUTTON="${2:-left}" \
    "$SCRIPT" focus --space "$space"
}

fail() {
  echo "FAIL: $1" >&2
  cat "$LOG_FILE" >&2
  exit 1
}

# Default state (key absent): merged.
printf '{"spaces":{}}\n' > "$CONFIG_DIR/state.json"
run_click 3
grep -Fq $'sketchybar\t--move front_app before space.3' "$LOG_FILE" \
  || fail "active space click should move front_app before the clicked chip"
grep -Fq $'menu\topened' "$LOG_FILE" || fail "active space click should run the front_app click_script"
if grep -Fq -- '--trigger space_change' "$LOG_FILE"; then
  fail "active space click must not trigger space_change (it closes the menu)"
fi

# Another space still focuses and refreshes.
run_click 5
grep -Fq $'sketchybar\t--trigger space_change' "$LOG_FILE" || fail "focusing another space should refresh"
if grep -Fq 'menu' "$LOG_FILE"; then
  fail "focusing another space should not open the front_app menu"
fi

# A right click that falls through to focus (close mode off) is not a menu click.
run_click 3 right
if grep -Fq -- '--move front_app' "$LOG_FILE" || grep -Fq 'menu' "$LOG_FILE"; then
  fail "right click on the active space must not open the front_app menu"
fi

# merge_front_app=false keeps the old no-op refresh, and the false is honored.
printf '{"spaces":{"merge_front_app":false}}\n' > "$CONFIG_DIR/state.json"
run_click 3
grep -Fq $'sketchybar\t--trigger space_change' "$LOG_FILE" || fail "unmerged active space click should refresh"
if grep -Fq -- '--move front_app' "$LOG_FILE"; then
  fail "unmerged active space click should not move front_app"
fi

echo "PASS: test_space_action_merge_front_app"
