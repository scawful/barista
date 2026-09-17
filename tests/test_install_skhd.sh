#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# shellcheck source=../scripts/install.sh
source "$ROOT_DIR/scripts/install.sh"

target="$TMP_DIR/skhdrc"
template="$ROOT_DIR/extras/skhd/skhdrc"
generated="$TMP_DIR/barista_shortcuts.conf"

printf '%s\n' '# personal entrypoint' 'alt - space ; leader' >"$target"
cp "$target" "$TMP_DIR/original"
prepare_skhd_entrypoint "$target" "$template"
cmp -s "$target" "$TMP_DIR/original" || {
  echo "FAIL: existing skhd entrypoint was overwritten" >&2
  exit 1
}

append_skhd_load "$target" "$generated"
append_skhd_load "$target" "$generated"
[ "$(grep -Fxc ".load \"$generated\"" "$target")" -eq 1 ] || {
  echo "FAIL: generated shortcut include should be appended exactly once" >&2
  exit 1
}
grep -Fq 'alt - space ; leader' "$target"

fresh="$TMP_DIR/fresh-skhdrc"
prepare_skhd_entrypoint "$fresh" "$template"
cmp -s "$fresh" "$template" || {
  echo "FAIL: missing skhd entrypoint should receive the portable template" >&2
  exit 1
}

if grep -Eq '^(:: (leader|agent)|agent <|leader <|alt - space ;)' "$template"; then
  echo "FAIL: portable template contains a personal modal map" >&2
  exit 1
fi

printf 'test_install_skhd.sh: ok\n'
