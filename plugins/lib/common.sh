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

read_state_json_string() {
  _state_json_file="$1"
  _state_json_path1="${2:-}"
  _state_json_path2="${3:-}"
  [ -f "$_state_json_file" ] || return 1

  if [ -n "${BARISTA_JQ_BIN+x}" ]; then
    _state_jq_bin="$BARISTA_JQ_BIN"
  else
    _state_jq_bin="$(command -v jq 2>/dev/null || true)"
  fi
  if [ -n "$_state_jq_bin" ]; then
    "$_state_jq_bin" -r --arg p1 "$_state_json_path1" --arg p2 "$_state_json_path2" '
      . as $root
      | [$p1, $p2]
      | map(select(length > 0) | split(".") as $path | $root | getpath($path))
      | map(select(type == "string" and length > 0))
      | .[0] // empty
    ' "$_state_json_file" 2>/dev/null
    return $?
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$_state_json_file" "$_state_json_path1" "$_state_json_path2" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        root = json.load(handle)
    for dotted in sys.argv[2:]:
        if not dotted:
            continue
        value = root
        for component in dotted.split("."):
            value = value[component]
        if isinstance(value, str) and value:
            print(value)
            raise SystemExit(0)
except (OSError, UnicodeError, ValueError, KeyError, TypeError):
    pass
raise SystemExit(1)
PY
    return $?
  fi

  return 1
}

# SCRIPTS_DIR: env BARISTA_SCRIPTS_DIR or state.json, then fallbacks
if [ -z "${SCRIPTS_DIR:-}" ]; then
  SCRIPTS_DIR="${BARISTA_SCRIPTS_DIR:-}"
fi
if [ -z "$SCRIPTS_DIR" ] && [ -f "$STATE_FILE" ]; then
  SCRIPTS_DIR="$(read_state_json_string "$STATE_FILE" "paths.scripts_dir" "paths.scripts" || true)"
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
BARISTA_HOVER_COLOR="${BARISTA_HOVER_COLOR:-${POPUP_HOVER_COLOR:-${SUBMENU_HOVER_BG:-0x40f5c2e7}}}"
BARISTA_HOVER_ANIMATION_CURVE="${BARISTA_HOVER_ANIMATION_CURVE:-${POPUP_HOVER_ANIMATION_CURVE:-${SUBMENU_ANIMATION_CURVE:-sin}}}"
BARISTA_HOVER_ANIMATION_DURATION="${BARISTA_HOVER_ANIMATION_DURATION:-${POPUP_HOVER_ANIMATION_DURATION:-${SUBMENU_ANIMATION_DURATION:-8}}}"
HIGHLIGHT="$BARISTA_HOVER_COLOR"
ANIMATION_CURVE="$BARISTA_HOVER_ANIMATION_CURVE"
ANIMATION_DURATION="$BARISTA_HOVER_ANIMATION_DURATION"
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
  case "$ANIMATION_DURATION" in
    0|0.0)
      hover_dispatch --set "$@"
      return $?
      ;;
  esac
  if hover_dispatch --animate "$ANIMATION_CURVE" "$ANIMATION_DURATION" --set "$@" >/dev/null 2>&1; then
    return 0
  else
    _animate_status=$?
  fi
  case "$_animate_status" in 124|137|142|143) return "$_animate_status" ;; esac
  hover_dispatch --set "$@"
}

hover_dispatch() {
  if [ "${HOVER_LOCK_HELD:-0}" != 1 ]; then
    sketchybar "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout -s KILL 0.5 "${SKETCHYBAR_BIN:-sketchybar}" "$@" 9>&-
  elif command -v timeout >/dev/null 2>&1; then
    timeout -s KILL 0.5 "${SKETCHYBAR_BIN:-sketchybar}" "$@" 9>&-
  else
    perl -MTime::HiRes=alarm -MPOSIX -MErrno=EINTR -e '
      my $child = fork;
      defined($child) or exit 74;
      if (!$child) { setpgrp(0, 0) or exit 74; exec @ARGV; exit 127; }
      POSIX::setpgid($child, $child);
      my $timed_out = 0;
      $SIG{ALRM} = sub { $timed_out = 1; kill 9, -$child; kill 9, $child; };
      alarm 0.5;
      my $waited;
      do { $waited = waitpid($child, 0); } while ($waited < 0 && $! == EINTR);
      my $status = $?;
      alarm 0;
      exit 124 if $timed_out;
      exit 74 if $waited < 0;
      exit(($status & 127) ? 128 + ($status & 127) : $status >> 8);
    ' "${SKETCHYBAR_BIN:-sketchybar}" "$@" 9>&-
  fi
}

hover_state_file() {
  key="${1:-item}"
  case "$key" in
    *[!a-zA-Z0-9._-]*) key="$(printf '%s' "$key" | LC_ALL=C tr -cs '[:alnum:]._-' '_')" ;;
  esac
  [ -d "$HOVER_STATE_DIR" ] || mkdir -p "$HOVER_STATE_DIR" 2>/dev/null || true
  printf '%s/%s.state' "$HOVER_STATE_DIR" "$key"
}

hover_acquire_lock() {
  _hover_file="${3:-}"
  [ -n "$_hover_file" ] || _hover_file="$(hover_state_file "$1")"
  _hover_wait="${2:-1200}"
  _hover_helper="${BARISTA_FILE_LOCK_BIN:-$CONFIG_DIR/bin/file_lock}"
  exec 9> "${_hover_file%.state}.apply.lock" || return 1
  _hover_status=64
  if [ "${BARISTA_LUA_ONLY:-0}" != 1 ] && [ -x "$_hover_helper" ]; then
    if "$_hover_helper" 9 "$_hover_wait" 2>/dev/null; then
      _hover_status=0
    else
      _hover_status=$?
    fi
  fi
  # Old installed helpers reject the second argument. Use the same kernel
  # lock through Perl until rebuilt helpers are deployed, including Lua-only.
  if [ "$_hover_status" = 64 ] && command -v perl >/dev/null 2>&1; then
    if perl -MFcntl=:flock -MTime::HiRes=alarm -e '
      my ($fd, $wait) = @ARGV;
      open(my $lock, ">&=$fd") or exit 74;
      $SIG{ALRM} = sub { exit 75 };
      alarm($wait / 1000) if $wait > 0;
      flock($lock, LOCK_EX | ($wait > 0 ? 0 : LOCK_NB)) or exit 75;
      alarm(0);
    ' 9 "$_hover_wait"; then
      _hover_status=0
    else
      _hover_status=$?
    fi
  fi
  if [ "$_hover_status" != 0 ]; then
    exec 9>&-
    return 1
  fi
  HOVER_LOCK_HELD=1
}

hover_release_lock() {
  exec 9>&-
  HOVER_LOCK_HELD=0
}

hover_cancel_native_timer() {
  _native_hover_state="${TMPDIR:-/tmp}/sketchybar_popup_state/$1.anchor"
  [ ! -e "$_native_hover_state" ] || rm -f "$_native_hover_state" 2>/dev/null || true
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
  hover_acquire_lock "$name" 1200 "$state_file" || return 0
  hover_cancel_native_timer "$name"
  token="$(hover_token)"
  printf '%s' "$token" > "$state_file"
  if [ -n "${POPUP_ANCHOR_STATE_FILE:-}" ]; then
    printf '%s' "$token" > "$POPUP_ANCHOR_STATE_FILE"
  fi
  # shellcheck disable=SC2086
  animate_set "$name" $on_props || true
  case "$HOVER_TIMEOUT" in
    ""|0|0.0|false|off)
      hover_release_lock
      return 0
      ;;
  esac
  (
    hover_release_lock
    sleep "$HOVER_TIMEOUT"
    hover_acquire_lock "$name" 0 "$state_file" || exit 0
    current=""
    if [ -f "$state_file" ]; then
      IFS= read -r current < "$state_file" || true
    fi
    if [ "$current" = "$token" ]; then
      # shellcheck disable=SC2086
      animate_set "$name" $off_props
    fi
  ) >/dev/null 2>&1 &
  hover_release_lock
}

clear_highlight() {
  name="$1"
  off_props="${2:-background.drawing=off background.border_width=0}"
  [ -n "$name" ] || return 0
  state_file="$(hover_state_file "$name")"
  hover_acquire_lock "$name" 1200 "$state_file" || return 0
  hover_cancel_native_timer "$name"
  rm -f "$state_file" >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  animate_set "$name" $off_props || true
  hover_release_lock
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
