#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CONFIG_DIR="$TMP_DIR/config"
LOG="$TMP_DIR/yabai.log"
PHASE_FILE="$TMP_DIR/phase"
mkdir -p "$CONFIG_DIR/plugins" "$TMP_DIR/before" "$TMP_DIR/after"

cat > "$CONFIG_DIR/plugins/refresh_spaces.sh" <<EOF
#!/bin/bash
printf 'refresh %s\n' "\$BARISTA_REASON" >> "$LOG"
EOF
chmod +x "$CONFIG_DIR/plugins/refresh_spaces.sh"

cat > "$TMP_DIR/yabai" <<EOF
#!/bin/bash
phase="\$(cat "$PHASE_FILE")"
case "\$*" in
  "-m query --spaces") cat "$TMP_DIR/\$phase/spaces.json" ;;
  "-m query --windows") cat "$TMP_DIR/\$phase/windows.json" ;;
  *) printf '%s\n' "\$*" >> "$LOG" ;;
esac
EOF
chmod +x "$TMP_DIR/yabai"

# Space A (index 2) is dragged from display 1 to display 2 and becomes index 3.
cat > "$TMP_DIR/before/spaces.json" <<'EOF'
[{"uuid":"A","index":2,"display":1},{"uuid":"B","index":3,"display":1},{"uuid":"C","index":4,"display":2}]
EOF
cat > "$TMP_DIR/before/windows.json" <<'EOF'
[{"id":10,"space":2,"display":1,"is-sticky":false,"is-minimized":false},
 {"id":11,"space":2,"display":1,"is-sticky":false,"is-minimized":false},
 {"id":12,"space":3,"display":1,"is-sticky":false,"is-minimized":false},
 {"id":13,"space":2,"display":1,"is-sticky":true,"is-minimized":false}]
EOF
cat > "$TMP_DIR/after/spaces.json" <<'EOF'
[{"uuid":"B","index":2,"display":1},{"uuid":"A","index":3,"display":2},{"uuid":"C","index":4,"display":2}]
EOF
# Window 10 snapped back to the old display; 11 stayed with its space.
cat > "$TMP_DIR/after/windows.json" <<'EOF'
[{"id":10,"space":2,"display":1,"is-sticky":false,"is-minimized":false},
 {"id":11,"space":3,"display":2,"is-sticky":false,"is-minimized":false},
 {"id":12,"space":2,"display":1,"is-sticky":false,"is-minimized":false},
 {"id":13,"space":2,"display":1,"is-sticky":true,"is-minimized":false}]
EOF

export CONFIG_DIR YABAI_BIN="$TMP_DIR/yabai" BARISTA_MC_SNAPSHOT_FILE="$TMP_DIR/snapshot.json"
GUARD="$ROOT_DIR/plugins/mission_control_guard.sh"

echo before > "$PHASE_FILE"
"$GUARD" enter
[ -s "$BARISTA_MC_SNAPSHOT_FILE" ] || { echo 'FAIL: enter must write a snapshot' >&2; exit 1; }

echo after > "$PHASE_FILE"
: > "$LOG"
"$GUARD" exit

expected="$(cat <<'EOF'
-m space 3 --gap rel:0
-m window 10 --space 3
-m space 3 --gap rel:0
refresh mission_control_exit
EOF
)"
if [ "$(cat "$LOG")" != "$expected" ]; then
  echo 'FAIL: unexpected restore actions:' >&2
  cat "$LOG" >&2
  exit 1
fi
[ ! -e "$BARISTA_MC_SNAPSHOT_FILE" ] || { echo 'FAIL: exit must consume the snapshot' >&2; exit 1; }

# Without a snapshot (or with no moved spaces) exit only refreshes the bar.
: > "$LOG"
"$GUARD" exit
[ "$(cat "$LOG")" = "refresh mission_control_exit" ] || {
  echo 'FAIL: exit without a snapshot must only refresh' >&2; cat "$LOG" >&2; exit 1;
}

echo after > "$PHASE_FILE"
"$GUARD" enter
: > "$LOG"
"$GUARD" exit
[ "$(cat "$LOG")" = "refresh mission_control_exit" ] || {
  echo 'FAIL: unchanged displays must not touch spaces or windows' >&2; cat "$LOG" >&2; exit 1;
}

echo "test_mission_control_guard.sh: ok"
