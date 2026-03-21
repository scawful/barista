#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="${BARISTA_STATE_FILE:-$CONFIG_DIR/state.json}"
FONT_DIRS_RAW="${BARISTA_FONT_DIRS:-$HOME/Library/Fonts:/Library/Fonts:/System/Library/Fonts}"

APPLY_STATE=0
REPORT=0

usage() {
  cat <<EOF
Usage: $0 [--state <path>] [--apply-state] [--report]

Detect the best available Barista font families for icons, text, and numbers.

Options:
  --state <path>   state.json path (default: ~/.config/sketchybar/state.json)
  --apply-state    write selected fonts back into state.json
  --report         print machine-readable key=value output

Environment:
  BARISTA_FONT_DIRS  Colon-separated font search paths for detection/testing
EOF
}

expand_home() {
  case "$1" in
    ~/*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    ~) printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --state)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --apply-state)
      APPLY_STATE=1
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

IFS=':' read -r -a FONT_DIRS <<< "$FONT_DIRS_RAW"
for i in "${!FONT_DIRS[@]}"; do
  FONT_DIRS[i]="$(expand_home "${FONT_DIRS[i]}")"
done

font_patterns_for_family() {
  case "$1" in
    "Hack Nerd Font")
      printf '%s\n' "Hack Nerd Font" "HackNerdFont"
      ;;
    "Symbols Nerd Font Mono")
      printf '%s\n' "Symbols Nerd Font Mono" "SymbolsNerdFontMono"
      ;;
    "Symbols Nerd Font")
      printf '%s\n' "Symbols Nerd Font" "SymbolsNerdFont"
      ;;
    "JetBrainsMono Nerd Font")
      printf '%s\n' "JetBrainsMono Nerd Font" "JetBrainsMonoNerdFont"
      ;;
    "JetBrains Mono")
      printf '%s\n' "JetBrains Mono" "JetBrainsMono"
      ;;
    "MesloLGS Nerd Font")
      printf '%s\n' "MesloLGS Nerd Font" "MesloLGSNerdFont"
      ;;
    "Source Code Pro")
      printf '%s\n' "Source Code Pro" "SourceCodePro"
      ;;
    "SF Pro Text")
      printf '%s\n' "SF Pro Text" "SFProText"
      ;;
    "SF Pro Display")
      printf '%s\n' "SF Pro Display" "SFProDisplay"
      ;;
    "SF Pro")
      printf '%s\n' "SF Pro" "SFPro"
      ;;
    "SF Mono")
      printf '%s\n' "SF Mono" "SFMono"
      ;;
    "SF Symbols")
      printf '%s\n' "SF Symbols" "SFSymbols" "SF-Symbols"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

font_family_installed() {
  local family="$1"
  local dir pattern

  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    for dir in "${FONT_DIRS[@]}"; do
      [ -d "$dir" ] || continue
      if find "$dir" -maxdepth 1 -iname "*$pattern*" -print -quit 2>/dev/null | grep -q .; then
        return 0
      fi
    done
  done < <(font_patterns_for_family "$family")

  return 1
}

read_state_font() {
  local key="$1"
  if ! command -v jq >/dev/null 2>&1 || [ ! -f "$STATE_FILE" ]; then
    return 0
  fi
  jq -r ".appearance.${key} // empty" "$STATE_FILE" 2>/dev/null || true
}

choose_font() {
  local configured="$1"
  shift

  if [ -n "$configured" ] && font_family_installed "$configured"; then
    printf '%s\n' "$configured|configured|1"
    return 0
  fi

  local family
  for family in "$@"; do
    if font_family_installed "$family"; then
      printf '%s\n' "$family|detected|1"
      return 0
    fi
  done

  if [ -n "$configured" ]; then
    printf '%s\n' "$configured|missing|0"
  else
    printf '%s\n' "|missing|0"
  fi
}

ICON_FONTS=(
  "Hack Nerd Font"
  "Symbols Nerd Font Mono"
  "JetBrainsMono Nerd Font"
  "MesloLGS Nerd Font"
  "Symbols Nerd Font"
  "SF Symbols"
  "Menlo"
)

TEXT_FONTS=(
  "Source Code Pro"
  "SF Pro Text"
  "SF Pro Display"
  "SF Pro"
  "JetBrains Mono"
  "SF Mono"
  "Menlo"
)

NUMBER_FONTS=(
  "SF Mono"
  "JetBrains Mono"
  "Source Code Pro"
  "Menlo"
  "Monaco"
)

CONFIGURED_ICON="$(read_state_font font_icon)"
CONFIGURED_TEXT="$(read_state_font font_text)"
CONFIGURED_NUMBERS="$(read_state_font font_numbers)"

IFS='|' read -r SELECTED_ICON ICON_SOURCE ICON_INSTALLED <<< "$(choose_font "$CONFIGURED_ICON" "${ICON_FONTS[@]}")"
IFS='|' read -r SELECTED_TEXT TEXT_SOURCE TEXT_INSTALLED <<< "$(choose_font "$CONFIGURED_TEXT" "${TEXT_FONTS[@]}")"
IFS='|' read -r SELECTED_NUMBERS NUMBERS_SOURCE NUMBERS_INSTALLED <<< "$(choose_font "$CONFIGURED_NUMBERS" "${NUMBER_FONTS[@]}")"

apply_state() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for --apply-state" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$STATE_FILE")"
  if [ ! -f "$STATE_FILE" ]; then
    printf '{}' > "$STATE_FILE"
  fi

  local tmp
  tmp="$(mktemp)"
  jq \
    --arg icon "$SELECTED_ICON" \
    --arg text "$SELECTED_TEXT" \
    --arg numbers "$SELECTED_NUMBERS" \
    '
      .appearance = (.appearance // {}) |
      .appearance.font_icon = (if $icon != "" then $icon else .appearance.font_icon end) |
      .appearance.font_text = (if $text != "" then $text else .appearance.font_text end) |
      .appearance.font_numbers = (if $numbers != "" then $numbers else .appearance.font_numbers end)
    ' \
    "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

if [ "$APPLY_STATE" -eq 1 ]; then
  apply_state
fi

if [ "$REPORT" -eq 1 ]; then
  printf 'font.report.state_file=%s\n' "$STATE_FILE"
  printf 'font.report.configured.icon=%s\n' "$CONFIGURED_ICON"
  printf 'font.report.configured.text=%s\n' "$CONFIGURED_TEXT"
  printf 'font.report.configured.numbers=%s\n' "$CONFIGURED_NUMBERS"
  printf 'font.report.selected.icon=%s\n' "$SELECTED_ICON"
  printf 'font.report.selected.text=%s\n' "$SELECTED_TEXT"
  printf 'font.report.selected.numbers=%s\n' "$SELECTED_NUMBERS"
  printf 'font.report.source.icon=%s\n' "$ICON_SOURCE"
  printf 'font.report.source.text=%s\n' "$TEXT_SOURCE"
  printf 'font.report.source.numbers=%s\n' "$NUMBERS_SOURCE"
  printf 'font.report.installed.icon=%s\n' "$ICON_INSTALLED"
  printf 'font.report.installed.text=%s\n' "$TEXT_INSTALLED"
  printf 'font.report.installed.numbers=%s\n' "$NUMBERS_INSTALLED"
  exit 0
fi

printf 'Icon font: %s (%s)\n' "${SELECTED_ICON:-missing}" "$ICON_SOURCE"
printf 'Text font: %s (%s)\n' "${SELECTED_TEXT:-missing}" "$TEXT_SOURCE"
printf 'Number font: %s (%s)\n' "${SELECTED_NUMBERS:-missing}" "$NUMBERS_SOURCE"
