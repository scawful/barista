#!/usr/bin/env bash

set -euo pipefail

PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.lmstudio/bin:$HOME/src/tools/bin:$HOME/src/config/dotfiles/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SRC_DIR="${BARISTA_CODE_DIR:-$HOME/src}"
LOG_FILE="${TMPDIR:-/tmp}/barista-local-workflow.log"
GHOSTTY_APP="${BARISTA_GHOSTTY_APP:-/Applications/Ghostty.app}"

usage() {
  printf '%s\n' \
    "usage: open_local_workflow.sh <workflow>" \
    "" \
    "Workflows:" \
    "  ghostty              Open Ghostty" \
    "  lmstudio            Open LM Studio" \
    "  lmstudio-status     Show loaded LM Studio models in a terminal" \
    "  afs-repo            Open the AFS repo" \
    "  afs-studio          Launch AFS Studio" \
    "  afs-context         Show AFS context overview in a terminal" \
    "  scawfulbot          Open the local scawfulbot macOS app" \
    "  scawfulbot-repo     Open the scawfulbot repo" \
    "  yaze                Launch Yaze" \
    "  yaze-repo           Open the Yaze repo" \
    "  z3ed                Open a z3ed terminal session" \
    "  loom                Launch Loom Studio" \
    "  premia              Launch premia" \
    "  halext-repo         Open the halext-org repo" \
    "  barista-repo        Open the Barista repo"
}

resolve_dir() {
  local fallback="${1:-}"
  local candidate
  for candidate in "$@"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf '%s' "$fallback"
}

open_path() {
  local path="$1"
  if [[ -e "$path" || -d "$path" ]]; then
    open "$path"
    return 0
  fi
  return 1
}

open_app_or_repo() {
  local app_path="$1"
  local repo_path="$2"
  if [[ -d "$app_path" ]]; then
    open "$app_path"
    return 0
  fi
  open_path "$repo_path"
}

terminal_session() {
  local command="$1"
  if [[ -d "$GHOSTTY_APP" ]]; then
    open -na "$GHOSTTY_APP" --args -e /bin/zsh -lc "$command"
    return 0
  fi

  local escaped
  escaped="${command//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  osascript -e "tell application \"Terminal\" to do script \"$escaped\""
}

background_exec() {
  "$@" >"$LOG_FILE" 2>&1 &
}

AFS_ROOT="$(resolve_dir "$SRC_DIR/lab/afs" "$SRC_DIR/afs" "$SRC_DIR/tools/afs")"
AFS_STUDIO_LAUNCHER="$(resolve_dir "$SRC_DIR/lab/afs-scawful/scripts/afs/utils" "$SRC_DIR/afs-scawful/scripts/afs/utils")/afs-studio"
HALEXT_ROOT="$(resolve_dir "$SRC_DIR/lab/halext-org" "$SRC_DIR/halext-org")"
SCAWFULBOT_ROOT="$(resolve_dir "$SRC_DIR/lab/scawfulbot" "$SRC_DIR/scawfulbot")"
YAZE_ROOT="$(resolve_dir "$SRC_DIR/hobby/yaze" "$SRC_DIR/yaze")"
LOOM_ROOT="$(resolve_dir "$SRC_DIR/lab/loom-studio" "$SRC_DIR/loom-studio")"
PREMIA_ROOT="$(resolve_dir "$SRC_DIR/lab/premia" "$SRC_DIR/premia")"

workflow="${1:-}"
case "$workflow" in
  ghostty|terminal)
    if [[ -d "$GHOSTTY_APP" ]]; then
      open -na "$GHOSTTY_APP"
    else
      open -a Terminal
    fi
    ;;
  lmstudio|lmstudio-open)
    if [[ -x "$CONFIG_DIR/scripts/lmstudio_control.sh" ]]; then
      "$CONFIG_DIR/scripts/lmstudio_control.sh" open
    else
      open -ga "LM Studio" >/dev/null 2>&1 || open -a "LM Studio"
    fi
    ;;
  lmstudio-status)
    terminal_session "$(printf '%q' "$CONFIG_DIR/scripts/lmstudio_control.sh") status; printf '\\n'; exec /bin/zsh -l"
    ;;
  afs-repo)
    open_path "$AFS_ROOT"
    ;;
  afs-studio)
    if [[ -x "$AFS_STUDIO_LAUNCHER" ]]; then
      background_exec "$AFS_STUDIO_LAUNCHER"
    else
      terminal_session "cd $(printf '%q' "$AFS_ROOT") && AFS_ROOT=$(printf '%q' "$AFS_ROOT") PYTHONPATH=$(printf '%q' "$AFS_ROOT/src") python3 -m afs studio run --build; printf '\\n'; exec /bin/zsh -l"
    fi
    ;;
  afs-context)
    terminal_session "cd $(printf '%q' "$AFS_ROOT") && (afs context overview || AFS_ROOT=$(printf '%q' "$AFS_ROOT") PYTHONPATH=$(printf '%q' "$AFS_ROOT/src") python3 -m afs context overview); printf '\\n'; exec /bin/zsh -l"
    ;;
  scawfulbot)
    app="$SCAWFULBOT_ROOT/apps/apple/build-macos/Build/Products/Debug/Scawfulbot.app"
    if [[ -d "$app" ]]; then
      open "$app"
    else
      open -b com.scawful.Scawfulbot.mac >/dev/null 2>&1 || open_path "$SCAWFULBOT_ROOT"
    fi
    ;;
  scawfulbot-repo)
    open_path "$SCAWFULBOT_ROOT"
    ;;
  yaze)
    if command -v yaze-nightly >/dev/null 2>&1; then
      background_exec yaze-nightly
    elif [[ -d "$YAZE_ROOT/dist/nightly/yaze.app" ]]; then
      open "$YAZE_ROOT/dist/nightly/yaze.app"
    elif [[ -d "$YAZE_ROOT/dist/yaze-macos-local-test/yaze.app" ]]; then
      open "$YAZE_ROOT/dist/yaze-macos-local-test/yaze.app"
    else
      open_path "$YAZE_ROOT"
    fi
    ;;
  yaze-repo)
    open_path "$YAZE_ROOT"
    ;;
  z3ed)
    z3ed_bin="$(command -v z3ed || true)"
    if [[ -z "$z3ed_bin" && -x "$YAZE_ROOT/scripts/z3ed" ]]; then
      z3ed_bin="$YAZE_ROOT/scripts/z3ed"
    fi
    if [[ -n "$z3ed_bin" ]]; then
      terminal_session "cd $(printf '%q' "$YAZE_ROOT") && clear && printf 'z3ed\\n\\n' && $(printf '%q' "$z3ed_bin") --help; printf '\\n'; exec /bin/zsh -l"
    else
      open_path "$YAZE_ROOT"
    fi
    ;;
  loom)
    if [[ -x "$LOOM_ROOT/build/bin/loom-studio" ]]; then
      background_exec "$LOOM_ROOT/build/bin/loom-studio" "$SRC_DIR/lab"
    else
      open_path "$LOOM_ROOT"
    fi
    ;;
  premia)
    if [[ -x "$PREMIA_ROOT/build-arch-next/bin/premia" ]]; then
      background_exec "$PREMIA_ROOT/build-arch-next/bin/premia"
    elif [[ -x "$PREMIA_ROOT/build/bin/premia" ]]; then
      background_exec "$PREMIA_ROOT/build/bin/premia"
    else
      open_path "$PREMIA_ROOT"
    fi
    ;;
  halext-repo)
    open_path "$HALEXT_ROOT"
    ;;
  barista-repo)
    open_path "$CONFIG_DIR"
    ;;
  help|--help|-h|"")
    usage
    ;;
  *)
    echo "Unknown workflow: $workflow" >&2
    usage >&2
    exit 1
    ;;
esac
