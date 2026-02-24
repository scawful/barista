#!/usr/bin/env bash
set -euo pipefail

HOST=""
REMOTE_DIR="${BARISTA_REMOTE_DIR:-~/.config/sketchybar}"
REMOTE_URL="${BARISTA_REMOTE_URL:-https://github.com/scawful/barista.git}"
TARGET_REF="${BARISTA_TARGET_REF:-origin/main}"
WORK_DOMAIN="${BARISTA_WORK_GOOGLE_DOMAIN:-}"
PANEL_MODE="${BARISTA_ALT_PANEL_MODE:-tui}"
SKIP_RESTART="${BARISTA_SKIP_RESTART:-0}"
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

ssh "$HOST" \
  BARISTA_REMOTE_DIR="$REMOTE_DIR" \
  BARISTA_REMOTE_URL="$REMOTE_URL" \
  BARISTA_TARGET_REF="$TARGET_REF" \
  BARISTA_WORK_DOMAIN="$WORK_DOMAIN" \
  BARISTA_PANEL_MODE="$PANEL_MODE" \
  BARISTA_SKIP_RESTART="$SKIP_RESTART" \
  BARISTA_INSTALL_EXTRAS="$INSTALL_EXTRAS" \
  'bash -s' <<'REMOTE'
set -euo pipefail

expand_home() {
  case "$1" in
    "~/"*) printf '%s/%s' "$HOME" "${1#~/}" ;;
    "~") printf '%s' "$HOME" ;;
    *) printf '%s' "$1" ;;
  esac
}

repo_dir="$(expand_home "$BARISTA_REMOTE_DIR")"
mkdir -p "$(dirname "$repo_dir")"

if [ ! -d "$repo_dir/.git" ]; then
  echo "[remote] cloning barista into $repo_dir"
  git clone "$BARISTA_REMOTE_URL" "$repo_dir"
fi

cd "$repo_dir"

if [ ! -x "./bin/barista-update" ]; then
  echo "[remote] missing ./bin/barista-update in $repo_dir" >&2
  exit 1
fi

echo "[remote] updating to $BARISTA_TARGET_REF"
BARISTA_SKIP_RESTART="$BARISTA_SKIP_RESTART" ./bin/barista-update --yes --target "$BARISTA_TARGET_REF"

if [ "${BARISTA_INSTALL_EXTRAS:-1}" = "1" ] && [ -x "./scripts/install_missing_fonts_and_panel.sh" ]; then
  echo "[remote] installing fonts and panel mode"
  ./scripts/install_missing_fonts_and_panel.sh --yes --panel-mode "$BARISTA_PANEL_MODE" --state "$repo_dir/state.json" --no-reload
fi

if [ -n "${BARISTA_WORK_DOMAIN:-}" ] && [ -x "./scripts/configure_work_google_apps.sh" ]; then
  echo "[remote] applying work Google apps for domain ${BARISTA_WORK_DOMAIN}"
  ./scripts/configure_work_google_apps.sh --state "$repo_dir/state.json" --domain "$BARISTA_WORK_DOMAIN" --replace --no-reload
fi

if command -v sketchybar >/dev/null 2>&1; then
  sketchybar --reload >/dev/null 2>&1 || true
fi
if command -v skhd >/dev/null 2>&1; then
  skhd --reload >/dev/null 2>&1 || true
fi

echo "[remote] update complete"
REMOTE
