#!/usr/bin/env bash
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:${PATH:-}"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CI_MODE=0

usage() {
  cat <<EOF
Usage: $0 [--ci]

Checks:
  - Shell syntax (bash -n)
  - shellcheck (if available, required with --ci)
  - shfmt formatting (if available, required with --ci)
  - smoke checks for setup/update scripts
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ci)
      CI_MODE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

cd "$REPO_ROOT"

if command -v rg >/dev/null 2>&1; then
  mapfile -t shell_files < <(rg --files -g 'scripts/**' -g 'plugins/**' -g 'bin/**' | while read -r f; do
    [ -f "$f" ] || continue
    head -n 1 "$f" | grep -Eq '^#!.*(ba|z|sh)' && echo "$f"
  done | sort)
else
  mapfile -t shell_files < <(find scripts plugins bin -type f | sort)
fi

if [ "${#shell_files[@]}" -eq 0 ]; then
  echo "No shell files found."
  exit 0
fi

echo "[check] bash -n syntax"
for f in "${shell_files[@]}"; do
  bash -n "$f"
done

lint_candidates=(
  scripts/setup_machine.sh
  scripts/barista-doctor.sh
  scripts/work_mac_sync.sh
  scripts/update_work_mac.sh
  scripts/check_scripts.sh
  scripts/install_missing_fonts_and_panel.sh
  scripts/configure_work_google_apps.sh
)

lint_files=()
for f in "${lint_candidates[@]}"; do
  [ -f "$f" ] && lint_files+=("$f")
done

if command -v shellcheck >/dev/null 2>&1; then
  echo "[check] shellcheck"
  shellcheck -x -e SC2016 "${lint_files[@]}"
else
  if [ "$CI_MODE" -eq 1 ]; then
    echo "shellcheck is required in CI mode." >&2
    exit 1
  fi
  echo "[warn] shellcheck not installed; skipping"
fi

if command -v shfmt >/dev/null 2>&1; then
  echo "[check] shfmt"
  shfmt -d "${lint_files[@]}"
else
  if [ "$CI_MODE" -eq 1 ]; then
    echo "shfmt is required in CI mode." >&2
    exit 1
  fi
  echo "[warn] shfmt not installed; skipping"
fi

echo "[check] smoke tests"
./scripts/setup_machine.sh --help >/dev/null
tmp_state="$(mktemp)"
printf '{}' > "$tmp_state"
./scripts/setup_machine.sh --state "$tmp_state" --skip-fonts --skip-panel --work-apps --replace --dry-run --yes --no-reload >/dev/null
rm -f "$tmp_state" >/dev/null 2>&1 || true
./scripts/barista-doctor.sh --help >/dev/null
./scripts/work_mac_sync.sh --help >/dev/null
./scripts/update_work_mac.sh --help >/dev/null
./bin/barista-update --help >/dev/null

echo "[ok] script checks passed"
