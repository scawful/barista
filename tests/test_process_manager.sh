#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/process_manager.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
SNAPSHOT="$TMP_DIR/ps.txt"

cat > "$SNAPSHOT" <<'PS'
  101     1   0.1  0.2 01:00:00 S /opt/homebrew/opt/sketchybar/bin/sketchybar --config /Users/example/.config/sketchybar/sketchybarrc
  102   101   0.0  0.0 01:00:00 S lua /Users/example/src/lab/barista/sketchybarrc
  201   101   6.0  0.1 00:45 R /bin/sh /Users/example/.config/sketchybar/plugins/space.sh
  202   101   6.5  0.1 00:45 R /bin/sh /Users/example/.config/sketchybar/plugins/space.sh
  203   101   7.0  0.1 00:45 R /bin/sh /Users/example/.config/sketchybar/plugins/space.sh
  204   101   7.5  0.1 00:45 R /bin/sh /Users/example/.config/sketchybar/plugins/space.sh
  301     1  99.0  0.1 00:12 R /bin/bash /Users/example/.config/sketchybar/plugins/space_visuals.sh
PS

barista_output=$(BARISTA_PROCESS_SNAPSHOT="$SNAPSHOT" "$SCRIPT" barista)
printf '%s\n' "$barista_output" | grep -Fq 'PID' || { echo 'FAIL: barista report missing header' >&2; exit 1; }
printf '%s\n' "$barista_output" | grep -Fq 'plugins/space_visuals.sh' || { echo 'FAIL: barista report missing visual process' >&2; exit 1; }

runaways_output=$(BARISTA_PROCESS_SNAPSHOT="$SNAPSHOT" "$SCRIPT" runaways)
printf '%s\n' "$runaways_output" | grep -Fq 'RUNAWAY cpu pid=301' || { echo 'FAIL: hot visual process not flagged' >&2; exit 1; }
printf '%s\n' "$runaways_output" | grep -Fq 'RUNAWAY count kind=space.sh count=4' || { echo 'FAIL: space.sh count not flagged' >&2; exit 1; }

load_output=$(BARISTA_PROCESS_SNAPSHOT="$SNAPSHOT" "$SCRIPT" load)
printf '%s\n' "$load_output" | grep -Fq 'Load snapshot' || { echo 'FAIL: load snapshot missing header' >&2; exit 1; }
printf '%s\n' "$load_output" | grep -Fq 'Top: pid=301 cpu=99.0%' || { echo 'FAIL: load snapshot missing top process' >&2; exit 1; }
printf '%s\n' "$load_output" | grep -Fq 'Barista: processes=7 cpu=126.1%' || { echo 'FAIL: load snapshot missing Barista aggregate' >&2; exit 1; }
printf '%s\n' "$load_output" | grep -Fq 'Runaways: 6 flagged' || { echo 'FAIL: load snapshot missing runaway count' >&2; exit 1; }

dry_run_output=$(BARISTA_PROCESS_SNAPSHOT="$SNAPSHOT" "$SCRIPT" cleanup-runaways)
printf '%s\n' "$dry_run_output" | grep -Fq 'Dry run: would kill Barista runaway PIDs' || { echo 'FAIL: cleanup should dry-run by default' >&2; exit 1; }
printf '%s\n' "$dry_run_output" | grep -Fq '301' || { echo 'FAIL: cleanup dry-run missing hot PID' >&2; exit 1; }

if "$SCRIPT" cleanup-mounts >"$TMP_DIR/mount-cleanup.out" 2>&1; then
  echo 'FAIL: mount cleanup accepted an unspecified target' >&2
  exit 1
fi
grep -Fq 'requires BARISTA_MOUNT_HOST and BARISTA_MOUNT_PATH' "$TMP_DIR/mount-cleanup.out" \
  || { echo 'FAIL: mount cleanup did not explain required target' >&2; exit 1; }

SSHFS_SNAPSHOT="$TMP_DIR/sshfs.txt"
cat > "$SSHFS_SNAPSHOT" <<'PS'
  401 /opt/homebrew/bin/sshfs company-host:/company/tools /Volumes/tools
  402 /opt/homebrew/bin/sshfs company-host:/company/tools-old /Volumes/tools-old
  403 /opt/homebrew/bin/sshfs other-host:/company/tools /Volumes/other
PS
mount_output=$(BARISTA_MOUNTS_TOOL="$TMP_DIR/no-mount-tool" \
  BARISTA_MOUNT_HOST="company-host" \
  BARISTA_MOUNT_PATH="/company/tools" \
  BARISTA_SSHFS_PROCESS_SNAPSHOT="$SSHFS_SNAPSHOT" \
  "$SCRIPT" cleanup-mounts)
printf '%s\n' "$mount_output" | grep -Fq '401' \
  || { echo 'FAIL: exact mount cleanup target was not selected' >&2; exit 1; }
if printf '%s\n' "$mount_output" | grep -Fq '402'; then
  echo 'FAIL: mount cleanup selected a similar but different target' >&2
  exit 1
fi

printf 'test_process_manager.sh: ok\n'
