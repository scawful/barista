#!/usr/bin/env bash
# Keep windows with a space that was dragged to another display in Mission Control.
# Yabai keeps the old display's tiling area for a moved space that is visible on
# exit, so its windows get flushed back onto the original monitor.
#
# Usage: mission_control_guard.sh enter|exit
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
JQ_BIN="${JQ_BIN:-$(command -v jq || true)}"
SNAPSHOT_FILE="${BARISTA_MC_SNAPSHOT_FILE:-${TMPDIR:-/tmp}/barista_mission_control_${UID}.json}"

[ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || exit 0

query_spaces_and_windows() {
  "$YABAI_BIN" -m query --spaces 2>/dev/null && "$YABAI_BIN" -m query --windows 2>/dev/null
}

snapshot() {
  local tmp="$SNAPSHOT_FILE.$$"
  if query_spaces_and_windows | "$JQ_BIN" -s '
    .[0] as $spaces | .[1] as $windows
    | ($spaces | map({key: (.index | tostring), value: .uuid}) | from_entries) as $uuid
    | {
        spaces: [$spaces[] | {uuid, display}],
        windows: [$windows[]
          | select((."is-sticky" | not) and (."is-minimized" | not))
          | {id, uuid: $uuid[(.space | tostring)]}]
      }' >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$SNAPSHOT_FILE"
  else
    rm -f "$tmp"
  fi
}

# Prints "space <index>" for each space whose display changed, then
# "window <id> <index>" for each of its windows left on the old display.
restore_plan() {
  { cat "$SNAPSHOT_FILE"; query_spaces_and_windows; } | "$JQ_BIN" -rs '
    .[0] as $snap | .[1] as $spaces | .[2] as $windows
    | ($snap.spaces | map({key: .uuid, value: .display}) | from_entries) as $old_display
    | [$spaces[]
        | select($old_display[.uuid] != null and $old_display[.uuid] != .display)
        | {uuid, index, old: $old_display[.uuid]}] as $moved
    | ($moved | map({key: .uuid, value: .}) | from_entries) as $moved_by_uuid
    | ($windows | map({key: (.id | tostring), value: .}) | from_entries) as $now
    | ($moved[] | "space \(.index)"),
      ($snap.windows[]
        | $moved_by_uuid[.uuid // ""] as $space
        | select($space != null)
        | $now[(.id | tostring)] as $current
        | select($current != null and $current.space != $space.index and $current.display == $space.old)
        | "window \(.id) \($space.index)")
  ' 2>/dev/null || true
}

restore() {
  [ -f "$SNAPSHOT_FILE" ] || return 0
  local plan kind id target moved_spaces="" moved_windows=0
  plan="$(restore_plan)"
  rm -f "$SNAPSHOT_FILE"

  while read -r kind id target; do
    case "$kind" in
      space)
        moved_spaces="$moved_spaces $id"
        # A zero relative gap change makes Yabai recompute the area for the new display.
        "$YABAI_BIN" -m space "$id" --gap rel:0 >/dev/null 2>&1 || true
        ;;
      window)
        "$YABAI_BIN" -m window "$id" --space "$target" >/dev/null 2>&1 || true
        moved_windows=1
        ;;
    esac
  done <<<"$plan"

  if [ "$moved_windows" -eq 1 ]; then
    for id in $moved_spaces; do
      "$YABAI_BIN" -m space "$id" --gap rel:0 >/dev/null 2>&1 || true
    done
  fi
}

case "${1:-}" in
  enter)
    snapshot
    ;;
  exit)
    restore
    export CONFIG_DIR
    BARISTA_REASON=mission_control_exit "$CONFIG_DIR/plugins/refresh_spaces.sh" >/dev/null 2>&1 || true
    ;;
  *)
    echo "usage: $(basename "$0") enter|exit" >&2
    exit 2
    ;;
esac
