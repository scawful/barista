#!/bin/bash
set -euo pipefail

MODEL="${OLLAMA_MODEL:-llama2}"
PROMPT=$(osascript <<'APPLESCRIPT'
try
  set dlg to display dialog "Ask Ollama" default answer "" with title "Local LLM" buttons {"Cancel", "Ask"} default button "Ask"
  return text returned of dlg
on error number -128
  return ""
end try
APPLESCRIPT
)

if [ -z "$PROMPT" ]; then
  exit 0
fi

if ! command -v ollama >/dev/null 2>&1; then
  osascript -e 'display alert "Ollama not found" message "Install via brew install ollama" as warning'
  exit 1
fi

TMP=$(mktemp /tmp/ollama_response.XXXX)
if ! ollama run "$MODEL" "$PROMPT" > "$TMP" 2>&1; then
  echo "Failed to run ollama" > "$TMP"
fi

pbcopy < "$TMP" || true
osascript <<APPLESCRIPT
set tmpPath to "$TMP"
set summary to do shell script "python3 - <<'PY'\nimport pathlib, textwrap\npath = pathlib.Path('" & tmpPath & "')\ndata = path.read_text(encoding='utf-8', errors='replace').strip()\nif len(data) > 700:\n    data = data[:700] + '…'\nprint(data)\nPY"
set notice to "\n\nFull response saved at " & tmpPath & " and copied to the clipboard."
set ans to display dialog (summary & notice) buttons {"Open", "OK"} default button "OK" with title "Ollama"
if button returned of ans is "Open" then
  do shell script "open -a TextEdit " & quoted form of tmpPath
end if
APPLESCRIPT
