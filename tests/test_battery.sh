#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/battery.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
PMSET_FIXTURE="$TMP_DIR/pmset.txt"
IOREG_FIXTURE="$TMP_DIR/ioreg.txt"
SKETCHYBAR_LOG="$TMP_DIR/sketchybar.log"
FAST_LOG="$TMP_DIR/battery_fast.log"
PROBE_LOG="$TMP_DIR/probes.log"
EXPECTED_LOG="$TMP_DIR/expected.log"
FAST_BIN="$TMP_DIR/battery_fast"

GREEN_COLOR="test-green"
YELLOW_COLOR="test-yellow"
RED_COLOR="test-red"
BLUE_COLOR="test-blue"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_empty() {
  local path="$1"
  local message="$2"
  [ ! -s "$path" ] || fail "$message"
}

assert_log_matches() {
  if ! cmp -s "$EXPECTED_LOG" "$SKETCHYBAR_LOG"; then
    echo "FAIL: $1" >&2
    diff -u "$EXPECTED_LOG" "$SKETCHYBAR_LOG" >&2 || true
    exit 1
  fi
}

reset_logs() {
  : > "$SKETCHYBAR_LOG"
  : > "$FAST_LOG"
  : > "$PROBE_LOG"
}

run_battery() {
  local action="$1"
  shift
  env \
    PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$TMP_DIR/home" \
    BARISTA_CONFIG_DIR="$TMP_DIR/config" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_TEST_PMSET_FIXTURE="$PMSET_FIXTURE" \
    BARISTA_TEST_IOREG_FIXTURE="$IOREG_FIXTURE" \
    BARISTA_TEST_SKETCHYBAR_LOG="$SKETCHYBAR_LOG" \
    BARISTA_TEST_FAST_LOG="$FAST_LOG" \
    BARISTA_TEST_PROBE_LOG="$PROBE_LOG" \
    BARISTA_BATTERY_FAST_BIN= \
    NAME=battery \
    "$@" \
    "$SCRIPT" \
    "$GREEN_COLOR" "$YELLOW_COLOR" "$RED_COLOR" "$BLUE_COLOR" "$action"
}

mkdir -p "$BIN_DIR" "$TMP_DIR/home" "$TMP_DIR/config"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail
{
  printf '<call>\n'
  printf '%s\n' "$@"
} >> "${BARISTA_TEST_SKETCHYBAR_LOG:?}"
EOF
chmod +x "$BIN_DIR/sketchybar"

cat > "$BIN_DIR/pmset" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$#" -eq 2 ] && [ "$1" = "-g" ] && [ "$2" = "batt" ] || exit 64
printf 'pmset\n' >> "${BARISTA_TEST_PROBE_LOG:?}"
cat "${BARISTA_TEST_PMSET_FIXTURE:?}"
EOF
chmod +x "$BIN_DIR/pmset"

cat > "$BIN_DIR/ioreg" <<'EOF'
#!/bin/bash
set -euo pipefail
[ "$#" -eq 2 ] && [ "$1" = "-rc" ] && [ "$2" = "AppleSmartBattery" ] || exit 64
printf 'ioreg\n' >> "${BARISTA_TEST_PROBE_LOG:?}"
cat "${BARISTA_TEST_IOREG_FIXTURE:?}"
EOF
chmod +x "$BIN_DIR/ioreg"

cat > "$FAST_BIN" <<'EOF'
#!/bin/bash
set -euo pipefail
{
  printf '<call>\n'
  printf '%s\n' "$@"
} >> "${BARISTA_TEST_FAST_LOG:?}"
EOF
chmod +x "$FAST_BIN"

# The portable popup path parses both producers and commits the anchor plus all
# five detail rows in one ordered SketchyBar request.
cat > "$PMSET_FIXTURE" <<'EOF'
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=1234567)	47%; discharging; 3:12 remaining present: true
EOF
cat > "$IOREG_FIXTURE" <<'EOF'
    "CycleCount" = 123
    "BatteryHealth" = "Good"
    "MaxCapacity" = 80
    "AppleRawMaxCapacity" = 4250
    "DesignCapacity" = 5000
EOF
reset_logs
run_battery popup_refresh

cat > "$EXPECTED_LOG" <<EOF
<call>
--set
battery
icon=
label=47%
label.drawing=on
icon.color=$YELLOW_COLOR
label.color=$YELLOW_COLOR
--set
battery.status
label=On Battery
icon=󰁹
icon.color=$YELLOW_COLOR
--set
battery.time
label=3:12 left
icon=󰥔
icon.color=$BLUE_COLOR
--set
battery.power
label=Battery
icon=
icon.color=$BLUE_COLOR
--set
battery.cycle
label=123 cycles
icon=󰑓
icon.color=$BLUE_COLOR
--set
battery.health
label=85%
icon=󰓽
icon.color=$GREEN_COLOR
EOF
assert_log_matches "battery refresh should issue one exact, ordered batched update"
[ "$(grep -c '^<call>$' "$SKETCHYBAR_LOG")" -eq 1 ] \
  || fail "battery refresh should invoke SketchyBar exactly once"
[ "$(cat "$PROBE_LOG")" = $'pmset\nioreg' ] \
  || fail "portable battery refresh should query pmset and ioreg exactly once"

# AC power retains precedence over a raw charged state. An explicit popup
# refresh bypasses the native routine owner, and no-estimate stays hidden.
cat > "$PMSET_FIXTURE" <<'EOF'
Now drawing from 'AC Power'
 -InternalBattery-0 (id=1234567)	100%; charged; (no estimate) present: true
EOF
cat > "$IOREG_FIXTURE" <<'EOF'
    "BatteryHealth" = "Good"
EOF
reset_logs
run_battery popup_refresh BARISTA_BATTERY_FAST_BIN="$FAST_BIN"

cat > "$EXPECTED_LOG" <<EOF
<call>
--set
battery
icon=
label=100%
label.drawing=on
icon.color=$BLUE_COLOR
label.color=$BLUE_COLOR
--set
battery.status
label=Charging
icon=󰁹
icon.color=$BLUE_COLOR
--set
battery.time
label=Charging
icon=󰥔
icon.color=$BLUE_COLOR
--set
battery.power
label=AC
icon=
icon.color=$BLUE_COLOR
--set
battery.cycle
label=— cycles
icon=󰑓
icon.color=$BLUE_COLOR
--set
battery.health
label=Good
icon=󰓽
icon.color=$GREEN_COLOR
EOF
assert_log_matches "AC plus charged should remain Charging without exposing no-estimate"
assert_empty "$FAST_LOG" "popup_refresh should bypass the native routine owner"
if grep -Fqi -- 'no estimate' "$SKETCHYBAR_LOG"; then
  fail "no-estimate text should not reach a popup label"
fi

# Keep the portable label/icon preferences and the historical awk-style
# round-to-even health result while using only Bash arithmetic.
cat > "$PMSET_FIXTURE" <<'EOF'
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=1234567)	19%; discharging; 0:42 remaining present: true
EOF
cat > "$IOREG_FIXTURE" <<'EOF'
    "CycleCount" = 2
    "BatteryHealth" = "Good"
    "MaxCapacity" = 169
    "DesignCapacity" = 200
EOF
reset_logs
run_battery popup_refresh \
  BARISTA_BATTERY_LABEL_MODE=icon \
  BARISTA_ICON_BATTERY=custom-icon
[ "$(grep -c '^<call>$' "$SKETCHYBAR_LOG")" -eq 1 ] \
  || fail "custom battery refresh should still invoke SketchyBar exactly once"
grep -Fxq 'icon=custom-icon' "$SKETCHYBAR_LOG" \
  || fail "battery icon override should be retained"
grep -Fxq 'label=' "$SKETCHYBAR_LOG" \
  || fail "icon-only mode should clear the battery label"
grep -Fxq 'label.drawing=off' "$SKETCHYBAR_LOG" \
  || fail "icon-only mode should hide the battery label"
grep -Fxq "icon.color=$RED_COLOR" "$SKETCHYBAR_LOG" \
  || fail "battery percentages below 20 should remain red"
grep -Fxq 'label=84%' "$SKETCHYBAR_LOG" \
  || fail "health percentage ties should retain awk round-to-even behavior"

# A normal routine event is owned entirely by the executable native helper.
reset_logs
run_battery "" SENDER=routine BARISTA_BATTERY_FAST_BIN="$FAST_BIN"
cat > "$EXPECTED_LOG" <<'EOF'
<call>
update
battery
EOF
if ! cmp -s "$EXPECTED_LOG" "$FAST_LOG"; then
  echo "FAIL: routine update should delegate exactly to 'update battery'" >&2
  diff -u "$EXPECTED_LOG" "$FAST_LOG" >&2 || true
  exit 1
fi
assert_empty "$SKETCHYBAR_LOG" "native-owned routine should not call shell SketchyBar"
assert_empty "$PROBE_LOG" "native-owned routine should not run pmset or ioreg"

# Preserve the historical set -e contract: a successful pmset response with no
# percentage exits 1 before probing ioreg or updating SketchyBar.
cat > "$PMSET_FIXTURE" <<'EOF'
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=1234567); discharging; no estimate
EOF
reset_logs
set +e
run_battery popup_refresh
rc=$?
set -e
[ "$rc" -eq 1 ] || fail "missing battery percentage should return 1 (got $rc)"
assert_empty "$SKETCHYBAR_LOG" "missing percentage should not update SketchyBar"
[ "$(cat "$PROBE_LOG")" = "pmset" ] \
  || fail "missing percentage should stop before the ioreg probe"

printf 'test_battery.sh: ok\n'
