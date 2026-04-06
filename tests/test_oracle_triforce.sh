#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/oracle_triforce.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
POPUP_FILE="$TMP_DIR/triforce.popup"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"
printf 'off\n' > "$POPUP_FILE"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
LOG_FILE="$LOG_FILE"
POPUP_FILE="$POPUP_FILE"
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "triforce" ]; then
  state=\$(cat "\$POPUP_FILE")
  printf '{\"popup\":{\"drawing\":\"%s\"}}\n' "\$state"
  exit 0
fi
if [ "\${1:-}" = "--set" ] && [ "\${2:-}" = "triforce" ]; then
  shift 2
  for arg in "\$@"; do
    case "\$arg" in
      popup.drawing=on) printf 'on\n' > "\$POPUP_FILE" ;;
      popup.drawing=off) printf 'off\n' > "\$POPUP_FILE" ;;
    esac
  done
fi
printf '%s\n' "\$*" >> "\$LOG_FILE"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=triforce \
  SENDER=mouse.entered \
  "$SCRIPT"

if [ "$(cat "$POPUP_FILE")" != "off" ]; then
  echo "FAIL: hover should not open the popup" >&2
  exit 1
fi

if ! grep -q 'background.drawing=on' "$LOG_FILE"; then
  echo "FAIL: hover should still enable highlight" >&2
  exit 1
fi

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=triforce \
  BARISTA_TRIFORCE_ACTION=click \
  "$SCRIPT"

if [ "$(cat "$POPUP_FILE")" != "on" ]; then
  echo "FAIL: click should open the popup" >&2
  exit 1
fi

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=triforce \
  SENDER=mouse.exited.global \
  "$SCRIPT"

if [ "$(cat "$POPUP_FILE")" != "off" ]; then
  echo "FAIL: leaving the popup area should dismiss the popup" >&2
  exit 1
fi

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=triforce \
  BARISTA_TRIFORCE_ACTION=click \
  "$SCRIPT"

if [ "$(cat "$POPUP_FILE")" != "on" ]; then
  echo "FAIL: click should reopen the popup after dismissal" >&2
  exit 1
fi

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=triforce \
  BARISTA_TRIFORCE_ACTION=click \
  "$SCRIPT"

if [ "$(cat "$POPUP_FILE")" != "off" ]; then
  echo "FAIL: second click should close the popup" >&2
  exit 1
fi

printf 'test_oracle_triforce.sh: ok\n'
