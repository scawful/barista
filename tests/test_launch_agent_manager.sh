#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/helpers/launch_agent_manager.sh"
TMP_DIR="$(mktemp -d)"
HOME_DIR="$TMP_DIR/home"
BIN_DIR="$TMP_DIR/bin"
LOG="$TMP_DIR/launchctl.log"
LABEL="com.example.barista-test"
PLIST="$HOME_DIR/Library/LaunchAgents/$LABEL.plist"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$(dirname "$PLIST")" "$BIN_DIR"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
</dict></plist>
EOF

cat > "$BIN_DIR/id" <<'EOF'
#!/bin/bash
[ "${1:-}" = "-u" ] && { printf '501\n'; exit 0; }
exec /usr/bin/id "$@"
EOF
cat > "$BIN_DIR/launchctl" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$LOG"
case "\${1:-}" in
  print) exit "\${TEST_AGENT_LOADED_STATUS:-0}" ;;
esac
exit 0
EOF
chmod +x "$BIN_DIR/id" "$BIN_DIR/launchctl"

HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" TEST_AGENT_LOADED_STATUS=0 \
  bash "$SCRIPT" restart "$LABEL" >/dev/null

expected_restart="$(cat <<EOF
print gui/501/$LABEL
bootout gui/501/$LABEL
bootstrap gui/501 $PLIST
EOF
)"
[ "$(cat "$LOG")" = "$expected_restart" ] || {
  echo "FAIL: restart must perform bootout/bootstrap" >&2
  cat "$LOG" >&2
  exit 1
}

: > "$LOG"
HOME="$HOME_DIR" PATH="$BIN_DIR:/usr/bin:/bin" TEST_AGENT_LOADED_STATUS=0 \
  bash "$SCRIPT" kickstart "$LABEL" >/dev/null

expected_kickstart="$(cat <<EOF
print gui/501/$LABEL
kickstart -kp gui/501/$LABEL
EOF
)"
[ "$(cat "$LOG")" = "$expected_kickstart" ] || {
  echo "FAIL: kickstart must replace only the loaded process" >&2
  cat "$LOG" >&2
  exit 1
}

printf 'test_launch_agent_manager.sh: ok\n'
