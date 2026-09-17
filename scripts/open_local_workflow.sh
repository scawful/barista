#!/usr/bin/env bash

set -euo pipefail

PATH="${HOMEBREW_PREFIX:+$HOMEBREW_PREFIX/bin:$HOMEBREW_PREFIX/sbin:}$HOME/.lmstudio/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
SRC_DIR="${BARISTA_CODE_DIR:-$HOME/src}"
LOG_FILE="${TMPDIR:-/tmp}/barista-local-workflow.log"
GHOSTTY_APP="${BARISTA_GHOSTTY_APP:-/Applications/Ghostty.app}"
OSASCRIPT_BIN="${BARISTA_OSASCRIPT_BIN:-/usr/bin/osascript}"
OPEN_BIN="${BARISTA_OPEN_BIN:-/usr/bin/open}"
PATH="$HOME/.local/bin:$SRC_DIR/config/dotfiles/bin:$HOME/bin:$PATH"

usage() {
  printf '%s\n' \
    "usage: open_local_workflow.sh <workflow>" \
    "" \
    "Workflows:" \
    "  antigravity         Launch Antigravity in a terminal" \
    "  claude-code        Launch Claude Code in a terminal" \
    "  workspace-navigator Open the ws workspace explorer" \
    "  open-path PATH       Open a validated local path" \
    "  stop-managed-agents Stop only registered autonomous agent trees" \
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
    "$OPEN_BIN" "$path"
    return 0
  fi
  return 1
}

open_app_or_repo() {
  local app_path="$1"
  local repo_path="$2"
  if [[ -d "$app_path" ]]; then
    "$OPEN_BIN" "$app_path"
    return 0
  fi
  open_path "$repo_path"
}

terminal_session() {
  local command="$1"
  if [[ -d "$GHOSTTY_APP" ]]; then
    "$OPEN_BIN" -na "$GHOSTTY_APP" --args -e /bin/zsh -lc "$command"
    return 0
  fi

  local escaped
  escaped="${command//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  "$OSASCRIPT_BIN" -e "tell application \"Terminal\" to do script \"$escaped\""
}

resolve_executable() {
  local override="${1:-}"
  shift || true
  local candidate resolved
  for candidate in "$override" "$@"; do
    [[ -n "$candidate" ]] || continue
    if [[ "$candidate" == */* ]]; then
      if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      continue
    fi
    resolved="$(command -v "$candidate" 2>/dev/null || true)"
    if [[ -n "$resolved" && -x "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  done
  return 1
}

terminal_cli_session() {
  local binary="$1"
  shift || true
  local command
  printf -v command '%q ' "$binary" "$@"
  command="${command% }"
  terminal_session "$command; status=\$?; printf '\\n'; exec /bin/zsh -l"
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
  antigravity)
    binary="$(resolve_executable "${ANTIGRAVITY_LAUNCHER:-}" \
      "$SRC_DIR/config/dotfiles/bin/agy" agy || true)"
    [[ -n "$binary" ]] || {
      echo "Antigravity launcher not found" >&2
      exit 127
    }
    terminal_cli_session "$binary"
    ;;
  claude-code|claude)
    binary="$(resolve_executable "${CLAUDE_LAUNCHER:-}" \
      "$SRC_DIR/config/dotfiles/bin/claude" claude || true)"
    [[ -n "$binary" ]] || {
      echo "Claude Code launcher not found" >&2
      exit 127
    }
    terminal_cli_session "$binary"
    ;;
  workspace-navigator|ws)
    binary="$(resolve_executable "${WS_LAUNCHER:-}" \
      "$SRC_DIR/config/dotfiles/bin/ws" ws || true)"
    [[ -n "$binary" ]] || {
      echo "Workspace Navigator launcher not found" >&2
      exit 127
    }
    terminal_cli_session "$binary" explore
    ;;
  open-path)
    target="${2:-}"
    [[ -n "$target" && -e "$target" ]] || {
      echo "Local workflow path not found: ${target:-<empty>}" >&2
      exit 1
    }
    "$OPEN_BIN" "$target"
    ;;
  stop-managed-agents)
    binary="$(resolve_executable "${STOP_AGENTS_LAUNCHER:-}" \
      "$SRC_DIR/tools/ws/stop-all-agents.sh" \
      "$SRC_DIR/config/dotfiles/bin/stop-agents" stop-agents || true)"
    [[ -n "$binary" ]] || {
      echo "Managed agent stop command not found" >&2
      exit 127
    }
    exec "$binary" --managed
    ;;
  ghostty|terminal)
    if [[ -d "$GHOSTTY_APP" ]]; then
      "$OPEN_BIN" -na "$GHOSTTY_APP"
    else
      "$OPEN_BIN" -a Terminal
    fi
    ;;
  lmstudio|lmstudio-open)
    if [[ -x "$CONFIG_DIR/scripts/lmstudio_control.sh" ]]; then
      "$CONFIG_DIR/scripts/lmstudio_control.sh" open
    else
      "$OPEN_BIN" -ga "LM Studio" >/dev/null 2>&1 || "$OPEN_BIN" -a "LM Studio"
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
      "$OPEN_BIN" "$app"
    else
      "$OPEN_BIN" -b com.scawful.Scawfulbot.mac >/dev/null 2>&1 || open_path "$SCAWFULBOT_ROOT"
    fi
    ;;
  scawfulbot-repo)
    open_path "$SCAWFULBOT_ROOT"
    ;;
  yaze)
    if command -v yaze-nightly >/dev/null 2>&1; then
      background_exec yaze-nightly
    elif [[ -d "$YAZE_ROOT/dist/nightly/yaze.app" ]]; then
      "$OPEN_BIN" "$YAZE_ROOT/dist/nightly/yaze.app"
    elif [[ -d "$YAZE_ROOT/dist/yaze-macos-local-test/yaze.app" ]]; then
      "$OPEN_BIN" "$YAZE_ROOT/dist/yaze-macos-local-test/yaze.app"
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
