#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/home/.config/skhd"
cat > "$TMP_DIR/bin/yabai" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_CALLS"
case "$*" in
  '-m query --windows --window') printf '{"id":42,"space":2}\n' ;;
  '-m space --focus 2') exit 0 ;;
  *) echo "Unexpected command: $*" >&2; exit 1 ;;
esac
STUB
cat > "$TMP_DIR/bin/pgrep" <<'STUB'
#!/bin/bash
printf '123\n'
STUB
cat > "$TMP_DIR/bin/skhd" <<'STUB'
#!/bin/bash
printf 'skhd %s\n' "$*" >> "$TEST_CALLS"
exit 1
STUB
chmod +x "$TMP_DIR/bin/yabai" "$TMP_DIR/bin/pgrep" "$TMP_DIR/bin/skhd"
printf '.load "%s"\n' "$TMP_DIR/home/.config/skhd/barista_shortcuts.conf" > "$TMP_DIR/home/.config/skhd/skhdrc"
printf 'alt - x : /usr/bin/true\n' > "$TMP_DIR/home/.config/skhd/barista_shortcuts.conf"
run_doctor() {
  HOME="$TMP_DIR/home" PATH="$TMP_DIR/bin:$PATH" YABAI_BIN="$TMP_DIR/bin/yabai" \
    SKHD_BIN="$TMP_DIR/bin/skhd" SKHD_CONFIG="$TMP_DIR/home/.config/skhd/skhdrc" \
    TEST_CALLS="$TMP_DIR/calls" "$ROOT_DIR/scripts/yabai_control.sh" doctor "$@" > "$TMP_DIR/output" 2> "$TMP_DIR/error"
}
run_doctor
if grep -Fq -- '--focus' "$TMP_DIR/calls"; then echo 'FAIL: default doctor mutated focus' >&2; exit 1; fi
grep -Fq 'space focus: not probed' "$TMP_DIR/output"
run_doctor --probe-focus
grep -Fxq -- '-m space --focus 2' "$TMP_DIR/calls"
if run_doctor --invalid; then echo 'FAIL: unknown doctor option accepted' >&2; exit 1; fi
printf 'test_yabai_control_doctor.sh: ok\n'
