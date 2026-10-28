#!/bin/bash
# Round-trips the Barista/native dock switch against fake defaults/launchctl.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

BIN_DIR="$TMP_DIR/bin"
DEFAULTS_DIR="$TMP_DIR/defaults"
LAUNCHCTL_LOG="$TMP_DIR/launchctl.log"
mkdir -p "$BIN_DIR" "$DEFAULTS_DIR" "$TMP_DIR/build/release"
printf '#!/bin/bash\n' > "$TMP_DIR/build/release/barista-agent"
chmod +x "$TMP_DIR/build/release/barista-agent"

cat > "$BIN_DIR/defaults" <<EOF
#!/bin/bash
file="$DEFAULTS_DIR/\$3"
case "\$1" in
  read) [ -f "\$file" ] && cat "\$file" || exit 1 ;;
  write)
    value="\$5"
    [ "\$4" != -bool ] || { [ "\$value" = true ] && value=1 || value=0; }
    printf '%s\n' "\$value" > "\$file"
    ;;
  delete) rm -f "\$file" ;;
esac
EOF
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$LAUNCHCTL_LOG" > "$BIN_DIR/launchctl"
printf '#!/bin/bash\nexit 0\n' > "$BIN_DIR/killall"
chmod +x "$BIN_DIR"/*

run() {
  PATH="$BIN_DIR:/usr/bin:/bin" HOME="$TMP_DIR/home" XDG_STATE_HOME="$TMP_DIR/state" \
    BARISTA_AGENT_BUILD_DIR="$TMP_DIR/build" \
    bash "$ROOT_DIR/scripts/barista_agent.sh" dock "$1"
}

value() { cat "$DEFAULTS_DIR/$1" 2>/dev/null || echo unset; }

fail() { echo "FAIL: $*" >&2; exit 1; }

PLIST="$TMP_DIR/home/Library/LaunchAgents/dev.barista.agent.plist"

printf '1\n' > "$DEFAULTS_DIR/autohide"
[ "$(run status)" = "dock: native" ] || fail "fresh install should report native"

run barista >/dev/null
run barista >/dev/null
[ "$(value autohide-delay)" = 1000 ] || fail "barista mode should hide the native Dock"
[ -f "$PLIST" ] || fail "barista mode should install the LaunchAgent"
grep -q "<string>$TMP_DIR/build/release/barista-agent</string>" "$PLIST" || fail "plist should run the built agent"
grep -q "^bootstrap gui/" "$LAUNCHCTL_LOG" || fail "barista mode should load the agent"
[ "$(run status)" = "dock: barista" ] || fail "status should report barista"

run native >/dev/null
[ "$(value autohide)" = 1 ] || fail "native mode should keep the original autohide"
[ "$(value autohide-delay)" = unset ] || fail "a repeated barista switch must not save its own delay as the original"
[ ! -f "$PLIST" ] || fail "native mode should remove the LaunchAgent"
tail -1 "$LAUNCHCTL_LOG" | grep -q "^bootout gui/.*/dev.barista.agent$" || fail "native mode should unload the agent last"

printf '0\n' > "$DEFAULTS_DIR/autohide"
printf '0.5\n' > "$DEFAULTS_DIR/autohide-delay"
run toggle >/dev/null
[ "$(value autohide)" = 1 ] || fail "toggle into barista should enable autohide"
run toggle >/dev/null
[ "$(value autohide)" = 0 ] && [ "$(value autohide-delay)" = 0.5 ] \
  || fail "toggle back should restore autohide=0 and delay=0.5, got $(value autohide)/$(value autohide-delay)"

# Paths are XML text in the plist; & and < must not break it.
ODD_BUILD="$TMP_DIR/R&D <builds>"
mkdir -p "$ODD_BUILD/release"
cp "$TMP_DIR/build/release/barista-agent" "$ODD_BUILD/release/"
BARISTA_AGENT_BUILD_DIR="$ODD_BUILD" PATH="$BIN_DIR:/usr/bin:/bin" HOME="$TMP_DIR/home" \
  XDG_STATE_HOME="$TMP_DIR/state" bash "$ROOT_DIR/scripts/barista_agent.sh" dock barista >/dev/null
python3 - "$PLIST" "$ODD_BUILD/release/barista-agent" <<'PY' || fail "plist must stay valid XML for paths with & and <"
import plistlib, sys
with open(sys.argv[1], "rb") as handle:
    assert plistlib.load(handle)["ProgramArguments"][0] == sys.argv[2]
PY

echo "test_barista_agent_dock.sh: ok"
