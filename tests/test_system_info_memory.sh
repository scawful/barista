#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/system_info.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
NATIVE_BIN="$TMP_DIR/system_info_widget"
NATIVE_LOG="$TMP_DIR/system_info_widget.log"
JQ_LOG="$TMP_DIR/jq.log"
DETAIL_LOG="$TMP_DIR/detail_probes.log"
STATE_FILE="$TMP_DIR/state.json"
REAL_JQ="$(command -v jq 2>/dev/null || true)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR" "$TMP_DIR/home"
printf '{"system_info_items":{}}\n' > "$STATE_FILE"

cat > "$BIN_DIR/sketchybar" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "${BARISTA_TEST_SKETCHYBAR_LOG:?}"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

cat > "$NATIVE_BIN" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "${BARISTA_TEST_NATIVE_LOG:?}"
exit "${BARISTA_TEST_NATIVE_RC:-0}"
EOF
chmod +x "$NATIVE_BIN"

# Log state reads while still exercising the real jq filter when jq is
# available. The fallback keeps this test portable on hosts without jq.
cat > "$BIN_DIR/jq" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'jq\n' >> "${BARISTA_TEST_JQ_LOG:?}"
if [ -n "${BARISTA_TEST_REAL_JQ:-}" ]; then
  exec "$BARISTA_TEST_REAL_JQ" "$@"
fi
printf '0\t1\t1\t1\t1\t1\t0\n'
EOF
chmod +x "$BIN_DIR/jq"

cat > "$BIN_DIR/sysctl" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-n" ]; then
  case "${2:-}" in
    hw.pagesize) printf '16384\n' ;;
    hw.memsize) printf '34359738368\n' ;;
    vm.loadavg) printf '{ 1.23 1.00 0.98 }\n' ;;
    hw.ncpu) printf '8\n' ;;
    vm.swapusage)
      printf 'sysctl %s\n' "$2" >> "${BARISTA_TEST_DETAIL_LOG:?}"
      printf 'total = 2.00G  used = 0.50G  free = 1.50G\n'
      ;;
    kern.boottime)
      printf 'sysctl %s\n' "$2" >> "${BARISTA_TEST_DETAIL_LOG:?}"
      printf '{ sec = 1700000000, usec = 0 }\n'
      ;;
    *) exit 1 ;;
  esac
  exit 0
fi
exit 1
EOF
chmod +x "$BIN_DIR/sysctl"

cat > "$BIN_DIR/vm_stat" <<'EOF'
#!/bin/bash
set -euo pipefail
cat <<'VM'
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                                1000.
Pages active:                            700000.
Pages inactive:                          300000.
Pages speculative:                        10000.
Pages throttled:                              0.
Pages wired down:                        500000.
Pages purgeable:                          65536.
"Translation faults":                  59339189.
Pages copy-on-write:                    5498496.
Pages zero filled:                     22923389.
Pages reactivated:                      2335104.
Pages purged:                            375678.
File-backed pages:                       200000.
Anonymous pages:                        720896.
Pages stored in compressor:             300000.
Pages occupied by compressor:            65536.
VM
EOF
chmod +x "$BIN_DIR/vm_stat"

cat > "$BIN_DIR/memory_pressure" <<'EOF'
#!/bin/bash
set -euo pipefail
cat <<'PRESSURE'
The system has 34359738368 (2097152 pages with a page size of 16384).
System-wide memory free percentage: 66%
PRESSURE
EOF
chmod +x "$BIN_DIR/memory_pressure"

cat > "$BIN_DIR/df" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'df\n' >> "${BARISTA_TEST_DETAIL_LOG:?}"
printf 'Filesystem Size Used Avail Capacity Mounted on\n/dev/disk3s1 460Gi 120Gi 320Gi 28%% /\n'
EOF
chmod +x "$BIN_DIR/df"

cat > "$BIN_DIR/ipconfig" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'ipconfig\n' >> "${BARISTA_TEST_DETAIL_LOG:?}"
printf '192.168.1.5\n'
EOF
chmod +x "$BIN_DIR/ipconfig"

cat > "$BIN_DIR/networksetup" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'networksetup\n' >> "${BARISTA_TEST_DETAIL_LOG:?}"
case "${1:-}" in
  -listallhardwareports)
    printf 'Hardware Port: Wi-Fi\nDevice: en0\n'
    ;;
  -getairportnetwork)
    printf 'Current Wi-Fi Network: TestNet\n'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$BIN_DIR/networksetup"

cat > "$BIN_DIR/route" <<'EOF'
#!/bin/bash
set -euo pipefail
printf 'route\n' >> "${BARISTA_TEST_DETAIL_LOG:?}"
printf 'interface: en0\n'
EOF
chmod +x "$BIN_DIR/route"

run_system_info() {
  env \
    PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$TMP_DIR/home" \
    BARISTA_CONFIG_DIR="$TMP_DIR" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_TEST_SKETCHYBAR_LOG="$LOG_FILE" \
    BARISTA_TEST_NATIVE_LOG="$NATIVE_LOG" \
    BARISTA_TEST_JQ_LOG="$JQ_LOG" \
    BARISTA_TEST_DETAIL_LOG="$DETAIL_LOG" \
    BARISTA_TEST_REAL_JQ="$REAL_JQ" \
    STATE_FILE="$STATE_FILE" \
    NAME=system_info \
    "$@"
}

# A successful routine helper owns the update and skips all shell metrics.
: > "$LOG_FILE"
: > "$NATIVE_LOG"
: > "$JQ_LOG"
: > "$DETAIL_LOG"
run_system_info \
  SENDER=routine \
  SYSTEM_INFO_BIN="$NATIVE_BIN" \
  "$SCRIPT"
if [ ! -s "$NATIVE_LOG" ]; then
  echo "FAIL: routine system info updates should attempt the native helper" >&2
  exit 1
fi
if [ -s "$LOG_FILE" ]; then
  echo "FAIL: a successful native routine update should skip the shell refresh" >&2
  exit 1
fi
if [ -s "$JQ_LOG" ]; then
  echo "FAIL: a successful native routine update should not read state.json" >&2
  exit 1
fi

# An explicit native-disable boundary ignores a stale executable and uses the
# portable implementation, matching Lua-only/restricted profiles.
: > "$LOG_FILE"
: > "$NATIVE_LOG"
: > "$JQ_LOG"
: > "$DETAIL_LOG"
run_system_info \
  SENDER=routine \
  SYSTEM_INFO_BIN="$NATIVE_BIN" \
  BARISTA_SYSTEM_INFO_NATIVE_DISABLE=1 \
  BARISTA_SYSTEM_INFO_ROWS=mem \
  "$SCRIPT"
if [ -s "$NATIVE_LOG" ]; then
  echo "FAIL: native-disabled routine updates should not execute a stale helper" >&2
  exit 1
fi
grep -Fq -- '--set system_info ' "$LOG_FILE" || {
  echo "FAIL: native-disabled routine updates should retain the shell main update" >&2
  exit 1
}
if grep -Fq -- '--set system_info.' "$LOG_FILE" || [ -s "$DETAIL_LOG" ]; then
  echo "FAIL: native-disabled routine updates should skip popup updates and detail probes" >&2
  exit 1
fi

# A native failure falls through to the portable shell implementation.
: > "$LOG_FILE"
: > "$NATIVE_LOG"
: > "$JQ_LOG"
: > "$DETAIL_LOG"
run_system_info \
  SENDER=routine \
  SYSTEM_INFO_BIN="$NATIVE_BIN" \
  BARISTA_TEST_NATIVE_RC=7 \
  "$SCRIPT"
if [ ! -s "$NATIVE_LOG" ]; then
  echo "FAIL: routine system info updates should attempt the native helper before fallback" >&2
  exit 1
fi
grep -Fq -- '--set system_info ' "$LOG_FILE" || {
  echo "FAIL: a failed native routine update should retain the main shell update" >&2
  exit 1
}
if grep -Fq -- '--set system_info.' "$LOG_FILE" || [ -s "$DETAIL_LOG" ]; then
  echo "FAIL: a failed native routine update should skip popup updates and detail probes" >&2
  exit 1
fi
if [ -s "$JQ_LOG" ]; then
  echo "FAIL: a failed native routine update should not read popup topology state" >&2
  exit 1
fi

# An explicit popup fallback never retries the native helper.
: > "$LOG_FILE"
: > "$NATIVE_LOG"
: > "$JQ_LOG"
run_system_info \
  SENDER=routine \
  SYSTEM_INFO_BIN="$NATIVE_BIN" \
  BARISTA_SYSTEM_INFO_ROWS=mem \
  "$SCRIPT" popup_refresh
if [ -s "$NATIVE_LOG" ]; then
  echo "FAIL: an explicit popup fallback must not retry the native helper" >&2
  exit 1
fi
grep -Fq -- '--set system_info.mem ' "$LOG_FILE" || {
  echo "FAIL: an explicit popup fallback should complete through the shell path" >&2
  exit 1
}

# The exact environment allowlist gates every dynamic row without JSON state.
: > "$LOG_FILE"
: > "$NATIVE_LOG"
: > "$JQ_LOG"
run_system_info \
  SYSTEM_INFO_BIN="$NATIVE_BIN" \
  BARISTA_SYSTEM_INFO_ROWS=mem,uptime \
  "$SCRIPT" popup_refresh
grep -Fq -- '--set system_info.mem ' "$LOG_FILE" || {
  echo "FAIL: the enabled memory row should be refreshed" >&2
  exit 1
}
grep -Fq -- '--set system_info.uptime ' "$LOG_FILE" || {
  echo "FAIL: the enabled uptime row should be refreshed" >&2
  exit 1
}
for disabled_row in cpu disk net swap procs; do
  if grep -Fq -- "--set system_info.$disabled_row " "$LOG_FILE"; then
    echo "FAIL: disabled row $disabled_row should not be targeted" >&2
    exit 1
  fi
done
if [ "$(wc -l < "$LOG_FILE" | tr -d ' ')" -ne 2 ]; then
  echo "FAIL: the row subset should emit exactly two SketchyBar updates" >&2
  exit 1
fi
if [ -s "$JQ_LOG" ]; then
  echo "FAIL: BARISTA_SYSTEM_INFO_ROWS should bypass state.json" >&2
  exit 1
fi

# `none` is the explicit empty allowlist and should do no popup work.
: > "$LOG_FILE"
: > "$JQ_LOG"
run_system_info \
  SYSTEM_INFO_BIN="$NATIVE_BIN" \
  BARISTA_SYSTEM_INFO_ROWS=none \
  "$SCRIPT" popup_refresh
if [ -s "$LOG_FILE" ] || [ -s "$JQ_LOG" ]; then
  echo "FAIL: the none allowlist should avoid dynamic updates and JSON state" >&2
  exit 1
fi

# Malformed or unknown row lists fail closed instead of partially targeting a
# popup topology that may not exist.
: > "$LOG_FILE"
if run_system_info \
  SYSTEM_INFO_BIN="$NATIVE_BIN" \
  BARISTA_SYSTEM_INFO_ROWS=mem,unknown \
  "$SCRIPT" popup_refresh >/dev/null 2>&1; then
  echo "FAIL: an invalid row allowlist should be rejected" >&2
  exit 1
fi
if [ -s "$LOG_FILE" ]; then
  echo "FAIL: an invalid row allowlist should not issue partial updates" >&2
  exit 1
fi

# Without an environment allowlist, state is read once and missing flags keep
# the compatibility defaults: CPU/procs off, the other five dynamic rows on.
: > "$LOG_FILE"
: > "$JQ_LOG"
run_system_info \
  SYSTEM_INFO_BIN="$TMP_DIR/missing-system-info-widget" \
  "$SCRIPT" popup_refresh
if [ "$(wc -l < "$JQ_LOG" | tr -d ' ')" -ne 1 ]; then
  echo "FAIL: portable row discovery should read state.json exactly once" >&2
  exit 1
fi
for default_row in mem disk net swap uptime; do
  grep -Fq -- "--set system_info.$default_row " "$LOG_FILE" || {
    echo "FAIL: missing $default_row state should preserve its enabled default" >&2
    exit 1
  }
done
for default_off_row in cpu procs; do
  if grep -Fq -- "--set system_info.$default_off_row " "$LOG_FILE"; then
    echo "FAIL: missing $default_off_row state should preserve its disabled default" >&2
    exit 1
  fi
done

grep -Fq 'label=Memory: 11/32G (34%)' "$LOG_FILE" || {
  echo "FAIL: memory popup should use anonymous plus compressed memory instead of active+wired totals" >&2
  exit 1
}

printf 'test_system_info_memory.sh: ok\n'
