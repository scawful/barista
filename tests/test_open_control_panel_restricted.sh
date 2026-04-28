#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/bin/open_control_panel.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/config/bin" "$TMP_DIR/config/docs/guides" "$TMP_DIR/source" "$TMP_DIR/path"
printf '{"modes":{"runtime_backend":"lua"},"control_panel":{"preferred":"tui"}}\n' > "$TMP_DIR/config/state.json"
printf 'TUI docs\n' > "$TMP_DIR/config/docs/guides/TUI_CONFIGURATION.md"

cat > "$TMP_DIR/path/open" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$BARISTA_OPEN_LOG"
EOF
chmod +x "$TMP_DIR/path/open"

set +e
PATH="$TMP_DIR/path:/usr/bin:/bin" \
  BARISTA_CONFIG_DIR="$TMP_DIR/config" \
  BARISTA_SOURCE_DIR="$TMP_DIR/source" \
  BARISTA_CONTROL_PANEL=tui \
  BARISTA_RUNTIME_BACKEND=lua \
  BARISTA_OPEN_LOG="$TMP_DIR/open.log" \
  "$SCRIPT" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "FAIL: restricted TUI fallback should exit non-zero when no TUI is available" >&2
  exit 1
fi

if grep -Fq "Building control panel" "$TMP_DIR/stdout" "$TMP_DIR/stderr"; then
  echo "FAIL: restricted TUI fallback should not try to build native panel" >&2
  exit 1
fi

if grep -Fq "Falling back to native control panel" "$TMP_DIR/stderr"; then
  echo "FAIL: restricted TUI fallback should not route to native panel" >&2
  exit 1
fi

grep -Fq "$TMP_DIR/config/state.json" "$TMP_DIR/open.log"
grep -Fq "$TMP_DIR/config/docs/guides/TUI_CONFIGURATION.md" "$TMP_DIR/open.log"

printf 'test_open_control_panel_restricted.sh: ok\n'
