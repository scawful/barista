#!/bin/bash
# Recompute display density after display topology changes.
# Reloads SketchyBar only when the density fingerprint changes.

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}}"
CACHE_DIR="${CONFIG_DIR}/cache"
FINGERPRINT_FILE="${CACHE_DIR}/display_density_fingerprint"
JQ_BIN="${BARISTA_JQ_BIN:-$(command -v jq 2>/dev/null || true)}"
SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar || true)}}"
RELOAD_SCRIPT="${CONFIG_DIR}/plugins/reload_sketchybar.sh"
DENSE_MAX_WIDTH="${BARISTA_DENSE_MAX_WIDTH:-1000}"
COMPACT_MAX_WIDTH="${BARISTA_COMPACT_MAX_WIDTH:-1400}"

mkdir -p "$CACHE_DIR"

density_for_width() {
  local width="$1"
  if [ -z "$width" ] || [ "$width" -le 0 ] 2>/dev/null; then
    echo "comfortable"
    return
  fi
  if [ "$width" -lt "$DENSE_MAX_WIDTH" ]; then
    echo "dense"
  elif [ "$width" -lt "$COMPACT_MAX_WIDTH" ]; then
    echo "compact"
  else
    echo "comfortable"
  fi
}

compute_fingerprint() {
  local min_width=""
  local wide=""
  local narrow=""
  local id width height

  if [ -z "$SKETCHYBAR_BIN" ] || ! command -v "$SKETCHYBAR_BIN" >/dev/null 2>&1; then
    echo "comfortable|min=|wide=|narrow="
    return
  fi

  while IFS=$'\t' read -r id width height; do
    [ -n "$id" ] || continue
    [ -n "$width" ] || continue
    if [ -z "$min_width" ] || [ "$width" -lt "$min_width" ]; then
      min_width="$width"
    fi
    if [ "$width" -lt "$DENSE_MAX_WIDTH" ] || { [ -n "$height" ] && [ "$height" -gt "$width" ]; }; then
      if [ -n "$narrow" ]; then
        narrow="${narrow},${id}"
      else
        narrow="$id"
      fi
    else
      if [ -n "$wide" ]; then
        wide="${wide},${id}"
      else
        wide="$id"
      fi
    fi
  done < <(
    [ -n "$JQ_BIN" ] || exit 0
    "$SKETCHYBAR_BIN" --query displays 2>/dev/null | "$JQ_BIN" -r '
      .[]? | select(."arrangement-id" != null and .frame.w != null)
      | "\(."arrangement-id" | floor)\t\(.frame.w | round)\t\((.frame.h // 0) | round)"
    ' 2>/dev/null || true
  )

  # Must match display_profile.classify_displays byte for byte: main.lua
  # writes that fingerprint on every reload, so any difference reloads forever.
  local density split=0
  density="$(density_for_width "${min_width:-0}")"
  if [ -n "$wide" ] && [ -n "$narrow" ]; then
    split=1
  fi
  echo "${density}|min=${min_width:-}|wide=${wide}|narrow=${narrow}|split=${split}"
}

PREVIOUS="$(cat "$FINGERPRINT_FILE" 2>/dev/null || true)"
CURRENT="$(compute_fingerprint)"

# Do not clobber a valid fingerprint with an empty topology probe
# (common during early post-config before SketchyBar answers queries).
if [[ "$CURRENT" == comfortable\|min=\|wide=\|narrow=\|split=0 ]] \
  || [[ "$CURRENT" == comfortable\|min=\|wide=\|narrow= ]]; then
  if [ -n "$PREVIOUS" ] && [[ "$PREVIOUS" != comfortable\|min=\|wide=\|narrow=\|split=0 ]] \
    && [[ "$PREVIOUS" != comfortable\|min=\|wide=\|narrow= ]]; then
    exit 0
  fi
fi

if [ -n "$PREVIOUS" ] && [ "$PREVIOUS" = "$CURRENT" ]; then
  exit 0
fi

echo "$CURRENT" > "$FINGERPRINT_FILE"

# First boot / empty previous: publish fingerprint only; main.lua already
# configured for the current topology.
if [ -z "$PREVIOUS" ] \
  || [[ "$PREVIOUS" == comfortable\|min=\|wide=\|narrow=\|split=0 ]] \
  || [[ "$PREVIOUS" == comfortable\|min=\|wide=\|narrow= ]]; then
  exit 0
fi

if [ -x "$RELOAD_SCRIPT" ]; then
  CONFIG_DIR="$CONFIG_DIR" "$RELOAD_SCRIPT" >/dev/null 2>&1 &
fi
