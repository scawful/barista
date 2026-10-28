#!/bin/bash
# Barista Performance Statistics Script
# Tracks reload frequency, update frequencies, and performance metrics

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATS_FILE="${CONFIG_DIR}/.barista_stats.json"
LOG_FILE="${CONFIG_DIR}/.barista_stats.log"
STATS_MAX_BYTES="${BARISTA_STATS_MAX_BYTES:-524288}"
STATS_KEEP_LINES="${BARISTA_STATS_KEEP_LINES:-2000}"

# Initialize stats file if it doesn't exist
init_stats() {
    if [ ! -f "$STATS_FILE" ]; then
        cat > "$STATS_FILE" <<'EOF'
{
  "reloads": {
    "count": 0,
    "last_reload": null,
    "reloads_per_hour": 0
  },
  "updates": {
    "total": 0,
    "by_widget": {}
  },
  "performance": {
    "avg_reload_time": 0,
    "last_reload_time": 0
  },
  "start_time": null
}
EOF
    fi
}

# Get current timestamp
get_timestamp() {
    date +%s
}

ensure_log_format() {
    [ -f "$LOG_FILE" ] || return 0
    [ -s "$LOG_FILE" ] || return 0

    local first_char
    first_char="$(head -c 1 "$LOG_FILE" 2>/dev/null || true)"
    if [ "$first_char" != "{" ]; then
        mv "$LOG_FILE" "${LOG_FILE}.legacy" 2>/dev/null || true
    fi
}

rotate_log_if_needed() {
    [ -f "$LOG_FILE" ] || return 0
    local max_bytes="${STATS_MAX_BYTES:-524288}"
    local keep_lines="${STATS_KEEP_LINES:-2000}"
    case "$max_bytes" in ''|*[!0-9]*) max_bytes=524288 ;; esac
    case "$keep_lines" in ''|*[!0-9]*) keep_lines=2000 ;; esac
    [ "$max_bytes" -gt 0 ] || return 0
    [ "$keep_lines" -gt 0 ] || keep_lines=2000

    local file_bytes
    file_bytes="$(wc -c < "$LOG_FILE" 2>/dev/null | tr -d ' ' || printf '0')"
    if [ "${file_bytes:-0}" -gt "$max_bytes" ] 2>/dev/null; then
        local tmp_file="${LOG_FILE}.tmp.$$"
        if tail -n "$keep_lines" "$LOG_FILE" > "$tmp_file" 2>/dev/null; then
            mv "$tmp_file" "$LOG_FILE" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null || true
        else
            rm -f "$tmp_file" 2>/dev/null || true
        fi
    fi
}

prune_log() {
    local keep_lines="${1:-${STATS_KEEP_LINES:-2000}}"
    case "$keep_lines" in ''|*[!0-9]*) keep_lines=2000 ;; esac
    [ "$keep_lines" -gt 0 ] || keep_lines=2000
    rm -f "${LOG_FILE}".*.bak 2>/dev/null || true
    [ -f "$LOG_FILE" ] || return 0
    local tmp_file="${LOG_FILE}.tmp.$$"
    if tail -n "$keep_lines" "$LOG_FILE" > "$tmp_file" 2>/dev/null; then
        mv "$tmp_file" "$LOG_FILE" 2>/dev/null || rm -f "$tmp_file" 2>/dev/null || true
    else
        rm -f "$tmp_file" 2>/dev/null || true
    fi
}

# Log an event as JSONL
log_event() {
    local event_type="$1"
    local payload_json="${2:-}"
    local timestamp
    timestamp=$(get_timestamp)
    if [ -z "$payload_json" ]; then
        payload_json='{}'
    fi

    ensure_log_format
    jq -cn \
       --arg event "$event_type" \
       --argjson timestamp "$timestamp" \
       --argjson payload "$payload_json" \
       '$payload + {timestamp: $timestamp, event: $event}' >> "$LOG_FILE"
    rotate_log_if_needed
}

event_payload_json() {
    local duration_ms="${1:-0}"
    local details="${2:-}"
    local meta_json="${BARISTA_EVENT_META_JSON:-}"

    if [ -n "$meta_json" ]; then
        jq -cn \
          --argjson duration_ms "$duration_ms" \
          --arg details "$details" \
          --argjson meta "$meta_json" \
          '$meta + {duration_ms: $duration_ms, details: $details}'
        return
    fi

    jq -cn --argjson duration_ms "$duration_ms" --arg details "$details" '{duration_ms: $duration_ms, details: $details}'
}

track_reload_time() {
    local duration_ms="${1:-0}"
    init_stats
    local avg_reload_time=$(jq -r '.performance.avg_reload_time // 0' "$STATS_FILE" 2>/dev/null || echo "0")
    local reload_count=$(jq -r '.reloads.count // 0' "$STATS_FILE" 2>/dev/null || echo "0")
    local samples=$reload_count
    if [ "$samples" -le 0 ]; then
        samples=1
    fi
    local new_avg
    new_avg=$(awk -v old="$avg_reload_time" -v n="$samples" -v cur="$duration_ms" 'BEGIN { printf "%.2f", (((old * (n - 1)) + cur) / n) }')
    jq --argjson avg "$new_avg" \
       --argjson last "$duration_ms" \
       '.performance.avg_reload_time = $avg |
        .performance.last_reload_time = $last' \
       "$STATS_FILE" > "${STATS_FILE}.tmp" && mv "${STATS_FILE}.tmp" "$STATS_FILE"
    log_event "reload_time" "$(jq -cn --argjson duration_ms "$duration_ms" '{duration_ms: $duration_ms}')"
}

track_event() {
    local event_name="$1"
    local duration_ms="${2:-0}"
    local details="${3:-}"
    log_event "$event_name" "$(event_payload_json "$duration_ms" "$details")"
}

track_events_batch() {
    local timestamp
    local event_name duration_ms details

    ensure_log_format
    timestamp=$(get_timestamp)
    while IFS=$'\t' read -r event_name duration_ms details || [ -n "${event_name:-}" ]; do
        [ -n "${event_name:-}" ] || continue
        duration_ms="${duration_ms:-0}"
        details="${details:-}"
        printf '{"duration_ms":%s,"details":"%s","timestamp":%s,"event":"%s"}\n' \
            "$duration_ms" \
            "$details" \
            "$timestamp" \
            "$event_name" >> "$LOG_FILE"
    done
    rotate_log_if_needed
}

# Update reload stats
track_reload() {
    init_stats
    local timestamp=$(get_timestamp)
    local start_time=$(jq -r '.start_time // empty' "$STATS_FILE" 2>/dev/null || echo "")
    
    # Calculate reloads per hour
    local reload_count=$(jq -r '.reloads.count // 0' "$STATS_FILE" 2>/dev/null || echo "0")
    reload_count=$((reload_count + 1))
    
    local reloads_per_hour=0
    if [ -n "$start_time" ] && [ "$start_time" != "null" ]; then
        local elapsed=$((timestamp - start_time))
        if [ $elapsed -gt 0 ]; then
            reloads_per_hour=$((reload_count * 3600 / elapsed))
        fi
    fi
    
    # Update stats
    jq --arg ts "$timestamp" \
       --argjson count "$reload_count" \
       --argjson rph "$reloads_per_hour" \
       '.reloads.count = $count |
        .reloads.last_reload = $ts |
        .reloads.reloads_per_hour = $rph |
        .start_time = (if .start_time == null then $ts else .start_time end)' \
       "$STATS_FILE" > "${STATS_FILE}.tmp" && mv "${STATS_FILE}.tmp" "$STATS_FILE"
    
    log_event "reload" "$(jq -cn --argjson count "$reload_count" --argjson reloads_per_hour "$reloads_per_hour" '{count: $count, reloads_per_hour: $reloads_per_hour}')"
}

# Track widget update
track_update() {
    local widget_name="$1"
    if [ -z "$widget_name" ]; then
        return
    fi
    
    init_stats
    local timestamp=$(get_timestamp)
    
    # Update widget update count
    jq --arg widget "$widget_name" \
       --arg ts "$timestamp" \
       '.updates.total = (.updates.total // 0) + 1 |
        .updates.by_widget[$widget] = ((.updates.by_widget[$widget] // 0) + 1)' \
       "$STATS_FILE" > "${STATS_FILE}.tmp" && mv "${STATS_FILE}.tmp" "$STATS_FILE"
    
    log_event "update" "$(jq -cn --arg widget "$widget_name" '{widget: $widget}')"
}

show_stats_json() {
    local stats_json='{}'
    if [ -f "$STATS_FILE" ]; then
        stats_json="$(cat "$STATS_FILE" 2>/dev/null || printf '{}')"
    fi
    if [ ! -f "$LOG_FILE" ]; then
        jq -cn --argjson stats "$stats_json" '$stats + {events: {}}'
        return 0
    fi
    jq -sr --argjson stats "$stats_json" '
      . as $rows
      | def summary($vals):
          if ($vals | length) > 0 then
            {
              count: ($vals | length),
              avg_ms: (((($vals | add) / ($vals | length)) * 100 | round) / 100),
              last_ms: $vals[-1]
            }
          else null end;
        def event_vals($ev):
          [ $rows[] | select(.event == $ev and (.duration_ms? != null)) | .duration_ms ];
        ($stats + {
          log_entries: ($rows | length),
          events: (
            reduce (
              "reload_prep_time",
              "reload_daemon_stop_time",
              "config_build_time",
              "config_build_wall_time",
              "config_menu_render_time",
              "config_left_layout_time",
              "config_left_layout_build_time",
              "config_left_layout_apply_time",
              "config_left_layout_front_app_time",
              "config_left_layout_triforce_time",
              "config_left_layout_spaces_time",
              "config_left_layout_control_center_time",
              "config_left_layout_group_time",
              "config_right_layout_time",
              "config_right_layout_build_time",
              "config_right_layout_apply_time",
              "config_registry_time",
              "reload_stats_flush_time",
              "space_topology_refresh",
              "space_refresh_overhead",
              "space_visual_refresh"
            ) as $ev ({};
              (event_vals($ev)) as $v
              | if ($v | length) > 0 then . + {($ev): summary($v)} else . end
            )
          ),
          topology_strategies: (
            [ $rows[] | select(.event == "space_topology_refresh" and (.duration_ms != null) and (.strategy != null)) ]
            | group_by(.strategy)
            | reduce .[] as $g ({};
                ($g[0].strategy) as $st
                | . + {($st): summary([ $g[].duration_ms ])}
              )
          )
        })
    ' "$LOG_FILE"
}

# Display statistics (single jq pass over STATS_FILE + single jq pass over LOG_FILE)
show_stats() {
    if [ "${1:-}" = "--json" ]; then
        show_stats_json
        return 0
    fi
    if [ ! -f "$STATS_FILE" ]; then
        echo "No statistics available yet."
        echo "Statistics are tracked automatically when sketchybar reloads."
        return
    fi
    
    echo "Barista Performance Statistics"
    echo "============================"
    echo ""
    
    local reload_count="0" last_reload="never" reloads_per_hour="0" total_updates="0" avg_reload_time="0" last_reload_time="0"
    local header_tsv=""
    header_tsv="$(jq -r '[
      (.reloads.count // 0 | tostring),
      (.reloads.last_reload // "never" | tostring),
      (.reloads.reloads_per_hour // 0 | tostring),
      (.updates.total // 0 | tostring),
      (.performance.avg_reload_time // 0 | tostring),
      (.performance.last_reload_time // 0 | tostring)
    ] | @tsv' "$STATS_FILE" 2>/dev/null || true)"
    if [ -n "$header_tsv" ]; then
        IFS=$'\t' read -r reload_count last_reload reloads_per_hour total_updates avg_reload_time last_reload_time <<< "$header_tsv"
    fi
    
    echo "Reload Statistics:"
    echo "  Total reloads: $reload_count"
    if [ "$last_reload" != "never" ] && [ "$last_reload" != "null" ]; then
        local last_reload_date=$(date -r "$last_reload" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")
        echo "  Last reload: $last_reload_date"
    else
        echo "  Last reload: never"
    fi
    echo "  Reloads per hour: $reloads_per_hour"
    echo ""
    
    echo "Update Statistics:"
    echo "  Total updates: $total_updates"
    echo "  Updates by widget:"
    jq -r '.updates.by_widget // {} | to_entries | .[] | "    \(.key): \(.value)"' "$STATS_FILE" 2>/dev/null || echo "    (none)"
    echo ""
    
    echo "Performance Metrics:"
    echo "  Average reload time: ${avg_reload_time}ms"
    echo "  Last reload time: ${last_reload_time}ms"
    if [ -f "$LOG_FILE" ]; then
        jq -sr '
          . as $rows
          | def fmt_ms($label; $vals):
              if ($vals | length) > 0 then
                "\($label): \($vals | length) (avg \(((($vals | add) / ($vals | length)) * 100 | round) / 100)ms, last \($vals[-1])ms)"
              else empty end;
            def fmt_raw($label; $vals):
              if ($vals | length) > 0 then
                "\($label): \($vals | length) (avg \(((($vals | add) / ($vals | length)) * 100 | round) / 100), last \($vals[-1]))"
              else empty end;
            def ev_vals($ev):
              [ $rows[] | select(.event == $ev and (.duration_ms != null)) | .duration_ms ];
            def fld_vals($ev; $fld):
              [ $rows[] | select(.event == $ev and (.[$fld] != null)) | .[$fld] ];
            def strat_fld_vals($ev; $st; $fld):
              [ $rows[] | select(.event == $ev and .strategy == $st and (.[$fld] != null)) | .[$fld] ];
            [
              fmt_ms("  Reload prep time"; ev_vals("reload_prep_time")),
              fmt_ms("  Reload daemon stop"; ev_vals("reload_daemon_stop_time")),
              (
                (ev_vals("config_build_time")) as $cb
                | if ($cb | length) > 0 then (
                    fmt_ms("  Config build time"; $cb),
                    fmt_ms("    wall"; ev_vals("config_build_wall_time")),
                    fmt_ms("    menu render"; ev_vals("config_menu_render_time")),
                    fmt_ms("    left layout"; ev_vals("config_left_layout_time")),
                    fmt_ms("      build"; ev_vals("config_left_layout_build_time")),
                    fmt_ms("      apply"; ev_vals("config_left_layout_apply_time")),
                    fmt_ms("      front_app"; ev_vals("config_left_layout_front_app_time")),
                    fmt_ms("      triforce"; ev_vals("config_left_layout_triforce_time")),
                    fmt_ms("      spaces"; ev_vals("config_left_layout_spaces_time")),
                    fmt_ms("      control_center"; ev_vals("config_left_layout_control_center_time")),
                    fmt_ms("      group"; ev_vals("config_left_layout_group_time")),
                    fmt_ms("    right layout"; ev_vals("config_right_layout_time")),
                    fmt_ms("      build"; ev_vals("config_right_layout_build_time")),
                    fmt_ms("      apply"; ev_vals("config_right_layout_apply_time")),
                    fmt_ms("    registry"; ev_vals("config_registry_time"))
                  ) else empty end
              ),
              fmt_ms("  Reload stats flush"; ev_vals("reload_stats_flush_time")),
              (
                (ev_vals("space_topology_refresh")) as $topo
                | if ($topo | length) > 0 then (
                    fmt_ms("  Space topology refreshes"; $topo),
                    (
                      [ $rows[] | select(.event == "space_topology_refresh" and (.duration_ms? != null) and (.strategy? != null)) ]
                      | group_by(.strategy)[]
                      | fmt_ms("    \(.[0].strategy)"; [ .[].duration_ms ])
                    ),
                    fmt_ms("      prepare"; strat_fld_vals("space_topology_refresh"; "full_rebuild"; "prepare_ms")),
                    fmt_ms("      apply"; strat_fld_vals("space_topology_refresh"; "full_rebuild"; "apply_ms")),
                    fmt_ms("      discovery"; strat_fld_vals("space_topology_refresh"; "full_rebuild"; "discovery_ms")),
                    fmt_ms("      build"; strat_fld_vals("space_topology_refresh"; "full_rebuild"; "build_ms")),
                    fmt_ms("      decision"; strat_fld_vals("space_topology_refresh"; "full_rebuild"; "decision_ms"))
                  ) else empty end
              ),
              fmt_ms("  Space refresh overhead"; ev_vals("space_refresh_overhead")),
              (
                (ev_vals("space_visual_refresh")) as $vis
                | if ($vis | length) > 0 then (
                    fmt_ms("  Space visual refreshes"; $vis),
                    (
                      ("spaces_ms", "lookup_ms", "state_ms", "loop_ms", "app_ms", "glyph_ms", "style_ms", "apply_ms") as $f
                      | fmt_ms("    \($f | sub("_ms$"; ""))"; fld_vals("space_visual_refresh"; $f))
                    ),
                    (
                      ("style_writes", "style_skips") as $f
                      | fmt_raw("    style \($f | sub("^style_"; ""))"; fld_vals("space_visual_refresh"; $f))
                    )
                  ) else empty end
              )
            ]
          | .[]
        ' "$LOG_FILE" 2>/dev/null || true
    fi
    echo ""
    
    # Recommendations
    if [ "$reloads_per_hour" -gt 10 ]; then
        echo "⚠️  Warning: High reload frequency detected!"
        echo "   Consider optimizing state management and event handling."
    fi
    
    if [ "$total_updates" -gt 1000 ]; then
        echo "⚠️  Warning: High update frequency detected!"
        echo "   Consider increasing widget update intervals."
    fi
}

# Main command handler
case "${1:-show}" in
    reload)
        track_reload
        ;;
    reload-time)
        track_reload_time "${2:-0}"
        ;;
    update)
        track_update "${2:-}"
        ;;
    event)
        track_event "${2:-}" "${3:-0}" "${4:-}"
        ;;
    events-batch)
        track_events_batch
        ;;
    json)
        show_stats_json
        ;;
    prune|compact)
        prune_log "${2:-}"
        ;;
    show|stats)
        shift || true
        show_stats "$@"
        ;;
    reset)
        rm -f "$STATS_FILE" "$LOG_FILE" "${LOG_FILE}".*.bak
        echo "Statistics reset."
        ;;
    *)
        echo "Usage: $0 {reload|reload-time <ms>|update <widget>|event <name> <duration_ms> [details]|events-batch|show [--json]|json|prune [lines]|reset}"
        echo ""
        echo "Commands:"
        echo "  reload          - Track a reload event"
        echo "  reload-time <ms> - Track reload duration in milliseconds"
        echo "  update <widget> - Track a widget update"
        echo "  event <name> <duration_ms> [details] - Track a named timing event"
        echo "  events-batch    - Track newline-delimited <event><tab><duration><tab><details> timing events from stdin"
        echo "  show            - Display statistics (default)"
        echo "  reset           - Reset all statistics"
        exit 1
        ;;
esac
