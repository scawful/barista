#!/usr/bin/env bash

set -euo pipefail

PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/.lmstudio/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

DEFAULT_MODEL="scawfulbot-qwen3-8b-v1-mlx"
DEFAULT_IDENTIFIER="scawfulbot-qwen3-8b-v1-mlx"
LONG_IDENTIFIER="scawfulbot-qwen3-8b-v1-mlx-long"
GGUF_MODEL="scawful@q4_k_m"
GGUF_IDENTIFIER="scawful@q4_k_m"
ECHO_MODEL="scawful-echo-mlx"
ECHO_IDENTIFIER="scawful-echo-mlx"

DEFAULT_CONTEXT="${LMSTUDIO_CONTEXT_DEFAULT:-12288}"
LONG_CONTEXT="${LMSTUDIO_CONTEXT_LONG:-32768}"
ECHO_CONTEXT="${LMSTUDIO_CONTEXT_ECHO:-8192}"
PARALLEL="${LMSTUDIO_PARALLEL:-1}"
TTL="${LMSTUDIO_TTL:-3600}"

usage() {
  cat <<'EOF'
usage: lmstudio_control.sh [mlx|long|gguf|echo|off|status|open]

  mlx     load scawfulbot MLX default
  long    load scawfulbot MLX long-context
  gguf    load scawfulbot GGUF fallback
  echo    load scawful echo MLX
  off     unload all models
  status  show loaded models
  open    open LM Studio
EOF
}

require_lms() {
  if ! command -v lms >/dev/null 2>&1; then
    echo "lms not found on PATH" >&2
    exit 1
  fi
}

wait_for_lms() {
  local attempts=20
  local sleep_s=0.5
  local i
  for ((i = 0; i < attempts; i++)); do
    if lms ps --json >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_s"
  done
  echo "LM Studio local service did not come up in time" >&2
  return 1
}

ensure_lmstudio() {
  open -ga "LM Studio" >/dev/null 2>&1 || true
  wait_for_lms
}

load_model() {
  local model="$1"
  local identifier="$2"
  local context="$3"
  local gpu="${4:-}"

  require_lms
  ensure_lmstudio
  lms unload --all >/dev/null 2>&1 || true

  local cmd=(lms load "$model" -c "$context" --parallel "$PARALLEL" --ttl "$TTL" --identifier "$identifier" -y)
  if [[ -n "$gpu" ]]; then
    cmd+=(--gpu "$gpu")
  fi
  "${cmd[@]}"
}

main() {
  local action="${1:-mlx}"

  case "$action" in
    mlx|default)
      load_model "$DEFAULT_MODEL" "$DEFAULT_IDENTIFIER" "$DEFAULT_CONTEXT"
      ;;
    long|mlx-long)
      load_model "$DEFAULT_MODEL" "$LONG_IDENTIFIER" "$LONG_CONTEXT"
      ;;
    gguf)
      load_model "$GGUF_MODEL" "$GGUF_IDENTIFIER" "$DEFAULT_CONTEXT" "max"
      ;;
    echo)
      load_model "$ECHO_MODEL" "$ECHO_IDENTIFIER" "$ECHO_CONTEXT"
      ;;
    off|unload)
      require_lms
      ensure_lmstudio
      lms unload --all
      ;;
    status|ps)
      require_lms
      ensure_lmstudio
      lms ps
      ;;
    open)
      open -a "LM Studio"
      ;;
    help|--help|-h)
      usage
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
