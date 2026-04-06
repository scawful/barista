#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/front_app_context.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/yabai" <<'EOF'
#!/bin/bash
set -euo pipefail
case "${FRONT_APP_CONTEXT_TEST_MODE:-window_match}:${1:-}:${2:-}:${3:-}:${4:-}" in
  window_match:-m:query:--spaces:)
    printf '[{"index":3,"display":2,"is-visible":true,"has-focus":true}]\n'
    ;;
  window_match:-m:query:--windows:--window)
    printf ''
    ;;
  window_match:-m:query:--windows:)
    printf '[{"id":10,"app":"Finder","space":3,"display":2,"is-floating":false,"is-sticky":true,"has-fullscreen-zoom":false,"layer":"normal","is-minimized":false}]\n'
    ;;
  no_window:-m:query:--spaces:)
    printf '[{"index":5,"display":1,"is-visible":true,"has-focus":true}]\n'
    ;;
  no_window:-m:query:--windows:--window)
    printf ''
    ;;
  no_window:-m:query:--windows:)
    printf '[]\n'
    ;;
  backfill_window:-m:query:--spaces:)
    printf '[]\n'
    ;;
  backfill_window:-m:query:--windows:--window)
    printf '{"id":22,"app":"Ghostty","space":8,"display":2,"has-focus":true,"is-floating":false,"is-sticky":false,"has-fullscreen-zoom":false,"layer":"normal","is-minimized":false}\n'
    ;;
  backfill_window:-m:query:--windows:)
    printf '[{"id":22,"app":"Ghostty","space":8,"display":2,"has-focus":true,"is-floating":false,"is-sticky":false,"has-fullscreen-zoom":false,"layer":"normal","is-minimized":false}]\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/yabai"

cat > "$BIN_DIR/osascript" <<'EOF'
#!/bin/bash
set -euo pipefail
case "$*" in
  *'name of first process whose frontmost is true'*)
    printf 'Ghostty\n'
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$BIN_DIR/osascript"

JQ_BIN="$(command -v jq)"
[ -n "$JQ_BIN" ] || { echo "FAIL: jq is required for test_front_app_context.sh" >&2; exit 1; }

WINDOW_MATCH_OUTPUT="$(
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    INFO="" \
    FRONT_APP_CONTEXT_TEST_MODE=window_match \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$JQ_BIN" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_RUNTIME_CONTEXT_SCRIPT="$TMP_DIR/missing_runtime_context.sh" \
    "$SCRIPT" --app Finder
)"

printf '%s\n' "$WINDOW_MATCH_OUTPUT" | grep -Fxq $'app_name\tFinder' || { echo "FAIL: helper should preserve explicit app name" >&2; exit 1; }
printf '%s\n' "$WINDOW_MATCH_OUTPUT" | grep -Fxq $'state_label\tTiled · Sticky' || { echo "FAIL: helper should derive tiled sticky state" >&2; exit 1; }
printf '%s\n' "$WINDOW_MATCH_OUTPUT" | grep -Fxq $'location_label\tSpace 3 · Display 2' || { echo "FAIL: helper should derive window location" >&2; exit 1; }

NO_WINDOW_OUTPUT="$(
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    INFO="" \
    FRONT_APP_CONTEXT_TEST_MODE=no_window \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$JQ_BIN" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_RUNTIME_CONTEXT_SCRIPT="$TMP_DIR/missing_runtime_context.sh" \
    "$SCRIPT"
)"

printf '%s\n' "$NO_WINDOW_OUTPUT" | grep -Fxq $'app_name\tGhostty' || { echo "FAIL: helper should fall back to frontmost app name" >&2; exit 1; }
printf '%s\n' "$NO_WINDOW_OUTPUT" | grep -Fxq $'state_label\tNo managed window' || { echo "FAIL: helper should surface unmanaged-window fallback state" >&2; exit 1; }
printf '%s\n' "$NO_WINDOW_OUTPUT" | grep -Fxq $'location_label\tSpace 5 · Display 1' || { echo "FAIL: helper should preserve current space/display fallback" >&2; exit 1; }
printf '%s\n' "$NO_WINDOW_OUTPUT" | grep -Fxq $'space_index\t5' || { echo "FAIL: helper should emit raw current space index in unmanaged fallback" >&2; exit 1; }
printf '%s\n' "$NO_WINDOW_OUTPUT" | grep -Fxq $'display_index\t1' || { echo "FAIL: helper should emit raw current display index in unmanaged fallback" >&2; exit 1; }

BACKFILL_OUTPUT="$(
  PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    INFO="" \
    FRONT_APP_CONTEXT_TEST_MODE=backfill_window \
    BARISTA_YABAI_BIN="$BIN_DIR/yabai" \
    BARISTA_JQ_BIN="$JQ_BIN" \
    BARISTA_OSASCRIPT_BIN="$BIN_DIR/osascript" \
    BARISTA_RUNTIME_CONTEXT_SCRIPT="$TMP_DIR/missing_runtime_context.sh" \
    "$SCRIPT" --mode focused-space --app Ghostty
)"

printf '%s\n' "$BACKFILL_OUTPUT" | grep -Fxq $'space_index\t8' || { echo "FAIL: focused-space mode should backfill raw space index from the selected window when current-space discovery is missing" >&2; exit 1; }
printf '%s\n' "$BACKFILL_OUTPUT" | grep -Fxq $'display_index\t2' || { echo "FAIL: focused-space mode should backfill raw display index from the selected window when current-space discovery is missing" >&2; exit 1; }
printf '%s\n' "$BACKFILL_OUTPUT" | grep -Fxq $'space_visible\ttrue' || { echo "FAIL: focused-space mode should mark the selected focused window as visible when backfilling" >&2; exit 1; }

printf 'test_front_app_context.sh: ok\n'
