#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
CC_BIN="${CC:-$(command -v clang 2>/dev/null || command -v cc 2>/dev/null || true)}"
if [ -z "$CC_BIN" ]; then
  printf 'test_hover_serialization.sh: skipped (C compiler unavailable)\n'
  exit 0
fi
"$CC_BIN" -O2 -Wall -Wextra -o "$TMP_DIR/popup_anchor" "$ROOT_DIR/helpers/popup_anchor.c"
"$CC_BIN" -O2 -Wall -Wextra -o "$TMP_DIR/file_lock" "$ROOT_DIR/helpers/file_lock.c"

python3 - "$ROOT_DIR" "$TMP_DIR" <<'PY'
import fcntl
import os
import re
from pathlib import Path
import subprocess
import sys
import time

root, work = map(Path, sys.argv[1:])
native = Path(os.environ.get('BARISTA_TEST_POPUP_ANCHOR_BIN', str(work / 'popup_anchor')))
shell = root / 'plugins/popup_anchor.sh'
portable_shell = work / 'popup_anchor_portable.sh'
portable_shell.write_text(shell.read_text().replace(
    '[ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"',
    '. "' + str(root / 'plugins/lib/common.sh') + '"\nPATH=/usr/bin:/bin:/usr/sbin:/sbin'))
portable_shell.chmod(0o700)
stub = work / 'sketchybar-stub'
stub.write_text('''#!/bin/bash
case "$*" in
  *background.drawing=off*)
    if [ "${BLOCK_RESTORE:-0}" = 1 ]; then
      if [ "${SPAWN_DESCENDANT:-0}" = 1 ]; then
        (trap '' TERM; sleep 0.8; printf 'stale\\n' > "$TEST_DIR/descendant-style") &
        printf '%s\\n' "$!" > "$TEST_DIR/descendant-pid"
      fi
      : > "$TEST_DIR/restore-started"
      while [ ! -e "$TEST_DIR/release-restore" ]; do sleep 0.01; done
    fi
    printf 'idle\\n' > "$TEST_DIR/final-style"
    ;;
  *background.drawing=on*) printf 'hover\\n' > "$TEST_DIR/final-style" ;;
esac
''')
stub.chmod(0o700)
old_lock = work / 'old-file-lock'
old_lock.write_text('#!/bin/sh\nexit 64\n')
old_lock.chmod(0o700)

def wait_for(predicate, message, timeout=2):
    deadline = time.monotonic() + timeout
    while not predicate():
        if time.monotonic() >= deadline:
            raise AssertionError(message)
        time.sleep(0.005)

def environment(directory, **extra):
    directory.mkdir(exist_ok=True)
    return {**os.environ, 'TMPDIR': str(directory), 'CONFIG_DIR': str(directory),
            'NAME': 'review.anchor', 'SENDER': 'mouse.entered',
            'BARISTA_SKETCHYBAR_BIN': str(stub), 'TEST_DIR': str(directory),
            'BARISTA_HOVER_TIMEOUT': '0', 'BARISTA_HOVER_ANIMATION_DURATION': '0',
            'BARISTA_FILE_LOCK_BIN': str(work / 'file_lock'), **extra}

def run(target, env):
    subprocess.run([str(target)], env=env, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2)

def style(directory):
    path = directory / 'final-style'
    return path.read_text().strip() if path.exists() else ''

lanes = [
    ('native', native, native, {}),
    ('shell-native-lock', shell, shell, {}),
    ('shell-perl', portable_shell, portable_shell, {'BARISTA_LUA_ONLY': '1'}),
    ('shell-old-lock', shell, shell, {'BARISTA_FILE_LOCK_BIN': str(old_lock)}),
    ('native-to-shell', native, shell, {}),
    ('shell-to-native', shell, native, {}),
    ('mixed-name', native, shell, {'NAME': 'review__  anchor'}),
]
for label, previous, current, overrides in lanes:
    directory = work / label
    env = environment(directory, **overrides)
    run(previous, {**env, 'BARISTA_HOVER_TIMEOUT': '0.02', 'BLOCK_RESTORE': '1'})
    wait_for(lambda: (directory / 'restore-started').exists(), label + ': restore did not start')
    process = subprocess.Popen([str(current)], env=env,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        time.sleep(0.04)
        assert process.poll() is None, label + ': newer hover bypassed the in-flight restore lock'
    finally:
        (directory / 'release-restore').touch()
        process.communicate(timeout=2)
    assert process.returncode == 0, (label, process.returncode)
    assert style(directory) == 'hover', label + ': stale restore overwrote newer hover'

    # Also cancel a timer which has not dispatched when the backend changes.
    run(previous, {**env, 'BARISTA_HOVER_TIMEOUT': '0.12'})
    run(current, env)
    time.sleep(0.18)
    assert style(directory) == 'hover', label + ': previous backend timer survived a newer enter'

    run(previous, env)
    run(previous, {**env, 'SENDER': 'mouse.exited.global', 'POPUP_CLOSE_DELAY': '0.12'})
    run(current, env)
    time.sleep(0.18)
    assert style(directory) == 'hover', label + ': previous backend popup-close timer survived a newer enter'

    # A stuck command must release the lock; it cannot block future events.
    started = time.monotonic()
    (directory / 'release-restore').unlink()
    run(current, {**env, 'SENDER': 'mouse.exited', 'BLOCK_RESTORE': '1', 'SPAWN_DESCENDANT': '1'})
    assert time.monotonic() - started < 1.2, label + ': hover dispatch exceeded its deadline'
    run(current, env)
    assert style(directory) == 'hover', label + ': lock survived failed dispatch'
    time.sleep(0.35)
    assert not (directory / 'descendant-style').exists(), label + ': timed-out descendant survived'

    key = env['NAME']
    if re.search(r'[^a-zA-Z0-9._-]', key):
        key = re.sub('_+', '_', re.sub(r'[^a-zA-Z0-9._-]', '_', key))
    lock_path = directory / 'sketchybar_hover_state' / (key + '.apply.lock')
    with lock_path.open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        started = time.monotonic()
        run(current, {**env, 'SENDER': 'mouse.exited'})
        assert 1.0 <= time.monotonic() - started < 1.8, label + ': lock wait was not bounded'
        assert style(directory) == 'hover', label + ': contended event dispatched without lock'
    run(current, {**env, 'SENDER': 'mouse.exited'})
    assert style(directory) == 'idle', label + ': lock was not released with its owner'

print('hover serialization: seven native/shell/fallback lanes passed')
PY

printf 'test_hover_serialization.sh: ok\n'
