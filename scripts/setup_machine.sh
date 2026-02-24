#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

STATE_FILE="${BARISTA_STATE_FILE:-$HOME/.config/sketchybar/state.json}"
PANEL_MODE="${BARISTA_ALT_PANEL_MODE:-tui}"
WORK_DOMAIN="${BARISTA_WORK_GOOGLE_DOMAIN:-}"
WORK_APPS_FILE=""
WORK_APPS_OUT_FILE=""

INSTALL_FONTS=1
CONFIGURE_PANEL=1
CONFIGURE_WORK_APPS=0
REPLACE_WORK_APPS=0
AUTO_YES=0
DO_RELOAD=1
DRY_RUN=0
REPORT=0

ACTION_FONTS=0
ACTION_PANEL=0
ACTION_WORK_APPS=0
ACTION_RELOAD=0
WORK_APPS_OUTPUT_FILE_RESOLVED=""

usage() {
  cat <<EOF
Usage: $0 [options]

Core options:
  --state <path>                          State file (default: ~/.config/sketchybar/state.json)
  --yes                                   Non-interactive confirmation
  --no-reload                             Skip sketchybar reload
  --dry-run                               Show planned changes without modifying files/system
  --report                                Print a machine-readable action report

Fonts + panel options:
  --panel-mode <native|tui|imgui|custom>  Preferred control panel mode
  --skip-fonts                            Skip font installation
  --skip-panel                            Skip panel preference/readability updates
  --fonts-only                            Only install fonts
  --panel-only                            Only configure panel/readability

Work apps options:
  --work-apps                             Configure work apps menu items
  --domain <workspace-domain>             Workspace domain for Google app URLs
  --from-file <apps.json>                 JSON array payload for custom apps input
  --work-apps-out-file <path>             Output JSON path for per-machine work apps data
  --replace                               Replace existing work app menu items
  --skip-work-apps                        Skip work app configuration
  --apps-only                             Only configure work app menu items
EOF
}

note() {
  printf '%s\n' "$*"
}

note_warn() {
  printf '[warn] %s\n' "$*" >&2
}

note_dry() {
  printf '[dry-run] %s\n' "$*"
}

require_value() {
  local opt="$1"
  local val="${2:-}"
  if [ -z "$val" ] || [[ "$val" == --* ]]; then
    echo "Missing value for $opt" >&2
    exit 1
  fi
}

expand_home() {
  case "$1" in
    ~/*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    ~) printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

resolve_relative_to_state_dir() {
  local raw="$1"
  case "$raw" in
    "" ) printf '%s\n' "" ;;
    ~/*|~) expand_home "$raw" ;;
    /*) printf '%s\n' "$raw" ;;
    *) printf '%s/%s\n' "$(dirname "$STATE_FILE")" "$raw" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      require_value "$1" "${2:-}"
      STATE_FILE="$2"
      shift 2
      ;;
    --panel-mode)
      require_value "$1" "${2:-}"
      PANEL_MODE="$2"
      shift 2
      ;;
    --work-apps|--configure-work-apps)
      CONFIGURE_WORK_APPS=1
      shift
      ;;
    --domain|--work-domain)
      require_value "$1" "${2:-}"
      WORK_DOMAIN="$2"
      CONFIGURE_WORK_APPS=1
      shift 2
      ;;
    --from-file|--work-apps-file)
      require_value "$1" "${2:-}"
      WORK_APPS_FILE="$2"
      CONFIGURE_WORK_APPS=1
      shift 2
      ;;
    --work-apps-out-file|--apps-out-file)
      require_value "$1" "${2:-}"
      WORK_APPS_OUT_FILE="$2"
      CONFIGURE_WORK_APPS=1
      shift 2
      ;;
    --replace|--replace-work-apps)
      REPLACE_WORK_APPS=1
      shift
      ;;
    --skip-work-apps)
      CONFIGURE_WORK_APPS=0
      shift
      ;;
    --fonts-only)
      INSTALL_FONTS=1
      CONFIGURE_PANEL=0
      CONFIGURE_WORK_APPS=0
      shift
      ;;
    --panel-only)
      INSTALL_FONTS=0
      CONFIGURE_PANEL=1
      CONFIGURE_WORK_APPS=0
      shift
      ;;
    --apps-only)
      INSTALL_FONTS=0
      CONFIGURE_PANEL=0
      CONFIGURE_WORK_APPS=1
      shift
      ;;
    --skip-fonts)
      INSTALL_FONTS=0
      shift
      ;;
    --skip-panel)
      CONFIGURE_PANEL=0
      shift
      ;;
    --yes|-y)
      AUTO_YES=1
      shift
      ;;
    --no-reload)
      DO_RELOAD=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --report)
      REPORT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

STATE_FILE="$(expand_home "$STATE_FILE")"

confirm() {
  local prompt="$1"
  if [ "$AUTO_YES" -eq 1 ]; then
    return 0
  fi
  read -r -p "$prompt [Y/n] " reply
  case "${reply:-y}" in
    y|Y|yes|YES|"")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_state_file() {
  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi
  mkdir -p "$(dirname "$STATE_FILE")"
  if [ ! -f "$STATE_FILE" ]; then
    printf '{}' > "$STATE_FILE"
  fi
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for state updates." >&2
    exit 1
  fi
}

jq_edit_state() {
  local filter="$1"
  shift

  require_jq
  if [ "$DRY_RUN" -eq 1 ]; then
    local source_file
    source_file="$STATE_FILE"
    if [ ! -f "$source_file" ]; then
      source_file="$(mktemp)"
      printf '{}' > "$source_file"
    fi
    jq "$@" "$filter" "$source_file" >/dev/null
    if [ "$source_file" != "$STATE_FILE" ]; then
      rm -f "$source_file" >/dev/null 2>&1 || true
    fi
    return 0
  fi

  ensure_state_file
  local tmp
  tmp="$(mktemp)"
  jq "$@" "$filter" "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

ensure_font_cask() {
  local cask="$1"
  if brew list --cask "$cask" >/dev/null 2>&1; then
    note "[fonts] $cask already installed"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "[fonts] would install $cask"
    return 0
  fi
  note "[fonts] installing $cask"
  brew install --cask "$cask"
}

install_fonts() {
  ACTION_FONTS=1
  if ! command -v brew >/dev/null 2>&1; then
    note_warn "Homebrew not found, skipping font install"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "[fonts] would tap homebrew/cask-fonts"
  else
    brew tap homebrew/cask-fonts >/dev/null 2>&1 || true
  fi
  ensure_font_cask font-hack-nerd-font
  ensure_font_cask font-source-code-pro
}

set_panel_preference() {
  local mode="$1"
  jq_edit_state '
    .control_panel = (.control_panel // {}) |
    .control_panel.preferred = $mode
  ' --arg mode "$mode"
}

apply_menu_readability_defaults() {
  jq_edit_state '
    .appearance = (.appearance // {}) |
    .appearance.popup_bg_color = "0xEE21162F" |
    .appearance.menu_popup_bg_color = "0xF021162F" |
    .appearance.popup_border_color = (.appearance.popup_border_color // "0xB0cdd6f4") |
    .appearance.menu_font_style = (
      if ((.appearance.menu_font_style // "Bold") | ascii_downcase | test("regular|light|thin")) then
        "Semibold"
      else
        (.appearance.menu_font_style // "Bold")
      end
    ) |
    .appearance.menu_header_font_style = (
      if ((.appearance.menu_header_font_style // "Bold") | ascii_downcase | test("regular|light|thin")) then
        "Bold"
      else
        (.appearance.menu_header_font_style // "Bold")
      end
    ) |
    .appearance.menu_font_size_offset = (
      if (.appearance.menu_font_size_offset // 0) < 2 then 2 else .appearance.menu_font_size_offset end
    ) |
    .appearance.font_text = (.appearance.font_text // "Source Code Pro") |
    .appearance.widget_scale = (
      if (.appearance.widget_scale // 1) < 1.05 then 1.05 else .appearance.widget_scale end
    )
  '
}

configure_panel_mode() {
  ACTION_PANEL=1
  local mode
  mode="$(printf '%s' "$PANEL_MODE" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    native)
      set_panel_preference native
      ;;
    tui)
      if [ -x "$ROOT_DIR/scripts/install-tui.sh" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
          note_dry "[panel] would install TUI dependencies"
        else
          "$ROOT_DIR/scripts/install-tui.sh" --yes
        fi
      fi
      set_panel_preference tui
      ;;
    imgui)
      if [ -x "$HOME/src/lab/barista_config/build/barista_config" ] || command -v barista_config >/dev/null 2>&1; then
        set_panel_preference imgui
      else
        note_warn "barista_config binary not found; leaving current preference"
      fi
      ;;
    custom)
      set_panel_preference custom
      ;;
    *)
      echo "[panel] unsupported mode: $PANEL_MODE" >&2
      return 1
      ;;
  esac
  apply_menu_readability_defaults
}

google_url() {
  local host="$1"
  if [ -n "$WORK_DOMAIN" ]; then
    printf 'https://%s/a/%s/' "$host" "$WORK_DOMAIN"
  else
    printf 'https://%s/' "$host"
  fi
}

default_apps_json() {
  local mail_url calendar_url drive_url docs_url sheets_url meet_url
  mail_url="$(google_url mail.google.com)"
  calendar_url="$(google_url calendar.google.com)"
  drive_url="$(google_url drive.google.com)"
  docs_url="https://docs.google.com/document/u/0/"
  sheets_url="https://docs.google.com/spreadsheets/u/0/"
  meet_url="https://meet.google.com/"
  cat <<JSON
[
  {"id":"gmail","label":"Gmail","icon":"󰇮","url":"$mail_url","section":"work","order":1,"enabled":true},
  {"id":"calendar","label":"Calendar","icon":"󰃭","url":"$calendar_url","section":"work","order":2,"enabled":true},
  {"id":"drive","label":"Drive","icon":"󰉋","url":"$drive_url","section":"work","order":3,"enabled":true},
  {"id":"docs","label":"Docs","icon":"󰈬","url":"$docs_url","section":"work","order":4,"enabled":true},
  {"id":"sheets","label":"Sheets","icon":"󰈛","url":"$sheets_url","section":"work","order":5,"enabled":true},
  {"id":"meet","label":"Meet","icon":"󰤙","url":"$meet_url","section":"work","order":6,"enabled":true}
]
JSON
}

default_work_apps_output_file() {
  printf '%s/data/work_apps.local.json\n' "$(dirname "$STATE_FILE")"
}

resolve_work_apps_output_file() {
  local candidate="$WORK_APPS_OUT_FILE"
  if [ -z "$candidate" ] && command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
    candidate="$(jq -r '.menus.work.apps_file // empty' "$STATE_FILE" 2>/dev/null || true)"
  fi
  if [ -z "$candidate" ]; then
    candidate="$(default_work_apps_output_file)"
  fi
  WORK_APPS_OUTPUT_FILE_RESOLVED="$(resolve_relative_to_state_dir "$candidate")"
  printf '%s\n' "$WORK_APPS_OUTPUT_FILE_RESOLVED"
}

load_apps_json() {
  require_jq
  local apps_json
  if [ -n "$WORK_APPS_FILE" ]; then
    local apps_file
    apps_file="$(resolve_relative_to_state_dir "$WORK_APPS_FILE")"
    if [ ! -f "$apps_file" ]; then
      echo "Apps file not found: $apps_file" >&2
      exit 1
    fi
    apps_json="$(cat "$apps_file")"
  else
    apps_json="$(default_apps_json)"
  fi

  if ! printf '%s' "$apps_json" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "Work apps payload must be a JSON array." >&2
    exit 1
  fi

  APPS_JSON="$(printf '%s' "$apps_json" | jq '
    map(
      .enabled = (.enabled // true) |
      .id = ("work_google_" + ((.id // .label // .url // "item")
        | tostring
        | ascii_downcase
        | gsub("[^a-z0-9]+"; "_")
        | gsub("^_+"; "")
        | gsub("_+$"; ""))) |
      .section = (.section // "custom") |
      .command = (.command // .action // (if (.url // "") != "" then ("open " + .url) else "" end))
    ) |
    map({id, label, title, icon, color, icon_color, label_color, command, section, order, enabled, shortcut})
  ')"
}

write_work_apps_file() {
  local out_file="$1"
  require_jq
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "[work-apps] would write JSON to $out_file"
    return 0
  fi
  mkdir -p "$(dirname "$out_file")"
  printf '%s' "$APPS_JSON" | jq '.' > "$out_file"
}

apply_work_apps() {
  ACTION_WORK_APPS=1
  require_jq
  load_apps_json

  local apps_file
  apps_file="$(resolve_work_apps_output_file)"
  WORK_APPS_OUTPUT_FILE_RESOLVED="$apps_file"
  write_work_apps_file "$apps_file"

  if [ "$REPLACE_WORK_APPS" -eq 1 ]; then
    jq_edit_state '
      .menus = (.menus // {}) |
      .menus.apple = (.menus.apple // {}) |
      .menus.apple.sections = (.menus.apple.sections // {}) |
      .menus.apple.sections.work = (.menus.apple.sections.work // {"label":"Work Apps","order":3}) |
      .menus.work = (.menus.work // {}) |
      .menus.work.apps_file = $apps_file |
      .menus.work.workspace_domain = $domain |
      .menus.work.google_apps = $apps |
      .menus.apple.custom = $apps
    ' --argjson apps "$APPS_JSON" --arg apps_file "$apps_file" --arg domain "$WORK_DOMAIN"
  else
    jq_edit_state '
      .menus = (.menus // {}) |
      .menus.apple = (.menus.apple // {}) |
      .menus.apple.sections = (.menus.apple.sections // {}) |
      .menus.apple.sections.work = (.menus.apple.sections.work // {"label":"Work Apps","order":3}) |
      .menus.work = (.menus.work // {}) |
      .menus.work.apps_file = $apps_file |
      .menus.work.workspace_domain = $domain |
      .menus.work.google_apps = $apps |
      .menus.apple.custom = (
        ((.menus.apple.custom // []) as $existing |
         ($apps | map((.id // .label // "") | tostring)) as $incoming_keys |
         ($existing | map(select((.id // .label // "") as $k | ($incoming_keys | index(($k|tostring))) | not)))
         + $apps)
      )
    ' --argjson apps "$APPS_JSON" --arg apps_file "$apps_file" --arg domain "$WORK_DOMAIN"
  fi
}

print_report() {
  [ "$REPORT" -eq 1 ] || return 0
  printf 'setup.report.status=ok\n'
  printf 'setup.report.dry_run=%s\n' "$DRY_RUN"
  printf 'setup.report.state_file=%s\n' "$STATE_FILE"
  printf 'setup.report.panel_mode=%s\n' "$PANEL_MODE"
  printf 'setup.report.work_domain=%s\n' "$WORK_DOMAIN"
  printf 'setup.report.work_apps_output_file=%s\n' "$WORK_APPS_OUTPUT_FILE_RESOLVED"
  printf 'setup.report.actions.fonts=%s\n' "$ACTION_FONTS"
  printf 'setup.report.actions.panel=%s\n' "$ACTION_PANEL"
  printf 'setup.report.actions.work_apps=%s\n' "$ACTION_WORK_APPS"
  printf 'setup.report.actions.reload=%s\n' "$ACTION_RELOAD"
}

if [ "$INSTALL_FONTS" -eq 0 ] && [ "$CONFIGURE_PANEL" -eq 0 ] && [ "$CONFIGURE_WORK_APPS" -eq 0 ]; then
  note "No setup actions selected."
  print_report
  exit 0
fi

if [ "$INSTALL_FONTS" -eq 1 ]; then
  if confirm "Install missing Barista fonts?"; then
    install_fonts
  fi
fi

if [ "$CONFIGURE_PANEL" -eq 1 ]; then
  if confirm "Configure control panel mode ($PANEL_MODE) and menu readability defaults?"; then
    configure_panel_mode
  fi
fi

if [ "$CONFIGURE_WORK_APPS" -eq 1 ]; then
  if confirm "Configure work Google apps menu items?"; then
    apply_work_apps
  fi
fi

if [ "$DO_RELOAD" -eq 1 ] && command -v sketchybar >/dev/null 2>&1; then
  ACTION_RELOAD=1
  if [ "$DRY_RUN" -eq 1 ]; then
    note_dry "would reload sketchybar"
  else
    sketchybar --reload >/dev/null 2>&1 || true
  fi
fi

print_report
if [ "$DRY_RUN" -eq 1 ]; then
  note "Machine setup dry-run complete."
else
  note "Machine setup complete."
fi
