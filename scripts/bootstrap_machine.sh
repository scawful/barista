#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNTIME_DIR="${BARISTA_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/sketchybar}"
PROFILE="${BARISTA_PROFILE_VARIANT:-work}"
INSTALL_MODE="copy"
WORK_DOMAIN="${BARISTA_WORK_GOOGLE_DOMAIN:-}"
CODE_DIR="${BARISTA_CODE_DIR:-}"
BIN_DIRS=()
INSTALL_DEPENDENCIES=0
INSTALL_AGENT=0
REPLACE=0
RELOAD=0
DRY_RUN=0

usage() {
  cat <<EOF
Usage: $0 [options]

Install the current Barista checkout as a machine-local SketchyBar runtime.

Options:
  --runtime-dir <path>       Runtime directory (default: \$BARISTA_CONFIG_DIR or XDG config)
  --profile <name>           minimal, cozy, personal, work, or restricted-work (default: work)
  --domain <domain>          Optional Google Workspace domain for Work menu links
  --code-dir <path>         Optional machine-local source root saved in Barista state
  --bin-dir <path>          Extra executable directory for the login agent (repeatable)
  --copy                     Copy portable tracked files into the runtime (default)
  --link                     Symlink the runtime to this checkout
  --replace                  Back up and replace an existing runtime
  --install-dependencies     Install missing Homebrew packages and SbarLua
  --launch-agent             Render and load Barista's login LaunchAgent
  --reload                   Start or reload SketchyBar after setup
  --dry-run                  Print resolved actions without changing the machine
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --runtime-dir)
      RUNTIME_DIR="${2:?missing value for --runtime-dir}"
      shift 2
      ;;
    --profile|--profile-variant)
      PROFILE="${2:?missing value for --profile}"
      shift 2
      ;;
    --domain)
      WORK_DOMAIN="${2:?missing value for --domain}"
      shift 2
      ;;
    --code-dir)
      CODE_DIR="${2:?missing value for --code-dir}"
      shift 2
      ;;
    --bin-dir)
      BIN_DIRS+=("${2:?missing value for --bin-dir}")
      shift 2
      ;;
    --copy)
      INSTALL_MODE="copy"
      shift
      ;;
    --link)
      INSTALL_MODE="link"
      shift
      ;;
    --replace)
      REPLACE=1
      shift
      ;;
    --install-dependencies)
      INSTALL_DEPENDENCIES=1
      shift
      ;;
    --launch-agent)
      INSTALL_AGENT=1
      shift
      ;;
    --reload)
      RELOAD=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$PROFILE" in
  minimal|cozy|personal|work|restricted-work) ;;
  *)
    echo "Unsupported profile: $PROFILE" >&2
    exit 1
    ;;
esac
case "$RUNTIME_DIR" in
  ~/*) RUNTIME_DIR="$HOME/${RUNTIME_DIR#~/}" ;;
esac
if [[ "$RUNTIME_DIR" != /* ]]; then
  RUNTIME_DIR="$(pwd)/$RUNTIME_DIR"
fi
if [ -n "$CODE_DIR" ]; then
  case "$CODE_DIR" in
    ~/*) CODE_DIR="$HOME/${CODE_DIR#~/}" ;;
  esac
  if [[ "$CODE_DIR" != /* ]]; then
    CODE_DIR="$(pwd)/$CODE_DIR"
  fi
fi

note() {
  printf '[barista-bootstrap] %s\n' "$*"
}

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

install_dependencies() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "Dependency installation is supported only on macOS." >&2
    exit 1
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required for --install-dependencies: https://brew.sh" >&2
    exit 1
  fi
  local packages=(felixkratz/formulae/sketchybar lua jq)
  if [ "$PROFILE" = "personal" ] || [ "$PROFILE" = "work" ]; then
    packages+=(koekeishiya/formulae/yabai koekeishiya/formulae/skhd)
  fi
  for package in "${packages[@]}"; do
    if ! brew list "$package" >/dev/null 2>&1; then
      run brew install "$package"
    fi
  done
  if ! find "$(brew --prefix)/share" "$HOME/.local/share" -path '*/sketchybar_lua/sketchybar.so' -print -quit 2>/dev/null | grep -q .; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note "Would install SbarLua from its official repository"
    else
      local build_dir
      build_dir="$(mktemp -d)"
      git clone --depth 1 https://github.com/FelixKratz/SbarLua.git "$build_dir/SbarLua"
      make -C "$build_dir/SbarLua" install
      rm -rf "$build_dir"
    fi
  fi
}

if [ "$INSTALL_DEPENDENCIES" -eq 1 ]; then
  install_dependencies
fi

note "source=$REPO_ROOT"
note "runtime=$RUNTIME_DIR"
note "profile=$PROFILE mode=$INSTALL_MODE"
if [ -n "$CODE_DIR" ]; then
  note "code_dir=$CODE_DIR"
fi

if [ -e "$RUNTIME_DIR" ] || [ -L "$RUNTIME_DIR" ]; then
  same_link=0
  if [ -L "$RUNTIME_DIR" ] && [ "$(cd "$(dirname "$RUNTIME_DIR")" && cd "$(readlink "$RUNTIME_DIR")" 2>/dev/null && pwd -P || true)" = "$REPO_ROOT" ]; then
    same_link=1
  fi
  if [ "$same_link" -eq 0 ]; then
    if [ "$REPLACE" -ne 1 ]; then
      echo "Runtime already exists: $RUNTIME_DIR (use --replace to back it up)" >&2
      exit 1
    fi
    backup="${RUNTIME_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    run mv "$RUNTIME_DIR" "$backup"
    note "backup=$backup"
  fi
fi

if [ ! -e "$RUNTIME_DIR" ] && [ ! -L "$RUNTIME_DIR" ]; then
  run mkdir -p "$(dirname "$RUNTIME_DIR")"
  if [ "$INSTALL_MODE" = "link" ]; then
    run ln -s "$REPO_ROOT" "$RUNTIME_DIR"
  elif [ "$DRY_RUN" -eq 1 ]; then
    note "Would copy portable repository files into $RUNTIME_DIR"
  else
    mkdir -p "$RUNTIME_DIR"
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/install.sh"
    copy_local_config "$REPO_ROOT" "$RUNTIME_DIR"
  fi
fi

if [ "$DRY_RUN" -eq 0 ]; then
  machine_args=(
    apply
    --variant "$PROFILE"
    --state "$RUNTIME_DIR/state.json"
    --machine-file "$RUNTIME_DIR/data/machine.local.json"
    --report
    --no-reload
  )
  if [ -n "$WORK_DOMAIN" ]; then
    machine_args+=(--domain "$WORK_DOMAIN" --replace)
  fi
  if [ -n "$CODE_DIR" ]; then
    machine_args+=(--code-dir "$CODE_DIR")
  fi
  python3 "$RUNTIME_DIR/scripts/machine_profile.py" "${machine_args[@]}"
else
  note "Would apply machine profile $PROFILE without reloading services"
fi

if [ "$INSTALL_AGENT" -eq 1 ]; then
  agent_args=(--config-dir "$RUNTIME_DIR")
  if [ -n "$CODE_DIR" ]; then
    agent_args+=(--code-dir "$CODE_DIR")
  fi
  for bin_dir in "${BIN_DIRS[@]}"; do
    agent_args+=(--bin-dir "$bin_dir")
  done
  if [ "$DRY_RUN" -eq 1 ]; then
    agent_args+=(--dry-run)
  fi
  "$REPO_ROOT/bin/install-launch-agent" "${agent_args[@]}"
fi

if [ "$RELOAD" -eq 1 ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    note "Would start or reload SketchyBar"
  elif command -v sketchybar >/dev/null 2>&1 && pgrep -x sketchybar >/dev/null 2>&1; then
    BARISTA_CONFIG_DIR="$RUNTIME_DIR" "$RUNTIME_DIR/plugins/reload_sketchybar.sh"
  elif command -v brew >/dev/null 2>&1; then
    brew services start sketchybar
  else
    echo "SketchyBar is not running and Homebrew is unavailable; start it manually." >&2
  fi
fi

if [ "$DRY_RUN" -eq 0 ] && [ -x "$RUNTIME_DIR/scripts/barista-doctor.sh" ]; then
  BARISTA_CONFIG_DIR="$RUNTIME_DIR" "$RUNTIME_DIR/scripts/barista-doctor.sh" --report || true
fi

note "setup complete"
