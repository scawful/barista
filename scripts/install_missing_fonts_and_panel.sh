#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="${BARISTA_STATE_FILE:-$HOME/.config/sketchybar/state.json}"
PANEL_MODE="${BARISTA_ALT_PANEL_MODE:-tui}"
INSTALL_FONTS=1
INSTALL_PANEL=1
AUTO_YES=0
DO_RELOAD=1

usage() {
  cat <<EOF
Usage: $0 [--state <path>] [--panel-mode <native|tui|imgui|custom>] [--fonts-only] [--panel-only] [--yes] [--no-reload]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --panel-mode)
      PANEL_MODE="${2:-}"
      shift 2
      ;;
    --fonts-only)
      INSTALL_PANEL=0
      shift
      ;;
    --panel-only)
      INSTALL_FONTS=0
      shift
      ;;
    --yes)
      AUTO_YES=1
      shift
      ;;
    --no-reload)
      DO_RELOAD=0
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

confirm() {
  local prompt="$1"
  if [ "$AUTO_YES" -eq 1 ]; then
    return 0
  fi
  read -r -p "$prompt [Y/n] " reply
  case "${reply:-y}" in
    y|Y|yes|YES|"")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ensure_font_cask() {
  local cask="$1"
  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo "[fonts] $cask already installed"
    return 0
  fi
  echo "[fonts] installing $cask"
  brew install --cask "$cask"
}

install_fonts() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "[fonts] Homebrew not found, skipping font install" >&2
    return 0
  fi
  brew tap homebrew/cask-fonts >/dev/null 2>&1 || true
  ensure_font_cask font-hack-nerd-font
  ensure_font_cask font-source-code-pro
}

set_panel_preference() {
  local mode="$1"
  if ! command -v jq >/dev/null 2>&1; then
    echo "[panel] jq not found, cannot update state preference" >&2
    return 0
  fi
  mkdir -p "$(dirname "$STATE_FILE")"
  if [ ! -f "$STATE_FILE" ]; then
    printf '{}' > "$STATE_FILE"
  fi
  local tmp
  tmp="$(mktemp)"
  jq --arg mode "$mode" '
    .control_panel = (.control_panel // {}) |
    .control_panel.preferred = $mode
  ' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

apply_menu_readability_defaults() {
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  mkdir -p "$(dirname "$STATE_FILE")"
  if [ ! -f "$STATE_FILE" ]; then
    printf '{}' > "$STATE_FILE"
  fi
  local tmp
  tmp="$(mktemp)"
  jq '
    .appearance = (.appearance // {}) |
    .appearance.popup_bg_color = "0xE021162F" |
    .appearance.popup_border_color = (.appearance.popup_border_color // "0x80cdd6f4") |
    .appearance.font_text = (.appearance.font_text // "Source Code Pro") |
    .appearance.widget_scale = (
      if (.appearance.widget_scale // 1) < 1.05 then 1.05 else .appearance.widget_scale end
    )
  ' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

install_panel_mode() {
  local mode
  mode="$(printf '%s' "$PANEL_MODE" | tr '[:upper:]' '[:lower:]')"
  case "$mode" in
    native)
      set_panel_preference native
      ;;
    tui)
      if [ -x "$ROOT_DIR/scripts/install-tui.sh" ]; then
        "$ROOT_DIR/scripts/install-tui.sh" --yes
      fi
      set_panel_preference tui
      ;;
    imgui)
      if [ -x "$HOME/src/lab/barista_config/build/barista_config" ] || command -v barista_config >/dev/null 2>&1; then
        set_panel_preference imgui
      else
        echo "[panel] barista_config binary not found; leaving current preference" >&2
      fi
      ;;
    custom)
      set_panel_preference custom
      ;;
    *)
      echo "[panel] unsupported mode: $PANEL_MODE" >&2
      return 1
      ;;
  esac
}

if [ "$INSTALL_FONTS" -eq 1 ]; then
  if confirm "Install missing Barista fonts?"; then
    install_fonts
  fi
fi

if [ "$INSTALL_PANEL" -eq 1 ]; then
  if confirm "Configure alternative control panel mode ($PANEL_MODE)?"; then
    install_panel_mode
    apply_menu_readability_defaults
  fi
fi

if [ "$DO_RELOAD" -eq 1 ] && command -v sketchybar >/dev/null 2>&1; then
  sketchybar --reload >/dev/null 2>&1 || true
fi

echo "Completed font/panel setup."
