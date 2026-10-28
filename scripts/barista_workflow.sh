#!/usr/bin/env bash
set -euo pipefail

PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
STATE_FILE="${BARISTA_STATE_FILE:-$CONFIG_DIR/state.json}"
YABAI_BIN="${BARISTA_YABAI_BIN:-${YABAI_BIN:-$(command -v yabai 2>/dev/null || true)}}"
JQ_BIN="${BARISTA_JQ_BIN:-${JQ_BIN:-$(command -v jq 2>/dev/null || true)}}"
OPEN_BIN="${BARISTA_OPEN_BIN:-/usr/bin/open}"
GHOSTTY_APP="${BARISTA_GHOSTTY_APP:-/Applications/Ghostty.app}"
MARKS_FILE="${BARISTA_MARKS_FILE:-/tmp/barista_window_marks_${UID}.json}"
SCRATCH_PREV_FOCUS_FILE="${BARISTA_SCRATCH_PREV_FOCUS_FILE:-/tmp/barista_scratch_prev_${UID}}"

expand_tilde() {
  local raw="${1:-}"
  case "$raw" in
    "~") printf '%s' "$HOME" ;;
    "~/"*) printf '%s/%s' "$HOME" "${raw#\~/}" ;;
    *) printf '%s' "$raw" ;;
  esac
}

state_get_str() {
  local jq_expr="$1"
  local fallback="$2"
  if [[ -n "$JQ_BIN" && -r "$STATE_FILE" ]]; then
    local val
    val="$("$JQ_BIN" -r "($jq_expr) // empty" "$STATE_FILE" 2>/dev/null || true)"
    if [[ -n "$val" && "$val" != "null" ]]; then
      printf '%s' "$val"
      return 0
    fi
  fi
  printf '%s' "$fallback"
}

json_field() {
  printf '%s\n' "$1" | "$JQ_BIN" -r "$2" 2>/dev/null || true
}

query_windows_json() {
  if [[ -z "$YABAI_BIN" ]]; then
    printf '[]\n'
    return 0
  fi
  "$YABAI_BIN" -m query --windows 2>/dev/null || printf '[]\n'
}

query_focused_window_json() {
  if [[ -z "$YABAI_BIN" ]]; then
    printf '{}\n'
    return 0
  fi
  "$YABAI_BIN" -m query --windows --window 2>/dev/null || printf '{}\n'
}

# Terminals and Emacs own every window from one process, so the process tree
# alone cannot say which shell belongs to the focused window. With several
# candidate directories, only accept one the window title names.
resolve_pid_cwd() {
  local root_pid="${1:-}"
  local title="${2:-}"
  [[ "$root_pid" =~ ^[0-9]+$ ]] || return 1
  command -v lsof >/dev/null 2>&1 || return 1

  local children grandchildren="" cpid pids
  children="$(pgrep -P "$root_pid" 2>/dev/null || true)"
  for cpid in $children; do
    grandchildren+="$(pgrep -P "$cpid" 2>/dev/null || true)"$'\n'
  done
  pids="$(printf '%s\n' "$grandchildren" | grep -E '^[0-9]+$' || true)"
  [[ -n "$pids" ]] || pids="$children"
  [[ -n "$pids" ]] || pids="$root_pid"

  local cwds
  # shellcheck disable=SC2086
  cwds="$(lsof -a -p "$(printf '%s\n' $pids | paste -sd, -)" -d cwd -Fn 2>/dev/null \
    | sed -n 's/^n//p' | grep -vx '/' | sort -u || true)"
  [[ -n "$cwds" ]] || return 1
  if [[ "$(printf '%s\n' "$cwds" | wc -l | tr -d ' ')" == "1" ]]; then
    printf '%s' "$cwds"
    return 0
  fi

  [[ -n "$title" ]] || return 1
  local cwd short best=""
  while IFS= read -r cwd; do
    short="$cwd"
    if [[ "$cwd" == "$HOME"* ]]; then
      short="~${cwd#"$HOME"}"
    fi
    if [[ "$title" == *"$cwd"* || "$title" == *"$short"* ]]; then
      if (( ${#cwd} > ${#best} )); then
        best="$cwd"
      fi
    fi
  done <<< "$cwds"
  [[ -n "$best" ]] || return 1
  printf '%s' "$best"
}

resolve_context_json() {
  local default_root
  default_root="$(expand_tilde "${BARISTA_DEFAULT_ROOT:-$(state_get_str '.workflow.files.default_root' "$HOME/src")}")"
  [[ -d "$default_root" ]] || default_root="$HOME"

  local win_json app_name win_id win_pid win_title cwd="" repo_root=""
  win_json="$(query_focused_window_json)"
  app_name="$(json_field "$win_json" '.app // empty')"
  win_id="$(json_field "$win_json" '.id // empty')"
  win_pid="$(json_field "$win_json" '.pid // empty')"
  win_title="$(json_field "$win_json" '.title // empty')"

  if [[ -n "${BARISTA_CONTEXT_CWD:-}" && -d "${BARISTA_CONTEXT_CWD}" ]]; then
    cwd="$BARISTA_CONTEXT_CWD"
  elif [[ -n "$win_pid" ]]; then
    cwd="$(resolve_pid_cwd "$win_pid" "$win_title" || true)"
  fi

  if [[ -z "$cwd" && -n "$win_title" ]]; then
    local maybe_path
    maybe_path="$(expand_tilde "$win_title")"
    if [[ -d "$maybe_path" ]]; then
      cwd="$maybe_path"
    elif [[ -f "$maybe_path" ]]; then
      cwd="$(dirname "$maybe_path")"
    fi
  fi

  if [[ -z "$cwd" || ! -d "$cwd" ]]; then
    cwd="$default_root"
  fi

  if command -v git >/dev/null 2>&1; then
    repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  fi

  "$JQ_BIN" -cn \
    --arg cwd "$cwd" \
    --arg repo_root "${repo_root:-$cwd}" \
    --arg default_root "$default_root" \
    --arg app "${app_name:-}" \
    --arg window_id "${win_id:-}" \
    --arg title "${win_title:-}" \
    '{
      cwd: $cwd,
      repo_root: $repo_root,
      default_root: $default_root,
      front_app: $app,
      window_id: (if $window_id != "" then ($window_id | tonumber) else null end),
      window_title: $title
    }'
}

cmd_context() {
  local ctx
  ctx="$(resolve_context_json)"
  if [[ "${1:-}" == "--json" ]]; then
    printf '%s\n' "$ctx"
  else
    printf '%s\n' "$ctx" | "$JQ_BIN" -r '"cwd: \(.cwd)\nrepo_root: \(.repo_root)\nfront_app: \(.front_app)\nwindow_id: \(.window_id // "none")"'
  fi
}

scratchpad_grid_spec() {
  local width_pct="${BARISTA_SCRATCHPAD_WIDTH_PCT:-$(state_get_str '.workflow.scratchpad.width_pct' '75')}"
  local height_pct="${BARISTA_SCRATCHPAD_HEIGHT_PCT:-$(state_get_str '.workflow.scratchpad.height_pct' '75')}"
  case "$width_pct" in ''|*[!0-9]*) width_pct=75 ;; esac
  case "$height_pct" in ''|*[!0-9]*) height_pct=75 ;; esac

  local cols=12 rows=12
  local w=$(( (width_pct * cols + 50) / 100 ))
  local h=$(( (height_pct * rows + 50) / 100 ))
  (( w < 4 )) && w=4
  (( w > 12 )) && w=12
  (( h < 4 )) && h=4
  (( h > 12 )) && h=12
  local x=$(( (cols - w) / 2 ))
  local y=$(( (rows - h) / 2 ))
  printf '%d:%d:%d:%d:%d:%d' "$rows" "$cols" "$x" "$y" "$w" "$h"
}

find_window_by_tag() {
  local tag="$1"
  query_windows_json | "$JQ_BIN" -c --arg tag "$tag" '
    [ .[] | select((.title // "") | ascii_downcase | contains($tag | ascii_downcase)) ]
    | sort_by(if ."has-focus" == true then 0 else 1 end, .id)
    | .[0] // empty
  ' 2>/dev/null || true
}

float_and_focus_window() {
  local win_json="$1"
  local wid
  wid="$(json_field "$win_json" '.id')"
  if [[ "$(json_field "$win_json" '."is-minimized" // false')" == "true" ]]; then
    "$YABAI_BIN" -m window "$wid" --deminimize 2>/dev/null || true
  fi
  "$YABAI_BIN" -m window "$wid" --space mouse 2>/dev/null || true
  if [[ "$(json_field "$win_json" '."is-floating" // false')" != "true" ]]; then
    "$YABAI_BIN" -m window "$wid" --toggle float 2>/dev/null || true
  fi
  "$YABAI_BIN" -m window "$wid" --sub-layer normal 2>/dev/null || true
  "$YABAI_BIN" -m window "$wid" --grid "$(scratchpad_grid_spec)" 2>/dev/null || true
  "$YABAI_BIN" -m window --focus "$wid" 2>/dev/null || true
}

float_spawned_window() {
  local tag="$1"
  [[ -n "$YABAI_BIN" ]] || return 0
  local _ win_json
  for _ in $(seq 1 20); do
    win_json="$(find_window_by_tag "$tag")"
    if [[ -n "$win_json" ]]; then
      float_and_focus_window "$win_json"
      return 0
    fi
    sleep 0.1
  done
}

spawn_terminal_with_title() {
  local title="$1"
  local workdir="$2"
  local cmd="${3:-}"
  if [[ -n "${BARISTA_TERMINAL_LAUNCHER:-}" ]]; then
    "$BARISTA_TERMINAL_LAUNCHER" "$title" "$workdir" "$cmd"
    return 0
  fi
  if [[ -d "$GHOSTTY_APP" ]]; then
    if [[ -n "$cmd" ]]; then
      "$OPEN_BIN" -na "$GHOSTTY_APP" --args "--title=$title" "--working-directory=$workdir" -e /bin/zsh -lc "$cmd"
    else
      "$OPEN_BIN" -na "$GHOSTTY_APP" --args "--title=$title" "--working-directory=$workdir"
    fi
    return 0
  fi
  local shell_cmd
  shell_cmd="printf '\\033]0;%s\\007' $(printf '%q' "$title"); cd $(printf '%q' "$workdir")"
  if [[ -n "$cmd" ]]; then
    shell_cmd+="; $cmd"
  fi
  shell_cmd="${shell_cmd//\\/\\\\}"
  shell_cmd="${shell_cmd//\"/\\\"}"
  /usr/bin/osascript -e "tell application \"Terminal\" to do script \"$shell_cmd\"" >/dev/null 2>&1 || true
}

resolve_emacsclient_bin() {
  local configured
  configured="$(state_get_str '.workflow.emacs.client_bin' 'emacsclient')"
  command -v "$configured" 2>/dev/null || command -v emacsclient 2>/dev/null || true
}

emacs_server_bin() {
  local ec_bin
  ec_bin="$(resolve_emacsclient_bin)"
  if [[ -n "$ec_bin" ]] && "$ec_bin" -e 't' >/dev/null 2>&1; then
    printf '%s' "$ec_bin"
  fi
}

open_in_emacs() {
  local target="$1"
  local elisp="${2:-}"
  local frame_title="${3:-}"
  local ec_bin
  ec_bin="$(emacs_server_bin)"

  if [[ -n "$ec_bin" ]]; then
    local args=(-n -c)
    if [[ -n "$frame_title" ]]; then
      args+=(-F "((name . \"$frame_title\") (title . \"$frame_title\"))")
    fi
    if [[ -n "$elisp" ]]; then
      "$ec_bin" "${args[@]}" -e "$elisp" >/dev/null 2>&1
    else
      "$ec_bin" "${args[@]}" "$target" >/dev/null 2>&1
    fi
    return 0
  fi

  local emacs_app
  emacs_app="$(state_get_str '.workflow.emacs.app_name' 'Emacs')"
  if [[ -n "$target" ]]; then
    "$OPEN_BIN" -a "$emacs_app" "$target"
  else
    "$OPEN_BIN" -a "$emacs_app"
  fi
}

elisp_string() {
  local raw="${1//\\/\\\\}"
  printf '"%s"' "${raw//\"/\\\"}"
}

spawn_scratchpad_window() {
  local name="$1"
  local tag="barista-scratch-${name}"
  local cwd
  cwd="$(resolve_context_json | "$JQ_BIN" -r '.cwd')"
  [[ -d "$cwd" ]] || cwd="$HOME"

  case "$name" in
    emacs)
      if [[ -n "$(emacs_server_bin)" ]]; then
        open_in_emacs "$cwd" "" "$tag"
      else
        "$OPEN_BIN" -a "$(state_get_str '.workflow.emacs.app_name' 'Emacs')" "$cwd" >/dev/null 2>&1 || true
      fi
      ;;
    files)
      local files_cmd
      files_cmd="$(state_get_str '.workflow.scratchpad.files_cmd' 'yazi')"
      if ! command -v "${files_cmd%% *}" >/dev/null 2>&1; then
        files_cmd="ls -la; exec /bin/zsh -l"
      fi
      spawn_terminal_with_title "$tag" "$cwd" "$files_cmd"
      ;;
    *)
      spawn_terminal_with_title "$tag" "$cwd" "$(state_get_str '.workflow.scratchpad.terminal_cmd' '')"
      ;;
  esac
  float_spawned_window "$tag"
}

remember_focus_unless() {
  local skip_id="$1"
  local cur_id
  cur_id="$(json_field "$(query_focused_window_json)" '.id // empty')"
  if [[ -n "$cur_id" && "$cur_id" != "$skip_id" ]]; then
    printf '%s\n' "$cur_id" > "$SCRATCH_PREV_FOCUS_FILE"
  fi
}

cmd_scratchpad() {
  local action="${1:-toggle}"
  shift || true

  if [[ "$action" == "list" ]]; then
    query_windows_json | "$JQ_BIN" '
      [ .[]
        | select((.title // "") | ascii_downcase | contains("barista-scratch-"))
        | {
            id: .id,
            name: ((.title // "") | capture("(?i)barista-scratch-(?<n>[a-z0-9_-]+)").n // "unknown"),
            app: .app,
            space: .space,
            minimized: (."is-minimized" // false),
            focused: (."has-focus" // false)
          }
      ]
    '
    return 0
  fi

  local name="${1:-term}"
  case "$name" in
    terminal|shell) name="term" ;;
  esac

  local win_json wid=""
  win_json="$(find_window_by_tag "barista-scratch-${name}")"
  [[ -n "$win_json" ]] && wid="$(json_field "$win_json" '.id')"

  case "$action" in
    toggle|show)
      if [[ -z "$wid" ]]; then
        remember_focus_unless ""
        spawn_scratchpad_window "$name"
        return 0
      fi
      if [[ "$action" == "toggle" \
        && "$(json_field "$win_json" '."has-focus" // false')" == "true" \
        && "$(json_field "$win_json" '."is-minimized" // false')" != "true" ]]; then
        "$YABAI_BIN" -m window "$wid" --minimize 2>/dev/null || true
        local prev_wid=""
        [[ -r "$SCRATCH_PREV_FOCUS_FILE" ]] && prev_wid="$(cat "$SCRATCH_PREV_FOCUS_FILE")"
        if [[ -n "$prev_wid" && "$prev_wid" != "$wid" ]]; then
          "$YABAI_BIN" -m window --focus "$prev_wid" 2>/dev/null || true
        fi
        return 0
      fi
      remember_focus_unless "$wid"
      float_and_focus_window "$win_json"
      ;;
    hide)
      if [[ -n "$wid" ]]; then
        "$YABAI_BIN" -m window "$wid" --minimize 2>/dev/null || true
      fi
      ;;
    *)
      echo "Usage: barista scratchpad <toggle|show|hide|list> [term|emacs|files|<name>]" >&2
      exit 1
      ;;
  esac
}

cmd_emacs() {
  local subcmd="${1:-here}"
  shift || true

  local ctx cwd repo_root
  ctx="$(resolve_context_json)"
  cwd="$(json_field "$ctx" '.cwd')"
  repo_root="$(json_field "$ctx" '.repo_root')"

  case "$subcmd" in
    here|open)
      open_in_emacs "$(expand_tilde "${1:-$repo_root}")"
      ;;
    dired)
      local dir
      dir="$(expand_tilde "${1:-$cwd}")"
      open_in_emacs "$dir" "(dired $(elisp_string "$dir"))"
      ;;
    magit|git)
      local repo
      repo="$(elisp_string "$(expand_tilde "${1:-$repo_root}")")"
      open_in_emacs "" "(if (fboundp 'magit-status) (magit-status $repo) (vc-dir $repo))"
      ;;
    capture)
      local key="${1:-$(state_get_str '.workflow.emacs.capture_key' '')}"
      if [[ -n "$key" ]]; then
        open_in_emacs "" "(org-capture nil $(elisp_string "$key"))"
      else
        open_in_emacs "" "(org-capture)"
      fi
      ;;
    *)
      echo "Usage: barista emacs <here|dired|magit|capture> [path|key]" >&2
      exit 1
      ;;
  esac
}

cmd_files() {
  local subcmd="${1:-browse}"
  shift || true

  local cwd
  cwd="$(resolve_context_json | "$JQ_BIN" -r '.cwd')"

  case "$subcmd" in
    browse)
      local target_dir
      target_dir="$(expand_tilde "${1:-$cwd}")"
      [[ -d "$target_dir" ]] || target_dir="$HOME"
      local picker
      picker="$(state_get_str '.workflow.files.picker' 'auto')"
      if [[ "$picker" == "auto" ]]; then
        if command -v yazi >/dev/null 2>&1; then
          picker="yazi"
        elif command -v fzf >/dev/null 2>&1; then
          picker="fzf"
        else
          picker="dired"
        fi
      fi
      case "$picker" in
        yazi)
          spawn_terminal_with_title "barista-scratch-files" "$target_dir" "yazi $(printf '%q' "$target_dir")"
          float_spawned_window "barista-scratch-files"
          ;;
        fzf)
          local fzf_cmd
          fzf_cmd="sel=\$(find . -maxdepth 4 -not -path '*/.*' | fzf --prompt='File > ') && $(printf '%q' "$SELF") emacs here \"\$PWD/\$sel\""
          spawn_terminal_with_title "barista-scratch-files" "$target_dir" "$fzf_cmd"
          float_spawned_window "barista-scratch-files"
          ;;
        *)
          cmd_emacs dired "$target_dir"
          ;;
      esac
      ;;
    windows)
      local action_mode="${1:-jump}"
      if [[ -t 0 && -t 1 ]] && command -v fzf >/dev/null 2>&1; then
        local chosen wid
        chosen="$(query_windows_json | "$JQ_BIN" -r '
          .[]
          | select((."is-minimized" // false) == false)
          | select(((.title // "") | contains("barista-scratch-switcher")) | not)
          | "\(.id)\t[S\(.space // 0)] \(.app // "?") — \(.title // "")"
        ' | fzf --with-nth=2.. --delimiter=$'\t' --prompt="Window ($action_mode) > " || true)"
        wid="${chosen%%$'\t'*}"
        if [[ "$wid" =~ ^[0-9]+$ ]]; then
          if [[ "$action_mode" == "summon" ]]; then
            "$YABAI_BIN" -m window "$wid" --space mouse 2>/dev/null || true
          fi
          "$YABAI_BIN" -m window --focus "$wid" 2>/dev/null || true
        fi
      else
        spawn_terminal_with_title "barista-scratch-switcher" "$cwd" "$(printf '%q' "$SELF") files windows $(printf '%q' "$action_mode")"
        float_spawned_window "barista-scratch-switcher"
      fi
      ;;
    *)
      echo "Usage: barista files <browse [dir]|windows [jump|summon]>" >&2
      exit 1
      ;;
  esac
}

cmd_mark() {
  local action="${1:-list}"
  shift || true
  [[ -f "$MARKS_FILE" ]] || printf '{}\n' > "$MARKS_FILE"

  case "$action" in
    set)
      local mark_key="${1:-}"
      local target_wid="${2:-}"
      if [[ -z "$mark_key" ]]; then
        echo "Usage: barista mark set <key> [window_id]" >&2
        exit 1
      fi
      local win_json
      if [[ -n "$target_wid" ]]; then
        win_json="$(query_windows_json | "$JQ_BIN" -c --argjson id "$target_wid" '.[] | select(.id == $id)' 2>/dev/null || true)"
      else
        win_json="$(query_focused_window_json)"
      fi
      local wid
      wid="$(json_field "$win_json" '.id // empty')"
      if [[ -z "$wid" ]]; then
        echo "No target window found to mark '$mark_key'" >&2
        exit 1
      fi
      local tmp="${MARKS_FILE}.tmp.$$"
      printf '%s\n' "$win_json" | "$JQ_BIN" --arg key "$mark_key" --slurpfile marks "$MARKS_FILE" \
        '$marks[0] + {($key): {id: .id, app: (.app // ""), title: (.title // ""), space: (.space // 0)}}' \
        > "$tmp" && mv "$tmp" "$MARKS_FILE"
      printf 'Marked [%s] -> window %s (%s)\n' "$mark_key" "$wid" "$(json_field "$win_json" '.app // ""')"
      ;;
    focus|goto|summon)
      local mark_key="${1:-}"
      if [[ -z "$mark_key" ]]; then
        echo "Usage: barista mark $action <key>" >&2
        exit 1
      fi
      local entry
      entry="$("$JQ_BIN" -c --arg key "$mark_key" '.[$key] // empty' "$MARKS_FILE" 2>/dev/null || true)"
      if [[ -z "$entry" ]]; then
        echo "Mark '$mark_key' is not set." >&2
        exit 1
      fi
      local windows_json target_json
      windows_json="$(query_windows_json)"
      target_json="$(printf '%s\n' "$windows_json" | "$JQ_BIN" -c --argjson mark "$entry" '
        ([ .[] | select(.id == $mark.id) ][0])
        // ([ .[] | select(.app == $mark.app and .title == $mark.title) ][0])
        // ([ .[] | select(.app == $mark.app) ][0])
        // empty
      ' 2>/dev/null || true)"
      if [[ -z "$target_json" ]]; then
        echo "Window for mark '$mark_key' ($(json_field "$entry" '.app // ""')) is no longer open." >&2
        exit 1
      fi
      local target_id
      target_id="$(json_field "$target_json" '.id')"
      if [[ "$action" == "summon" ]]; then
        if [[ "$(json_field "$target_json" '."is-minimized" // false')" == "true" ]]; then
          "$YABAI_BIN" -m window "$target_id" --deminimize 2>/dev/null || true
        fi
        "$YABAI_BIN" -m window "$target_id" --space mouse 2>/dev/null || true
      fi
      "$YABAI_BIN" -m window --focus "$target_id" 2>/dev/null || true
      ;;
    list)
      local enriched
      enriched="$("$JQ_BIN" -cn --slurpfile marks "$MARKS_FILE" --argjson wins "$(query_windows_json)" '
        ($marks[0] // {})
        | to_entries
        | map(
            .key as $k
            | .value as $v
            | ($wins | map(select(.id == $v.id))[0]) as $live
            | {
                mark: $k,
                id: $v.id,
                app: ($live.app // $v.app),
                title: ($live.title // $v.title),
                space: ($live.space // $v.space),
                alive: ($live != null)
              }
          )
      ')"
      if [[ "${1:-}" == "--json" ]]; then
        printf '%s\n' "$enriched"
      elif [[ "$(printf '%s' "$enriched" | "$JQ_BIN" 'length')" == "0" ]]; then
        echo "No window marks set."
      else
        printf '%s\n' "$enriched" | "$JQ_BIN" -r '.[] | "[\(.mark)] id=\(.id) app=\(.app) space=\(.space) alive=\(.alive) title=\(.title)"'
      fi
      ;;
    clear)
      local mark_key="${1:-}"
      if [[ -z "$mark_key" || "$mark_key" == "--all" ]]; then
        printf '{}\n' > "$MARKS_FILE"
      else
        local tmp="${MARKS_FILE}.tmp.$$"
        "$JQ_BIN" --arg key "$mark_key" 'del(.[$key])' "$MARKS_FILE" > "$tmp" && mv "$tmp" "$MARKS_FILE"
      fi
      ;;
    *)
      echo "Usage: barista mark <set|focus|summon|list|clear> [key]" >&2
      exit 1
      ;;
  esac
}

command="${1:-}"
shift || true
case "$command" in
  context) cmd_context "$@" ;;
  scratchpad) cmd_scratchpad "$@" ;;
  emacs) cmd_emacs "$@" ;;
  files) cmd_files "$@" ;;
  mark) cmd_mark "$@" ;;
  *)
    cat >&2 <<EOF
Usage: $(basename "$0") <command> [args...]

Commands:
  context [--json]                              Focused window's directory and git repo root
  scratchpad <toggle|show|hide|list> [name]     Floating scratchpads: term, emacs, files, or any name
  emacs <here|dired|magit|capture> [path|key]   emacsclient in the focused project
  files <browse [dir]|windows [jump|summon]>    File browser and fuzzy window switcher
  mark <set|focus|summon|list|clear> [key]      Window marks across spaces
EOF
    exit 1
    ;;
esac
