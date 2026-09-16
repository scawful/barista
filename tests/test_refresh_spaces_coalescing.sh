#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export CONFIG_DIR="$TMP_DIR/config"
export SCRIPTS_DIR="$CONFIG_DIR/scripts"
export BARISTA_TEST_LOG="$TMP_DIR/events"
export BARISTA_TEST_SPACES="$TMP_DIR/spaces.json"
export BARISTA_SPACE_REFRESH_COALESCE_DELAY=0.04
export BARISTA_YABAI_BIN="$TMP_DIR/yabai"
export BARISTA_SKETCHYBAR_BIN="$TMP_DIR/sketchybar"
export BARISTA_PERF_CLOCK_BIN="$TMP_DIR/perf_clock"
export PATH="$TMP_DIR:$PATH"
mkdir -p "$CONFIG_DIR/plugins" "$SCRIPTS_DIR" "$CONFIG_DIR/cache/space_visuals"
ln -s "$ROOT_DIR/plugins/refresh_spaces.sh" "$CONFIG_DIR/plugins/refresh_spaces.sh"
ln -s "$ROOT_DIR/plugins/lib" "$CONFIG_DIR/plugins/lib"

cat > "$BARISTA_TEST_SPACES" <<'EOF'
[{"display":1,"index":1,"is-visible":true,"has-focus":true},{"display":2,"index":2,"is-visible":true,"has-focus":false}]
EOF
printf '1,2|1-1,2-2' > "$CONFIG_DIR/.spaces_cache"
printf '1:1,2:2' > "$CONFIG_DIR/.spaces_active_cache"
printf 'space.1\nspace.2\n' > "$CONFIG_DIR/cache/space_visuals/space_items"
printf '38' > "$CONFIG_DIR/cache/external_bar_height"
cat > "$BARISTA_YABAI_BIN" <<'EOF'
#!/bin/bash
if [ "${2:-}" = config ]; then
  printf 'external_bar %s\n' "$4" >> "$BARISTA_TEST_LOG"
  [ "${BARISTA_TEST_EXTERNAL_FAIL:-0}" != 1 ]
  exit $?
fi
printf 'query spaces\n' >> "$BARISTA_TEST_LOG"
cat "$BARISTA_TEST_SPACES"
EOF
cat > "$BARISTA_SKETCHYBAR_BIN" <<'EOF'
#!/bin/bash
case "$*" in
  '--query bar') printf '{"height":38,"items":["space.1","space.2"]}\n' ;;
  '--query space.'*) printf '{"geometry":{"background":{"height":30}}}\n' ;;
  *) printf '%s\n' "$*" >> "$BARISTA_TEST_LOG" ;;
esac
EOF
cat > "$BARISTA_PERF_CLOCK_BIN" <<'EOF'
#!/bin/bash
printf '1000\n'
EOF
cat > "$CONFIG_DIR/plugins/space_visuals.sh" <<'EOF'
#!/bin/bash
printf 'visual %s\n' "$SENDER" >> "$BARISTA_TEST_LOG"
EOF
cat > "$CONFIG_DIR/plugins/simple_spaces.sh" <<'EOF'
#!/bin/bash
printf 'topology %s retry=%s\n' "$BARISTA_REASON" "${BARISTA_TOPOLOGY_APPLY_RETRY:-0}" >> "$BARISTA_TEST_LOG"
[ "${BARISTA_TEST_TOPOLOGY_FAIL:-0}" != 1 ]
EOF
ln -s "$ROOT_DIR/scripts/update_external_bar.sh" "$SCRIPTS_DIR/update_external_bar.sh"
chmod +x "$TMP_DIR/yabai" "$TMP_DIR/sketchybar" "$TMP_DIR/perf_clock" \
  "$CONFIG_DIR/plugins/space_visuals.sh" "$CONFIG_DIR/plugins/simple_spaces.sh"

wait_for_queue() {
  local _attempt
  for _attempt in {1..100}; do
    if [ ! -d "$CONFIG_DIR/.refresh_spaces.lock" ] \
      && [ ! -d "$CONFIG_DIR/cache/space_refresh_pending.lock" ]; then
      sleep 0.05
      [ ! -d "$CONFIG_DIR/.refresh_spaces.lock" ] \
        && [ ! -d "$CONFIG_DIR/cache/space_refresh_pending.lock" ] && return 0
    fi
    sleep 0.02
  done
  echo 'FAIL: coalesced refresh did not settle' >&2
  exit 1
}

# A focus burst must keep the focused path after waiting behind topology.
: > "$BARISTA_TEST_LOG"
mkdir "$CONFIG_DIR/.refresh_spaces.lock"
for _ in {1..5}; do
  BARISTA_REASON=space_changed "$CONFIG_DIR/plugins/refresh_spaces.sh"
done
rmdir "$CONFIG_DIR/.refresh_spaces.lock"
wait_for_queue
[ "$(grep -c '^visual space_active_refresh$' "$BARISTA_TEST_LOG" || true)" = 1 ] || {
  echo 'FAIL: coalesced focus events must retain one active-only visual refresh' >&2; exit 1;
}
if grep -q '^query spaces$' "$BARISTA_TEST_LOG"; then
  echo 'FAIL: coalesced focus events must not query topology' >&2; exit 1
fi

# A following focus event must not downgrade pending display repair.
: > "$BARISTA_TEST_LOG"
cat > "$BARISTA_TEST_SPACES" <<'EOF'
[{"display":1,"index":1,"is-visible":true,"has-focus":false},{"display":2,"index":2,"is-visible":true,"has-focus":true}]
EOF
mkdir "$CONFIG_DIR/.refresh_spaces.lock"
BARISTA_REASON=display_added SENDER=space_changed "$CONFIG_DIR/plugins/refresh_spaces.sh"
BARISTA_REASON=space_changed "$CONFIG_DIR/plugins/refresh_spaces.sh"
rmdir "$CONFIG_DIR/.refresh_spaces.lock"
wait_for_queue
grep -qx 'query spaces' "$BARISTA_TEST_LOG" || {
  echo 'FAIL: a display event followed by focus must still inspect topology' >&2; exit 1;
}
grep -qx 'external_bar all:38:0' "$BARISTA_TEST_LOG" || {
  echo 'FAIL: unchanged space indexes must not suppress display external_bar repair' >&2; exit 1;
}
if grep -q '^topology ' "$BARISTA_TEST_LOG"; then
  echo 'FAIL: unchanged display topology must not rebuild space items' >&2; exit 1
fi
grep -qx 'visual space_active_refresh' "$BARISTA_TEST_LOG" || {
  echo 'FAIL: mixed display and focus events must refresh focus when visible spaces are unchanged' >&2; exit 1;
}
grep -qx -- '--trigger space_active_refresh' "$BARISTA_TEST_LOG" || {
  echo 'FAIL: mixed display and focus events must notify active-space consumers' >&2; exit 1;
}

# A direct display event needs the same repair without a forced rebuild.
: > "$BARISTA_TEST_LOG"
BARISTA_REASON=display_removed "$CONFIG_DIR/plugins/refresh_spaces.sh"
grep -qx 'external_bar all:38:0' "$BARISTA_TEST_LOG" || {
  echo 'FAIL: direct display events must repair external_bar with unchanged spaces' >&2; exit 1;
}

# A mixed repair/display retry may meet contention again before it samples.
# Its retry flag must survive even though the display reason has priority.
: > "$BARISTA_TEST_LOG"
mkdir "$CONFIG_DIR/.refresh_spaces.lock"
BARISTA_REASON=display_changed BARISTA_TOPOLOGY_APPLY_RETRY=1 BARISTA_SPACE_ACTIVE_PENDING=1 \
  "$CONFIG_DIR/plugins/refresh_spaces.sh"
rmdir "$CONFIG_DIR/.refresh_spaces.lock"
wait_for_queue
grep -qx 'topology display_changed retry=1' "$BARISTA_TEST_LOG" || {
  echo 'FAIL: recontended display repair must retain its topology retry flag' >&2; exit 1;
}
grep -qx 'external_bar all:38:0' "$BARISTA_TEST_LOG" || {
  echo 'FAIL: mixed display repair must still update external_bar' >&2; exit 1;
}
grep -qx -- '--trigger space_active_refresh' "$BARISTA_TEST_LOG" || {
  echo 'FAIL: recontended display repair must retain its pending focus update' >&2; exit 1;
}

# Failed reservation updates remain eligible for the next refresh.
printf '37' > "$CONFIG_DIR/cache/external_bar_height"
BARISTA_REASON=display_removed BARISTA_TEST_EXTERNAL_FAIL=1 "$CONFIG_DIR/plugins/refresh_spaces.sh"
[ "$(cat "$CONFIG_DIR/cache/external_bar_height")" = 37 ] || {
  echo 'FAIL: failed external_bar updates must not advance the successful height cache' >&2; exit 1;
}
# Explicit absent Yabai remains a supported no-op, even with another binary
# on PATH; a supplied failing Yabai must propagate failure to the caller.
BARISTA_YABAI_BIN="$TMP_DIR/missing-yabai" "$SCRIPTS_DIR/update_external_bar.sh" 38
if BARISTA_TEST_EXTERNAL_FAIL=1 "$SCRIPTS_DIR/update_external_bar.sh" 38; then
  echo 'FAIL: an available Yabai config failure must propagate from update_external_bar.sh' >&2; exit 1
fi

# Failed topology applies must not commit their new map into the focus cache.
cat > "$BARISTA_TEST_SPACES" <<'EOF'
[{"display":1,"index":1,"is-visible":true,"has-focus":true},{"display":3,"index":2,"is-visible":true,"has-focus":false}]
EOF
if BARISTA_REASON=display_added BARISTA_TEST_TOPOLOGY_FAIL=1 "$CONFIG_DIR/plugins/refresh_spaces.sh"; then
  echo 'FAIL: a failed topology apply must propagate failure' >&2; exit 1
fi
[ "$(cat "$CONFIG_DIR/.spaces_cache")" = '1,2|1-1,2-2' ] || {
  echo 'FAIL: failed topology apply must preserve the last successful topology cache' >&2; exit 1;
}
[ "$(cat "$CONFIG_DIR/.spaces_active_cache")" = '1:1,2:2' ] || {
  echo 'FAIL: failed topology apply must preserve the last successful active cache' >&2; exit 1;
}

printf 'test_refresh_spaces_coalescing.sh: ok\n'
