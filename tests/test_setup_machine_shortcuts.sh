#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

STATE_FILE="$TMP_DIR/state.json"
MACHINE_FILE="$TMP_DIR/machine.local.json"
SKHD_FILE="$TMP_DIR/home/.config/skhd/barista_shortcuts.conf"
WORKFLOW_FILE="$TMP_DIR/workflow_shortcuts.local.generated.json"
SKHD_CONFIG_FILE="$TMP_DIR/home/.config/skhd/skhdrc"

cat >"$STATE_FILE" <<'JSON'
{
  "profile": "personal",
  "menus": {
    "calendar": {
      "task_provider": "syshelp",
      "task_sources": ["~/private/personal-tasks.md"]
    }
  },
  "widgets": {
    "task_focus": true
  }
}
JSON

mkdir -p "$(dirname "$SKHD_FILE")"
cat >"$SKHD_FILE" <<'SKHD'
# stale personal capture binding
cmd + alt - n : BARISTA_CALENDAR_TASK_SOURCES='~/private/personal-tasks.md' '/tmp/task_capture.sh'
SKHD

HOME="$TMP_DIR/home" \
  BARISTA_RELOAD_SKHD=0 \
  BARISTA_SKHD_CONFIG_FILE="$SKHD_CONFIG_FILE" \
  BARISTA_SKHD_SHORTCUTS_FILE="$SKHD_FILE" \
  BARISTA_RUNTIME_WORKFLOW_FILE="$WORKFLOW_FILE" \
  "$ROOT_DIR/scripts/setup_machine.sh" \
    --state "$STATE_FILE" \
    --machine-file "$MACHINE_FILE" \
    --profile-variant work \
    --skip-fonts \
    --skip-panel \
    --skip-work-apps \
    --yes \
    --no-reload >/dev/null

jq -e '.menus.calendar.task_sources == [] and .widgets.task_focus == false' "$STATE_FILE" >/dev/null
grep -Fq '# barista-action: open_task_focus' "$SKHD_FILE"
if grep -Fq 'barista-action: capture_task' "$SKHD_FILE" \
  || grep -Fq 'personal-tasks.md' "$SKHD_FILE" \
  || grep -Fq 'cmd + alt - n :' "$SKHD_FILE"; then
  echo "FAIL: Work profile left a stale personal capture shortcut" >&2
  exit 1
fi
jq -e '.keymap[0].items[] | select(.action == "capture_task" and .requires == "task_source")' \
  "$WORKFLOW_FILE" >/dev/null
grep -Fqx ".load \"$SKHD_FILE\"" "$SKHD_CONFIG_FILE"

cat >"$SKHD_FILE" <<'SKHD'
# stale restricted-work task bindings
cmd + alt - d : BARISTA_CALENDAR_TASK_SOURCES='~/private/restricted-tasks.md' '/tmp/task_focus.sh'
cmd + alt - n : BARISTA_CALENDAR_TASK_SOURCES='~/private/restricted-tasks.md' '/tmp/task_capture.sh'
SKHD

HOME="$TMP_DIR/home" \
  BARISTA_RELOAD_SKHD=0 \
  BARISTA_SKHD_CONFIG_FILE="$SKHD_CONFIG_FILE" \
  BARISTA_SKHD_SHORTCUTS_FILE="$SKHD_FILE" \
  BARISTA_RUNTIME_WORKFLOW_FILE="$WORKFLOW_FILE" \
  "$ROOT_DIR/scripts/setup_machine.sh" \
    --state "$STATE_FILE" \
    --machine-file "$MACHINE_FILE" \
    --restricted-work \
    --skip-work-apps \
    --yes \
    --no-reload >/dev/null

grep -Fq '# barista-action: open_task_focus' "$SKHD_FILE"
if grep -Fq 'restricted-tasks.md' "$SKHD_FILE" \
  || grep -Fq 'barista-action: capture_task' "$SKHD_FILE" \
  || grep -Fq 'cmd + alt - n :' "$SKHD_FILE"; then
  echo "FAIL: restricted Work left stale personal task bindings" >&2
  exit 1
fi

[ "$(grep -Fxc ".load \"$SKHD_FILE\"" "$SKHD_CONFIG_FILE")" -eq 1 ] || {
  echo "FAIL: setup duplicated the generated shortcut include" >&2
  exit 1
}

printf 'test_setup_machine_shortcuts.sh: ok\n'
