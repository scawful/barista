#!/bin/bash
# plugins/afs_approvals.sh: badge hidden at 0, count + rows when pending,
# review opens a terminal with bin/afs-approvals-review.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/plugins/afs_approvals.sh"
TMP_DIR="$(mktemp -d)"
BIN_DIR="$TMP_DIR/bin"
FIXTURE="$TMP_DIR/approvals.json"
SKETCHYBAR_LOG="$TMP_DIR/sketchybar.log"
OPEN_LOG="$TMP_DIR/open.log"
OSASCRIPT_LOG="$TMP_DIR/osascript.log"
REVIEWER="$TMP_DIR/afs-approvals-review"

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

assert_log_has() {
  grep -qF -- "$1" "$SKETCHYBAR_LOG" || { echo "--- sketchybar log ---" >&2; cat "$SKETCHYBAR_LOG" >&2; fail "$2"; }
}
assert_log_lacks() {
  ! grep -qF -- "$1" "$SKETCHYBAR_LOG" || { echo "--- sketchybar log ---" >&2; cat "$SKETCHYBAR_LOG" >&2; fail "$2"; }
}

mkdir -p "$BIN_DIR"
cat > "$BIN_DIR/sketchybar" <<'STUB'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "${BARISTA_TEST_SKETCHYBAR_LOG:?}"
STUB
cat > "$BIN_DIR/open" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${BARISTA_TEST_OPEN_LOG:?}"
STUB
cat > "$BIN_DIR/osascript" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${BARISTA_TEST_OSASCRIPT_LOG:?}"
STUB
chmod +x "$BIN_DIR/sketchybar" "$BIN_DIR/open" "$BIN_DIR/osascript"
printf '#!/bin/bash\n' > "$REVIEWER"; chmod +x "$REVIEWER"
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

run_plugin() {
  : > "$SKETCHYBAR_LOG"
  env \
    PATH="$BIN_DIR:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    HOME="$TMP_DIR" \
    NAME=afs_approvals \
    AFS_APPROVALS_FILE="$FIXTURE" \
    BARISTA_SKETCHYBAR_BIN="$BIN_DIR/sketchybar" \
    BARISTA_AFS_REVIEWER="$REVIEWER" \
    BARISTA_TEST_SKETCHYBAR_LOG="$SKETCHYBAR_LOG" \
    BARISTA_TEST_OPEN_LOG="$OPEN_LOG" \
    BARISTA_TEST_OSASCRIPT_LOG="$OSASCRIPT_LOG" \
    "$@" \
    "$SCRIPT" "${PLUGIN_ARGS[@]}"
}

# --- 1. no file at all → hidden ---------------------------------------------
PLUGIN_ARGS=(refresh)
rm -f "$FIXTURE"
run_plugin
assert_log_has "--set afs_approvals drawing=off popup.drawing=off label=" "missing queue file should hide the badge"
assert_log_has "--set afs_approvals.row.5 drawing=off" "all rows hidden when nothing is pending"

# --- 2. two pending (older one listed first) + one approved ------------------
cat > "$FIXTURE" <<'JSON'
[
  {"agent": "mission-runner", "action": "git_push", "detail": "Mission 'pr-review-prep': push branch",
   "timestamp": "2026-09-01T10:00:00+00:00", "status": "pending", "request_id": "gate_newer000000"},
  {"agent": "mission-runner", "action": "file_delete", "detail": "Mission 'git-hygiene': remove 3 merged worktrees under ~/src/hobby",
   "timestamp": "2026-07-16T21:50:54+00:00", "status": "pending", "request_id": "gate_older000000"},
  {"agent": "scout", "action": "deploy", "detail": "done already",
   "timestamp": "2026-06-01T00:00:00+00:00", "status": "approved", "request_id": "gate_done0000000"}
]
JSON
run_plugin
assert_log_has "--set afs_approvals drawing=on icon=" "badge shows when requests are pending"
assert_log_has " label=2 " "badge label is the pending count"
assert_log_has "--set afs_approvals.summary label=2 pending · oldest 2026-07-16" "summary names the oldest request"
assert_log_has "--set afs_approvals.row.1 drawing=on label=mission-runner · file_delete — Mission 'git-hygiene': remove 3 merged workt click_script=$SCRIPT review 'gate_older000000'" "row 1 is the oldest request, detail trimmed, click opens its review"
assert_log_has "--set afs_approvals.row.2 drawing=on label=mission-runner · git_push — Mission 'pr-review-prep': push branch click_script=$SCRIPT review 'gate_newer000000'" "row 2 is the newer request"
assert_log_has "--set afs_approvals.row.3 drawing=off" "unused rows are hidden"
assert_log_lacks "gate_done0000000" "approved requests never reach the popup"

# --- 3. list action prints the pending rows as JSON --------------------------
PLUGIN_ARGS=(list)
listed="$(run_plugin)"
[ "$(printf '%s' "$listed" | jq 'length')" = "2" ] || fail "list should print the two pending rows"
[ "$(printf '%s' "$listed" | jq -r '.[0].request_id')" = "gate_older000000" ] || fail "list is sorted oldest first"

# --- 4. review → Ghostty when present, with the request id -------------------
PLUGIN_ARGS=(review gate_older000000)
mkdir -p "$TMP_DIR/Ghostty.app"; : > "$OPEN_LOG"; : > "$OSASCRIPT_LOG"
run_plugin BARISTA_GHOSTTY_APP="$TMP_DIR/Ghostty.app"
assert_log_has "--set afs_approvals popup.drawing=off" "review closes the popup first"
grep -qF -- "-na $TMP_DIR/Ghostty.app --args -e /bin/zsh -lc '$REVIEWER' --request-id 'gate_older000000'" "$OPEN_LOG" \
  || { cat "$OPEN_LOG" >&2; fail "review should open the reviewer in Ghostty with the request id"; }
[ ! -s "$OSASCRIPT_LOG" ] || fail "Terminal fallback must not run when Ghostty exists"

# --- 5. review → Terminal.app fallback, no request id ------------------------
PLUGIN_ARGS=(review)
: > "$OPEN_LOG"; : > "$OSASCRIPT_LOG"
run_plugin BARISTA_GHOSTTY_APP="$TMP_DIR/nope.app"
grep -qF -- "tell application \"Terminal\" to do script \"'$REVIEWER'\"" "$OSASCRIPT_LOG" \
  || { cat "$OSASCRIPT_LOG" >&2; fail "review should fall back to Terminal.app with the reviewer command"; }
[ ! -s "$OPEN_LOG" ] || fail "open must not run for the Terminal fallback"

echo "afs_approvals plugin tests passed"
