#!/usr/bin/env bash
# Enable a portable or machine-local interface-extension pack without hardcoding
# personal tools into the shared Barista checkout.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
PACK=""
REPLACE=0
FORCE=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $0 --pack <name> [options]

Install or refresh a local interface-extension pack from a committed example.

Options:
  --pack <name>              Pack id from data/onboard.defaults.json (e.g. personal, work)
  --config-dir <path>        Runtime/config directory (default: \$BARISTA_CONFIG_DIR or repo root)
  --replace                  Backup and replace an existing local extensions file
  --force                    Allow a pack even when the machine profile variant omits it
  --dry-run                  Print actions without writing files

Portable rule:
  Shared examples stay in git. Machine-local customizations write only to
  gitignored files such as data/interface_extensions.local.json.
EOF
}

expand_home() {
  case "$1" in
    ~/*) printf '%s/%s\n' "$HOME" "${1#~/}" ;;
    ~) printf '%s\n' "$HOME" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

note() {
  printf '%s\n' "$*"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pack)
      PACK="${2:?missing value for --pack}"
      shift 2
      ;;
    --config-dir)
      CONFIG_DIR="${2:?missing value for --config-dir}"
      shift 2
      ;;
    --replace)
      REPLACE=1
      shift
      ;;
    --force)
      FORCE=1
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
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$PACK" ]; then
  usage >&2
  exit 2
fi

CONFIG_DIR="$(expand_home "$CONFIG_DIR")"
DEFAULTS_FILE="$CONFIG_DIR/data/onboard.defaults.json"
MACHINE_FILE="$CONFIG_DIR/data/machine.local.json"

if [ ! -f "$DEFAULTS_FILE" ]; then
  echo "Missing portable onboard defaults: $DEFAULTS_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to enable extension packs" >&2
  exit 1
fi

pack_json="$(jq -c --arg pack "$PACK" '.extension_packs[$pack] // empty' "$DEFAULTS_FILE")"
if [ -z "$pack_json" ]; then
  echo "Unknown pack '$PACK'. Known packs:" >&2
  jq -r '.extension_packs | keys[]' "$DEFAULTS_FILE" >&2
  exit 1
fi

example_rel="$(printf '%s\n' "$pack_json" | jq -r '.example')"
local_rel="$(printf '%s\n' "$pack_json" | jq -r '.local')"
example_file="$CONFIG_DIR/$example_rel"
local_file="$CONFIG_DIR/$local_rel"

if [ ! -f "$example_file" ]; then
  echo "Pack example missing: $example_file" >&2
  exit 1
fi

variant="unknown"
if [ -f "$MACHINE_FILE" ]; then
  variant="$(jq -r '.profile_variant // "unknown"' "$MACHINE_FILE")"
fi

allowed="$(printf '%s\n' "$pack_json" | jq -r --arg variant "$variant" '
  (.allowed_variants // []) as $allowed
  | if ($allowed | length) == 0 then "1"
    elif ($allowed | index($variant)) != null then "1"
    else "0"
    end
')"
if [ "$allowed" != "1" ] && [ "$FORCE" -ne 1 ]; then
  echo "Pack '$PACK' is not allowed for profile variant '$variant'." >&2
  echo "Use a matching --profile when bootstrapping, or pass --force for an explicit local override." >&2
  exit 1
fi

normalize_pack_file() {
  local source="$1"
  local pack_name="$2"
  python3 - "$source" "$pack_name" <<'PY'
import json
import sys

source = sys.argv[1]
pack_name = sys.argv[2]
with open(source, encoding="utf-8") as handle:
    data = json.load(handle)

if isinstance(data, list):
    payload = {"packs": [pack_name], "items": data}
elif isinstance(data, dict):
    payload = dict(data)
    packs = payload.get("packs")
    if not isinstance(packs, list):
        packs = []
    if pack_name not in packs:
        packs.append(pack_name)
    payload["packs"] = packs
    if "items" not in payload or not isinstance(payload["items"], list):
        raise SystemExit(f"extension file must contain an items array: {source}")
else:
    raise SystemExit(f"extension file must be a JSON object or array: {source}")

json.dump(payload, sys.stdout, indent=2)
sys.stdout.write("\n")
PY
}

write_local() {
  local payload
  payload="$(normalize_pack_file "$example_file" "$PACK")"
  if [ "$DRY_RUN" -eq 1 ]; then
    note "Would write $local_file"
    return 0
  fi
  mkdir -p "$(dirname "$local_file")"
  if [ -e "$local_file" ] && [ "$REPLACE" -eq 1 ]; then
    backup="${local_file}.backup.$(date +%Y%m%d_%H%M%S)"
    mv "$local_file" "$backup"
    note "backup=$backup"
  fi
  printf '%s\n' "$payload" >"$local_file"
  note "enabled pack=$PACK local=$local_file"
}

if [ -e "$local_file" ] && [ "$REPLACE" -ne 1 ]; then
  if jq -e --arg pack "$PACK" '
      (if type == "array" then false
       else ((.packs // []) | index($pack) != null)
       end)
    ' "$local_file" >/dev/null; then
    note "pack already enabled: $PACK ($local_file)"
    exit 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "Would merge pack '$PACK' into existing $local_file"
    exit 0
  fi
  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  normalize_pack_file "$local_file" "$PACK" >"$tmp"
  mv "$tmp" "$local_file"
  trap - EXIT
  note "merged pack=$PACK local=$local_file"
  exit 0
fi

write_local
