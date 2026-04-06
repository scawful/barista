#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/runtime_context.sh"
TMP_DIR="$(mktemp -d)"
CONFIG_DIR="$TMP_DIR/config"
BIN_DIR="$TMP_DIR/bin"
HELPER_BIN="$BIN_DIR/runtime_context_helper"
DAEMON_PID=""

cleanup() {
  if [ -n "$DAEMON_PID" ]; then
    kill "$DAEMON_PID" >/dev/null 2>&1 || true
    wait "$DAEMON_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$CONFIG_DIR/cache" "$BIN_DIR"

cat > "$HELPER_BIN" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
  refresh-front-app)
    mkdir -p "${BARISTA_RUNTIME_CONTEXT_DIR:?}"
    cat > "${BARISTA_RUNTIME_CONTEXT_DIR}/front_app.tsv" <<'TSV'
app_name	Finder
state_icon	󰒄
state_label	Floating
location_label	Space 1 · Display 1
space_index	1
display_index	1
space_visible	true
TSV
    ;;
  daemon)
    trap 'exit 0' INT TERM
    while true; do
      sleep 0.1
    done
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$HELPER_BIN"

cat > "$BIN_DIR/osascript" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$*" in
  *'application "Spotify" is running'*) printf 'false\n' ;;
  *'application "Music" is running'*) printf 'false\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN_DIR/osascript"

cat > "$BIN_DIR/SwitchAudioSource" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${1:-}" in
  -c) printf 'Studio Display\n' ;;
  -a) printf 'Studio Display\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$BIN_DIR/SwitchAudioSource"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_RUNTIME_CONTEXT_HELPER_BIN="$HELPER_BIN" \
  BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$BIN_DIR/SwitchAudioSource" \
  BARISTA_RUNTIME_CONTEXT_INTERVAL=5 \
  CONFIG_DIR="$CONFIG_DIR" \
  "$SCRIPT" daemon >/dev/null 2>&1 &
DAEMON_PID=$!

sleep 0.3

if pgrep -P "$DAEMON_PID" -f 'runtime_context\.sh daemon' >/dev/null 2>&1; then
  echo "FAIL: runtime context daemon should not spawn a nested shell daemon when helper mode is enabled" >&2
  exit 1
fi

if ! pgrep -P "$DAEMON_PID" -f 'runtime_context_helper daemon' >/dev/null 2>&1; then
  echo "FAIL: runtime context daemon should launch the helper daemon directly" >&2
  exit 1
fi

echo "PASS: runtime context daemon launches helper directly"
