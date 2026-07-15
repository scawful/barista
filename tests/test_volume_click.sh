#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
PLUGIN_DIR="$TMP_DIR/plugins"
LIB_DIR="$PLUGIN_DIR/lib"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
POPUP_FILE="$TMP_DIR/volume.popup"
REFRESH_FILE="$TMP_DIR/volume.refresh"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$PLUGIN_DIR" "$LIB_DIR" "$BIN_DIR"
cp "$ROOT_DIR/plugins/volume_click.sh" "$PLUGIN_DIR/volume_click.sh"
cp "$ROOT_DIR/plugins/lib/common.sh" "$LIB_DIR/common.sh"

cat > "$PLUGIN_DIR/volume.sh" <<EOF
#!/bin/bash
set -euo pipefail
printf 'refresh\n' >> "$REFRESH_FILE"
EOF
chmod +x "$PLUGIN_DIR/volume.sh"

printf 'off\n' > "$POPUP_FILE"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
LOG_FILE="$LOG_FILE"
POPUP_FILE="$POPUP_FILE"
if [ "\${1:-}" = "--query" ] && [ "\${2:-}" = "volume" ]; then
  printf 'query\n' >> "\$LOG_FILE"
  state=\$(cat "\$POPUP_FILE")
  printf '{\"popup\":{\"drawing\":\"%s\"}}\n' "\$state"
  exit 0
fi
if [ "\${1:-}" = "--set" ] && [ "\${2:-}" = "volume" ]; then
  shift 2
  for arg in "\$@"; do
    case "\$arg" in
      popup.drawing=on) printf 'on\n' > "\$POPUP_FILE" ;;
      popup.drawing=off) printf 'off\n' > "\$POPUP_FILE" ;;
      popup.drawing=toggle)
        if [ "\$(cat "\$POPUP_FILE")" = "on" ]; then
          printf 'off\n' > "\$POPUP_FILE"
        else
          printf 'on\n' > "\$POPUP_FILE"
        fi
        ;;
    esac
  done
fi
printf '%s\n' "\$*" >> "\$LOG_FILE"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=volume \
  "$PLUGIN_DIR/volume_click.sh"

if [ "$(cat "$POPUP_FILE")" != "on" ]; then
  echo "FAIL: first click should open the volume popup" >&2
  exit 1
fi

if [ "$(wc -l < "$REFRESH_FILE")" -ne 1 ]; then
  echo "FAIL: first click should refresh volume state after toggling" >&2
  exit 1
fi

if grep -Fq 'query' "$LOG_FILE"; then
  echo "FAIL: volume click should not query popup state before toggling" >&2
  exit 1
fi

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  NAME=volume \
  "$PLUGIN_DIR/volume_click.sh"

if [ "$(cat "$POPUP_FILE")" != "off" ]; then
  echo "FAIL: second click should close the volume popup" >&2
  exit 1
fi

if [ "$(wc -l < "$REFRESH_FILE")" -ne 2 ]; then
  echo "FAIL: second click should use the same toggle-then-refresh path" >&2
  exit 1
fi

printf 'test_volume_click.sh: ok\n'
