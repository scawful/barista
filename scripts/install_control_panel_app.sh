#!/usr/bin/env bash
# Install the native Barista settings panel to the per-user Applications folder.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_EXEC="Barista"
LEGACY_APP_EXEC="BaristaControlPanel"
APP_NAME="Barista"
SOURCE_APP="${BARISTA_CONTROL_PANEL_SOURCE_APP:-$ROOT/build/bin/${APP_EXEC}.app}"
DEST_APP="${BARISTA_CONTROL_PANEL_APP:-$HOME/Applications/${APP_NAME}.app}"

usage() {
  cat <<EOF
Usage: $0 [--source /path/to/Barista.app] [--dest /path/to/Barista.app]

Copies the built Barista.app into ~/Applications by default.
Does not launch the app or reload SketchyBar.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      shift
      SOURCE_APP="${1:-}"
      ;;
    --dest)
      shift
      DEST_APP="${1:-}"
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift || true
done

if [[ -z "$SOURCE_APP" || ( ! -x "$SOURCE_APP/Contents/MacOS/$APP_EXEC" && ! -x "$SOURCE_APP/Contents/MacOS/$LEGACY_APP_EXEC" ) ]]; then
  echo "Built control panel app not found: $SOURCE_APP" >&2
  echo "Run: cmake --build build --target barista_control_panel_app" >&2
  exit 1
fi

if [[ ! -x "$SOURCE_APP/Contents/MacOS/$APP_EXEC" && -x "$SOURCE_APP/Contents/MacOS/$LEGACY_APP_EXEC" ]]; then
  APP_EXEC="$LEGACY_APP_EXEC"
fi

mkdir -p "$(dirname "$DEST_APP")"
/usr/bin/ditto "$SOURCE_APP" "$DEST_APP"
printf 'APPL????' > "$DEST_APP/Contents/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$DEST_APP" >/dev/null
fi

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$DEST_APP" >/dev/null 2>&1 || true
fi

touch "$DEST_APP" "$DEST_APP/Contents" "$DEST_APP/Contents/MacOS"

if [[ ! -x "$DEST_APP/Contents/MacOS/$APP_EXEC" ]]; then
  echo "Install failed: $DEST_APP/Contents/MacOS/$APP_EXEC is not executable" >&2
  exit 1
fi

echo "$DEST_APP"
