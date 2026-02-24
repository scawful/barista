#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

STATE_FILE="${BARISTA_STATE_FILE:-$HOME/.config/sketchybar/state.json}"
DOMAIN="${BARISTA_WORK_GOOGLE_DOMAIN:-}"
APPS_FILE=""
REPLACE=0
DO_RELOAD=1

usage() {
  cat <<EOF
Usage: $0 [--state <path>] [--domain <workspace-domain>] [--from-file <apps.json>] [--replace] [--no-reload]

Examples:
  $0 --domain company.com
  $0 --from-file ./data/work_google_apps.example.json --replace
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --state)
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --domain)
      DOMAIN="${2:-}"
      shift 2
      ;;
    --from-file)
      APPS_FILE="${2:-}"
      shift 2
      ;;
    --replace)
      REPLACE=1
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

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for this script." >&2
  exit 1
fi

if [ ! -f "$STATE_FILE" ]; then
  mkdir -p "$(dirname "$STATE_FILE")"
  printf '{}' > "$STATE_FILE"
fi

google_url() {
  local path="$1"
  if [ -n "$DOMAIN" ]; then
    printf 'https://%s/a/%s/' "$path" "$DOMAIN"
    return 0
  fi
  printf 'https://%s/' "$path"
}

default_apps_json() {
  local mail_url calendar_url drive_url docs_url sheets_url meet_url
  mail_url="$(google_url mail.google.com)"
  calendar_url="$(google_url calendar.google.com)"
  drive_url="$(google_url drive.google.com)"
  docs_url="https://docs.google.com/document/u/0/"
  sheets_url="https://docs.google.com/spreadsheets/u/0/"
  meet_url="https://meet.google.com/"
  cat <<JSON
[
  {"id":"gmail","label":"Gmail","icon":"󰇮","url":"$mail_url","section":"work","order":1,"enabled":true},
  {"id":"calendar","label":"Calendar","icon":"󰃭","url":"$calendar_url","section":"work","order":2,"enabled":true},
  {"id":"drive","label":"Drive","icon":"󰉋","url":"$drive_url","section":"work","order":3,"enabled":true},
  {"id":"docs","label":"Docs","icon":"󰈬","url":"$docs_url","section":"work","order":4,"enabled":true},
  {"id":"sheets","label":"Sheets","icon":"󰈛","url":"$sheets_url","section":"work","order":5,"enabled":true},
  {"id":"meet","label":"Meet","icon":"󰤙","url":"$meet_url","section":"work","order":6,"enabled":true}
]
JSON
}

if [ -n "$APPS_FILE" ]; then
  if [ ! -f "$APPS_FILE" ]; then
    echo "Apps file not found: $APPS_FILE" >&2
    exit 1
  fi
  APPS_JSON="$(cat "$APPS_FILE")"
else
  APPS_JSON="$(default_apps_json)"
fi

if ! printf '%s' "$APPS_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "Google apps payload must be a JSON array." >&2
  exit 1
fi

APPS_JSON="$(printf '%s' "$APPS_JSON" | jq '
  map(
    .enabled = (.enabled // true) |
    .id = ("work_google_" + ((.id // .label // .url // "item")
      | tostring
      | ascii_downcase
      | gsub("[^a-z0-9]+"; "_")
      | gsub("^_+"; "")
      | gsub("_+$"; ""))) |
    .section = (.section // "custom") |
    .command = (.command // .action // (if (.url // "") != "" then ("open " + .url) else "" end))
  ) |
  map({id, label, title, icon, color, icon_color, label_color, command, section, order, enabled, shortcut})
')"

tmp_file="$(mktemp)"
if [ "$REPLACE" -eq 1 ]; then
  jq --argjson apps "$APPS_JSON" '
    .menus = (.menus // {}) |
    .menus.apple = (.menus.apple // {}) |
    .menus.apple.sections = (.menus.apple.sections // {}) |
    .menus.apple.sections.work = (.menus.apple.sections.work // {"label":"Work Apps","order":3}) |
    .menus.apple.custom = $apps
  ' "$STATE_FILE" > "$tmp_file"
else
  jq --argjson apps "$APPS_JSON" '
    .menus = (.menus // {}) |
    .menus.apple = (.menus.apple // {}) |
    .menus.apple.sections = (.menus.apple.sections // {}) |
    .menus.apple.sections.work = (.menus.apple.sections.work // {"label":"Work Apps","order":3}) |
    .menus.apple.custom = (
      ((.menus.apple.custom // []) as $existing |
       ($apps | map((.id // .label // "") | tostring)) as $incoming_keys |
       ($existing | map(select((.id // .label // "") as $k | ($incoming_keys | index(($k|tostring))) | not)))
       + $apps)
    )
  ' "$STATE_FILE" > "$tmp_file"
fi

mv "$tmp_file" "$STATE_FILE"

if [ "$DO_RELOAD" -eq 1 ] && command -v sketchybar >/dev/null 2>&1; then
  sketchybar --reload >/dev/null 2>&1 || true
fi

echo "Updated work Google apps in $STATE_FILE"
