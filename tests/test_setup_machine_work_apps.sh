#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STATE_FILE="$TMP_DIR/state.json"
cat > "$STATE_FILE" <<'JSON'
{
  "_version": 2,
  "menus": {
    "apple": {
      "custom": [
        {
          "id": "personal_keep",
          "label": "Personal Tool",
          "section": "personal",
          "command": "open /tmp/personal"
        },
        {
          "id": "work_google_old",
          "label": "Old Work App",
          "section": "work",
          "command": "open https://old.example"
        },
        {
          "id": "work_google_gmail",
          "label": "Stale Gmail",
          "section": "custom",
          "command": "open https://stale.example"
        }
      ]
    }
  }
}
JSON

"$ROOT_DIR/scripts/setup_machine.sh" \
  --state "$STATE_FILE" \
  --apps-only \
  --replace \
  --domain example.com \
  --work-apps-out-file data/work_apps.local.json \
  --yes \
  --no-reload >/dev/null

jq -e '
  ([.menus.apple.custom[] | select(.id == "personal_keep")] | length) == 1 and
  ([.menus.apple.custom[] | select(.id == "work_google_old")] | length) == 0 and
  ([.menus.apple.custom[] | select(.id == "work_google_gmail")] | length) == 0 and
  ([.menus.apple.custom[] | select(.id | startswith("work_google_"))] | length) == 0 and
  ([.menus.work.google_apps[] | select(.id | startswith("work_google_"))] | length) == 6 and
  .menus.work.workspace_domain == "example.com"
' "$STATE_FILE" >/dev/null
