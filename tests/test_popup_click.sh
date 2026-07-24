#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
FAKE_SKETCHYBAR="${TMP_ROOT}/sketchybar"
FAKE_MANAGER="${TMP_ROOT}/popup_switch"
CLICK_LOG="${TMP_ROOT}/click.log"
DIRECT_LOG="${TMP_ROOT}/direct.log"
CURRENT_SCRIPT="$(
  printf "BARISTA_POPUP_TOPOLOGY_TOKEN=current-token %q switch control_center" \
    "${FAKE_MANAGER}"
)"

cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

cat > "${FAKE_MANAGER}" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s\n' \
  "${BARISTA_POPUP_TOPOLOGY_TOKEN:-}" "$1" "$2" > "${BARISTA_TEST_CLICK_LOG:?}"
EOF

cat > "${FAKE_SKETCHYBAR}" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--query" && "${BARISTA_TEST_QUERY_FAIL:-0}" != "1" ]]; then
  jq -n --arg script "${BARISTA_TEST_CURRENT_CLICK:?}" \
    '{scripting: {click_script: $script}}'
  exit 0
fi
printf '%s\n' "$@" > "${BARISTA_TEST_DIRECT_LOG:?}"
EOF
chmod +x "${FAKE_MANAGER}" "${FAKE_SKETCHYBAR}"

BARISTA_TEST_CURRENT_CLICK="${CURRENT_SCRIPT}" \
  BARISTA_TEST_CLICK_LOG="${CLICK_LOG}" \
  BARISTA_TEST_DIRECT_LOG="${DIRECT_LOG}" \
  SKETCHYBAR_BIN="${FAKE_SKETCHYBAR}" \
  bash "${ROOT_DIR}/scripts/invoke_popup_click.sh" control_center
test "$(cat "${CLICK_LOG}")" = "current-token|switch|control_center"

BARISTA_TEST_QUERY_FAIL=1 \
  BARISTA_TEST_CURRENT_CLICK="${CURRENT_SCRIPT}" \
  BARISTA_TEST_CLICK_LOG="${CLICK_LOG}" \
  BARISTA_TEST_DIRECT_LOG="${DIRECT_LOG}" \
  SKETCHYBAR_BIN="${FAKE_SKETCHYBAR}" \
  bash "${ROOT_DIR}/scripts/invoke_popup_click.sh" control_center
test "$(paste -sd' ' "${DIRECT_LOG}")" = "--set control_center popup.drawing=toggle"

CONFIG_ROOT="${TMP_ROOT}/config"
mkdir -p "${CONFIG_ROOT}/scripts"
cp "${ROOT_DIR}/scripts/invoke_popup_click.sh" "${CONFIG_ROOT}/scripts/"
: > "${CLICK_LOG}"
BARISTA_TEST_CURRENT_CLICK="${CURRENT_SCRIPT}" \
  BARISTA_TEST_CLICK_LOG="${CLICK_LOG}" \
  BARISTA_TEST_DIRECT_LOG="${DIRECT_LOG}" \
  CONFIG_DIR="${CONFIG_ROOT}" \
  SKETCHYBAR_BIN="${FAKE_SKETCHYBAR}" \
  YABAI_BIN=/nonexistent \
  bash "${ROOT_DIR}/scripts/focus_display_and_toggle_popup.sh" control_center
test "$(cat "${CLICK_LOG}")" = "current-token|switch|control_center"

printf '%s\n' "popup click forwarding tests passed"
