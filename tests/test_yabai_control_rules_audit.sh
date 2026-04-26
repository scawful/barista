#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/yabai_control.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
EXPECTED_JSON='[
  {"label":"Finder","app":"^Finder$","sub_layer":"below"},
  {"label":"Barista","app":"^Barista$","sub_layer":"below"},
  {"label":"Cortex","app":"^Cortex$","sub_layer":"below"}
]'

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$*" in
  '-m rule --list')
    cat <<'JSON'
[
  {"app":"^Finder$","title":"","manage":false,"sub-layer":"below"},
  {"app":"^Barista$","title":"","manage":false,"sub-layer":"auto"}
]
JSON
    ;;
  '-m query --windows')
    cat <<'JSON'
[
  {"id":1,"app":"Finder","title":"Finder","sub-layer":"normal","layer":"normal","is-minimized":false},
  {"id":2,"app":"ghostty","title":"","sub-layer":"above","layer":"normal","is-minimized":false},
  {"id":3,"app":"Scawfulbot","title":"hello","sub-layer":"normal","layer":"normal","is-minimized":false}
]
JSON
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/yabai"

run_control() {
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_RULES_AUDIT_EXPECTED_JSON="$EXPECTED_JSON" \
    "$SCRIPT" "$@"
}

set +e
TEXT_OUTPUT="$(run_control rules-audit 2>&1)"
TEXT_RC=$?
set -e

[ "$TEXT_RC" -eq 1 ] || {
  echo "FAIL: rules-audit should fail when expected rules are missing or malformed" >&2
  printf '%s\n' "$TEXT_OUTPUT" >&2
  exit 1
}
printf '%s\n' "$TEXT_OUTPUT" | grep -Fq 'expected unmanaged rules: 2/3 present' || {
  echo "FAIL: expected-rule count missing" >&2
  printf '%s\n' "$TEXT_OUTPUT" >&2
  exit 1
}
for expected in missing-rule rule-without-below live-policy-mismatch manual-topmost app-variant-review; do
  printf '%s\n' "$TEXT_OUTPUT" | grep -Fq "$expected" || {
    echo "FAIL: expected finding '$expected'" >&2
    printf '%s\n' "$TEXT_OUTPUT" >&2
    exit 1
  }
done

set +e
JSON_OUTPUT="$(run_control rules-audit --json 2>&1)"
JSON_RC=$?
set -e

[ "$JSON_RC" -eq 1 ] || {
  echo "FAIL: rules-audit --json should preserve failure status" >&2
  printf '%s\n' "$JSON_OUTPUT" >&2
  exit 1
}
RULES_AUDIT_JSON="$JSON_OUTPUT" /usr/bin/python3 - <<'PY'
import json
import os

payload = json.loads(os.environ["RULES_AUDIT_JSON"])
summary = payload["summary"]
types = {item["type"] for item in payload["findings"]}
assert summary["errors"] == 2, summary
assert summary["warnings"] == 2, summary
assert summary["info"] == 1, summary
assert {"missing-rule", "rule-without-below", "live-policy-mismatch", "manual-topmost", "app-variant-review"} <= types
PY

printf 'test_yabai_control_rules_audit.sh: ok\n'
