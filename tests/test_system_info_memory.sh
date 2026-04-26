#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/system_info.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
LOG_FILE="$TMP_DIR/sketchybar.log"
STATE_FILE="$TMP_DIR/state.json"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$BIN_DIR"
printf '{"system_info_items":{"cpu":false,"procs":false}}\n' > "$STATE_FILE"

cat > "$BIN_DIR/sketchybar" <<EOF
#!/bin/bash
set -euo pipefail
printf '%s\n' "\$*" >> "$LOG_FILE"
exit 0
EOF
chmod +x "$BIN_DIR/sketchybar"

cat > "$BIN_DIR/sysctl" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "${1:-}" = "-n" ]; then
  case "${2:-}" in
    hw.pagesize) printf '16384\n' ;;
    hw.memsize) printf '34359738368\n' ;;
    vm.loadavg) printf '{ 1.23 1.00 0.98 }\n' ;;
    hw.ncpu) printf '8\n' ;;
    vm.swapusage) printf 'total = 2.00G  used = 0.50G  free = 1.50G\n' ;;
    kern.boottime) printf '{ sec = 1700000000, usec = 0 }\n' ;;
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
printf 'Filesystem Size Used Avail Capacity Mounted on\n/dev/disk3s1 460Gi 120Gi 320Gi 28%% /\n'
EOF
chmod +x "$BIN_DIR/df"

cat > "$BIN_DIR/ipconfig" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '192.168.1.5\n'
EOF
chmod +x "$BIN_DIR/ipconfig"

cat > "$BIN_DIR/networksetup" <<'EOF'
#!/bin/bash
set -euo pipefail
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
printf 'interface: en0\n'
EOF
chmod +x "$BIN_DIR/route"

PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
  STATE_FILE="$STATE_FILE" \
  NAME="system_info" \
  "$SCRIPT" popup_refresh

grep -Fq 'label=Memory: 11/32G (34%)' "$LOG_FILE" || {
  echo "FAIL: memory popup should use anonymous plus compressed memory instead of active+wired totals" >&2
  exit 1
}

printf 'test_system_info_memory.sh: ok\n'
