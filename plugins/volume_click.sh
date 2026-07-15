#!/bin/bash
set -euo pipefail

_d="${0%/*}"; [ -z "$_d" ] && _d="."; [ -r "${_d}/lib/common.sh" ] && . "${_d}/lib/common.sh"

NAME="${NAME:-volume}"
VOLUME_SCRIPT="${_d}/volume.sh"

sketchybar --set "$NAME" popup.drawing=toggle
"$VOLUME_SCRIPT" >/dev/null 2>&1 &
