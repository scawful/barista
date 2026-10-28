#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_SCRIPT="${BARISTA_TEST_YABAIRC:-$ROOT_DIR/extras/yabai/yabairc}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/home/.config/sketchybar/scripts"
cat > "$TMP_DIR/bin/yabai" <<'STUB'
#!/bin/sh
printf 'yabai %s\n' "$*" >> "$TEST_CALLS"
exit 0
STUB
cat > "$TMP_DIR/bin/sudo" <<'STUB'
#!/bin/sh
printf 'sudo %s\n' "$*" >> "$TEST_CALLS"
exit 0
STUB
cat > "$TMP_DIR/bin/python3" <<'STUB'
#!/bin/sh
printf 'restore %s\n' "$*" >> "$TEST_CALLS"
exit "${TEST_RESTORE_FAIL:-0}"
STUB
cat > "$TMP_DIR/bin/pgrep" <<'STUB'
#!/bin/sh
exit "${TEST_BAR_RUNNING:-1}"
STUB
chmod +x "$TMP_DIR/bin/yabai" "$TMP_DIR/bin/sudo" "$TMP_DIR/bin/python3" "$TMP_DIR/bin/pgrep"
printf '# fixture\n' > "$TMP_DIR/home/.config/sketchybar/scripts/yabai_restore.py"
printf '# comment\nYaze\nCustom (Beta)' > "$TMP_DIR/home/.config/sketchybar/unmanaged_apps.conf"
run_startup() {
  : > "$TMP_DIR/calls"
  HOME="$TMP_DIR/home" BARISTA_CONFIG_DIR="$TMP_DIR/home/.config/sketchybar" \
    PATH="$TMP_DIR/bin:/usr/bin:/bin" TEST_CALLS="$TMP_DIR/calls" \
    /bin/sh "$CONFIG_SCRIPT" > "$TMP_DIR/out" 2> "$TMP_DIR/err"
}
run_startup
grep -Fxq 'yabai -m rule --add label=claude-window-layer app=^Claude$ role=^AXWindow$ subrole=^AXStandardWindow$ sub-layer=below sticky=off' "$TMP_DIR/calls"
grep -Fq 'event=dock_did_restart action=sudo -n /opt/homebrew/bin/yabai --load-sa' "$TMP_DIR/calls"
grep -Fq 'label=unmanaged-Custom__Beta_ app=^Custom \(Beta\)$ manage=off' "$TMP_DIR/calls"
grep -Fq 'app=^Yaze$ manage=off sub-layer=below' "$TMP_DIR/calls"
grep -Fq 'app=^(Mesen|Mesen2.*)$ manage=off sub-layer=below' "$TMP_DIR/calls"
if grep -Fq 'yabai -m space ' "$TMP_DIR/calls"; then echo 'FAIL: startup must not reset hardcoded space indices' >&2; exit 1; fi
# Only the restack of open windows may follow the global layout.
after_layout="$(sed -n '/^yabai -m config layout bsp$/,$p' "$TMP_DIR/calls" | tail -n +2)"
if ! grep -Fxq 'yabai -m config layout bsp' "$TMP_DIR/calls" \
    || [ "$after_layout" != "restore $TMP_DIR/home/.config/sketchybar/scripts/yabai_restore.py --restack" ]; then
  echo 'FAIL: global layout must follow saved layout pins' >&2; exit 1
fi
printf '%s\n' "$after_layout" | grep -q -- '--restack$' || {
  echo 'FAIL: startup must restack open windows after the global layout' >&2; exit 1
}
before_default="$(grep -Fx -B1 'yabai -m config layout bsp' "$TMP_DIR/calls" | head -n 1)"
case "$before_default" in restore*' --startup') ;; *) echo 'FAIL: saved app defaults and layouts must restore after base/custom rules and before global layout' >&2; exit 1 ;; esac
if [ "$(grep -cF 'yabai -m config layout bsp' "$TMP_DIR/calls")" -ne 1 ]; then echo 'FAIL: startup applies global layout before saved pins' >&2; exit 1; fi
if TEST_RESTORE_FAIL=1 run_startup; then echo 'FAIL: restore failure hidden by startup' >&2; exit 1; fi
grep -Fq 'saved preferences could not be fully restored' "$TMP_DIR/err"
if grep -Fq 'yabai -m config layout bsp' "$TMP_DIR/calls"; then echo 'FAIL: global layout must not run after saved layout restore failure' >&2; exit 1; fi
if grep -Fq 'configuration loaded successfully' "$TMP_DIR/out"; then echo 'FAIL: startup falsely reports success' >&2; exit 1; fi

# A running bar gets the signals it registered back, after everything else.
mkdir -p "$TMP_DIR/home/.local/state/barista"
printf 'printf "replay\\n" >> "$TEST_CALLS"\n' > "$TMP_DIR/home/.local/state/barista/yabai_signals.sh"
TEST_BAR_RUNNING=0 run_startup
[ "$(tail -n 1 "$TMP_DIR/calls")" = replay ] || { echo 'FAIL: startup must replay the bar signals last' >&2; exit 1; }
if TEST_BAR_RUNNING=0 TEST_RESTORE_FAIL=1 run_startup; then echo 'FAIL: restore failure hidden by startup' >&2; exit 1; fi
grep -Fxq replay "$TMP_DIR/calls" || { echo 'FAIL: a failed restore must still give the running bar its signals back' >&2; exit 1; }
TEST_BAR_RUNNING=1 run_startup
if grep -Fxq replay "$TMP_DIR/calls"; then echo 'FAIL: a bar that is not running registers its own signals' >&2; exit 1; fi
printf 'test_yabai_startup.sh: ok\n'
