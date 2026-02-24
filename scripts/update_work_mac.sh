#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/work_mac_sync.sh"

HOST=""
REMOTE_DIR="${BARISTA_REMOTE_DIR:-~/.config/sketchybar}"
TARGET_REF="${BARISTA_TARGET_REF:-origin/main}"
WORK_DOMAIN="${BARISTA_WORK_GOOGLE_DOMAIN:-}"
PANEL_MODE="${BARISTA_ALT_PANEL_MODE:-tui}"
REMOTE_URL="${BARISTA_REMOTE_URL:-https://github.com/scawful/barista.git}"
SKIP_RESTART=0
INSTALL_EXTRAS=1

usage() {
  cat <<EOF
Usage: $0 --host <user@work-mac> [--remote-dir <path>] [--target <ref>] [--work-domain <domain>] [--panel-mode <native|tui|imgui|custom>] [--skip-restart] [--no-extras]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --remote-dir)
      REMOTE_DIR="${2:-}"
      shift 2
      ;;
    --target)
      TARGET_REF="${2:-}"
      shift 2
      ;;
    --work-domain)
      WORK_DOMAIN="${2:-}"
      shift 2
      ;;
    --panel-mode)
      PANEL_MODE="${2:-}"
      shift 2
      ;;
    --repo-url)
      REMOTE_URL="${2:-}"
      shift 2
      ;;
    --skip-restart)
      SKIP_RESTART=1
      shift
      ;;
    --no-extras)
      INSTALL_EXTRAS=0
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

if [ -z "$HOST" ]; then
  echo "--host is required" >&2
  usage
  exit 1
fi

if [ ! -x "$SYNC_SCRIPT" ]; then
  echo "Missing sync script: $SYNC_SCRIPT" >&2
  exit 1
fi

args=(
  --host "$HOST"
  --remote-dir "$REMOTE_DIR"
  --repo-url "$REMOTE_URL"
  --target "$TARGET_REF"
  --panel-mode "$PANEL_MODE"
)

if [ -n "$WORK_DOMAIN" ]; then
  args+=(--work-domain "$WORK_DOMAIN")
fi
if [ "$SKIP_RESTART" -eq 1 ]; then
  args+=(--skip-reload)
fi
if [ "$INSTALL_EXTRAS" -eq 0 ]; then
  args+=(--skip-setup)
fi

exec "$SYNC_SCRIPT" "${args[@]}"
