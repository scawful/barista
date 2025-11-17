#!/bin/bash
set -euo pipefail

DEFAULT_PATH="$HOME/Code/z3ed/bin/z3ed"
CMD="${Z3ED_BIN:-$DEFAULT_PATH}"
if command -v z3ed >/dev/null 2>&1; then
  CMD="$(command -v z3ed)"
fi

if [ ! -x "$CMD" ]; then
  osascript -e 'display alert "z3ed not found" message "Set Z3ED_BIN or install z3ed" as warning'
  exit 1
fi

osascript <<APPLESCRIPT
set cmdPath to "$CMD"
set cmdDir to do shell script "dirname " & quoted form of cmdPath
set launchCmd to "cd " & cmdDir & "; ./" & do shell script "basename " & quoted form of cmdPath

tell application "Terminal"
  activate
  do script launchCmd
end tell
APPLESCRIPT
