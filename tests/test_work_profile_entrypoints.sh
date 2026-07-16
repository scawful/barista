#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
STATE_FILE="$TMP_DIR/state.json"
SWITCH_STATE="$TMP_DIR/switch-state.json"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_DIR/home" "$TMP_DIR/bin"
cat >"$TMP_DIR/bin/yabai" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP_DIR/bin/yabai"
cat > "$STATE_FILE" <<'JSON'
{
  "_version": 2,
  "profile": "personal",
  "modes": {"window_manager": "auto"},
  "widgets": {"task_focus": true},
  "integrations": {
    "oracle": {"enabled": true},
    "music": {"enabled": true},
    "journal": {"enabled": true},
    "nerv": {"enabled": true},
    "yaze": {"enabled": true},
    "halext": {"enabled": true},
    "halext_org": {"enabled": true},
    "workspace": {"enabled": true},
    "unrelated": {"enabled": true, "keep": "yes"}
  },
  "menus": {
    "calendar": {
      "task_provider": "syshelp",
      "task_sources": ["~/personal/tasks.md"],
      "meeting_cache_file": "~/personal/events.tsv",
      "syshelp_path": "/Users/personal/bin/syshelp"
    }
  }
}
JSON
cp "$STATE_FILE" "$SWITCH_STATE"

HOME="$TMP_DIR/home" \
  PATH="$TMP_DIR/bin:$PATH" \
  BARISTA_RELOAD_SKHD=0 \
  BARISTA_SKHD_CONFIG_FILE="$TMP_DIR/home/.config/skhd/skhdrc" \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  "$ROOT_DIR/scripts/setup_machine.sh" \
    --state "$STATE_FILE" \
    --profile-variant work \
    --window-manager required \
    --skip-fonts \
    --skip-panel \
    --skip-work-apps \
    --yes \
    --no-reload >/dev/null

SKHD_FILE="$TMP_DIR/home/.config/skhd/barista_shortcuts.conf"
grep -Fq '# barista-action: toggle_yabai_shortcuts' "$SKHD_FILE"

jq -e '. as $state |
  .profile == "work" and
  .modes.window_manager == "required" and
  .widgets.task_focus == false and
  .menus.calendar.task_provider == "files" and
  .menus.calendar.task_sources == [] and
  .menus.calendar.meeting_cache_file == "" and
  .menus.calendar.syshelp_path == "" and
  (["oracle","music","journal","nerv","yaze","halext","halext_org","workspace"] | all(. as $name | $state.integrations[$name].enabled == false)) and
  .integrations.unrelated == {"enabled":true,"keep":"yes"}
' "$STATE_FILE" >/dev/null

HOME="$TMP_DIR/home" \
  PATH="$TMP_DIR/bin:$PATH" \
  BARISTA_RELOAD_SKHD=0 \
  BARISTA_SKHD_CONFIG_FILE="$TMP_DIR/home/.config/skhd/skhdrc" \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_STATE_FILE="$STATE_FILE" \
  BARISTA_NO_RELOAD=1 \
  "$ROOT_DIR/scripts/set_mode.sh" work disabled >/dev/null

jq -e '.modes.window_manager == "disabled" and .toggles.yabai_shortcuts == false' "$STATE_FILE" >/dev/null
if grep -Fq '# barista-action: toggle_yabai_shortcuts' "$SKHD_FILE" \
  || grep -Fq '# barista-action: space_prev' "$SKHD_FILE"; then
  echo "FAIL: disabled Work mode left generated window-manager bindings" >&2
  exit 1
fi

HOME="$TMP_DIR/home-switch" \
  PATH="$TMP_DIR/bin:$PATH" \
  BARISTA_RELOAD_SKHD=0 \
  BARISTA_SKHD_CONFIG_FILE="$TMP_DIR/home-switch/.config/skhd/skhdrc" \
  BARISTA_CONFIG_DIR="$ROOT_DIR" \
  BARISTA_STATE_FILE="$SWITCH_STATE" \
  BARISTA_NO_RELOAD=1 \
  "$ROOT_DIR/scripts/set_mode.sh" work disabled >/dev/null

jq -e '.profile == "work" and
  .modes.window_manager == "disabled" and
  .widgets.task_focus == true and
  .menus.calendar.task_provider == "syshelp" and
  .menus.calendar.task_sources == ["~/personal/tasks.md"] and
  .menus.calendar.meeting_cache_file == "~/personal/events.tsv" and
  .menus.calendar.syshelp_path == "/Users/personal/bin/syshelp" and
  .integrations.oracle.enabled == true and
  .integrations.music.enabled == true
' "$SWITCH_STATE" >/dev/null

grep -Fq 'INTEGRATION_HALEXT=false' "$ROOT_DIR/scripts/install.sh"
grep -Fq -- '--exclude "/state.json"' "$ROOT_DIR/scripts/install.sh"
grep -Fq -- '--exclude "/barista_config.lua"' "$ROOT_DIR/scripts/install.sh"
grep -Fq -- '--exclude "/data/interface_extensions.local.json"' "$ROOT_DIR/scripts/install.sh"

PRIVACY_SOURCE="$TMP_DIR/install-source"
PRIVACY_DEST="$TMP_DIR/install-dest"
mkdir -p \
  "$PRIVACY_SOURCE/data" \
  "$PRIVACY_SOURCE/docs/dev/.context.pruned-test/history" \
  "$PRIVACY_SOURCE/nested/.context/history" \
  "$PRIVACY_SOURCE/.claude" \
  "$PRIVACY_SOURCE/scripts/__pycache__" \
  "$PRIVACY_SOURCE/gui/bin" \
  "$PRIVACY_DEST"
cp "$ROOT_DIR/.gitignore" "$PRIVACY_SOURCE/.gitignore"
touch \
  "$PRIVACY_SOURCE/README.md" \
  "$PRIVACY_SOURCE/state.json" \
  "$PRIVACY_SOURCE/state.json.bak" \
  "$PRIVACY_SOURCE/barista_config.lua" \
  "$PRIVACY_SOURCE/barista_config.lua.bak" \
  "$PRIVACY_SOURCE/data/interface_extensions.local.json" \
  "$PRIVACY_SOURCE/data/project_shortcuts.json.tmp" \
  "$PRIVACY_SOURCE/docs/dev/.context.pruned-test/history/events.jsonl" \
  "$PRIVACY_SOURCE/nested/.context/history/events.jsonl" \
  "$PRIVACY_SOURCE/.spaces_cache" \
  "$PRIVACY_SOURCE/.spaces_active_cache" \
  "$PRIVACY_SOURCE/.spaces_signatures" \
  "$PRIVACY_SOURCE/.claude/local.md" \
  "$PRIVACY_SOURCE/scripts/__pycache__/local.pyc" \
  "$PRIVACY_SOURCE/gui/bin/help_center"
git -C "$PRIVACY_SOURCE" init -q
git -C "$PRIVACY_SOURCE" add .gitignore README.md
git -C "$PRIVACY_SOURCE" add -f gui/bin/help_center

# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/install.sh"
copy_local_config "$PRIVACY_SOURCE" "$PRIVACY_DEST"
test -f "$PRIVACY_DEST/README.md"
test ! -e "$PRIVACY_DEST/state.json"
test ! -e "$PRIVACY_DEST/state.json.bak"
test ! -e "$PRIVACY_DEST/barista_config.lua"
test ! -e "$PRIVACY_DEST/barista_config.lua.bak"
test ! -e "$PRIVACY_DEST/data/interface_extensions.local.json"
test ! -e "$PRIVACY_DEST/data/project_shortcuts.json.tmp"
test ! -e "$PRIVACY_DEST/docs/dev/.context.pruned-test"
test ! -e "$PRIVACY_DEST/nested/.context"
test ! -e "$PRIVACY_DEST/.spaces_cache"
test ! -e "$PRIVACY_DEST/.spaces_active_cache"
test ! -e "$PRIVACY_DEST/.spaces_signatures"
test ! -e "$PRIVACY_DEST/.claude"
test ! -e "$PRIVACY_DEST/scripts/__pycache__"
test -f "$PRIVACY_DEST/gui/bin/help_center"

INSTALL_RUNTIME="$TMP_DIR/install-runtime"
INSTALL_ARGS_LOG="$TMP_DIR/install-setup-args.log"
mkdir -p "$INSTALL_RUNTIME/scripts"
cat > "$INSTALL_RUNTIME/scripts/setup_machine.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$@" >"${INSTALL_ARGS_LOG:?}"
SH
chmod +x "$INSTALL_RUNTIME/scripts/setup_machine.sh"

# shellcheck disable=SC2034  # consumed by sourced installer functions
INSTALL_DIR="$INSTALL_RUNTIME"
export BARISTA_PROFILE=work
export BARISTA_WINDOW_MANAGER_MODE=disabled
export BARISTA_INSTALL_NONINTERACTIVE=1
export BARISTA_INSTALL_EXTRAS=n
export INSTALL_ARGS_LOG
setup_profile >/dev/null
setup_fonts_panel_and_work_apps
setup_window_manager

jq -e '.profile == "work" and .modes.window_manager == "disabled"' \
  "$INSTALL_RUNTIME/state.json" >/dev/null
awk 'previous == "--profile-variant" && $0 == "work" { found = 1 } { previous = $0 } END { exit !found }' \
  "$INSTALL_ARGS_LOG"
awk 'previous == "--window-manager" && $0 == "disabled" { found = 1 } { previous = $0 } END { exit !found }' \
  "$INSTALL_ARGS_LOG"
grep -Fxq -- '--work-apps' "$INSTALL_ARGS_LOG"
grep -Fxq -- '--replace-work-apps' "$INSTALL_ARGS_LOG"

printf 'test_work_profile_entrypoints.sh: ok\n'
