#!/usr/bin/env bash
# Manage one selected skhd LaunchAgent and persist only a verified result.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$HOME/.config/sketchybar}"
STATE_FILE="$CONFIG_DIR/state.json"
HELPER="${BARISTA_AGENT_HELPER:-$CONFIG_DIR/helpers/launch_agent_manager.sh}"
USER_ID="$(id -u)"
DOMAIN="gui/$USER_ID"
action="${1:-status}"

any_skhd_running() { pgrep -x skhd >/dev/null 2>&1; }
fail() { printf 'Shortcuts: %s\n' "$*" >&2; exit 1; }

case "$action" in
  status)
    # Compatibility read-only status describes any running skhd instance.
    if any_skhd_running; then printf 'skhd running\n'; else printf 'skhd stopped\n'; fi
    exit 0 ;;
  toggle|on|off|start|stop|restart) ;;
  *) fail "Usage: $0 {toggle|on|off|status|restart}" ;;
esac

# Hold one user-wide lock through selection, mutation, verification, rollback,
# and saving. The JSON writer's shorter lock protects unrelated state fields.
if [[ "${BARISTA_SHORTCUT_OPERATION_LOCKED:-}" != "$DOMAIN" ]]; then
  exec python3 - "$SCRIPT_DIR/toggle_shortcuts.sh" "$action" "$DOMAIN" <<'PYLOCK'
import fcntl, math, os, pathlib, subprocess, sys, time
script, action, domain = sys.argv[1:]
# Independent callers can have different TMPDIR/config paths but manage the
# same per-user LaunchAgent. Keep their operation lock in one user cache.
path = pathlib.Path.home() / "Library" / "Caches" / "barista" / "shortcut-actions.lock"
try:
    timeout = float(os.environ.get("BARISTA_SHORTCUT_LOCK_TIMEOUT", "10"))
    if not math.isfinite(timeout) or timeout < 0:
        raise ValueError("lock timeout must be finite and nonnegative")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as lock:
        deadline = time.monotonic() + timeout
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    print("Shortcuts: another shortcut action is still running; try again.", file=sys.stderr)
                    sys.exit(1)
                time.sleep(0.05)
        env = dict(os.environ, BARISTA_SHORTCUT_OPERATION_LOCKED=domain)
        result = subprocess.run([script, action], env=env, pass_fds=(lock.fileno(),))
        sys.exit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
except (OSError, ValueError) as error:
    print(f"Shortcuts: cannot acquire action lock: {error}", file=sys.stderr)
    sys.exit(1)
PYLOCK
fi

python3 "$SCRIPT_DIR/yabai_state.py" "$STATE_FILE" shortcuts-check
[[ -x "$HELPER" ]] || fail "LaunchAgent helper not found: $HELPER"

labels=()
loaded=()
if [[ -n "${BARISTA_SKHD_LABEL:-}" ]]; then
  labels=("$BARISTA_SKHD_LABEL")
else
  for candidate in com.koekeishiya.skhd homebrew.mxcl.skhd; do
    if [[ -f "$HOME/Library/LaunchAgents/$candidate.plist" ]]; then
      labels+=("$candidate")
      if launchctl print "$DOMAIN/$candidate" >/dev/null 2>&1; then
        loaded+=("$candidate")
      fi
    fi
  done
fi
if [[ ${#loaded[@]} -eq 1 ]]; then
  label="${loaded[0]}"
elif [[ ${#loaded[@]} -gt 1 ]]; then
  fail "More than one skhd service is loaded; choose BARISTA_SKHD_LABEL before changing it."
elif [[ ${#labels[@]} -eq 1 ]]; then
  label="${labels[0]}"
else
  fail "Expected one installed skhd LaunchAgent; found ${#labels[@]}."
fi
PLIST="$HOME/Library/LaunchAgents/$label.plist"
[[ -f "$PLIST" ]] || fail "LaunchAgent not found: $label"

selected_running() {
  local job
  job="$(launchctl print "$DOMAIN/$label" 2>/dev/null)" || return 1
  printf '%s\n' "$job" | awk '
    /^[[:space:]]*state = running[[:space:]]*$/ { running = 1 }
    /^[[:space:]]*pid = [1-9][0-9]*[[:space:]]*$/ { pid = 1 }
    END { exit !(running && pid) }
  '
}

if [[ "$action" == "toggle" ]]; then
  if selected_running; then action=off; else action=on; fi
fi
case "$action" in
  on|start|restart)
    # Do not start a second instance when the selected job does not own the
    # already-running process. Other users' processes are outside this scope.
    if ! selected_running && pgrep -u "$USER_ID" -x skhd >/dev/null 2>&1; then
      fail "Another skhd process is running outside $label; stop it or select its LaunchAgent first."
    fi ;;
esac

# Restore the prior effective login policy if the service operation, its
# verification, or the final state write fails. launchctl has no unset-override
# command, so an absent override falls back to the plist's Disabled preference.
disabled_snapshot="$(launchctl print-disabled "$DOMAIN")" || fail "Cannot read the shortcut service login policy."
previous_disabled="$(python3 -c '
import plistlib, re, sys
label, plist = sys.argv[1:]
text = sys.stdin.read()
if "disabled services = {" not in text:
    raise ValueError("unexpected launchctl disabled-services response")
match = re.search(r"\"" + re.escape(label) + r"\"\s*=>\s*(true|false|enabled|disabled)\b", text)
if match:
    disabled = match.group(1) in ("true", "disabled")
else:
    with open(plist, "rb") as source:
        disabled = bool(plistlib.load(source).get("Disabled", False))
print("true" if disabled else "false")
' "$label" "$PLIST" <<< "$disabled_snapshot")"
policy_changed=false
committed=false
rollback_on_exit() {
  local status=$? restore=enable
  trap - EXIT
  if [[ "$status" != 0 && "$policy_changed" == true && "$committed" != true ]]; then
    [[ "$previous_disabled" != true ]] || restore=disable
    if ! launchctl "$restore" "$DOMAIN/$label"; then
      printf 'Shortcuts: rollback failed; login policy for %s may differ from the saved preference.\n' "$label" >&2
    fi
  fi
  exit "$status"
}
trap rollback_on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

case "$action" in
  on|start|restart)
    policy_changed=true
    launchctl enable "$DOMAIN/$label"
    if [[ "$action" == restart ]]; then
      "$HELPER" restart "$label"
    else
      # start is idempotent and does not replace an already-running job.
      "$HELPER" start "$label"
    fi
    desired=true ;;
  off|stop)
    policy_changed=true
    launchctl disable "$DOMAIN/$label"
    "$HELPER" stop "$label"
    desired=false ;;
esac

confirmed=false
for ((attempt=0; attempt<20; attempt++)); do
  actual=false
  if selected_running; then actual=true; fi
  if [[ "$actual" == "$desired" ]]; then confirmed=true; break; fi
  sleep 0.1
done
[[ "$confirmed" == true ]] || fail "$label did not reach the requested state; saved preference was not changed."
python3 "$SCRIPT_DIR/yabai_state.py" "$STATE_FILE" shortcuts-state "$desired"
committed=true
if [[ "$desired" == true ]]; then printf 'skhd running (%s)\n' "$label"; else printf 'skhd stopped (%s)\n' "$label"; fi
