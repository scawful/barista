#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

HOST=""
REMOTE_DIR="${BARISTA_REMOTE_DIR:-~/.config/sketchybar}"
REMOTE_URL="${BARISTA_REMOTE_URL:-https://github.com/scawful/barista.git}"
TARGET_REF="${BARISTA_TARGET_REF:-origin/main}"
PANEL_MODE="${BARISTA_ALT_PANEL_MODE:-tui}"
WORK_DOMAIN="${BARISTA_WORK_GOOGLE_DOMAIN:-}"
WORK_APPS_FILE=""
RUN_SETUP=1
RUN_DOCTOR=1
SKIP_RELOAD=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $0 --host <user@work-mac> [options]

Options:
  --host <user@work-mac>                 Remote SSH target (required)
  --remote-dir <path>                    Remote repo/runtime path (default: ~/.config/sketchybar)
  --repo-url <url>                       Git URL to clone/update
  --target <ref>                         Target git ref for barista-update
  --panel-mode <native|tui|imgui|custom> Panel preference for setup_machine
  --work-domain <domain>                 Workspace domain for work app links
  --work-apps-file <path>                Local JSON array file to upload/use for work apps
  --skip-setup                           Skip setup_machine on remote
  --skip-doctor                          Skip barista-doctor on remote
  --skip-reload                          Skip service restart/reload on remote
  --dry-run                              Print planned remote actions only
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
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --remote-dir)
      REMOTE_DIR="${2:-}"
      shift 2
      ;;
    --repo-url)
      REMOTE_URL="${2:-}"
      shift 2
      ;;
    --target)
      TARGET_REF="${2:-}"
      shift 2
      ;;
    --panel-mode)
      PANEL_MODE="${2:-}"
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
    --skip-setup)
      RUN_SETUP=0
      shift
      ;;
    --skip-doctor)
      RUN_DOCTOR=0
      shift
      ;;
    --skip-reload)
      SKIP_RELOAD=1
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

REMOTE_APPS_FILE=""
if [ -n "$WORK_APPS_FILE" ]; then
  WORK_APPS_FILE="$(expand_home "$WORK_APPS_FILE")"
  if [ ! -f "$WORK_APPS_FILE" ]; then
    echo "Work apps file not found: $WORK_APPS_FILE" >&2
    exit 1
  fi
  REMOTE_APPS_FILE="/tmp/barista_work_apps_$(id -u)_$$.json"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] would upload $WORK_APPS_FILE -> $HOST:$REMOTE_APPS_FILE"
  else
    scp -q "$WORK_APPS_FILE" "$HOST:$REMOTE_APPS_FILE"
  fi
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] would sync barista to $HOST"
  echo "[dry-run] remote_dir=$REMOTE_DIR"
  echo "[dry-run] repo_url=$REMOTE_URL"
  echo "[dry-run] target_ref=$TARGET_REF"
  echo "[dry-run] panel_mode=$PANEL_MODE"
  echo "[dry-run] work_domain=$WORK_DOMAIN"
  echo "[dry-run] run_setup=$RUN_SETUP run_doctor=$RUN_DOCTOR skip_reload=$SKIP_RELOAD"
  exit 0
fi

ssh "$HOST" \
  BARISTA_REMOTE_DIR="$REMOTE_DIR" \
  BARISTA_REMOTE_URL="$REMOTE_URL" \
  BARISTA_TARGET_REF="$TARGET_REF" \
  BARISTA_PANEL_MODE="$PANEL_MODE" \
  BARISTA_WORK_DOMAIN="$WORK_DOMAIN" \
  BARISTA_REMOTE_APPS_FILE="$REMOTE_APPS_FILE" \
  BARISTA_RUN_SETUP="$RUN_SETUP" \
  BARISTA_RUN_DOCTOR="$RUN_DOCTOR" \
  BARISTA_SKIP_RELOAD="$SKIP_RELOAD" \
  BARISTA_DRY_RUN="$DRY_RUN" \
  'bash -s' <<'REMOTE'
set -euo pipefail

expand_home() {
  case "$1" in
    ~/*) printf '%s/%s' "$HOME" "${1#~/}" ;;
    ~) printf '%s' "$HOME" ;;
    *) printf '%s' "$1" ;;
  esac
}

repo_dir="$(expand_home "$BARISTA_REMOTE_DIR")"
mkdir -p "$(dirname "$repo_dir")"

if [ ! -d "$repo_dir/.git" ]; then
  if [ "${BARISTA_DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run][remote] would clone $BARISTA_REMOTE_URL -> $repo_dir"
  else
    echo "[remote] cloning $BARISTA_REMOTE_URL -> $repo_dir"
    git clone "$BARISTA_REMOTE_URL" "$repo_dir"
  fi
fi

cd "$repo_dir"

if [ ! -x "./bin/barista-update" ]; then
  echo "[remote] missing ./bin/barista-update in $repo_dir" >&2
  exit 1
fi

if [ "${BARISTA_DRY_RUN:-0}" = "1" ]; then
  echo "[dry-run][remote] would run: ./bin/barista-update --yes --target $BARISTA_TARGET_REF --skip-restart"
else
  echo "[remote] updating to $BARISTA_TARGET_REF"
  ./bin/barista-update --yes --target "$BARISTA_TARGET_REF" --skip-restart
fi

if [ "${BARISTA_RUN_SETUP:-1}" = "1" ] && [ -x "./scripts/setup_machine.sh" ]; then
  setup_args=(--state "$repo_dir/state.json" --panel-mode "$BARISTA_PANEL_MODE" --yes --report)
  if [ "${BARISTA_SKIP_RELOAD:-0}" = "1" ]; then
    setup_args+=(--no-reload)
  fi
  if [ -n "${BARISTA_WORK_DOMAIN:-}" ]; then
    setup_args+=(--work-apps --replace --domain "$BARISTA_WORK_DOMAIN")
  fi
  if [ -n "${BARISTA_REMOTE_APPS_FILE:-}" ]; then
    setup_args+=(--work-apps --replace --from-file "$BARISTA_REMOTE_APPS_FILE")
  fi
  if [ "${BARISTA_DRY_RUN:-0}" = "1" ]; then
    setup_args+=(--dry-run)
  fi

  echo "[remote] running setup_machine"
  ./scripts/setup_machine.sh "${setup_args[@]}"
fi

if [ "${BARISTA_RUN_DOCTOR:-1}" = "1" ] && [ -x "./scripts/barista-doctor.sh" ]; then
  doctor_args=(--report)
  if [ "${BARISTA_DRY_RUN:-0}" != "1" ]; then
    doctor_args+=(--fix)
  fi
  echo "[remote] running barista-doctor ${doctor_args[*]}"
  ./scripts/barista-doctor.sh "${doctor_args[@]}" || true
fi

if [ "${BARISTA_SKIP_RELOAD:-0}" != "1" ]; then
  if [ "${BARISTA_DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run][remote] would restart/reload services"
  else
    if [ -x "./launch_agents/barista-launch.sh" ]; then
      ./launch_agents/barista-launch.sh restart >/dev/null 2>&1 || true
    fi
    if command -v sketchybar >/dev/null 2>&1; then
      sketchybar --reload >/dev/null 2>&1 || true
    fi
    if command -v skhd >/dev/null 2>&1; then
      skhd --reload >/dev/null 2>&1 || true
    fi
    if command -v yabai >/dev/null 2>&1; then
      yabai -m signal --add event=display_changed label=barista_post_sync_refresh action="sketchybar --trigger space_change; sketchybar --trigger space_mode_refresh" >/dev/null 2>&1 || true
    fi
  fi
fi

if [ -n "${BARISTA_REMOTE_APPS_FILE:-}" ] && [ -f "${BARISTA_REMOTE_APPS_FILE}" ]; then
  rm -f "${BARISTA_REMOTE_APPS_FILE}" >/dev/null 2>&1 || true
fi

echo "[remote] work mac sync complete"
REMOTE
