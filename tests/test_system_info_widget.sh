#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  printf 'test_system_info_widget.sh: skipped (Darwin only)\n'
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

clang -std=c99 -Wall -Wextra -Werror -O2 \
  "$ROOT_DIR/tests/test_system_info_widget.c" \
  -framework CoreFoundation -framework IOKit -framework SystemConfiguration \
  -o "$TMP_DIR/system_info_widget_test"
"$TMP_DIR/system_info_widget_test"

clang -std=c99 -Wall -Wextra -Werror -O2 \
  "$ROOT_DIR/helpers/system_info_widget.c" \
  -framework CoreFoundation -framework IOKit -framework SystemConfiguration \
  -o "$TMP_DIR/system_info_popup_helper"

if grep -Fq -- "-listallhardwareports" "$ROOT_DIR/helpers/system_info_widget.c"; then
  echo "FAIL: native source must not probe networksetup hardware ports" >&2
  exit 1
fi
if grep -aFq -- "-listallhardwareports" "$TMP_DIR/system_info_popup_helper"; then
  echo "FAIL: native binary must not contain the retired hardware-port probe" >&2
  exit 1
fi
if grep -Fq -- "/usr/bin/memory_pressure" "$ROOT_DIR/helpers/system_info_widget.c" \
  || grep -aFq -- "/usr/bin/memory_pressure" "$TMP_DIR/system_info_popup_helper"; then
  echo "FAIL: native helper must not contain the retired memory-pressure probe" >&2
  exit 1
fi
if grep -Fq -- 'pcpu=,comm=' "$ROOT_DIR/helpers/system_info_widget.c" \
  || grep -aFq -- 'pcpu=,comm=' "$TMP_DIR/system_info_popup_helper"; then
  echo "FAIL: native helper must not ask ps to format every executable path" >&2
  exit 1
fi

if "$TMP_DIR/system_info_popup_helper" invalid-action >/dev/null 2>&1; then
  echo "FAIL: unknown helper actions should be rejected" >&2
  exit 1
fi
if BARISTA_SYSTEM_INFO_NATIVE_DISABLE=1 \
  "$TMP_DIR/system_info_popup_helper" popup_refresh >/dev/null 2>&1; then
  echo "FAIL: the native disable gate should return nonzero for shell fallback" >&2
  exit 1
fi
if BARISTA_SYSTEM_INFO_ROWS=cpu,unknown \
  "$TMP_DIR/system_info_popup_helper" popup_refresh >/dev/null 2>&1; then
  echo "FAIL: an invalid popup row allowlist should be rejected" >&2
  exit 1
fi
BARISTA_SYSTEM_INFO_ROWS=none \
  "$TMP_DIR/system_info_popup_helper" popup_refresh >/dev/null

BARISTA_SYSTEM_INFO_ROWS=uptime \
  "$TMP_DIR/system_info_popup_helper" popup_refresh --dump0 > "$TMP_DIR/payload.bin"
python3 - "$TMP_DIR/payload.bin" <<'PY'
from pathlib import Path
import sys
payload = Path(sys.argv[1]).read_bytes()
assert payload.endswith(b"\0\0")
tokens = payload[:-2].split(b"\0")
assert tokens[:2] == [b"--set", b"system_info.uptime"]
assert any(token.startswith(b"label=Uptime: ") for token in tokens)
PY

BARISTA_SYSTEM_INFO_ROWS=net \
  "$TMP_DIR/system_info_popup_helper" popup_refresh --dump0 > "$TMP_DIR/network-payload.bin"
python3 - "$TMP_DIR/network-payload.bin" <<'PY'
from pathlib import Path
import sys
payload = Path(sys.argv[1]).read_bytes()
assert payload.endswith(b"\0\0")
tokens = payload[:-2].split(b"\0")
assert tokens[:2] == [b"--set", b"system_info.net"]
assert any(token.startswith((b"label=Network: ", b"label=Wi-Fi: ")) for token in tokens)
PY

BARISTA_SYSTEM_INFO_ROWS=procs \
  "$TMP_DIR/system_info_popup_helper" popup_refresh --dump0 > "$TMP_DIR/process-payload.bin"
python3 - "$TMP_DIR/process-payload.bin" <<'PY'
from pathlib import Path
import sys
payload = Path(sys.argv[1]).read_bytes()
assert payload.endswith(b"\0\0")
tokens = payload[:-2].split(b"\0")
assert tokens[:2] == [b"--set", b"system_info.procs"]
assert any(token.startswith(b"label=Top CPU: ") and token.endswith(b"%") for token in tokens)
PY

LC_ALL=fr_FR.UTF-8 BARISTA_SYSTEM_INFO_ROWS=procs \
  "$TMP_DIR/system_info_popup_helper" popup_refresh --dump0 > "$TMP_DIR/localized-process-payload.bin"
python3 - "$TMP_DIR/localized-process-payload.bin" <<'PY'
from pathlib import Path
import sys
tokens = Path(sys.argv[1]).read_bytes()[:-2].split(b"\0")
labels = [token for token in tokens if token.startswith(b"label=Top CPU: ")]
assert len(labels) == 1
assert labels[0] != b"label=Top CPU: --"
assert labels[0].endswith(b"%")
PY

if BAR_NAME="barista-system-info-missing-$$" BARISTA_SYSTEM_INFO_ROWS=uptime \
  "$TMP_DIR/system_info_popup_helper" popup_refresh >/dev/null 2>&1; then
  echo "FAIL: unavailable SketchyBar IPC should return nonzero for shell fallback" >&2
  exit 1
fi

printf 'test_system_info_widget.sh: ok\n'
