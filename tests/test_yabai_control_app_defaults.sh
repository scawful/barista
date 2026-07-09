#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/yabai_control.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
STATE_FILE="$TMP_DIR/state.json"
CALLS="$TMP_DIR/yabai_calls.log"
FRONT_CONTEXT="$TMP_DIR/front_app_context.sh"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/yabai" <<'YABAI'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$BARISTA_TEST_YABAI_CALLS"
case "$*" in
  '-m rule --list') printf '[]\n' ;;
  -m\ rule\ --remove*) exit 0 ;;
  -m\ rule\ --add*) exit 0 ;;
  *) exit 0 ;;
esac
YABAI
chmod +x "$BIN_DIR/yabai"

cat > "$FRONT_CONTEXT" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'app_name\tPreview\n'
printf 'space_index\t1\n'
printf 'display_index\t1\n'
EOF
chmod +x "$FRONT_CONTEXT"

run_control() {
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_STATE_FILE="$STATE_FILE" \
    BARISTA_CONFIG_DIR="$TMP_DIR/config" \
    BARISTA_FRONT_APP_CONTEXT_SCRIPT="$FRONT_CONTEXT" \
    BARISTA_TEST_YABAI_CALLS="$CALLS" \
    "$SCRIPT" "$@"
}

run_control app-default set Logic Pro float >/tmp/barista_app_default_out.txt
python3 - "$STATE_FILE" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
rec = data['window_defaults']['apps']['Logic Pro']
assert rec['mode'] == 'float', rec
assert rec['manage'] == 'off', rec
assert rec['sub_layer'] == 'normal', rec
assert rec['rule_label'] == 'barista-default-logic-pro', rec
PY

grep -Fq -- '-m rule --add label=barista-default-logic-pro app=^Logic\ Pro$ manage=off sub-layer=normal' "$CALLS"

run_control app-default set Logic Pro tile >/tmp/barista_app_default_out.txt
python3 - "$STATE_FILE" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
rec = data['window_defaults']['apps']['Logic Pro']
assert rec['mode'] == 'tile', rec
assert rec['manage'] == 'on', rec
PY

grep -Fq -- '-m rule --add label=barista-default-logic-pro app=^Logic\ Pro$ manage=on sub-layer=normal' "$CALLS"

run_control app-default unset Logic Pro >/tmp/barista_app_default_out.txt
python3 - "$STATE_FILE" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
assert data['window_defaults']['apps'] == {}, data
PY

run_control app-default-current float >/tmp/barista_app_default_out.txt
python3 - "$STATE_FILE" <<'PY'
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)
rec = data['window_defaults']['apps']['Preview']
assert rec['mode'] == 'float', rec
assert rec['manage'] == 'off', rec
PY

grep -Fq -- '-m rule --add label=barista-default-preview app=^Preview$ manage=off sub-layer=normal' "$CALLS"

echo 'test_yabai_control_app_defaults.sh: ok'
