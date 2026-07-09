#!/usr/bin/env bash

set -euo pipefail

PATH="${PATH:-}:$HOME/.lmstudio/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

_d="${0%/*}"
[ -z "$_d" ] && _d="."
[ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-lmstudio}"
ACTION="${1:-refresh}"
CONTROL_SCRIPT="${SCRIPTS_DIR}/lmstudio_control.sh"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"

set_popup_item() {
  local item="$1"
  shift
  "$SKETCHYBAR_BIN" --set "$item" "$@" >/dev/null 2>&1 || true
}

loaded_models_json() {
  if ! command -v lms >/dev/null 2>&1; then
    return 0
  fi
  lms ps --json 2>/dev/null || true
}

loaded_identifiers() {
  local json="${1:-}"
  if [[ -z "$json" ]]; then
    json="$(loaded_models_json)"
  fi
  if [[ -z "$json" ]]; then
    return 0
  fi
  printf '%s' "$json" | jq -r '.[] | (.identifier // .modelKey // .model_key // .id // .path // .name // "")' 2>/dev/null || true
}

primary_indexed_model_identifier() {
  local json="${1:-}"
  if [[ -z "$json" ]]; then
    json="$(loaded_models_json)"
  fi
  if [[ -z "$json" ]]; then
    return 0
  fi
  printf '%s' "$json" | jq -r '.[0] | (.indexedModelIdentifier // .indexed_model_identifier // .modelKey // .model_key // .path // .identifier // .id // empty)' 2>/dev/null || true
}

uri_encode() {
  local value="$1"
  jq -rn --arg value "$value" '$value|@uri' 2>/dev/null || return 1
}

current_model_deeplink() {
  local json="${1:-}"
  local identifier
  identifier="$(primary_indexed_model_identifier "$json")"
  if [[ -z "$identifier" ]]; then
    return 0
  fi

  local encoded
  encoded="$(uri_encode "$identifier")" || return 1
  printf 'lmstudio://open_from_hf?model=%s' "$encoded"
}

model_short_name() {
  local identifier="$1"
  case "$identifier" in
    *"scawfulbot-qwen3-8b-v1-mlx-long"*) printf '%s' "long" ;;
    *"scawfulbot-qwen3-8b-v1-mlx"*) printf '%s' "mlx" ;;
    *"scawful@q4_k_m"*|*"scawfulbot-qwen3-8b-v1-q4_k_m"*) printf '%s' "gguf" ;;
    *"scawful-echo-mlx"*|*"echo-v1"*) printf '%s' "echo" ;;
    *"scawful-echo.gguf"*|*"scawful-echo"*) printf '%s' "echo" ;;
    *"oracle-tools-7b"*) printf '%s' "oracle" ;;
    *"scawful-memory"*) printf '%s' "memory" ;;
    *"scawful-muse"*) printf '%s' "muse" ;;
    *"router-v1-q8"*) printf '%s' "router" ;;
    *"qwen2.5-coder-7b"*) printf '%s' "coder" ;;
    *"zelda-nayru"*) printf '%s' "nayru" ;;
    *"zelda-din"*) printf '%s' "din" ;;
    *"zelda-farore"*) printf '%s' "farore" ;;
    *"zelda-veran"*) printf '%s' "veran" ;;
    *"zelda-hylia"*) printf '%s' "hylia" ;;
    *"zelda-majora"*) printf '%s' "majora" ;;
    *"zelda-scribe"*) printf '%s' "scribe" ;;
    *)
      local base="${identifier##*/}"
      base="${base%.gguf}"
      base="${base%.safetensors}"
      base="${base%.bin}"
      base="${base#gguf-}"
      base="${base#mlx-}"
      base="${base#scawful-}"
      base="${base#zelda-}"
      base="${base%%-*}"
      if [[ -z "$base" ]]; then
        printf '%s' "model"
      else
        printf '%s' "${base:0:6}"
      fi
      ;;
  esac
}

model_long_name() {
  local identifier="$1"
  case "$identifier" in
    *"scawfulbot-qwen3-8b-v1-mlx-long"*) printf '%s' "scawfulbot MLX long" ;;
    *"scawfulbot-qwen3-8b-v1-mlx"*) printf '%s' "scawfulbot MLX" ;;
    *"scawful@q4_k_m"*|*"scawfulbot-qwen3-8b-v1-q4_k_m"*) printf '%s' "scawfulbot GGUF" ;;
    *"scawful-echo-mlx"*|*"echo-v1"*|*"scawful-echo"*) printf '%s' "scawful echo" ;;
    *"oracle-tools-7b"*) printf '%s' "oracle tools" ;;
    *"scawful-memory"*) printf '%s' "scawful memory" ;;
    *"scawful-muse"*) printf '%s' "scawful muse" ;;
    *"router-v1-q8"*) printf '%s' "router" ;;
    *"qwen2.5-coder-7b"*) printf '%s' "qwen coder" ;;
    *"zelda-nayru"*) printf '%s' "zelda nayru" ;;
    *"zelda-din"*) printf '%s' "zelda din" ;;
    *"zelda-farore"*) printf '%s' "zelda farore" ;;
    *"zelda-veran"*) printf '%s' "zelda veran" ;;
    *"zelda-hylia"*) printf '%s' "zelda hylia" ;;
    *"zelda-majora"*) printf '%s' "zelda majora" ;;
    *"zelda-scribe"*) printf '%s' "zelda scribe" ;;
    *)
      local base="${identifier##*/}"
      base="${base%.gguf}"
      base="${base%.safetensors}"
      base="${base%.bin}"
      printf '%s' "$base"
      ;;
  esac
}

model_color() {
  local identifier="$1"
  case "$identifier" in
    *"scawfulbot-qwen3-8b-v1-mlx"*) printf '%s' "0xffa6e3a1" ;;
    *"scawful@q4_k_m"*|*"scawfulbot-qwen3-8b-v1-q4_k_m"*) printf '%s' "0xfff9e2af" ;;
    *"scawful-echo"*|*"echo-v1"*) printf '%s' "0xff89b4fa" ;;
    *"oracle-tools-7b"*) printf '%s' "0xffcba6f7" ;;
    *"scawful-memory"*|*"scawful-muse"*) printf '%s' "0xff94e2d5" ;;
    *"zelda-"*) printf '%s' "0xfffab387" ;;
    *)
      printf '%s' "0xff94e2d5"
      ;;
  esac
}

join_by() {
  local delimiter="$1"
  shift
  local first=1
  local value
  for value in "$@"; do
    if [[ $first -eq 1 ]]; then
      printf '%s' "$value"
      first=0
    else
      printf '%s%s' "$delimiter" "$value"
    fi
  done
}

update_widget() {
  local label="$1"
  local icon_color="$2"
  local state_label="$3"

  "$SKETCHYBAR_BIN" --set "$NAME" \
    icon="󰭻" \
    icon.color="$icon_color" \
    label="$label" \
    label.color="0xffcdd6f4" >/dev/null 2>&1 || true

  set_popup_item "lmstudio.state" "label=$state_label" "icon.color=$icon_color"
}

refresh_status() {
  if ! command -v lms >/dev/null 2>&1; then
    update_widget "n/a" "0xfff38ba8" "LM Studio CLI unavailable"
    return 0
  fi

  local json
  json="$(loaded_models_json)"
  if [[ -z "$json" ]]; then
    update_widget "err" "0xfff38ba8" "LM Studio service unavailable"
    return 0
  fi

  local count
  count="$(printf '%s' "$json" | jq 'length' 2>/dev/null || printf '0')"
  if [[ "$count" == "0" ]]; then
    update_widget "off" "0xff6c7086" "No models loaded"
    return 0
  fi

  local -a identifiers=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && identifiers+=("$line")
  done < <(loaded_identifiers "$json")

  if [[ "${#identifiers[@]}" -eq 0 ]]; then
    update_widget "on" "0xff94e2d5" "Loaded: model"
    return 0
  fi

  local primary="${identifiers[0]}"
  local primary_short primary_long color
  primary_short="$(model_short_name "$primary")"
  primary_long="$(model_long_name "$primary")"
  color="$(model_color "$primary")"

  if [[ "${#identifiers[@]}" -eq 1 ]]; then
    update_widget "$primary_short" "$color" "Loaded: $primary_long"
    return 0
  fi

  local -a long_names=()
  for line in "${identifiers[@]}"; do
    long_names+=("$(model_long_name "$line")")
  done

  local short_bar="$primary_short"
  if [[ "${#short_bar}" -gt 6 ]]; then
    short_bar="${short_bar:0:6}"
  fi
  update_widget "${short_bar}+" "$color" "Loaded (${#identifiers[@]}): $(join_by ', ' "${long_names[@]}")"
}

open_current() {
  local json
  json="$(loaded_models_json)"

  local -a identifiers=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && identifiers+=("$line")
  done < <(loaded_identifiers "$json")

  if [[ "${#identifiers[@]}" -eq 0 ]]; then
    open -ga "LM Studio" >/dev/null 2>&1 || true
    osascript -e 'tell application "LM Studio" to activate' >/dev/null 2>&1 || true
    refresh_status
    return 0
  fi

  local deeplink
  deeplink="$(current_model_deeplink "$json")"
  if [[ -n "$deeplink" ]]; then
    open "$deeplink" >/dev/null 2>&1 || true
    refresh_status
    return 0
  fi

  open -ga "LM Studio" >/dev/null 2>&1 || true
  osascript -e 'tell application "LM Studio" to activate' >/dev/null 2>&1 || true

  local label
  if [[ "${#identifiers[@]}" -eq 1 ]]; then
    label="$(model_long_name "${identifiers[0]}")"
  else
    local -a names=()
    for line in "${identifiers[@]}"; do
      names+=("$(model_long_name "$line")")
    done
    label="$(join_by ', ' "${names[@]}")"
  fi

  set_popup_item "lmstudio.state" "label=Loaded: $label"
}

run_action_async() {
  local mode="$1"
  if [[ ! -x "$CONTROL_SCRIPT" ]]; then
    update_widget "err" "0xfff38ba8" "LM Studio control script missing"
    return 1
  fi

  update_widget "..." "0xfff9e2af" "Switching model..."
  (
    "$CONTROL_SCRIPT" "$mode" >/tmp/barista-lmstudio-control.log 2>&1 || true
    "$0" refresh >/dev/null 2>&1 || true
  ) >/dev/null 2>&1 &
}

case "${SENDER:-}" in
  mouse.entered)
    highlight_with_timeout "$NAME" "background.drawing=on background.color=$HIGHLIGHT" "background.drawing=off"
    exit 0
    ;;
  mouse.exited)
    clear_highlight "$NAME" "background.drawing=off"
    exit 0
    ;;
  mouse.exited.global)
    "$SKETCHYBAR_BIN" --set "$NAME" popup.drawing=off >/dev/null 2>&1 || true
    clear_highlight "$NAME" "background.drawing=off"
    exit 0
    ;;
esac

case "$ACTION" in
  refresh|"")
    refresh_status
    ;;
  mlx|long|gguf|echo|off)
    run_action_async "$ACTION"
    ;;
  open_current|current)
    open_current
    ;;
  open)
    if [[ -x "$CONTROL_SCRIPT" ]]; then
      "$CONTROL_SCRIPT" open >/dev/null 2>&1 || true
    else
      open -a "LM Studio" >/dev/null 2>&1 || true
    fi
    refresh_status
    ;;
  *)
    refresh_status
    ;;
esac
