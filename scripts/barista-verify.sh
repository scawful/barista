#!/bin/bash
# barista-verify.sh - Smoke test and validation suite for Barista
# Usage: ./scripts/barista-verify.sh [--quick]

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

pass=0
fail=0
skip=0

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf "${GREEN}  ✓${RESET} %s\n" "$label"
    ((pass++))
  else
    printf "${RED}  ✗${RESET} %s\n" "$label"
    ((fail++))
  fi
}

skip_check() {
  local label="$1"
  printf "${YELLOW}  ⊘${RESET} %s (skipped)\n" "$label"
  ((skip++))
}

echo ""
echo "━━ Barista Verification Suite ━━"
echo ""

# 1. Lua unit tests
echo "${YELLOW}▸ Lua Unit Tests${RESET}"
if command -v lua >/dev/null 2>&1; then
  if lua "$CONFIG_DIR/tests/run_tests.lua"; then
    ((pass++))
  else
    ((fail++))
  fi
else
  skip_check "Lua tests (lua not in PATH)"
fi

echo ""
echo "${YELLOW}▸ Binary Checks${RESET}"

# 2. Check compiled binaries
BINARIES=(
  "popup_hover"
  "popup_anchor"
  "submenu_hover"
  "popup_manager"
  "popup_guard"
  "menu_action"
  "state_manager"
  "space_manager"
  "clock_widget"
  "system_info_widget"
)
for bin in "${BINARIES[@]}"; do
  if [ -f "$CONFIG_DIR/build/bin/$bin" ] || [ -f "$CONFIG_DIR/bin/$bin" ]; then
    check "binary: $bin" test -x "$CONFIG_DIR/build/bin/$bin" -o -x "$CONFIG_DIR/bin/$bin"
  else
    skip_check "binary: $bin (not built)"
  fi
done

echo ""
echo "${YELLOW}▸ Configuration Checks${RESET}"

# 3. Validate state.json is parseable
if [ -f "$CONFIG_DIR/state.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    check "state.json: valid JSON" jq empty "$CONFIG_DIR/state.json"
  else
    skip_check "state.json validation (jq not available)"
  fi
else
  skip_check "state.json (file not found)"
fi

# 4. Check critical Lua modules exist
for mod in main theme bar_config state profile icons shortcuts widgets menu spaces; do
  if [ "$mod" = "main" ]; then
    check "module: $mod.lua" test -f "$CONFIG_DIR/$mod.lua"
  else
    check "module: $mod.lua" test -f "$CONFIG_DIR/modules/$mod.lua" -o -f "$CONFIG_DIR/$mod.lua"
  fi
done

# 5. Check extracted modules from Phase 1
for mod in shell_utils paths binary_resolver submenu_registry; do
  check "module: $mod.lua" test -f "$CONFIG_DIR/modules/$mod.lua"
done

# 6. ShellCheck (if available and not --quick)
if [ "${1:-}" != "--quick" ]; then
  echo ""
  echo "${YELLOW}▸ Shell Script Lint${RESET}"
  if command -v shellcheck >/dev/null 2>&1; then
    for script in "$CONFIG_DIR"/plugins/*.sh; do
      basename="$(basename "$script")"
      if shellcheck -S warning "$script" >/dev/null 2>&1; then
        check "shellcheck: $basename" true
      else
        printf "${YELLOW}  △${RESET} shellcheck: %s (warnings)\n" "$basename"
        ((skip++))
      fi
    done
  else
    skip_check "shellcheck (not installed)"
  fi
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "  ${GREEN}%d passed${RESET}  " "$pass"
if [ "$fail" -gt 0 ]; then
  printf "${RED}%d failed${RESET}  " "$fail"
fi
if [ "$skip" -gt 0 ]; then
  printf "${YELLOW}%d skipped${RESET}" "$skip"
fi
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit "$fail"
