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

# Config and paths
CONFIG_DIR="${BARISTA_CONFIG_DIR:-${CONFIG_DIR:-$HOME/.config/sketchybar}}"
STATE_FILE="${STATE_FILE:-$CONFIG_DIR/state.json}"

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

animate_set() {
  if sketchybar --animate "$ANIMATION_CURVE" "$ANIMATION_DURATION" --set "$@" >/dev/null 2>&1; then
    return 0
  fi
  sketchybar --set "$@"
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
