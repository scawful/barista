#!/bin/bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'test_volume_popup_helper.sh: skipped (Darwin only)\n'
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/helpers/volume_popup_helper.m"
TMP_DIR="$(mktemp -d)"
HELPER="$TMP_DIR/volume_popup_helper"
CACHE_DIR="$TMP_DIR/cache"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

CC_BIN="${CC:-$(command -v clang 2>/dev/null || command -v cc 2>/dev/null || true)}"
if [[ -z "$CC_BIN" ]]; then
  printf 'test_volume_popup_helper.sh: skipped (Objective-C compiler unavailable)\n'
  exit 0
fi

"$CC_BIN" -fobjc-arc -Wall -Wextra -Werror \
  -framework Foundation \
  -framework CoreAudio \
  -framework AudioToolbox \
  "$SOURCE" \
  -o "$HELPER"

cat > "$TMP_DIR/test_response.m" <<EOF
#define main barista_volume_popup_helper_main
#include "$SOURCE"
#undef main

int main(void) {
  const char success[] = "";
  const char notice[] = "[?] informational response";
  const char error[] = "[!] semantic failure";
  const char missingTerminator[] = {'o', 'k'};
  const char embeddedTerminator[] = {'o', 'k', '\0', '[', '!', ']', '\0'};
  if (!response_is_success(success, sizeof(success))) return 1;
  if (!response_is_success(notice, sizeof(notice))) return 2;
  if (response_is_success(error, sizeof(error))) return 3;
  if (response_is_success(missingTerminator, sizeof(missingTerminator))) return 4;
  if (!response_is_success(embeddedTerminator, sizeof(embeddedTerminator))) return 5;
  if (response_is_success(NULL, 1)) return 6;
  if (response_is_success(success, kMaxPayloadBytes + 1)) return 7;
  return 0;
}
EOF
"$CC_BIN" -fobjc-arc -Wall -Wextra -Werror \
  -framework Foundation \
  -framework CoreAudio \
  -framework AudioToolbox \
  "$TMP_DIR/test_response.m" \
  -o "$TMP_DIR/test_response"
"$TMP_DIR/test_response"

mkdir -p "$CACHE_DIR"
cat > "$CACHE_DIR/media.tsv" <<'EOF'
player	Music
state	playing
track	Don't Stop; $(touch should-not-exist) "go" 👩‍💻 é
artist	Koji Kondo
toggle_label	Pause
toggle_icon	󰏤
current_output	Cached Output
track	Duplicate Must Lose
unknown	ignored
EOF
cat > "$CACHE_DIR/outputs.tsv" <<'EOF'
output	1	true	Studio Display
output	2	false	MacBook Pro "Speakers"
output	2	true	Duplicate Must Lose
output	0	false	Bad Zero
output	5	false	Bad Five
output	-1	false	Bad Negative
output	bogus	false	Bad Text
output	3	yes	Bad Boolean
output	4	false	Too	Many Fields
EOF

dump_payload() {
  local cache_dir="$1"
  local output_file="$2"
  shift 2
  env -i \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    HOME="$TMP_DIR/home" \
    BARISTA_RUNTIME_CONTEXT_DIR="$cache_dir" \
    BARISTA_VOLUME_VALUE="42" \
    BARISTA_VOLUME_MUTED="false" \
    BARISTA_VOLUME_OUTPUT_NAME="Studio Display" \
    BARISTA_SWITCH_AUDIO_SOURCE_BIN="/usr/bin/true" \
    BARISTA_ICON_VOLUME="VOL" \
    BARISTA_VOLUME_OK="0xff00aa00" \
    BARISTA_VOLUME_WARN="0xffaa9900" \
    BARISTA_VOLUME_LOW="0xffaa0000" \
    BARISTA_VOLUME_MUTE="0xff0000aa" \
    BARISTA_VOLUME_OUTPUT_IDLE="0xffcccccc" \
    BARISTA_MEDIA_LABEL_MAX="200" \
    "$@" \
    "$HELPER" popup_refresh --dump0 > "$output_file"
}

PAYLOAD="$TMP_DIR/payload.bin"
HOSTILE_OUTPUT=$'Studio "Display"\n--set injected\tlabel=hacked'
dump_payload "$CACHE_DIR" "$PAYLOAD" BARISTA_VOLUME_OUTPUT_NAME="$HOSTILE_OUTPUT"
dump_payload "$CACHE_DIR" "$TMP_DIR/payload-repeat.bin" BARISTA_VOLUME_OUTPUT_NAME="$HOSTILE_OUTPUT"
cmp -s "$PAYLOAD" "$TMP_DIR/payload-repeat.bin" || {
  echo "FAIL: deterministic fixtures should produce identical payloads" >&2
  exit 1
}

python3 - "$PAYLOAD" "$TMP_DIR/should-not-exist" <<'PY'
from pathlib import Path
import sys

payload = Path(sys.argv[1]).read_bytes()
assert len(payload) <= 16 * 1024, len(payload)
assert payload.endswith(b"\0\0"), payload[-8:]
raw = payload[:-2].split(b"\0")
assert b"" not in raw, raw
assert len(raw) <= 64, len(raw)
assert all(len(token) <= 1024 for token in raw)
tokens = [token.decode("utf-8") for token in raw]
assert tokens.count("--set") == 10, tokens

sets = {}
index = 0
while index < len(tokens):
    assert tokens[index] == "--set", tokens[index:]
    item = tokens[index + 1]
    index += 2
    props = []
    while index < len(tokens) and tokens[index] != "--set":
        props.append(tokens[index])
        index += 1
    sets[item] = props

assert sets["volume"] == [
    "icon=VOL", "label=42%", "icon.color=0xffaa9900", "label.color=0xffaa9900"
]
assert "label=Volume: 42%" in sets["volume.state"]
assert 'label=Output: Studio "Display" --set injected label=hacked' in sets["volume.output"]
assert "drawing=on" in sets["volume.output.1"]
assert "label=Studio Display · Current" in sets["volume.output.1"]
assert 'label=MacBook Pro "Speakers"' in sets["volume.output.2"]
assert sets["volume.output.3"] == ["drawing=off", "label="]
assert sets["volume.output.4"] == ["drawing=off", "label="]
media = sets["volume.media"]
label = next(prop for prop in media if prop.startswith("label="))
assert "Don't Stop; $(touch should-not-exist) \"go\" 👩‍💻 é — Koji Kondo" in label, label
assert "Duplicate Must Lose" not in label
assert "icon=󰎈" in media
assert sets["volume.transport.toggle"] == ["icon=󰏤", "label=Pause"]
assert sets["volume.mute"] == ["icon=󰕾", "label=Mute"]
assert not Path(sys.argv[2]).exists()
PY

# Zero volume without a mute flag keeps the shell path's intentional label distinction.
dump_payload "$CACHE_DIR" "$TMP_DIR/zero.bin" \
  BARISTA_VOLUME_VALUE=0 BARISTA_VOLUME_MUTED=false
python3 - "$TMP_DIR/zero.bin" <<'PY'
from pathlib import Path
import sys
tokens = [part.decode() for part in Path(sys.argv[1]).read_bytes()[:-2].split(b"\0")]
main = tokens[tokens.index("volume") + 1:tokens.index("--set", tokens.index("volume") + 1)]
state_at = tokens.index("volume.state")
state = tokens[state_at + 1:tokens.index("--set", state_at + 1)]
assert "label=Muted" in main, main
assert "label=Volume: 0%" in state, state
PY

# Truncation remains valid UTF-8 and does not split a ZWJ or combining sequence.
dump_payload "$CACHE_DIR" "$TMP_DIR/truncated.bin" BARISTA_MEDIA_LABEL_MAX=32
python3 - "$TMP_DIR/truncated.bin" <<'PY'
from pathlib import Path
import sys, unicodedata
tokens = [part.decode("utf-8") for part in Path(sys.argv[1]).read_bytes()[:-2].split(b"\0")]
at = tokens.index("volume.media")
label = next(token.removeprefix("label=") for token in tokens[at + 1:] if token.startswith("label="))
assert label.endswith("…"), label
assert len(label) <= 32, label
before = label[:-1]
assert not before.endswith("\u200d"), repr(label)
assert not (before and unicodedata.combining(before[-1])), repr(label)
PY

# Missing caches are optional and produce bounded defaults with hidden routes.
MISSING_CACHE="$TMP_DIR/missing-cache"
mkdir -p "$MISSING_CACHE"
dump_payload "$MISSING_CACHE" "$TMP_DIR/missing.bin"
python3 - "$TMP_DIR/missing.bin" <<'PY'
from pathlib import Path
import sys
tokens = [part.decode() for part in Path(sys.argv[1]).read_bytes()[:-2].split(b"\0")]
assert "label=Now Playing: Nothing" in tokens
for index in range(1, 5):
    at = tokens.index(f"volume.output.{index}")
    assert tokens[at + 1:at + 3] == ["drawing=off", "label="]
PY

# Stale output caches never expose dead actions when switching is unavailable.
dump_payload "$CACHE_DIR" "$TMP_DIR/no-switch.bin" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$TMP_DIR/missing-switch"
python3 - "$TMP_DIR/no-switch.bin" <<'PY'
from pathlib import Path
import sys
tokens = [part.decode() for part in Path(sys.argv[1]).read_bytes()[:-2].split(b"\0")]
for index in range(1, 5):
    at = tokens.index(f"volume.output.{index}")
    assert tokens[at + 1:at + 3] == ["drawing=off", "label="]
PY

assert_native_ignores_invalid_cache() {
  local cache_dir="$1"
  local label="$2"
  local payload="$TMP_DIR/ignored-invalid.bin"
  dump_payload "$cache_dir" "$payload"
  python3 - "$payload" "$label" <<'PY'
from pathlib import Path
import sys

payload = Path(sys.argv[1]).read_bytes()
assert payload.endswith(b"\0\0"), sys.argv[2]
tokens = [part.decode("utf-8") for part in payload[:-2].split(b"\0")]
assert tokens.count("--set") == 10, sys.argv[2]
assert "label=Now Playing: Nothing" in tokens, sys.argv[2]
for index in range(1, 5):
    at = tokens.index(f"volume.output.{index}")
    assert tokens[at + 1:at + 3] == ["drawing=off", "label="], sys.argv[2]
PY
}

INVALID_UTF8="$TMP_DIR/invalid-utf8"
mkdir -p "$INVALID_UTF8"
python3 - "$INVALID_UTF8/media.tsv" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"track\tbad\xffvalue\n")
PY
assert_native_ignores_invalid_cache "$INVALID_UTF8" "invalid UTF-8"

EMBEDDED_NUL="$TMP_DIR/embedded-nul"
mkdir -p "$EMBEDDED_NUL"
python3 - "$EMBEDDED_NUL/media.tsv" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"track\tbad\0value\n")
PY
assert_native_ignores_invalid_cache "$EMBEDDED_NUL" "embedded NUL"

OVERSIZED="$TMP_DIR/oversized"
mkdir -p "$OVERSIZED"
python3 - "$OVERSIZED/media.tsv" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"track\t" + b"x" * (64 * 1024 + 1))
PY
assert_native_ignores_invalid_cache "$OVERSIZED" "oversized cache"

LONG_LINE="$TMP_DIR/long-line"
mkdir -p "$LONG_LINE"
python3 - "$LONG_LINE/media.tsv" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"track\t" + b"x" * 4097 + b"\n")
PY
assert_native_ignores_invalid_cache "$LONG_LINE" "oversized cache line"

SYMLINK_CACHE="$TMP_DIR/symlink-cache"
mkdir -p "$SYMLINK_CACHE"
printf 'track\tlinked\n' > "$TMP_DIR/linked-media.tsv"
ln -s "$TMP_DIR/linked-media.tsv" "$SYMLINK_CACHE/media.tsv"
assert_native_ignores_invalid_cache "$SYMLINK_CACHE" "symlinked cache"

FIFO_CACHE="$TMP_DIR/fifo-cache"
mkdir -p "$FIFO_CACHE"
mkfifo "$FIFO_CACHE/media.tsv"
assert_native_ignores_invalid_cache "$FIFO_CACHE" "FIFO cache"

# Invalid output data is independently ignored while valid media remains available.
INVALID_OUTPUTS="$TMP_DIR/invalid-outputs"
mkdir -p "$INVALID_OUTPUTS"
printf 'track\tValid Track\nartist\tValid Artist\n' > "$INVALID_OUTPUTS/media.tsv"
python3 - "$INVALID_OUTPUTS/outputs.tsv" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_bytes(b"output\t1\ttrue\tbad\xffname\n")
PY
dump_payload "$INVALID_OUTPUTS" "$TMP_DIR/invalid-outputs.bin"
python3 - "$TMP_DIR/invalid-outputs.bin" <<'PY'
from pathlib import Path
import sys
tokens = [part.decode("utf-8") for part in Path(sys.argv[1]).read_bytes()[:-2].split(b"\0")]
assert "label=Now Playing: Valid Track — Valid Artist" in tokens
for index in range(1, 5):
    at = tokens.index(f"volume.output.{index}")
    assert tokens[at + 1:at + 3] == ["drawing=off", "label="]
PY

if env -i BARISTA_VOLUME_NATIVE_DISABLE=1 "$HELPER" popup_refresh --dump0 > /dev/null; then
  echo "FAIL: native disable gate should return nonzero for shell fallback" >&2
  exit 1
fi

FALLBACK_LOG="$TMP_DIR/fallback.log"
cat > "$TMP_DIR/fallback.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" > "${BARISTA_TEST_FALLBACK_LOG:?}"
EOF
chmod +x "$TMP_DIR/fallback.sh"
BARISTA_TEST_FALLBACK_LOG="$FALLBACK_LOG" \
  BARISTA_VOLUME_NATIVE_DISABLE=1 \
  "$HELPER" popup_refresh \
  || BARISTA_TEST_FALLBACK_LOG="$FALLBACK_LOG" "$TMP_DIR/fallback.sh" popup_refresh
grep -Fxq 'popup_refresh' "$FALLBACK_LOG" || {
  echo "FAIL: a native failure should execute the shell-side fallback command" >&2
  exit 1
}

if BAR_NAME="barista-volume-test-$$" \
  BARISTA_RUNTIME_CONTEXT_DIR="$MISSING_CACHE" \
  BARISTA_VOLUME_VALUE=42 \
  BARISTA_VOLUME_MUTED=false \
  BARISTA_VOLUME_OUTPUT_NAME="Test Output" \
  BARISTA_SWITCH_AUDIO_SOURCE_BIN="$TMP_DIR/missing-switch" \
  "$HELPER" popup_refresh > /dev/null 2>&1; then
  echo "FAIL: an unavailable SketchyBar Mach service should return nonzero" >&2
  exit 1
fi
if "$HELPER" invalid-action > /dev/null 2>&1; then
  echo "FAIL: unknown actions should be rejected" >&2
  exit 1
fi

printf 'test_volume_popup_helper.sh: ok\n'
