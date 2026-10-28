#!/bin/bash
# Execute only the app/window that the menu snapshot showed, then show the result.
set -u
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/plugins/lib/common.sh"

SCOPE="${1:-}"
ACTION="${2:-}"
WINDOW_ID="${3:-}"
APP_NAME="${4:-}"
CONTROL="${BARISTA_YABAI_CONTROL_SCRIPT:-$SCRIPTS_DIR/yabai_control.sh}"
APP_ACTION="${BARISTA_FRONT_APP_ACTION_SCRIPT:-$SCRIPTS_DIR/front_app_action.sh}"
REFRESH="${BARISTA_FRONT_APP_PLUGIN_SCRIPT:-$ROOT_DIR/plugins/front_app.sh}"

feedback() {
  local text="$1" color="$2"
  # Close children so the feedback row in the root remains visible.
  sketchybar --set front_app.more popup.drawing=off \
    --set front_app.move popup.drawing=off \
    --set front_app.defaults popup.drawing=off \
    --set front_app.feedback drawing=on "label=$text" "label.color=$color" \
    --set front_app popup.drawing=on >/dev/null 2>&1 || true
}

fail() {
  feedback "$1" 0xffff8087
  printf '%s\n' "$1" >&2
  exit 1
}

[ -n "$APP_NAME" ] || fail "App unavailable. Reopen the menu."
case "$SCOPE" in
  window)
    case "$WINDOW_ID" in ''|*[!0-9]*|0) fail "Window unavailable. Reopen the menu." ;; esac
    case "$ACTION" in
      window-toggle-float|window-adopt-space-mode|window-toggle-fullscreen|window-toggle-sticky|window-toggle-topmost|window-center|window-preset-utility|window-preset-focus|window-preset-presentation|window-preset-tile-here|window-space-float|window-display-prev|window-display-next|window-space-prev-wrap|window-space-next-wrap) ;;
      *) fail "Unknown window action." ;;
    esac
    output="$(BARISTA_TARGET_WINDOW_ID="$WINDOW_ID" BARISTA_TARGET_APP="$APP_NAME" "$CONTROL" "$ACTION" 2>&1)"
    result=$?
    message="Window updated"
    ;;
  default)
    case "$ACTION" in
      float|tile) output="$("$CONTROL" app-default set "$APP_NAME" "$ACTION" 2>&1)"; result=$? ;;
      unset) output="$("$CONTROL" app-default unset "$APP_NAME" 2>&1)"; result=$? ;;
      *) fail "Unknown app default." ;;
    esac
    message="Saved for new $APP_NAME windows"
    [ "$ACTION" != "unset" ] || message="Barista default removed · Other rules may apply"
    ;;
  level)
    case "$ACTION" in
      normal|raised|top) output="$("$CONTROL" app-level set "$APP_NAME" "$ACTION" 2>&1)"; result=$? ;;
      unset) output="$("$CONTROL" app-level unset "$APP_NAME" 2>&1)"; result=$? ;;
      *) fail "Unknown app level." ;;
    esac
    case "$ACTION" in
      normal) message="$APP_NAME stacks with other windows · focus decides" ;;
      raised) message="$APP_NAME stays above normal windows" ;;
      top) message="$APP_NAME stays on top" ;;
      *) message="Barista level removed · Yabai rules apply" ;;
    esac
    ;;
  app)
    case "$ACTION" in show|hide|quit|force-quit|force_quit) ;; *) fail "Unknown app action." ;; esac
    output="$("$APP_ACTION" "$ACTION" "$APP_NAME" 2>&1)"
    result=$?
    message="App action completed"
    ;;
  *) fail "Unknown menu action." ;;
esac

if [ "$result" -ne 0 ]; then
  # Preserve actionable backend errors, but keep a single readable menu row.
  output="${output%%$'\n'*}"
  output="${output//$'\r'/ }"
  output="${output//$'\t'/ }"
  [ -n "$output" ] || output="Action failed. Reopen the menu and try again."
  fail "${output:0:180}"
fi

if [ -x "$REFRESH" ]; then
  INFO="$APP_NAME" NAME=front_app SENDER=action_refresh \
    BARISTA_FRONT_APP_TARGET_APP="$APP_NAME" "$REFRESH" >/dev/null 2>&1 || true
fi
feedback "$message" 0xffa6da95
