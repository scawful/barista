#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
REGISTRY_DIR="${TMP_ROOT}/registry"
LOG_FILE="${TMP_ROOT}/sketchybar.log"
NATIVE_LOG="${TMP_ROOT}/native.log"
SHELL_LOG="${TMP_ROOT}/shell.log"
FAKE_SKETCHYBAR="${TMP_ROOT}/sketchybar"
NATIVE_MANAGER="${TMP_ROOT}/popup_manager"

cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

mkdir -p "${REGISTRY_DIR}"
cat > "${FAKE_SKETCHYBAR}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'CALL\0'
  printf '%s\0' "$@"
  printf 'END\0'
} >> "${BARISTA_TEST_SKETCHYBAR_LOG:?}"
EOF
chmod +x "${FAKE_SKETCHYBAR}"

"${CC:-cc}" -std=c99 -Wall -Wextra -Werror \
  "${ROOT_DIR}/helpers/popup_manager.c" -o "${NATIVE_MANAGER}"
test "$("${NATIVE_MANAGER}" protocol)" = "barista-popup-switch-v1"
test "$("${ROOT_DIR}/plugins/popup_manager.sh" protocol)" = "barista-popup-switch-v1"

write_registry() {
  cat > "${REGISTRY_DIR}/sketchybar_popup_list" <<'EOF'
front_app
control_center
lmstudio
EOF
  cat > "${REGISTRY_DIR}/sketchybar_submenu_list" <<'EOF'
front_app.more
cc.more
music.studio.kits
menu.parent
menu.child
menu.grandchild
EOF
  cat > "${REGISTRY_DIR}/sketchybar_popup_topology" <<'EOF'
version	1
root	front_app
root	control_center
root	lmstudio
child	front_app.more
child	cc.more
child	music.studio.kits
child	menu.parent
child	menu.child
child	menu.grandchild
ancestor	menu.child	menu.parent
ancestor	menu.grandchild	menu.child
ancestor	menu.grandchild	menu.parent
EOF
}

run_manager() {
  local manager="$1"
  shift
  : > "${LOG_FILE}"
  TMPDIR="${REGISTRY_DIR}" \
    BARISTA_SKETCHYBAR_BIN="${FAKE_SKETCHYBAR}" \
    BARISTA_TEST_SKETCHYBAR_LOG="${LOG_FILE}" \
    BARISTA_POPUP_TOPOLOGY_TOKEN="${BARISTA_POPUP_TOPOLOGY_TOKEN:-}" \
    "${manager}" "$@"
}

assert_tokens() {
  local mode="$1"
  python3 - "${LOG_FILE}" "${mode}" <<'PY'
import sys
from pathlib import Path

path, mode = sys.argv[1:]
tokens = Path(path).read_bytes().split(b"\0")
assert tokens[-1] == b"", tokens
tokens = [token.decode("utf-8") for token in tokens[:-1]]
assert tokens[0] == "CALL" and tokens[-1] == "END", tokens
actual = tokens[1:-1]

roots = ["front_app", "control_center", "lmstudio"]
children = [
    "front_app.more", "cc.more", "music.studio.kits",
    "menu.parent", "menu.child", "menu.grandchild",
]

def close_root(name):
    return ["--set", name, "popup.drawing=off"]

def close_child(name):
    return [
        "--set", name, "popup.drawing=off",
        "background.drawing=off", "background.color=0x00000000",
    ]

if mode == "root":
    expected = []
    for name in roots:
        if name != "control_center":
            expected += close_root(name)
    for name in children:
        expected += close_child(name)
    expected += ["--set", "control_center", "popup.drawing=toggle"]
elif mode == "submenu":
    expected = []
    for name in children:
        if name != "cc.more":
            expected += close_child(name)
    expected += ["--set", "cc.more", "popup.drawing=toggle"]
elif mode == "nested":
    expected = []
    for name in children:
        if name not in {"menu.parent", "menu.child", "menu.grandchild"}:
            expected += close_child(name)
    expected += ["--set", "menu.grandchild", "popup.drawing=toggle"]
elif mode == "dismiss":
    expected = []
    for name in roots:
        expected += close_root(name)
    for name in children:
        expected += close_child(name)
elif mode == "target-only":
    expected = ["--set", "external.popup", "popup.drawing=toggle"]
elif mode == "deep":
    expected = ["--set", "chain.32", "popup.drawing=toggle"]
elif mode == "duplicate-relation":
    expected = (
        close_child("duplicate.other")
        + ["--set", "duplicate.child", "popup.drawing=toggle"]
    )
elif mode == "stale-registry":
    expected = (
        close_root("stale.root")
        + close_root("control_center")
        + close_child("stale.child")
        + ["--set", "external.popup", "popup.drawing=toggle"]
    )
else:
    raise AssertionError(f"unknown mode: {mode}")

assert actual == expected, f"{mode}\nexpected={expected!r}\nactual={actual!r}"
PY
}

write_registry
run_manager "${NATIVE_MANAGER}" switch control_center
assert_tokens root
cp "${LOG_FILE}" "${NATIVE_LOG}"

run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch control_center
assert_tokens root
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

run_manager "${NATIVE_MANAGER}" submenu cc.more
assert_tokens submenu
cp "${LOG_FILE}" "${NATIVE_LOG}"

run_manager "${ROOT_DIR}/plugins/popup_manager.sh" submenu cc.more
assert_tokens submenu
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

touch \
  "${REGISTRY_DIR}/sketchybar_submenu_active" \
  "${REGISTRY_DIR}/sketchybar_parent_popup_lock"
run_manager "${NATIVE_MANAGER}" submenu menu.grandchild
assert_tokens nested
test ! -e "${REGISTRY_DIR}/sketchybar_submenu_active"
test ! -e "${REGISTRY_DIR}/sketchybar_parent_popup_lock"
cp "${LOG_FILE}" "${NATIVE_LOG}"

touch \
  "${REGISTRY_DIR}/sketchybar_submenu_active" \
  "${REGISTRY_DIR}/sketchybar_parent_popup_lock"
run_manager "${ROOT_DIR}/plugins/popup_manager.sh" submenu menu.grandchild
assert_tokens nested
test ! -e "${REGISTRY_DIR}/sketchybar_submenu_active"
test ! -e "${REGISTRY_DIR}/sketchybar_parent_popup_lock"
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

{
  printf 'version\t1\n'
  for ((child = 1; child <= 32; child++)); do
    printf 'child\tchain.%d\n' "$child"
  done
  for ((child = 2; child <= 32; child++)); do
    for ((ancestor = 1; ancestor < child; ancestor++)); do
      printf 'ancestor\tchain.%d\tchain.%d\n' "$child" "$ancestor"
    done
  done
} > "${REGISTRY_DIR}/sketchybar_popup_topology"
run_manager "${NATIVE_MANAGER}" submenu chain.32
assert_tokens deep
cp "${LOG_FILE}" "${NATIVE_LOG}"
run_manager "${ROOT_DIR}/plugins/popup_manager.sh" submenu chain.32
assert_tokens deep
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

{
  printf 'version\t1\n'
  printf 'root\tduplicate.root\n'
  printf 'child\tduplicate.parent\n'
  printf 'child\tduplicate.child\n'
  printf 'child\tduplicate.other\n'
  for ((relation = 1; relation <= 513; relation++)); do
    printf 'ancestor\tduplicate.child\tduplicate.parent\n'
  done
} > "${REGISTRY_DIR}/sketchybar_popup_topology"
run_manager "${NATIVE_MANAGER}" submenu duplicate.child
assert_tokens duplicate-relation
cp "${LOG_FILE}" "${NATIVE_LOG}"
run_manager "${ROOT_DIR}/plugins/popup_manager.sh" submenu duplicate.child
assert_tokens duplicate-relation
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

: > "${LOG_FILE}"
TMPDIR="${REGISTRY_DIR}" \
  SENDER=space_change \
  BARISTA_SKETCHYBAR_BIN="${FAKE_SKETCHYBAR}" \
  BARISTA_TEST_SKETCHYBAR_LOG="${LOG_FILE}" \
  "${NATIVE_MANAGER}"
assert_tokens dismiss
cp "${LOG_FILE}" "${NATIVE_LOG}"

: > "${LOG_FILE}"
PATH="/usr/bin:/bin" \
  TMPDIR="${REGISTRY_DIR}" \
  SENDER=space_change \
  BARISTA_SKETCHYBAR_BIN="${FAKE_SKETCHYBAR}" \
  BARISTA_TEST_SKETCHYBAR_LOG="${LOG_FILE}" \
  "${ROOT_DIR}/plugins/popup_manager.sh"
assert_tokens dismiss
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

printf 'version\t1\n' > "${REGISTRY_DIR}/sketchybar_popup_topology"
run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${NATIVE_LOG}"

run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

rm -f \
  "${REGISTRY_DIR}/sketchybar_popup_topology"
run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${NATIVE_LOG}"

run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

printf 'version\t2\nroot\tstale.root\n' > "${REGISTRY_DIR}/sketchybar_popup_topology"
run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${NATIVE_LOG}"
run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

printf 'version\t1\nunknown\tbad.row\n' > "${REGISTRY_DIR}/sketchybar_popup_topology"
run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${NATIVE_LOG}"
run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

{
  printf 'version\t1\n'
  for ((index = 1; index <= 129; index++)); do
    printf 'root\toverflow.%d\n' "$index"
  done
} > "${REGISTRY_DIR}/sketchybar_popup_topology"
run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${NATIVE_LOG}"
run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

python3 - "${REGISTRY_DIR}/sketchybar_popup_topology" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(
    b"version\t1\n"
    + b"root\t"
    + ("é" * 64).encode("utf-8")
    + b"\nroot\tstale.root\n"
)
PY
run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${NATIVE_LOG}"
run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

python3 - "${REGISTRY_DIR}/sketchybar_popup_topology" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(
    b"version\t1\nroot\tstale.root\x00hidden\n"
)
PY
run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${NATIVE_LOG}"
run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

python3 - "${REGISTRY_DIR}/sketchybar_popup_topology" <<'PY'
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(
    b"version\t1\nroot\tstale.root\rhidden\n"
)
PY
run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${NATIVE_LOG}"
run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

cat > "${REGISTRY_DIR}/sketchybar_popup_topology" <<'EOF'
version	1
root	stale.root
root	control_center
child	stale.child
EOF
run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens stale-registry
cp "${LOG_FILE}" "${NATIVE_LOG}"

run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens stale-registry
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

cat > "${REGISTRY_DIR}/sketchybar_popup_topology" <<'EOF'
version	1
generation	old-token
root	stale.root
root	control_center
child	stale.child
EOF
BARISTA_POPUP_TOPOLOGY_TOKEN=old-token \
  run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens stale-registry
cp "${LOG_FILE}" "${NATIVE_LOG}"
BARISTA_POPUP_TOPOLOGY_TOKEN=old-token \
  run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens stale-registry
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

BARISTA_POPUP_TOPOLOGY_TOKEN=new-token \
  run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${NATIVE_LOG}"
BARISTA_POPUP_TOPOLOGY_TOKEN=new-token \
  run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

# With no requested generation, fixed-path CLI callers retain legacy behavior
# and may consume a versioned manifest that includes a generation record.
run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens stale-registry
cp "${LOG_FILE}" "${NATIVE_LOG}"
run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens stale-registry
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

cat > "${REGISTRY_DIR}/sketchybar_popup_topology" <<'EOF'
version	1
root	stale.root
root	control_center
child	stale.child
EOF
BARISTA_POPUP_TOPOLOGY_TOKEN=new-token \
  run_manager "${NATIVE_MANAGER}" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${NATIVE_LOG}"
BARISTA_POPUP_TOPOLOGY_TOKEN=new-token \
  run_manager "${ROOT_DIR}/plugins/popup_manager.sh" switch external.popup
assert_tokens target-only
cp "${LOG_FILE}" "${SHELL_LOG}"
cmp "${NATIVE_LOG}" "${SHELL_LOG}"

: > "${LOG_FILE}"
TMPDIR="${REGISTRY_DIR}" \
  SENDER=front_app_switched \
  BARISTA_SKETCHYBAR_BIN="${FAKE_SKETCHYBAR}" \
  BARISTA_TEST_SKETCHYBAR_LOG="${LOG_FILE}" \
  "${NATIVE_MANAGER}"
test ! -s "${LOG_FILE}"

printf '%s\n' "popup_manager tests passed"
