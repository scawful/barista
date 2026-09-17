#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RUNTIME="$TMP_DIR/runtime"
BIN_DIR="$TMP_DIR/bin"
mkdir -p "$RUNTIME/data" "$RUNTIME/scripts" "$RUNTIME/modules" "$RUNTIME/bin" "$BIN_DIR"
cp "$ROOT_DIR/data/onboard.defaults.json" "$RUNTIME/data/"
cp "$ROOT_DIR/data/interface_extensions.personal.example.json" "$RUNTIME/data/"
cp "$ROOT_DIR/data/interface_extensions.example.json" "$RUNTIME/data/"
cp "$ROOT_DIR/scripts/enable_extension_pack.sh" "$RUNTIME/scripts/"
chmod +x "$RUNTIME/scripts/enable_extension_pack.sh"

# Offline stubs so doctor can run without a live SketchyBar stack.
cat >"$BIN_DIR/sketchybar" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$BIN_DIR/jq" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/jq "$@"
EOF
# Prefer real jq when available.
if command -v jq >/dev/null 2>&1; then
  ln -sf "$(command -v jq)" "$BIN_DIR/jq"
fi
chmod +x "$BIN_DIR/sketchybar" "$BIN_DIR/jq"

# Minimal items_left and workflow runner for doctor source checks.
printf 'local shortcut_mode = true\n' >"$RUNTIME/modules/items_left.lua"
cat >"$RUNTIME/scripts/open_local_workflow.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$RUNTIME/scripts/open_local_workflow.sh"

# Stub yabai_control doctor summary used by onboard checks.
cat >"$RUNTIME/scripts/yabai_control.sh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "doctor" ]; then
  echo "skhd shortcut summary: active=1 disabled=0 duplicates=0 raw_yabai=0 missing_targets=0"
  exit 0
fi
exit 0
EOF
chmod +x "$RUNTIME/scripts/yabai_control.sh"

cat >"$RUNTIME/data/machine.local.json" <<'JSON'
{
  "_version": 1,
  "profile_variant": "personal",
  "menu_packs": ["core", "dev_tools", "personal"]
}
JSON

cat >"$RUNTIME/state.json" <<'JSON'
{
  "_version": 2,
  "profile": "personal",
  "modes": {
    "window_manager": "disabled",
    "runtime_backend": "lua"
  },
  "machine": {
    "profile_variant": "personal",
    "menu_packs": ["core", "dev_tools", "personal"]
  }
}
JSON

# Work profile must reject personal pack without --force.
cat >"$TMP_DIR/work-machine.json" <<'JSON'
{
  "profile_variant": "work",
  "menu_packs": ["core", "work", "dev_tools"]
}
JSON
cp "$TMP_DIR/work-machine.json" "$RUNTIME/data/machine.local.json"
if "$RUNTIME/scripts/enable_extension_pack.sh" --pack personal --config-dir "$RUNTIME" >/dev/null 2>&1; then
  echo "FAIL: personal pack should be blocked on work variant" >&2
  exit 1
fi

# Restore personal machine profile and enable pack.
cat >"$RUNTIME/data/machine.local.json" <<'JSON'
{
  "_version": 1,
  "profile_variant": "personal",
  "menu_packs": ["core", "dev_tools", "personal"]
}
JSON
"$RUNTIME/scripts/enable_extension_pack.sh" --pack personal --config-dir "$RUNTIME" >/dev/null
jq -e '.packs | index("personal") != null' "$RUNTIME/data/interface_extensions.local.json" >/dev/null
jq -e '.items | length > 0' "$RUNTIME/data/interface_extensions.local.json" >/dev/null

# Idempotent second enable.
"$RUNTIME/scripts/enable_extension_pack.sh" --pack personal --config-dir "$RUNTIME" | grep -Fq 'pack already enabled'

# Local onboard overlay should stay optional for portable defaults.
cp "$ROOT_DIR/data/onboard.local.example.json" "$RUNTIME/data/onboard.local.json"
# Point expected tools at fixtures that exist in the temp tree.
cat >"$RUNTIME/data/onboard.local.json" <<JSON
{
  "_version": 1,
  "expected_tools": [
    {
      "id": "fixture_tool",
      "label": "Fixture tool",
      "kind": "path",
      "candidates": ["$RUNTIME/scripts/open_local_workflow.sh"],
      "severity": "fail"
    }
  ],
  "expected_workflow_groups": ["agentic_ai", "workspaces"]
}
JSON

# Doctor onboard should succeed against the stubbed runtime without live sketchybar.
PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin" \
  BARISTA_CONFIG_DIR="$RUNTIME" \
  "$ROOT_DIR/scripts/barista-doctor.sh" --config-dir "$RUNTIME" --state "$RUNTIME/state.json" --onboard --offline --report \
  | tee "$TMP_DIR/doctor.out"

grep -Fq 'doctor.report.onboard_mode=1' "$TMP_DIR/doctor.out"
grep -Fq 'Onboard config loaded (defaults+local)' "$TMP_DIR/doctor.out"
grep -Fq 'Local tool ready: Fixture tool' "$TMP_DIR/doctor.out"
grep -Fq 'Local workflow group present: agentic_ai' "$TMP_DIR/doctor.out" || {
  # personal example uses workflow_group; ensure enable_extension_pack preserved it
  jq -e '[.items[].workflow_group] | index("agentic_ai") != null' "$RUNTIME/data/interface_extensions.local.json" >/dev/null
}

printf 'test_onboard_portable.sh: ok\n'
