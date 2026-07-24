#!/bin/bash
# Thin fallback stub — the compiled C binary (popup_manager) handles this.
# This script exists only as a fallback for Lua-only mode.

TMPDIR="${TMPDIR:-/tmp}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="sketchybar"
POPUP_ITEMS=()
SUBMENU_ITEMS=()
ANCESTOR_TARGETS=()
ANCESTOR_ITEMS=()
PRESERVED_SUBMENUS=()
MAX_TOPOLOGY_NAMES=128
MAX_TOPOLOGY_RELATIONS=512
MAX_TOPOLOGY_NAME_LENGTH=127

load_items() {
  local path="$1"
  local target="$2"
  if [ -f "$path" ]; then
    while IFS= read -r item || [ -n "$item" ]; do
      [ -n "$item" ] || continue
      case "$target" in
        POPUP_ITEMS) POPUP_ITEMS+=("$item") ;;
        SUBMENU_ITEMS) SUBMENU_ITEMS+=("$item") ;;
      esac
    done < "$path"
    return 0
  fi
  return 1
}

load_event_topology() {
  if ! load_items "$TMPDIR/sketchybar_popup_list" POPUP_ITEMS; then
    POPUP_ITEMS=(apple_menu front_app clock system_info volume battery control_center)
  fi

  if ! load_items "$TMPDIR/sketchybar_submenu_list" SUBMENU_ITEMS; then
    SUBMENU_ITEMS=(yaze.recent_roms emacs.recent_org)
  fi
}

load_click_topology() {
  local LC_ALL=C
  local path="$TMPDIR/sketchybar_popup_topology"
  local fields=()
  local version_seen=0
  local generation_seen=0
  local topology_entry_seen=0
  local expected_generation="${BARISTA_POPUP_TOPOLOGY_TOKEN:-}"
  local line
  [ -f "$path" ] || return 1
  /usr/bin/grep -Iq . "$path" || return 1
  if /usr/bin/grep -q $'\r' "$path"; then
    return 1
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    fields=()
    IFS=$'\t' read -r -a fields <<< "$line"

    if [ "$version_seen" -eq 0 ]; then
      if [ "${#fields[@]}" -ne 2 ] || [ "${fields[0]:-}" != "version" ] \
          || [ "${fields[1]:-}" != "1" ]; then
        POPUP_ITEMS=()
        SUBMENU_ITEMS=()
        ANCESTOR_TARGETS=()
        ANCESTOR_ITEMS=()
        return 1
      fi
      version_seen=1
      continue
    fi

    case "${fields[0]:-}" in
      generation)
        [ "${#fields[@]}" -eq 2 ] && [ -n "${fields[1]:-}" ] || return 1
        [ "$generation_seen" -eq 0 ] && [ "$topology_entry_seen" -eq 0 ] || return 1
        if [ -n "$expected_generation" ] \
            && [ "${fields[1]}" != "$expected_generation" ]; then
          return 1
        fi
        generation_seen=1
        ;;
      root)
        [ "${#fields[@]}" -eq 2 ] && [ -n "${fields[1]:-}" ] || return 1
        [ "${#fields[1]}" -le "$MAX_TOPOLOGY_NAME_LENGTH" ] || return 1
        topology_entry_seen=1
        if ! array_contains "${fields[1]}" "${POPUP_ITEMS[@]}"; then
          [ "${#POPUP_ITEMS[@]}" -lt "$MAX_TOPOLOGY_NAMES" ] || return 1
          POPUP_ITEMS+=("${fields[1]}")
        fi
        ;;
      child)
        [ "${#fields[@]}" -eq 2 ] && [ -n "${fields[1]:-}" ] || return 1
        [ "${#fields[1]}" -le "$MAX_TOPOLOGY_NAME_LENGTH" ] || return 1
        topology_entry_seen=1
        if ! array_contains "${fields[1]}" "${SUBMENU_ITEMS[@]}"; then
          [ "${#SUBMENU_ITEMS[@]}" -lt "$MAX_TOPOLOGY_NAMES" ] || return 1
          SUBMENU_ITEMS+=("${fields[1]}")
        fi
        ;;
      ancestor)
        [ "${#fields[@]}" -eq 3 ] && [ -n "${fields[1]:-}" ] \
          && [ -n "${fields[2]:-}" ] || return 1
        [ "${#fields[1]}" -le "$MAX_TOPOLOGY_NAME_LENGTH" ] \
          && [ "${#fields[2]}" -le "$MAX_TOPOLOGY_NAME_LENGTH" ] || return 1
        [ "${fields[1]}" != "${fields[2]}" ] || return 1
        topology_entry_seen=1
        if ! ancestor_relation_exists "${fields[1]}" "${fields[2]}"; then
          [ "${#ANCESTOR_TARGETS[@]}" -lt "$MAX_TOPOLOGY_RELATIONS" ] || return 1
          ANCESTOR_TARGETS+=("${fields[1]}")
          ANCESTOR_ITEMS+=("${fields[2]}")
        fi
        ;;
      *)
        return 1
        ;;
    esac
  done < "$path"

  [ "$version_seen" -eq 1 ] \
    && { [ -z "$expected_generation" ] || [ "$generation_seen" -eq 1 ]; }
}

array_contains() {
  local candidate="$1"
  shift
  local item
  for item in "$@"; do
    [ "$item" = "$candidate" ] && return 0
  done
  return 1
}

ancestor_relation_exists() {
  local candidate_target="$1"
  local candidate_ancestor="$2"
  local index
  for ((index = 0; index < ${#ANCESTOR_TARGETS[@]}; index++)); do
    if [ "${ANCESTOR_TARGETS[$index]}" = "$candidate_target" ] \
        && [ "${ANCESTOR_ITEMS[$index]}" = "$candidate_ancestor" ]; then
      return 0
    fi
  done
  return 1
}

clear_hover_state() {
  [ -e "$TMPDIR/sketchybar_submenu_active" ] \
    || [ -e "$TMPDIR/sketchybar_parent_popup_lock" ] \
    || return 0
  rm -f \
    "$TMPDIR/sketchybar_submenu_active" \
    "$TMPDIR/sketchybar_parent_popup_lock"
}

prepare_preserved_submenus() {
  local target="$1"
  local index
  PRESERVED_SUBMENUS=()
  for ((index = 0; index < ${#ANCESTOR_TARGETS[@]}; index++)); do
    if [ "${ANCESTOR_TARGETS[$index]}" = "$target" ]; then
      PRESERVED_SUBMENUS+=("${ANCESTOR_ITEMS[$index]}")
    fi
  done
}

is_preserved_submenu() {
  local candidate="$1"
  local item
  for item in "${PRESERVED_SUBMENUS[@]}"; do
    [ "$item" = "$candidate" ] && return 0
  done
  return 1
}

dismiss_all() {
  local args=()
  local status=0
  for item in "${POPUP_ITEMS[@]}"; do
    [ -n "$item" ] || continue
    args+=(--set "$item" popup.drawing=off)
  done
  for item in "${SUBMENU_ITEMS[@]}"; do
    [ -n "$item" ] || continue
    args+=(--set "$item" popup.drawing=off background.drawing=off background.color=0x00000000)
  done
  if [ "${#args[@]}" -gt 0 ]; then
    "$SKETCHYBAR_BIN" "${args[@]}" >/dev/null 2>&1 || status=$?
  fi
  clear_hover_state
  return "$status"
}

switch_popup() {
  local scope="$1"
  local target="$2"
  local args=()
  if [ "$scope" = "submenu" ]; then
    prepare_preserved_submenus "$target"
  fi

  if [ "$scope" = "switch" ]; then
    for item in "${POPUP_ITEMS[@]}"; do
      [ -n "$item" ] || continue
      [ "$item" = "$target" ] && continue
      args+=(--set "$item" popup.drawing=off)
    done
  fi

  for item in "${SUBMENU_ITEMS[@]}"; do
    [ -n "$item" ] || continue
    if [ "$scope" = "submenu" ] \
        && { [ "$item" = "$target" ] || is_preserved_submenu "$item"; }; then
      continue
    fi
    args+=(--set "$item" popup.drawing=off background.drawing=off background.color=0x00000000)
  done

  args+=(--set "$target" popup.drawing=toggle)
  clear_hover_state
  exec "$SKETCHYBAR_BIN" "${args[@]}"
}

case "${1:-}" in
  protocol)
    [ "$#" -eq 1 ] || {
      echo "Usage: $0 [protocol|switch|submenu <item>]" >&2
      exit 2
    }
    printf '%s\n' "barista-popup-switch-v1"
    exit 0
    ;;
  switch|submenu)
    if [ "$#" -ne 2 ] || [ -z "${2:-}" ]; then
      echo "Usage: $0 [protocol|switch|submenu <item>]" >&2
      exit 2
    fi
    if ! load_click_topology; then
      POPUP_ITEMS=()
      SUBMENU_ITEMS=()
      ANCESTOR_TARGETS=()
      ANCESTOR_ITEMS=()
    fi
    switch_popup "$1" "$2"
    exit $?
    ;;
  "")
    ;;
  *)
    echo "Usage: $0 [protocol|switch|submenu <item>]" >&2
    exit 2
    ;;
esac

load_event_topology
case "${SENDER:-}" in
  "space_change"|"display_changed"|"display_added"|"display_removed"|"system_woke")
    dismiss_all || true
    ;;
  "front_app_switched")
    if [ "${DISMISS_ON_APP_SWITCH:-0}" != "0" ]; then
      dismiss_all || true
    fi
    ;;
esac
