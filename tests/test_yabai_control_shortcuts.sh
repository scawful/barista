#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/yabai_control.sh"
TMP_DIR="$(mktemp -d)"
HOME_DIR="$TMP_DIR/home"
BIN_DIR="$TMP_DIR/bin"
SKHD_DIR="$HOME_DIR/.config/skhd"
LOCAL_BIN="$HOME_DIR/.local/bin"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR" "$SKHD_DIR" "$LOCAL_BIN"

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$BIN_DIR/yabai"

cat > "$SKHD_DIR/skhdrc" <<EOF
.load "$TMP_DIR/barista.conf"
.load "$TMP_DIR/keychron_k0.conf"
.load "$TMP_DIR/dotfiles.conf"
EOF

cat > "$TMP_DIR/barista.conf" <<EOF
# Reload SketchyBar - cmd alt r
cmd + alt - r : $ROOT_DIR/plugins/reload_sketchybar.sh

# Missing helper
cmd + alt - x : $TMP_DIR/missing-helper.sh
EOF

cat > "$TMP_DIR/keychron_k0.conf" <<'EOF'
# Section: should not be parsed as a disabled binding
f18 : yabai -m window --focus west
# f19 : yabai -m window --focus north
# === Alternative: should not be parsed either ===
EOF

cat > "$TMP_DIR/dotfiles.conf" <<'EOF'
cmd + alt - r : sketchybar --reload
ctrl - left : ~/.local/bin/yabai_control_wrapper.sh space-focus-prev-wrap
EOF

cat > "$LOCAL_BIN/yabai_control_wrapper.sh" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$LOCAL_BIN/yabai_control_wrapper.sh"

run_control() {
  HOME="$HOME_DIR" \
    PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    YABAI_BIN="$BIN_DIR/yabai" \
    SKHD_CONFIG="$SKHD_DIR/skhdrc" \
    "$SCRIPT" "$@"
}

TEXT_OUTPUT="$(run_control shortcuts)"
printf '%s\n' "$TEXT_OUTPUT" | grep -Fq 'summary: active=5 disabled=1 duplicates=1 raw_yabai=1 missing_targets=1' || {
  echo "FAIL: shortcut summary did not match expected counts" >&2
  printf '%s\n' "$TEXT_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$TEXT_OUTPUT" | grep -Fq 'missing=' || {
  echo "FAIL: missing target should be reported" >&2
  printf '%s\n' "$TEXT_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$TEXT_OUTPUT" | grep -Fq 'raw_yabai=1' || {
  echo "FAIL: raw yabai command should be counted" >&2
  printf '%s\n' "$TEXT_OUTPUT" >&2
  exit 1
}
if printf '%s\n' "$TEXT_OUTPUT" | grep -Fq 'Alternative:'; then
  echo "FAIL: commented section headings should not be parsed as bindings" >&2
  printf '%s\n' "$TEXT_OUTPUT" >&2
  exit 1
fi

JSON_OUTPUT="$(run_control shortcuts --json)"
SHORTCUT_JSON="$JSON_OUTPUT" /usr/bin/python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["SHORTCUT_JSON"])
rows = payload["shortcuts"]
assert len(rows) == 6, len(rows)
assert any("yabai -m" in row["command"] for row in rows)
assert any(row["status"] == "disabled" and row["combo"] == "f19" for row in rows)
assert sum(1 for row in rows if row["missing_target"]) == 1
PY

printf 'test_yabai_control_shortcuts.sh: ok\n'
