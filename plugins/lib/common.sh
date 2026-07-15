# Barista plugins shared library (POSIX sh)
# Source this from plugin scripts: _d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"
#
# Provides:
#   CONFIG_DIR, STATE_FILE, SCRIPTS_DIR (and expand_path for path resolution)
#   BARISTA_HOVER_COLOR, BARISTA_HOVER_ANIMATION_CURVE, BARISTA_HOVER_ANIMATION_DURATION
#   HIGHLIGHT, ANIMATION_CURVE, ANIMATION_DURATION (used by animate_set; also from POPUP_* / SUBMENU_* when set by main.lua)
#   animate_set NAME prop=value ...  (hover animation helper)
#   run_with_timeout SECONDS cmd [args...]
#
# Optional env (caller or main.lua): BARISTA_CONFIG_DIR, CONFIG_DIR, BARISTA_SCRIPTS_DIR.
# state.json paths.scripts_dir / paths.scripts are read when jq is available.

# Config and paths. Preserve caller PATH first so tests and live wrappers can
# inject stubs/overrides before Homebrew/system fallbacks.
PATH="${PATH:-}:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
if [ -z "${USER:-}" ]; then
  USER="$(id -un 2>/dev/null || logname 2>/dev/null || printf 'scawful')"
  export USER
fi
CONFIG_DIR="${BARISTA_CONFIG_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar}}"
STATE_FILE="${STATE_FILE:-$CONFIG_DIR/state.json}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
if [ -z "$SKETCHYBAR_BIN" ] && [ -x "/opt/homebrew/opt/sketchybar/bin/sketchybar" ]; then
  SKETCHYBAR_BIN="/opt/homebrew/opt/sketchybar/bin/sketchybar"
fi
if [ -z "$SKETCHYBAR_BIN" ] && [ -x "/opt/homebrew/bin/sketchybar" ]; then
  SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
fi

sketchybar() {
  if [ -n "$SKETCHYBAR_BIN" ]; then
    "$SKETCHYBAR_BIN" "$@"
  else
    command sketchybar "$@"
  fi
}

expand_path() {
  case "$1" in
    "~/"*) printf '%s' "$HOME/${1#~/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

# SCRIPTS_DIR: env BARISTA_SCRIPTS_DIR or state.json, then fallbacks
if [ -z "${SCRIPTS_DIR:-}" ]; then
  SCRIPTS_DIR="${BARISTA_SCRIPTS_DIR:-}"
fi
if [ -z "$SCRIPTS_DIR" ] && command -v jq >/dev/null 2>&1 && [ -f "$STATE_FILE" ]; then
  SCRIPTS_DIR=$(jq -r '.paths.scripts_dir // .paths.scripts // empty' "$STATE_FILE" 2>/dev/null || true)
  case "$SCRIPTS_DIR" in
    null|"") SCRIPTS_DIR="" ;;
  esac
fi
if [ -n "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$(expand_path "$SCRIPTS_DIR")"
fi
if [ -z "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$CONFIG_DIR/scripts"
fi
if [ ! -d "$SCRIPTS_DIR" ]; then
  SCRIPTS_DIR="$HOME/.config/scripts"
fi

# Hover/animation defaults (widgets use BARISTA_*; popup/submenu scripts get POPUP_* / SUBMENU_* from main.lua)
BARISTA_HOVER_COLOR="${BARISTA_HOVER_COLOR:-0x40f5c2e7}"
BARISTA_HOVER_ANIMATION_CURVE="${BARISTA_HOVER_ANIMATION_CURVE:-sin}"
BARISTA_HOVER_ANIMATION_DURATION="${BARISTA_HOVER_ANIMATION_DURATION:-12}"
HIGHLIGHT="${BARISTA_HOVER_COLOR:-${POPUP_HOVER_COLOR:-${SUBMENU_HOVER_BG:-0x40f5c2e7}}}"
ANIMATION_CURVE="${BARISTA_HOVER_ANIMATION_CURVE:-${POPUP_HOVER_ANIMATION_CURVE:-${SUBMENU_ANIMATION_CURVE:-sin}}}"
ANIMATION_DURATION="${BARISTA_HOVER_ANIMATION_DURATION:-${POPUP_HOVER_ANIMATION_DURATION:-${SUBMENU_ANIMATION_DURATION:-12}}}"
HOVER_TIMEOUT="${BARISTA_HOVER_TIMEOUT:-${POPUP_HOVER_TIMEOUT:-${SUBMENU_HOVER_TIMEOUT:-0.55}}}"
HOVER_STATE_DIR="${BARISTA_HOVER_STATE_DIR:-${TMPDIR:-/tmp}/sketchybar_hover_state}"

anchor_hover_props() {
  _anchor_hover_bg="${BARISTA_ANCHOR_HOVER_BG:-$HIGHLIGHT}"
  _anchor_hover_border_width="${BARISTA_ANCHOR_HOVER_BORDER_WIDTH:-${POPUP_HOVER_BORDER_WIDTH:-}}"
  _anchor_hover_border_color="${BARISTA_ANCHOR_HOVER_BORDER_COLOR:-${POPUP_HOVER_BORDER_COLOR:-0x60cdd6f4}}"
  if [ -n "$_anchor_hover_border_width" ]; then
    printf 'background.drawing=on background.color=%s background.border_width=%s background.border_color=%s' \
      "$_anchor_hover_bg" "$_anchor_hover_border_width" "$_anchor_hover_border_color"
  else
    printf 'background.drawing=on background.color=%s' "$_anchor_hover_bg"
  fi
}

anchor_idle_props() {
  _anchor_idle_drawing="${BARISTA_ANCHOR_IDLE_DRAWING:-off}"
  _anchor_idle_border_width="${BARISTA_ANCHOR_IDLE_BORDER_WIDTH:-0}"
  _anchor_idle_border_color="${BARISTA_ANCHOR_IDLE_BORDER_COLOR:-0x00000000}"
  _anchor_idle_bg="${BARISTA_ANCHOR_IDLE_BG:-0x00000000}"
  printf 'background.drawing=%s background.border_width=%s background.border_color=%s background.color=%s' \
    "$_anchor_idle_drawing" "$_anchor_idle_border_width" "$_anchor_idle_border_color" "$_anchor_idle_bg"
}

animate_set() {
  if sketchybar --animate "$ANIMATION_CURVE" "$ANIMATION_DURATION" --set "$@" >/dev/null 2>&1; then
    return 0
  fi
  sketchybar --set "$@"
}

hover_state_file() {
  key="${1:-item}"
  key="$(printf '%s' "$key" | tr -cs '[:alnum:]._-' '_')"
  [ -d "$HOVER_STATE_DIR" ] || mkdir -p "$HOVER_STATE_DIR" 2>/dev/null || true
  printf '%s/%s.state' "$HOVER_STATE_DIR" "$key"
}

hover_token() {
  printf '%s' "$$"
}

highlight_with_timeout() {
  name="$1"
  on_props="$2"
  off_props="${3:-background.drawing=off background.border_width=0}"
  [ -n "$name" ] || return 0
  state_file="$(hover_state_file "$name")"
  token="$(hover_token)"
  printf '%s' "$token" > "$state_file"
  # shellcheck disable=SC2086
  animate_set "$name" $on_props
  case "$HOVER_TIMEOUT" in
    ""|0|0.0|false|off)
      return 0
      ;;
  esac
  (
    sleep "$HOVER_TIMEOUT"
    current=""
    if [ -f "$state_file" ]; then
      IFS= read -r current < "$state_file" || true
    fi
    if [ "$current" = "$token" ]; then
      # shellcheck disable=SC2086
      animate_set "$name" $off_props
    fi
  ) >/dev/null 2>&1 &
}

clear_highlight() {
  name="$1"
  off_props="${2:-background.drawing=off background.border_width=0}"
  [ -n "$name" ] || return 0
  rm -f "$(hover_state_file "$name")" >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  animate_set "$name" $off_props
}

run_with_timeout() {
  timeout_s="$1"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_s" "$@"
    return $?
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_s" "$@"
    return $?
  fi
  if command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' "$timeout_s" "$@"
    return $?
  fi
  "$@"
}
