#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/work_mac_sync.sh"

HOST=""
REMOTE_DIR="${BARISTA_REMOTE_DIR:-~/.config/sketchybar}"
TARGET_REF="${BARISTA_TARGET_REF:-origin/main}"
PROFILE_VARIANT="${BARISTA_PROFILE_VARIANT:-}"
MACHINE_FILE="${BARISTA_MACHINE_PROFILE_FILE:-data/machine.local.json}"
WORK_DOMAIN="${BARISTA_WORK_GOOGLE_DOMAIN:-}"
PANEL_MODE="${BARISTA_ALT_PANEL_MODE:-tui}"
RUNTIME_BACKEND="${BARISTA_RUNTIME_BACKEND:-lua}"
REMOTE_URL="${BARISTA_REMOTE_URL:-https://github.com/scawful/barista.git}"
WORK_APPS_FILE=""
SKIP_RESTART=0
INSTALL_EXTRAS=1
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $0 --host <user@work-mac> [options]

Options:
  --remote-dir <path>
  --target <ref>
  --profile-variant <minimal|cozy|personal|work|restricted-work>
  --restricted-work
  --machine-file <path>
  --work-domain <domain>
  --work-apps-file <path>
  --panel-mode <native|tui|imgui|custom>
  --runtime-backend <auto|lua|compiled>
  --skip-restart
  --no-extras
  --dry-run
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
    --profile-variant|--variant)
      PROFILE_VARIANT="${2:-}"
      case "$PROFILE_VARIANT" in
        restricted|work-restricted|scripts-only)
          PROFILE_VARIANT="restricted-work"
          PANEL_MODE="tui"
          RUNTIME_BACKEND="lua"
          ;;
      esac
      shift 2
      ;;
    --restricted-work|--work-restricted|--restricted|--scripts-only)
      PROFILE_VARIANT="restricted-work"
      PANEL_MODE="tui"
      RUNTIME_BACKEND="lua"
      shift
      ;;
    --machine-file|--machine-profile)
      MACHINE_FILE="${2:-}"
      shift 2
      ;;
    --work-domain)
      WORK_DOMAIN="${2:-}"
      shift 2
      ;;
    --work-apps-file)
      WORK_APPS_FILE="${2:-}"
      shift 2
      ;;
    --panel-mode)
      PANEL_MODE="${2:-}"
      shift 2
      ;;
    --runtime-backend)
      RUNTIME_BACKEND="${2:-}"
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
    --dry-run)
      DRY_RUN=1
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
  --machine-file "$MACHINE_FILE"
)

if [ -n "$PROFILE_VARIANT" ]; then
  args+=(--profile-variant "$PROFILE_VARIANT")
fi
if [ "$PROFILE_VARIANT" != "restricted-work" ]; then
  args+=(--panel-mode "$PANEL_MODE" --runtime-backend "$RUNTIME_BACKEND")
fi
if [ -n "$WORK_DOMAIN" ]; then
  args+=(--work-domain "$WORK_DOMAIN")
fi
if [ -n "$WORK_APPS_FILE" ]; then
  args+=(--work-apps-file "$WORK_APPS_FILE")
fi
if [ "$SKIP_RESTART" -eq 1 ]; then
  args+=(--skip-reload)
fi
if [ "$INSTALL_EXTRAS" -eq 0 ]; then
  args+=(--skip-setup)
fi
if [ "$DRY_RUN" -eq 1 ]; then
  args+=(--dry-run)
fi

exec "$SYNC_SCRIPT" "${args[@]}"
