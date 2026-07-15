#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/process_manager.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
SNAPSHOT="$TMP_DIR/ps.txt"

cat > "$SNAPSHOT" <<'PS'
  101     1   0.1  0.2 01:00:00 S /opt/homebrew/opt/sketchybar/bin/sketchybar --config /Users/scawful/.config/sketchybar/sketchybarrc
  102   101   0.0  0.0 01:00:00 S lua /Users/scawful/src/lab/barista/sketchybarrc
  201   101   6.0  0.1 00:45 R /bin/sh /Users/scawful/.config/sketchybar/plugins/space.sh
  202   101   6.5  0.1 00:45 R /bin/sh /Users/scawful/.config/sketchybar/plugins/space.sh
  203   101   7.0  0.1 00:45 R /bin/sh /Users/scawful/.config/sketchybar/plugins/space.sh
  204   101   7.5  0.1 00:45 R /bin/sh /Users/scawful/.config/sketchybar/plugins/space.sh
  301     1  99.0  0.1 00:12 R /bin/bash /Users/scawful/.config/sketchybar/plugins/space_visuals.sh
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

printf 'test_process_manager.sh: ok\n'
