#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BARISTA_CLI="$ROOT_DIR/bin/barista"
FRONT_APP_CONTEXT="$ROOT_DIR/scripts/front_app_context.sh"
# lsof reports physical paths (/private/var/...), so compare against those.
TMP_DIR="$(cd "$(mktemp -d)" && pwd -P)"
MULTI_PID=""
cleanup() {
  if [[ -n "$MULTI_PID" ]]; then
    pkill -P "$MULTI_PID" 2>/dev/null || true
    kill "$MULTI_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

BIN_DIR="$TMP_DIR/bin"
CONFIG_DIR="$TMP_DIR/config"
STATE_FILE="$CONFIG_DIR/state.json"
MARKS_FILE="$TMP_DIR/marks.json"
PREV_FOCUS_FILE="$TMP_DIR/scratch_prev"
YABAI_LOG="$TMP_DIR/yabai.log"
WINDOWS_JSON_FILE="$TMP_DIR/windows.json"

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$TMP_DIR/workspace" "$TMP_DIR/master_swap"
printf '{}\n' > "$STATE_FILE"

cat > "$WINDOWS_JSON_FILE" <<'JSON'
[
  {
    "id": 101,
    "pid": 1001,
    "app": "Emacs",
    "title": "main.lua — Doom Emacs",
    "space": 1,
    "display": 1,
    "has-focus": true,
    "is-floating": false,
    "is-minimized": false,
    "is-hidden": false,
    "stack-index": 1,
    "frame": {"x": 0, "y": 0, "w": 800, "h": 900}
  },
  {
    "id": 102,
    "pid": 1002,
    "app": "Ghostty",
    "title": "zsh",
    "space": 1,
    "display": 1,
    "has-focus": false,
    "is-floating": false,
    "is-minimized": false,
    "is-hidden": false,
    "stack-index": 2,
    "frame": {"x": 800, "y": 0, "w": 800, "h": 900}
  },
  {
    "id": 205,
    "pid": 2005,
    "app": "Ghostty",
    "title": "barista-scratch-term",
    "space": 2,
    "display": 1,
    "has-focus": false,
    "is-floating": false,
    "is-minimized": true,
    "is-hidden": false,
    "stack-index": 0,
    "frame": {"x": 100, "y": 100, "w": 600, "h": 400}
  }
]
JSON

cat > "$BIN_DIR/yabai" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'yabai %s\n' "\$*" >> "$YABAI_LOG"
case "\$*" in
  "-m query --windows --window")
    jq -c '[ .[] | select(."has-focus" == true) ][0] // .[0]' "$WINDOWS_JSON_FILE"
    ;;
  "-m query --windows --space 1")
    jq -c '[ .[] | select(.space == 1) ]' "$WINDOWS_JSON_FILE"
    ;;
  "-m query --windows")
    cat "$WINDOWS_JSON_FILE"
    ;;
  "-m query --spaces")
    printf '[{"index":1,"display":1,"type":"stack","has-focus":true,"is-visible":true},{"index":2,"display":1,"type":"bsp","has-focus":false,"is-visible":false}]\n'
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

export PATH="$BIN_DIR:$PATH"
export BARISTA_CONFIG_DIR="$CONFIG_DIR"
export BARISTA_STATE_FILE="$STATE_FILE"
export BARISTA_YABAI_BIN="$BIN_DIR/yabai"
export BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar"
export BARISTA_MARKS_FILE="$MARKS_FILE"
export BARISTA_SCRATCH_PREV_FOCUS_FILE="$PREV_FOCUS_FILE"
export BARISTA_MASTER_SWAP_DIR="$TMP_DIR/master_swap"
export BARISTA_CONTEXT_CWD="$TMP_DIR/workspace"

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: %s (expected=%s actual=%s)\n' "$msg" "$expected" "$actual" >&2
    exit 1
  fi
}

set_focus() {
  jq --argjson id "$1" 'map(. + {"has-focus": (.id == $id)})' "$WINDOWS_JSON_FILE" > "$WINDOWS_JSON_FILE.tmp"
  mv "$WINDOWS_JSON_FILE.tmp" "$WINDOWS_JSON_FILE"
}

# 1. Feature toggles & workflow policies
"$BARISTA_CLI" feature stack_indicator off >/dev/null
assert_eq "$("$BARISTA_CLI" feature --json | jq -r '.stack_indicator')" "false" "stack_indicator should be off"
"$BARISTA_CLI" feature stack_indicator on >/dev/null
if "$BARISTA_CLI" feature yabai_shortcuts off >/dev/null 2>&1; then
  echo "FAIL: yabai_shortcuts must stay owned by toggle_shortcuts.sh" >&2
  exit 1
fi

"$BARISTA_CLI" workflow set scratchpad.width_pct 50 >/dev/null
"$BARISTA_CLI" workflow set scratchpad.height_pct 50 >/dev/null
assert_eq "$("$BARISTA_CLI" workflow get scratchpad.width_pct)" "50" "workflow scratchpad.width_pct should update"

# 2. Context resolution
ctx_json="$("$BARISTA_CLI" context --json)"
assert_eq "$(printf '%s' "$ctx_json" | jq -r '.cwd')" "$TMP_DIR/workspace" "context cwd should match workspace"
assert_eq "$(printf '%s' "$ctx_json" | jq -r '.front_app')" "Emacs" "context front_app should match focused window"

# One process owning shells in two directories (a multi-window terminal):
# the title must decide, otherwise fall back to the default root.
mkdir -p "$TMP_DIR/proj_a" "$TMP_DIR/proj_b"
bash -c "(cd '$TMP_DIR/proj_a' && exec sleep 30) & (cd '$TMP_DIR/proj_b' && exec sleep 30) & wait" &
MULTI_PID=$!
sleep 0.3
cp "$WINDOWS_JSON_FILE" "$WINDOWS_JSON_FILE.saved"
jq --argjson pid "$MULTI_PID" --arg title "zsh — $TMP_DIR/proj_b" \
  'map(if .id == 101 then . + {pid: $pid, title: $title} else . end)' \
  "$WINDOWS_JSON_FILE.saved" > "$WINDOWS_JSON_FILE"
assert_eq "$(BARISTA_CONTEXT_CWD="" "$BARISTA_CLI" context --json | jq -r '.cwd')" "$TMP_DIR/proj_b" "title should pick the matching shell directory"
jq --argjson pid "$MULTI_PID" 'map(if .id == 101 then . + {pid: $pid, title: "zsh"} else . end)' \
  "$WINDOWS_JSON_FILE.saved" > "$WINDOWS_JSON_FILE"
assert_eq "$(BARISTA_CONTEXT_CWD="" BARISTA_DEFAULT_ROOT="$TMP_DIR/workspace" "$BARISTA_CLI" context --json | jq -r '.cwd')" \
  "$TMP_DIR/workspace" "ambiguous shells should fall back to the default root"
mv "$WINDOWS_JSON_FILE.saved" "$WINDOWS_JSON_FILE"

# 3. Scratchpad toggle (unfocused/minimized -> deminimize, move to mouse space, float, grid, focus)
: > "$YABAI_LOG"
"$BARISTA_CLI" scratchpad toggle term
grep -Fq "yabai -m window 205 --deminimize" "$YABAI_LOG"
grep -Fq "yabai -m window 205 --space mouse" "$YABAI_LOG"
grep -Fq "yabai -m window 205 --toggle float" "$YABAI_LOG"
grep -Fq "yabai -m window 205 --grid 12:12:3:3:6:6" "$YABAI_LOG"
grep -Fq "yabai -m window --focus 205" "$YABAI_LOG"
assert_eq "$(cat "$PREV_FOCUS_FILE")" "101" "previous window focus should be saved"

# Scratchpad focused: toggling again minimizes it and restores window 101
jq 'map(if .id == 205 then . + {"is-minimized": false, "is-floating": true} else . end)' "$WINDOWS_JSON_FILE" > "$WINDOWS_JSON_FILE.tmp" && mv "$WINDOWS_JSON_FILE.tmp" "$WINDOWS_JSON_FILE"
set_focus 205
: > "$YABAI_LOG"
"$BARISTA_CLI" scratchpad toggle term
grep -Fq "yabai -m window 205 --minimize" "$YABAI_LOG"
grep -Fq "yabai -m window --focus 101" "$YABAI_LOG"

set_focus 102

# 4. Window marks (set, list, focus, summon, clear)
"$BARISTA_CLI" mark set e 101 >/dev/null
assert_eq "$("$BARISTA_CLI" mark list --json | jq -r '.[0].mark')" "e" "mark 'e' should be listed"
assert_eq "$("$BARISTA_CLI" mark list --json | jq -r '.[0].id')" "101" "mark 'e' should point to window 101"
: > "$YABAI_LOG"
"$BARISTA_CLI" mark summon e
grep -Fq "yabai -m window 101 --space mouse" "$YABAI_LOG"
grep -Fq "yabai -m window --focus 101" "$YABAI_LOG"
"$BARISTA_CLI" mark clear e
assert_eq "$("$BARISTA_CLI" mark list --json | jq 'length')" "0" "mark 'e' should be cleared"

# 5. Zoom master (promote, then swap back), stack cycle, and resize
: > "$YABAI_LOG"
"$BARISTA_CLI" window zoom-master
grep -Fq "yabai -m window 102 --swap 101" "$YABAI_LOG"
# After the swap 102 sits in the master slot; a second press restores 101.
jq 'map(if .id == 101 then .frame.x = 800 elif .id == 102 then .frame.x = 0 else . end)' "$WINDOWS_JSON_FILE" > "$WINDOWS_JSON_FILE.tmp" && mv "$WINDOWS_JSON_FILE.tmp" "$WINDOWS_JSON_FILE"
: > "$YABAI_LOG"
"$BARISTA_CLI" window zoom-master
grep -Fq "yabai -m window 102 --swap 101" "$YABAI_LOG"
if grep -Fq -- "--swap recent" "$YABAI_LOG"; then
  echo "FAIL: zoom-master swap-back should use the saved master, not 'recent'" >&2
  exit 1
fi
"$BARISTA_CLI" window stack-next
grep -Fq "yabai -m window --focus stack.next" "$YABAI_LOG"
"$BARISTA_CLI" window resize east 60
grep -Fq "yabai -m window --resize right:60:0" "$YABAI_LOG"

# 6. Stack indicator counts only windows sharing the focused window's stack
set_focus 101
context_out="$(BARISTA_RUNTIME_CONTEXT_SCRIPT=/nonexistent "$FRONT_APP_CONTEXT" --app Emacs)"
grep -Fq $'stack_badge\t[1/1]' <<< "$context_out"
jq 'map(if .id == 102 then .frame = {"x": 800, "y": 0, "w": 800, "h": 900} else . end)' "$WINDOWS_JSON_FILE" > "$WINDOWS_JSON_FILE.tmp" && mv "$WINDOWS_JSON_FILE.tmp" "$WINDOWS_JSON_FILE"
context_out="$(BARISTA_RUNTIME_CONTEXT_SCRIPT=/nonexistent "$FRONT_APP_CONTEXT" --app Emacs)"
grep -Fq $'stack_badge\t[1/2]' <<< "$context_out"
grep -Fq $'state_label\tStacked [1/2]' <<< "$context_out"

printf 'test_barista_workflow.sh: ok\n'
