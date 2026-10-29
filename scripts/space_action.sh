#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
RESOLVED_RUNTIME_FILE="${BARISTA_RESOLVED_RUNTIME_FILE:-$CONFIG_DIR/.barista_runtime_backend}"
YABAI_BIN="${YABAI_BIN:-$(command -v yabai || true)}"
if [ -z "${JQ_BIN+x}" ]; then
  JQ_BIN="$(command -v jq || true)"
fi
SKETCHYBAR_BIN="${SKETCHYBAR_BIN:-$(command -v sketchybar || true)}"
SPACE_MANAGER_BIN="${SPACE_MANAGER_BIN:-$CONFIG_DIR/bin/space_manager}"
SPACE_CLOSE_CONFIRM_TTL_SEC="${SPACE_CLOSE_CONFIRM_TTL_SEC:-2}"
SPACE_SWAP_ARM_TTL_SEC="${SPACE_SWAP_ARM_TTL_SEC:-10}"
SPACE_SWAP_INDICATOR_ITEM="${SPACE_SWAP_INDICATOR_ITEM:-spaces.swap_indicator}"

runtime_is_lua_only() {
  if [ "${BARISTA_LUA_ONLY:-0}" = "1" ] || [ "${BARISTA_NO_CMAKE:-0}" = "1" ]; then
    return 0
  fi

  local runtime_backend="${BARISTA_RUNTIME_BACKEND:-}"
  local resolved_runtime=""
  if [ -f "$RESOLVED_RUNTIME_FILE" ]; then
    IFS= read -r resolved_runtime < "$RESOLVED_RUNTIME_FILE" || true
    if [ "$resolved_runtime" = "lua" ]; then
      return 0
    fi
  fi
  if [ -z "$runtime_backend" ] && [ -n "$JQ_BIN" ] && [ -f "$STATE_FILE" ]; then
    runtime_backend="$("$JQ_BIN" -r '.modes.runtime_backend // empty' "$STATE_FILE" 2>/dev/null || true)"
  fi
  if [ -z "$runtime_backend" ] && [ -f "$STATE_FILE" ] \
    && grep -Eqi '"runtime_backend"[[:space:]]*:[[:space:]]*"[[:space:]]*(lua|lua-only|lua_only|pure-lua|pure_lua|fallback|shell|no-cmake|no_cmake)[[:space:]]*"' "$STATE_FILE"; then
    runtime_backend="lua"
  fi
  runtime_backend="$(printf '%s' "$runtime_backend" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  case "$runtime_backend" in
    lua|lua-only|lua_only|pure-lua|pure_lua|fallback|shell|no-cmake|no_cmake)
      return 0
      ;;
  esac
  [ "$resolved_runtime" = "compiled" ] && return 1
  return 0
}

if runtime_is_lua_only; then
  BARISTA_LUA_ONLY=1
  export BARISTA_LUA_ONLY
fi

SPACE_ACTION_ENV_PREFIX=""
if [ "${BARISTA_LUA_ONLY:-0}" = "1" ]; then
  SPACE_ACTION_ENV_PREFIX="/usr/bin/env BARISTA_LUA_ONLY=1 "
fi

native_space_manager_available() {
  [ "${BARISTA_LUA_ONLY:-0}" != "1" ] && [ -x "$SPACE_MANAGER_BIN" ]
}

sketchybar() {
  [ -n "$SKETCHYBAR_BIN" ] || return 1
  "$SKETCHYBAR_BIN" "$@"
}

run_with_timeout() {
  local timeout_s="$1"
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

state_value() {
  local jq_query="$1"
  local fallback="$2"
  if [ -n "$JQ_BIN" ] && [ -f "$STATE_FILE" ]; then
    local value
    # `// empty` would also drop `false`, so a disabled toggle read as unset.
    value=$("$JQ_BIN" -r "($jq_query) | select(. != null)" "$STATE_FILE" 2>/dev/null || true)
    if [ -n "$value" ] && [ "$value" != "null" ]; then
      printf '%s' "$value"
      return 0
    fi
  fi
  printf '%s' "$fallback"
}

resolve_space_item_height() {
  local bar_height=""
  if [ -n "$SKETCHYBAR_BIN" ] && [ -n "$JQ_BIN" ]; then
    bar_height="$(sketchybar --query bar 2>/dev/null | "$JQ_BIN" -r '.height // empty' 2>/dev/null || true)"
  fi
  if [ -z "$bar_height" ] || [ "$bar_height" = "null" ]; then
    bar_height="$(state_value '.appearance.bar_height' '28')"
  fi
  if ! [ "$bar_height" -eq "$bar_height" ] 2>/dev/null; then
    bar_height=28
  fi

  local space_height=$((bar_height - 8))
  if [ "$space_height" -lt 20 ]; then
    space_height=20
  fi
  printf '%s' "$space_height"
}

normalize_close_mode() {
  case "$1" in
    off|confirm|direct)
      printf '%s' "$1"
      ;;
    *)
      printf '%s' "confirm"
      ;;
  esac
}

right_click_close_mode() {
  local mode
  mode=$(state_value '.spaces.right_click_close' 'confirm')
  normalize_close_mode "$mode"
}

normalize_bool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on)
      printf '%s' "true"
      ;;
    *)
      printf '%s' "false"
      ;;
  esac
}

normalize_reorder_mode() {
  local mode
  mode="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    off|modifiers|menu|swap_mode)
      printf '%s' "$mode"
      ;;
    *)
      printf '%s' "menu"
      ;;
  esac
}

reorder_mode() {
  local mode
  mode=$(state_value '.spaces.reorder_mode' 'menu')
  normalize_reorder_mode "$mode"
}

modifier_reorder_enabled() {
  local explicit
  explicit=$(state_value '.spaces.modifier_reorder_enabled' '')
  if [ -n "$explicit" ]; then
    [ "$(normalize_bool "$explicit")" = "true" ]
    return
  fi
  [ "$(reorder_mode)" = "modifiers" ]
}

context_menu_on_right_click() {
  local enabled
  enabled=$(state_value '.spaces.context_menu_on_right_click' 'true')
  [ "$(normalize_bool "$enabled")" = "true" ]
}

swap_indicator_enabled() {
  local enabled
  enabled=$(state_value '.spaces.swap_indicator' 'true')
  [ "$(normalize_bool "$enabled")" = "true" ]
}

front_app_merged() {
  local enabled
  enabled=$(state_value '.spaces.merge_front_app' 'true')
  [ "$(normalize_bool "$enabled")" = "true" ]
}

max_spaces_per_display() {
  local val
  val=$(state_value '.spaces.max_spaces_per_display' '8')
  case "$val" in
    ''|*[!0-9]*) printf '8' ;;
    *) printf '%s' "$val" ;;
  esac
}

min_spaces_per_display() {
  local val
  val=$(state_value '.spaces.min_spaces_per_display' '1')
  case "$val" in
    ''|*[!0-9]*|0) printf '1' ;;
    *) printf '%s' "$val" ;;
  esac
}

destroy_non_empty_policy() {
  local val
  val=$(state_value '.spaces.destroy_non_empty_policy' 'allow')
  case "$val" in
    allow|refuse|evacuate) printf '%s' "$val" ;;
    *) printf 'allow' ;;
  esac
}

new_space_layout_policy() {
  local val
  val=$(state_value '.spaces.new_space_layout' 'default')
  case "$val" in
    default|bsp|stack|float|inherit) printf '%s' "$val" ;;
    *) printf 'default' ;;
  esac
}

space_is_locked() {
  local space_idx="${1:-}"
  local space_uuid="${2:-}"
  [ "${FORCE_SPACE_ACTION:-0}" != "1" ] || return 1
  [ -n "$JQ_BIN" ] && [ -f "$STATE_FILE" ] || return 1
  if [ -z "$space_uuid" ] && [ -n "$YABAI_BIN" ]; then
    space_uuid="$(run_with_timeout 1 "$YABAI_BIN" -m query --spaces 2>/dev/null \
      | "$JQ_BIN" -r --arg idx "$space_idx" 'map(select((.index | tostring) == $idx))[0].uuid // empty' 2>/dev/null || true)"
  fi
  "$JQ_BIN" -e --arg idx "$space_idx" --arg uuid "$space_uuid" '
    (.spaces.locked_spaces // {}) as $locked
    | if ($locked | type) == "array" then
        ($locked | map(tostring) | index($idx) != null)
        or (($uuid != "") and ($locked | map(tostring) | index($uuid) != null))
      elif ($locked | type) == "object" then
        (($locked[$idx] // false) == true)
        or (($uuid != "") and (($locked[$uuid] // false) == true))
      else
        false
      end
  ' "$STATE_FILE" >/dev/null 2>&1
}

modifier_has() {
  local needle="$1"
  local raw="${MODIFIER:-${modifiers:-}}"
  [ -n "$raw" ] || return 1
  case ",$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')," in
    *"$needle"*)
      return 0
      ;;
  esac
  return 1
}

confirm_file_for_space() {
  local space_idx="$1"
  printf '/tmp/barista_space_close_confirm_%s_%s' "$UID" "$space_idx"
}

confirm_recent() {
  local file="$1"
  [ -f "$file" ] || return 1
  local now mtime
  now=$(date +%s)
  mtime=$(stat -f %m "$file" 2>/dev/null || echo 0)
  [ "$mtime" -gt 0 ] || return 1
  [ $(( now - mtime )) -le "$SPACE_CLOSE_CONFIRM_TTL_SEC" ]
}

mark_confirm() {
  local space_idx="$1"
  local file="$2"
  date +%s > "$file" 2>/dev/null || true
  sketchybar --set "space.$space_idx" \
    icon="󰅖" \
    icon.color=0xfff38ba8 \
    background.drawing=on \
    background.color=0x60f38ba8 >/dev/null 2>&1 || true
  nohup sh -c "
    sleep \"$SPACE_CLOSE_CONFIRM_TTL_SEC\"
    rm -f \"$file\" 2>/dev/null || true
    sketchybar --trigger space_change >/dev/null 2>&1 || true
  " >/dev/null 2>&1 &
}

swap_state_file() {
  printf '/tmp/barista_space_swap_state_%s' "$UID"
}

read_swap_source() {
  local file
  file=$(swap_state_file)
  [ -f "$file" ] || return 1

  local source_idx armed_at now
  source_idx=$(awk '{print $1}' "$file" 2>/dev/null || true)
  armed_at=$(awk '{print $2}' "$file" 2>/dev/null || true)
  case "$source_idx" in
    ''|*[!0-9]*) return 1 ;;
  esac
  case "$armed_at" in
    ''|*[!0-9]*) return 1 ;;
  esac

  now=$(date +%s)
  if [ $(( now - armed_at )) -gt "$SPACE_SWAP_ARM_TTL_SEC" ]; then
    rm -f "$file" 2>/dev/null || true
    sketchybar --trigger space_change >/dev/null 2>&1 || true
    return 1
  fi

  printf '%s' "$source_idx"
}

clear_swap_state() {
  local file
  file=$(swap_state_file)
  rm -f "$file" 2>/dev/null || true
  sync_swap_indicator
  sketchybar --trigger space_change >/dev/null 2>&1 || true
}

arm_swap_state() {
  local space_idx="$1"
  local file
  file=$(swap_state_file)
  printf '%s %s\n' "$space_idx" "$(date +%s)" > "$file" 2>/dev/null || true
  sync_swap_indicator

  sketchybar --set "space.$space_idx" \
    icon="󰚗" \
    icon.color=0xfff9e2af \
    background.drawing=on \
    background.color=0x60f9e2af >/dev/null 2>&1 || true

  nohup sh -c "
    sleep \"$SPACE_SWAP_ARM_TTL_SEC\"
    if [ -f \"$file\" ]; then
      rm -f \"$file\" 2>/dev/null || true
      sketchybar --set \"$SPACE_SWAP_INDICATOR_ITEM\" drawing=off label='' background.drawing=off >/dev/null 2>&1 || true
      sketchybar --trigger space_change >/dev/null 2>&1 || true
    fi
  " >/dev/null 2>&1 &
}

ensure_swap_indicator_item() {
  local indicator_height="${1:-}"
  if [ -z "$indicator_height" ]; then
    indicator_height="$(resolve_space_item_height)"
  fi
  if ! swap_indicator_enabled; then
    return 0
  fi
  if sketchybar --query "$SPACE_SWAP_INDICATOR_ITEM" >/dev/null 2>&1; then
    sketchybar --set "$SPACE_SWAP_INDICATOR_ITEM" background.height="$indicator_height" >/dev/null 2>&1 || true
    return 0
  fi
  sketchybar --add item "$SPACE_SWAP_INDICATOR_ITEM" left >/dev/null 2>&1 || true
  sketchybar --set "$SPACE_SWAP_INDICATOR_ITEM" \
    icon="󰚗" \
    icon.color="0xfff9e2af" \
    label="" \
    label.color="0xfff9e2af" \
    label.padding_left=4 \
    label.padding_right=8 \
    background.drawing=off \
    background.color="0x00000000" \
    background.corner_radius=8 \
    background.height="$indicator_height" \
    drawing=off \
    click_script="${SPACE_ACTION_ENV_PREFIX}${CONFIG_DIR}/scripts/space_action.sh swap-cancel" >/dev/null 2>&1 || true
}

sync_swap_indicator() {
  local indicator_height
  indicator_height="$(resolve_space_item_height)"
  ensure_swap_indicator_item "$indicator_height"
  if ! swap_indicator_enabled; then
    sketchybar --set "$SPACE_SWAP_INDICATOR_ITEM" drawing=off >/dev/null 2>&1 || true
    return 0
  fi

  local source_idx
  source_idx=$(read_swap_source || true)
  if [ -n "$source_idx" ]; then
    sketchybar --set "$SPACE_SWAP_INDICATOR_ITEM" \
      drawing=on \
      icon="󰚗" \
      label="Swap $source_idx -> select target" \
      background.drawing=on \
      background.height="$indicator_height" \
      background.color="0x40f9e2af" >/dev/null 2>&1 || true
  else
    sketchybar --set "$SPACE_SWAP_INDICATOR_ITEM" \
      drawing=off \
      label="" \
      background.drawing=off >/dev/null 2>&1 || true
  fi
}

toggle_space_menu() {
  local space_idx="$1"
  sketchybar --set "space.$space_idx" popup.drawing=toggle >/dev/null 2>&1 || true
}

hide_space_menu() {
  local space_idx="$1"
  sketchybar --set "space.$space_idx" popup.drawing=off >/dev/null 2>&1 || true
}

refresh_space_items() {
  local refresh_script="$CONFIG_DIR/plugins/refresh_spaces.sh"
  if [ -x "$refresh_script" ]; then
    (CONFIG_DIR="$CONFIG_DIR" BARISTA_LUA_ONLY="${BARISTA_LUA_ONLY:-0}" "$refresh_script" >/dev/null 2>&1 || true) &
    return 0
  fi
  sketchybar --trigger space_change >/dev/null 2>&1 || true
  sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
}

# With spaces.merge_front_app on, the active space chip stands in for the
# front_app chip: front_app moves in front of that chip and its own click
# script opens the app menu there.
open_front_app_menu() {
  local space_idx="$1"
  local click_script=""
  [ -n "$JQ_BIN" ] || return 1
  click_script=$(sketchybar --query front_app 2>/dev/null \
    | "$JQ_BIN" -r '.scripting.click_script // empty' 2>/dev/null || true)
  [ -n "$click_script" ] || return 1
  sketchybar --move front_app before "space.$space_idx" >/dev/null 2>&1 || true
  /bin/sh -c "$click_script" >/dev/null 2>&1 || true
}

focus_space() {
  local space_idx="$1"
  local focus_error=""
  if [ -z "$YABAI_BIN" ]; then
    return 1
  fi
  if focus_error=$(run_with_timeout 1 "$YABAI_BIN" -m space --focus "$space_idx" 2>&1 >/dev/null); then
    :
  elif [ -n "${BUTTON:-}" ] && [[ "$focus_error" == *"already focused"* ]] \
      && front_app_merged && open_front_app_menu "$space_idx"; then
    # A space_change trigger here would close the menu that just opened.
    return 0
  fi
  sketchybar --trigger space_change >/dev/null 2>&1 || true
  sketchybar --trigger space_mode_refresh >/dev/null 2>&1 || true
}

space_display() {
  local space_idx="$1"
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --spaces --space "$space_idx" 2>/dev/null | "$JQ_BIN" -r '.display // empty'
}

space_has_focus() {
  local space_idx="$1"
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --spaces --space "$space_idx" 2>/dev/null | "$JQ_BIN" -r '."has-focus" // false'
}

display_space_count() {
  local display_idx="$1"
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --spaces --display "$display_idx" 2>/dev/null | "$JQ_BIN" -r 'length // 0'
}

alternate_space_on_display() {
  local display_idx="$1"
  local exclude_idx="$2"
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --spaces --display "$display_idx" 2>/dev/null \
    | "$JQ_BIN" -r --argjson exclude "$exclude_idx" 'map(.index) | map(select(. != $exclude)) | .[0] // empty'
}

display_space_indices() {
  local display_idx="$1"
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --spaces --display "$display_idx" 2>/dev/null \
    | "$JQ_BIN" -r 'map(.index) | sort | .[]'
}

display_indices() {
  [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ] || return 1
  run_with_timeout 1 "$YABAI_BIN" -m query --displays 2>/dev/null \
    | "$JQ_BIN" -r 'map(.index) | sort | .[]'
}

neighbor_display() {
  local display_idx="$1"
  local direction="$2"
  local displays=()
  local entry
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    displays+=("$entry")
  done < <(display_indices)
  [ "${#displays[@]}" -gt 1 ] || return 1

  local pos=-1
  local i
  for i in "${!displays[@]}"; do
    if [ "${displays[$i]}" = "$display_idx" ]; then
      pos="$i"
      break
    fi
  done
  [ "$pos" -ge 0 ] || return 1

  if [ "$direction" = "prev" ]; then
    [ "$pos" -gt 0 ] || return 1
    printf '%s' "${displays[$((pos - 1))]}"
    return 0
  fi

  [ "$pos" -lt $(( ${#displays[@]} - 1 )) ] || return 1
  printf '%s' "${displays[$((pos + 1))]}"
}

neighbor_space_on_display() {
  local current_idx="$1"
  local direction="$2"
  if [ -n "$YABAI_BIN" ] && [ -n "$JQ_BIN" ]; then
    local spaces_json
    spaces_json="$(run_with_timeout 1 "$YABAI_BIN" -m query --spaces 2>/dev/null || true)"
    if [ -n "$spaces_json" ]; then
      printf '%s' "$spaces_json" | "$JQ_BIN" -r --argjson cur "$current_idx" --arg dir "$direction" '
        (map(select(.index == $cur))[0].display // empty) as $disp
        | if $disp == "" then empty
          else
            (map(select(.display == $disp) | .index) | sort) as $list
            | ($list | index($cur)) as $pos
            | if $pos == null or ($list | length) <= 1 then empty
              elif $dir == "left" and $pos > 0 then ($list[$pos - 1] | tostring)
              elif $dir == "right" and $pos < (($list | length) - 1) then ($list[$pos + 1] | tostring)
              else empty end
          end
      ' 2>/dev/null
      return 0
    fi
  fi
  local display_idx
  display_idx=$(space_display "$current_idx" || true)
  [ -n "$display_idx" ] || return 1

  local spaces=()
  local space_entry
  while IFS= read -r space_entry; do
    [ -n "$space_entry" ] || continue
    spaces+=("$space_entry")
  done < <(display_space_indices "$display_idx")
  [ "${#spaces[@]}" -gt 1 ] || return 1

  local pos=-1
  local i
  for i in "${!spaces[@]}"; do
    if [ "${spaces[$i]}" = "$current_idx" ]; then
      pos="$i"
      break
    fi
  done
  [ "$pos" -ge 0 ] || return 1

  if [ "$direction" = "left" ]; then
    [ "$pos" -gt 0 ] || return 1
    printf '%s' "${spaces[$((pos - 1))]}"
    return 0
  fi

  [ "$pos" -lt $(( ${#spaces[@]} - 1 )) ] || return 1
  printf '%s' "${spaces[$((pos + 1))]}"
}

move_space_to_display_neighbor() {
  local space_idx="$1"
  local direction="$2"
  [ -n "$YABAI_BIN" ] || return 1

  if space_is_locked "$space_idx"; then
    echo "Refusing to move locked space $space_idx across displays (spaces.locked_spaces)." >&2
    return 1
  fi

  local current_display target_display
  current_display=$(space_display "$space_idx" || true)
  [ -n "$current_display" ] || return 1

  case "$direction" in
    prev)
      target_display=$(neighbor_display "$current_display" "prev" || true)
      ;;
    next)
      target_display=$(neighbor_display "$current_display" "next" || true)
      ;;
    *)
      return 1
      ;;
  esac
  [ -n "$target_display" ] || return 0

  if [ "${FORCE_SPACE_ACTION:-0}" != "1" ] && [ -n "$JQ_BIN" ]; then
    local max_spaces dest_count src_count min_spaces
    max_spaces="$(max_spaces_per_display)"
    min_spaces="$(min_spaces_per_display)"
    src_count="$(display_space_count "$current_display" || echo 0)"
    if [ "${src_count:-0}" -le "$min_spaces" ]; then
      echo "Refusing to move space $space_idx off display $current_display: minimum of $min_spaces space(s) required." >&2
      return 1
    fi
    if [ "${max_spaces:-0}" -gt 0 ]; then
      dest_count="$(display_space_count "$target_display" || echo 0)"
      if [ "${dest_count:-0}" -ge "$max_spaces" ]; then
        echo "Refusing to move space $space_idx to display $target_display: limit of $max_spaces spaces reached." >&2
        return 1
      fi
    fi
  fi

  run_with_timeout 1 "$YABAI_BIN" -m space "$space_idx" --display "$target_display" >/dev/null 2>&1 || true
  refresh_space_items
}

move_space() {
  local from_idx="$1"
  local to_idx="$2"
  [ -n "$YABAI_BIN" ] || return 1
  if [ "$from_idx" = "$to_idx" ]; then
    return 0
  fi
  if space_is_locked "$from_idx" || space_is_locked "$to_idx"; then
    echo "Refusing to reorder locked space ($from_idx <-> $to_idx; spaces.locked_spaces)." >&2
    return 1
  fi
  if native_space_manager_available; then
    BARISTA_SPACE_MANAGER_NO_TRIGGER=1 "$SPACE_MANAGER_BIN" move "$from_idx" "$to_idx" >/dev/null 2>&1 || true
  else
    run_with_timeout 1 "$YABAI_BIN" -m space "$from_idx" --move "$to_idx" >/dev/null 2>&1 || true
  fi
  refresh_space_items
}

swap_spaces() {
  local from_idx="$1"
  local to_idx="$2"
  [ -n "$YABAI_BIN" ] || return 1
  if [ "$from_idx" = "$to_idx" ]; then
    return 0
  fi
  if space_is_locked "$from_idx" || space_is_locked "$to_idx"; then
    echo "Refusing to swap locked space ($from_idx <-> $to_idx; spaces.locked_spaces)." >&2
    return 1
  fi
  if native_space_manager_available; then
    BARISTA_SPACE_MANAGER_NO_TRIGGER=1 "$SPACE_MANAGER_BIN" swap "$from_idx" "$to_idx" >/dev/null 2>&1 || true
  else
    run_with_timeout 1 "$YABAI_BIN" -m space "$from_idx" --swap "$to_idx" >/dev/null 2>&1 || true
  fi
  refresh_space_items
}

reorder_space_relative() {
  local space_idx="$1"
  local direction="$2"
  local neighbor
  neighbor=$(neighbor_space_on_display "$space_idx" "$direction" || true)
  [ -n "$neighbor" ] || return 0
  move_space "$space_idx" "$neighbor"
}

cleanup_destroyed_space_state() {
  local space_idx="$1"
  local space_uuid="${2:-}"
  local state_writer=""
  if [ -f "$CONFIG_DIR/scripts/yabai_state.py" ]; then
    state_writer="$CONFIG_DIR/scripts/yabai_state.py"
  elif [ -f "$(dirname "${BASH_SOURCE[0]}")/yabai_state.py" ]; then
    state_writer="$(dirname "${BASH_SOURCE[0]}")/yabai_state.py"
  fi
  if [ -n "$state_writer" ] && [ -f "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
    python3 "$state_writer" "$STATE_FILE" space-unset "$space_idx" "$space_uuid" >/dev/null 2>&1 || true
  fi
}

destroy_space() {
  local space_idx="$1"
  [ -n "$YABAI_BIN" ] || return 1

  local display_idx="" count="0" focused="false" alt="" space_uuid="" is_fullscreen="false" win_count="0" win_ids=""
  if [ -n "$JQ_BIN" ]; then
    local spaces_json info_tsv
    spaces_json="$(run_with_timeout 1 "$YABAI_BIN" -m query --spaces 2>/dev/null || true)"
    if [ -n "$spaces_json" ]; then
      info_tsv="$(printf '%s' "$spaces_json" | "$JQ_BIN" -r --argjson idx "$space_idx" '
        (map(select(.index == $idx))[0]) as $target
        | if $target == null then ""
          else
            ($target.display) as $disp
            | (map(select(.display == $disp))) as $on_disp
            | [
                ($disp | tostring),
                ($on_disp | length | tostring),
                (($target."has-focus" // false) | tostring),
                (($on_disp | map(.index) | map(select(. != $idx))[0] // "") | tostring),
                ($target.uuid // ""),
                (($target."is-native-fullscreen" // false) | tostring),
                ((($target.windows // []) | length) | tostring),
                ((($target.windows // []) | map(tostring) | join(" ")))
              ] | @tsv
          end
      ' 2>/dev/null || true)"
      if [ -n "$info_tsv" ]; then
        IFS=$'\t' read -r display_idx count focused alt space_uuid is_fullscreen win_count win_ids <<< "$info_tsv"
      fi
    fi
  else
    display_idx=$(space_display "$space_idx" || true)
    if [ -n "$display_idx" ]; then
      count=$(display_space_count "$display_idx" || echo 0)
      focused=$(space_has_focus "$space_idx" || echo false)
      alt=$(alternate_space_on_display "$display_idx" "$space_idx" || true)
    fi
  fi

  if [ -z "$display_idx" ]; then
    return 1
  fi

  if [ "$is_fullscreen" = "true" ]; then
    echo "Refusing to destroy space $space_idx while it is in native fullscreen" >&2
    return 1
  fi

  if space_is_locked "$space_idx" "$space_uuid"; then
    echo "Refusing to destroy locked space $space_idx (spaces.locked_spaces)" >&2
    return 1
  fi

  local min_spaces=1
  if [ "${FORCE_SPACE_ACTION:-0}" != "1" ]; then
    min_spaces="$(min_spaces_per_display)"
  fi
  if [ "${count:-0}" -le 1 ]; then
    echo "Refusing to destroy last space on display $display_idx" >&2
    return 1
  fi
  if [ "${count:-0}" -le "$min_spaces" ]; then
    echo "Refusing to destroy space $space_idx on display $display_idx: minimum of $min_spaces spaces required (spaces.min_spaces_per_display)" >&2
    return 1
  fi

  if [ "${FORCE_SPACE_ACTION:-0}" != "1" ] && [ "${win_count:-0}" -gt 0 ]; then
    local ne_policy
    ne_policy="$(destroy_non_empty_policy)"
    case "$ne_policy" in
      refuse)
        echo "Refusing to destroy non-empty space $space_idx ($win_count window(s) present; spaces.destroy_non_empty_policy=refuse)" >&2
        return 1
        ;;
      evacuate)
        if [ -n "$alt" ] && [ -n "$win_ids" ]; then
          local wid
          for wid in $win_ids; do
            run_with_timeout 1 "$YABAI_BIN" -m window "$wid" --space "$alt" >/dev/null 2>&1 || true
          done
        fi
        ;;
    esac
  fi

  if [ "$focused" = "true" ] && [ -n "$alt" ]; then
    run_with_timeout 1 "$YABAI_BIN" -m space --focus "$alt" >/dev/null 2>&1 || true
  fi

  if native_space_manager_available; then
    BARISTA_SPACE_MANAGER_NO_TRIGGER=1 "$SPACE_MANAGER_BIN" destroy "$space_idx" >/dev/null 2>&1 || true
  else
    run_with_timeout 1 "$YABAI_BIN" -m space "$space_idx" --destroy >/dev/null 2>&1 || true
  fi

  # Saved labels and layouts belong to the surviving space if the destroy was
  # refused, so only clear them once the uuid is confirmed gone.
  if [ -n "$space_uuid" ] && [ -n "$JQ_BIN" ]; then
    if run_with_timeout 1 "$YABAI_BIN" -m query --spaces 2>/dev/null \
      | "$JQ_BIN" -e --arg uuid "$space_uuid" 'any(.[]; .uuid == $uuid) | not' >/dev/null 2>&1; then
      cleanup_destroyed_space_state "$space_idx" "$space_uuid"
    else
      echo "Space $space_idx was not destroyed; keeping its saved state" >&2
      refresh_space_items
      return 1
    fi
  fi
  refresh_space_items
}

create_space() {
  local target_display="${1:-active}"
  [ -n "$YABAI_BIN" ] || return 1

  local pre_spaces_json="" resolved_display="" display_count="0" focused_layout="" pre_uuids_csv=""
  local layout_policy="default"
  if [ -n "$JQ_BIN" ]; then
    layout_policy="$(new_space_layout_policy)"
    local max_spaces
    max_spaces="$(max_spaces_per_display)"
    if [ "${FORCE_SPACE_ACTION:-0}" != "1" ] && [ "${max_spaces:-0}" -gt 0 ] || [ "$layout_policy" != "default" ]; then
      pre_spaces_json="$(run_with_timeout 1 "$YABAI_BIN" -m query --spaces 2>/dev/null || true)"
      if [ -n "$pre_spaces_json" ]; then
        local pre_tsv
        pre_tsv="$(printf '%s' "$pre_spaces_json" | "$JQ_BIN" -r --arg td "$target_display" '
          (if ($td == "" or $td == "active") then
            (map(select(."has-focus" == true))[0].display // .[0].display // 1)
          else
            ($td | tonumber? // 1)
          end) as $disp
          | (map(select(.display == $disp))) as $on_disp
          | [
              ($disp | tostring),
              ($on_disp | length | tostring),
              ((map(select(."has-focus" == true))[0].type // $on_disp[-1].type // "bsp") | tostring),
              (map(.uuid // "") | join(","))
            ] | @tsv
        ' 2>/dev/null || true)"
        if [ -n "$pre_tsv" ]; then
          IFS=$'\t' read -r resolved_display display_count focused_layout pre_uuids_csv <<< "$pre_tsv"
        fi
      fi
    fi
    if [ "${FORCE_SPACE_ACTION:-0}" != "1" ] && [ "${max_spaces:-0}" -gt 0 ] && [ -n "$resolved_display" ]; then
      if [ "${display_count:-0}" -ge "$max_spaces" ]; then
        echo "Refusing to create space on display $resolved_display: limit of $max_spaces spaces reached (spaces.max_spaces_per_display)" >&2
        return 1
      fi
    fi
  fi

  case "$target_display" in
    ""|active)
      run_with_timeout 1 "$YABAI_BIN" -m display --focus mouse >/dev/null 2>&1 || true
      ;;
    *)
      run_with_timeout 1 "$YABAI_BIN" -m display --focus "$target_display" >/dev/null 2>&1 || true
      ;;
  esac

  if native_space_manager_available; then
    BARISTA_SPACE_MANAGER_NO_TRIGGER=1 "$SPACE_MANAGER_BIN" create >/dev/null 2>&1 || true
  else
    run_with_timeout 1 "$YABAI_BIN" -m space --create >/dev/null 2>&1 || true
  fi

  if [ -n "$JQ_BIN" ] && [ "$layout_policy" != "default" ]; then
    local desired_layout="$layout_policy"
    if [ "$desired_layout" = "inherit" ]; then
      desired_layout="${focused_layout:-bsp}"
    fi
    case "$desired_layout" in
      bsp|stack|float)
        local post_spaces_json new_space_idx=""
        post_spaces_json="$(run_with_timeout 1 "$YABAI_BIN" -m query --spaces 2>/dev/null || true)"
        if [ -n "$post_spaces_json" ]; then
          # Creating a space shifts every later index, so only the uuid
          # identifies the new space on multi-display setups.
          new_space_idx="$(printf '%s' "$post_spaces_json" | "$JQ_BIN" -r --arg pre "$pre_uuids_csv" --arg disp "${resolved_display:-1}" '
            ($pre | split(",")) as $known
            | (map(select((.uuid // "") as $u | $u != "" and ($known | index($u) == null)))[0].index)
              // (map(select((.display | tostring) == $disp))[-1].index)
              // empty
          ' 2>/dev/null || true)"
        fi
        if [ -n "$new_space_idx" ]; then
          if [ -x "$CONFIG_DIR/plugins/set_space_mode.sh" ]; then
            BARISTA_CONFIG_DIR="$CONFIG_DIR" BARISTA_STATE_FILE="$STATE_FILE" \
              "$CONFIG_DIR/plugins/set_space_mode.sh" "$new_space_idx" "$desired_layout" >/dev/null 2>&1 || true
          else
            run_with_timeout 1 "$YABAI_BIN" -m space "$new_space_idx" --layout "$desired_layout" >/dev/null 2>&1 || true
          fi
        fi
        ;;
    esac
  fi

  refresh_space_items
}

is_right_click() {
  local raw_button="${BUTTON:-${MOUSE_BUTTON:-${CLICK_BUTTON:-}}}"
  local button
  button=$(printf '%s' "$raw_button" | tr '[:upper:]' '[:lower:]')
  case "$button" in
    right|secondary)
      return 0
      ;;
  esac
  return 1
}

handle_close_request() {
  local space_idx="$1"
  local source="${2:-right_click}"
  local mode
  mode=$(right_click_close_mode)
  case "$mode" in
    off)
      if [ "$source" = "menu" ]; then
        destroy_space "$space_idx"
      else
        focus_space "$space_idx"
      fi
      ;;
    direct)
      destroy_space "$space_idx"
      ;;
    confirm)
      local confirm_file
      confirm_file=$(confirm_file_for_space "$space_idx")
      if confirm_recent "$confirm_file"; then
        rm -f "$confirm_file" 2>/dev/null || true
        destroy_space "$space_idx"
      else
        mark_confirm "$space_idx" "$confirm_file"
      fi
      ;;
  esac
}

handle_space_click() {
  local space_idx="$1"

  if is_right_click; then
    if context_menu_on_right_click; then
      toggle_space_menu "$space_idx"
    else
      handle_close_request "$space_idx" "right_click"
    fi
    return 0
  fi

  if modifier_reorder_enabled && modifier_has "shift"; then
    if modifier_has "cmd" || modifier_has "command"; then
      reorder_space_relative "$space_idx" "right"
    else
      reorder_space_relative "$space_idx" "left"
    fi
    hide_space_menu "$space_idx"
    return 0
  fi

  local armed_space
  armed_space=$(read_swap_source || true)
  if [ -n "$armed_space" ]; then
    if [ "$armed_space" = "$space_idx" ]; then
      clear_swap_state
      hide_space_menu "$space_idx"
      return 0
    fi
    swap_spaces "$armed_space" "$space_idx"
    clear_swap_state
    hide_space_menu "$space_idx"
    return 0
  fi

  focus_space "$space_idx"
}

usage() {
  cat <<'USAGE'
Usage: space_action.sh <command> [args]

Commands:
  create [--display <index|active>]
  click --space <index>
  focus --space <index>
  destroy --space <index>
  menu --space <index>
  menu-close --space <index>
  move-left --space <index>
  move-right --space <index>
  move-display-prev --space <index>
  move-display-next --space <index>
  swap-arm --space <index>
  swap-cancel
USAGE
}

FORCE_SPACE_ACTION="${BARISTA_SPACE_FORCE:-0}"
parse_space_arg() {
  local space_idx=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --space)
        shift
        space_idx="${1:-}"
        ;;
    esac
    shift || true
  done
  printf '%s' "$space_idx"
}

scan_force_flag() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --force|-f)
        FORCE_SPACE_ACTION=1
        export FORCE_SPACE_ACTION
        ;;
    esac
    shift || true
  done
}

command="${1:-}"
shift || true
scan_force_flag "$@"

case "$command" in
  focus|menu|click)
    if [ -f "$(swap_state_file)" ]; then
      sync_swap_indicator >/dev/null 2>&1 || true
    fi
    ;;
  *)
    sync_swap_indicator >/dev/null 2>&1 || true
    ;;
esac

case "$command" in
  create)
    target_display="active"
    while [ $# -gt 0 ]; do
      case "$1" in
        --display)
          shift
          target_display="${1:-active}"
          ;;
      esac
      shift || true
    done
    create_space "$target_display"
    ;;
  click)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    handle_space_click "$space_idx"
    ;;
  focus)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    focus_space "$space_idx"
    ;;
  destroy)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    destroy_space "$space_idx"
    ;;
  menu)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    toggle_space_menu "$space_idx"
    ;;
  menu-close)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    handle_close_request "$space_idx" "menu"
    hide_space_menu "$space_idx"
    ;;
  move-left)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    reorder_space_relative "$space_idx" "left"
    hide_space_menu "$space_idx"
    ;;
  move-right)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    reorder_space_relative "$space_idx" "right"
    hide_space_menu "$space_idx"
    ;;
  move-display-prev)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    move_space_to_display_neighbor "$space_idx" "prev"
    hide_space_menu "$space_idx"
    ;;
  move-display-next)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    move_space_to_display_neighbor "$space_idx" "next"
    hide_space_menu "$space_idx"
    ;;
  swap-arm)
    space_idx=$(parse_space_arg "$@")
    if [ -z "$space_idx" ]; then
      usage
      exit 1
    fi
    arm_swap_state "$space_idx"
    hide_space_menu "$space_idx"
    ;;
  swap-cancel)
    space_idx=$(parse_space_arg "$@")
    clear_swap_state
    if [ -n "$space_idx" ]; then
      hide_space_menu "$space_idx"
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
