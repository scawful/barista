#!/bin/bash
# Barista Performance Statistics Script
# Tracks reload frequency, update frequencies, and performance metrics

set -euo pipefail

CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
STATS_FILE="${CONFIG_DIR}/.barista_stats.json"
LOG_FILE="${CONFIG_DIR}/.barista_stats.log"

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
}

summarize_event() {
    local event_name="$1"
    [ -f "$LOG_FILE" ] || return 1
    jq -sr --arg event "$event_name" '
      [ .[] | select(.event == $event and (.duration_ms? != null)) | .duration_ms ] as $durations
      | if ($durations | length) > 0 then
          [
            ($durations | length),
            (((($durations | add) / ($durations | length)) * 100 | round) / 100),
            ($durations[-1])
          ] | @tsv
        else
          empty
        end
    ' "$LOG_FILE"
}

summarize_event_by_strategy() {
    local event_name="$1"
    [ -f "$LOG_FILE" ] || return 1
    jq -sr --arg event "$event_name" '
      [ .[] | select(.event == $event and (.duration_ms? != null) and (.strategy? != null)) ]
      | group_by(.strategy)
      | map({
          strategy: .[0].strategy,
          count: length,
          avg: (((map(.duration_ms) | add) / length) * 100 | round) / 100,
          last: .[-1].duration_ms
        })
      | .[]
      | "\(.strategy)\t\(.count)\t\(.avg)\t\(.last)"
    ' "$LOG_FILE"
}

summarize_event_field_for_strategy() {
    local event_name="$1"
    local strategy_name="$2"
    local field_name="$3"
    [ -f "$LOG_FILE" ] || return 1
    jq -sr \
      --arg event "$event_name" \
      --arg strategy "$strategy_name" \
      --arg field "$field_name" '
      [ .[] | select(.event == $event and .strategy? == $strategy and .[$field]? != null) | .[$field] ] as $values
      | if ($values | length) > 0 then
          [
            ($values | length),
            (((($values | add) / ($values | length)) * 100 | round) / 100),
            ($values[-1])
          ] | @tsv
        else
          empty
        end
    ' "$LOG_FILE"
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

# Display statistics
show_stats() {
    if [ ! -f "$STATS_FILE" ]; then
        echo "No statistics available yet."
        echo "Statistics are tracked automatically when sketchybar reloads."
        return
    fi
    
    echo "Barista Performance Statistics"
    echo "============================"
    echo ""
    
    # Reload stats
    local reload_count=$(jq -r '.reloads.count // 0' "$STATS_FILE" 2>/dev/null || echo "0")
    local last_reload=$(jq -r '.reloads.last_reload // "never"' "$STATS_FILE" 2>/dev/null || echo "never")
    local reloads_per_hour=$(jq -r '.reloads.reloads_per_hour // 0' "$STATS_FILE" 2>/dev/null || echo "0")
    
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
    
    # Update stats
    local total_updates=$(jq -r '.updates.total // 0' "$STATS_FILE" 2>/dev/null || echo "0")
    echo "Update Statistics:"
    echo "  Total updates: $total_updates"
    echo "  Updates by widget:"
    jq -r '.updates.by_widget // {} | to_entries | .[] | "    \(.key): \(.value)"' "$STATS_FILE" 2>/dev/null || echo "    (none)"
    echo ""
    
    # Performance metrics
    echo "Performance Metrics:"
    local avg_reload_time=$(jq -r '.performance.avg_reload_time // 0' "$STATS_FILE" 2>/dev/null || echo "0")
    local last_reload_time=$(jq -r '.performance.last_reload_time // 0' "$STATS_FILE" 2>/dev/null || echo "0")
    echo "  Average reload time: ${avg_reload_time}ms"
    echo "  Last reload time: ${last_reload_time}ms"
    local config_build_stats
    local reload_prep_stats
    local reload_daemon_stop_stats
    local reload_stats_flush_stats
    local config_build_wall_stats
    reload_prep_stats="$(summarize_event "reload_prep_time" 2>/dev/null || true)"
    if [ -n "$reload_prep_stats" ]; then
        local phase_count phase_avg phase_last
        read -r phase_count phase_avg phase_last <<< "$reload_prep_stats"
        echo "  Reload prep time: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
    fi
    reload_daemon_stop_stats="$(summarize_event "reload_daemon_stop_time" 2>/dev/null || true)"
    if [ -n "$reload_daemon_stop_stats" ]; then
        local phase_count phase_avg phase_last
        read -r phase_count phase_avg phase_last <<< "$reload_daemon_stop_stats"
        echo "  Reload daemon stop: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
    fi
    config_build_stats="$(summarize_event "config_build_time" 2>/dev/null || true)"
    if [ -n "$config_build_stats" ]; then
        local config_count config_avg config_last
        read -r config_count config_avg config_last <<< "$config_build_stats"
        echo "  Config build time: ${config_count} (avg ${config_avg}ms, last ${config_last}ms)"
        config_build_wall_stats="$(summarize_event "config_build_wall_time" 2>/dev/null || true)"
        if [ -n "$config_build_wall_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_build_wall_stats"
            echo "    wall: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        local config_menu_stats
        local config_left_stats
        local config_left_build_stats
        local config_left_apply_stats
        local config_left_front_app_stats
        local config_left_triforce_stats
        local config_left_spaces_stats
        local config_left_control_center_stats
        local config_left_group_stats
        local config_right_stats
        local config_right_build_stats
        local config_right_apply_stats
        local config_registry_stats
        config_menu_stats="$(summarize_event "config_menu_render_time" 2>/dev/null || true)"
        if [ -n "$config_menu_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_menu_stats"
            echo "    menu render: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_left_stats="$(summarize_event "config_left_layout_time" 2>/dev/null || true)"
        if [ -n "$config_left_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_left_stats"
            echo "    left layout: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_left_build_stats="$(summarize_event "config_left_layout_build_time" 2>/dev/null || true)"
        if [ -n "$config_left_build_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_left_build_stats"
            echo "      build: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_left_apply_stats="$(summarize_event "config_left_layout_apply_time" 2>/dev/null || true)"
        if [ -n "$config_left_apply_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_left_apply_stats"
            echo "      apply: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_left_front_app_stats="$(summarize_event "config_left_layout_front_app_time" 2>/dev/null || true)"
        if [ -n "$config_left_front_app_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_left_front_app_stats"
            echo "      front_app: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_left_triforce_stats="$(summarize_event "config_left_layout_triforce_time" 2>/dev/null || true)"
        if [ -n "$config_left_triforce_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_left_triforce_stats"
            echo "      triforce: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_left_spaces_stats="$(summarize_event "config_left_layout_spaces_time" 2>/dev/null || true)"
        if [ -n "$config_left_spaces_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_left_spaces_stats"
            echo "      spaces: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_left_control_center_stats="$(summarize_event "config_left_layout_control_center_time" 2>/dev/null || true)"
        if [ -n "$config_left_control_center_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_left_control_center_stats"
            echo "      control_center: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_left_group_stats="$(summarize_event "config_left_layout_group_time" 2>/dev/null || true)"
        if [ -n "$config_left_group_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_left_group_stats"
            echo "      group: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_right_stats="$(summarize_event "config_right_layout_time" 2>/dev/null || true)"
        if [ -n "$config_right_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_right_stats"
            echo "    right layout: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_right_build_stats="$(summarize_event "config_right_layout_build_time" 2>/dev/null || true)"
        if [ -n "$config_right_build_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_right_build_stats"
            echo "      build: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_right_apply_stats="$(summarize_event "config_right_layout_apply_time" 2>/dev/null || true)"
        if [ -n "$config_right_apply_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_right_apply_stats"
            echo "      apply: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        config_registry_stats="$(summarize_event "config_registry_time" 2>/dev/null || true)"
        if [ -n "$config_registry_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$config_registry_stats"
            echo "    registry: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
    fi
    reload_stats_flush_stats="$(summarize_event "reload_stats_flush_time" 2>/dev/null || true)"
    if [ -n "$reload_stats_flush_stats" ]; then
        local phase_count phase_avg phase_last
        read -r phase_count phase_avg phase_last <<< "$reload_stats_flush_stats"
        echo "  Reload stats flush: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
    fi
    local topology_stats
    topology_stats="$(summarize_event "space_topology_refresh" 2>/dev/null || true)"
    if [ -n "$topology_stats" ]; then
        local topology_count topology_avg topology_last
        read -r topology_count topology_avg topology_last <<< "$topology_stats"
        echo "  Space topology refreshes: ${topology_count} (avg ${topology_avg}ms, last ${topology_last}ms)"
        local topology_strategy_stats
        topology_strategy_stats="$(summarize_event_by_strategy "space_topology_refresh" 2>/dev/null || true)"
        if [ -n "$topology_strategy_stats" ]; then
            while IFS=$'\t' read -r strategy count avg last; do
                [ -n "$strategy" ] || continue
                echo "    ${strategy}: ${count} (avg ${avg}ms, last ${last}ms)"
            done <<< "$topology_strategy_stats"
        fi
        local full_rebuild_prepare_stats
        local full_rebuild_apply_stats
        full_rebuild_prepare_stats="$(summarize_event_field_for_strategy "space_topology_refresh" "full_rebuild" "prepare_ms" 2>/dev/null || true)"
        if [ -n "$full_rebuild_prepare_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$full_rebuild_prepare_stats"
            echo "      prepare: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        full_rebuild_apply_stats="$(summarize_event_field_for_strategy "space_topology_refresh" "full_rebuild" "apply_ms" 2>/dev/null || true)"
        if [ -n "$full_rebuild_apply_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$full_rebuild_apply_stats"
            echo "      apply: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        local full_rebuild_discovery_stats
        local full_rebuild_build_stats
        local full_rebuild_decision_stats
        full_rebuild_discovery_stats="$(summarize_event_field_for_strategy "space_topology_refresh" "full_rebuild" "discovery_ms" 2>/dev/null || true)"
        if [ -n "$full_rebuild_discovery_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$full_rebuild_discovery_stats"
            echo "      discovery: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        full_rebuild_build_stats="$(summarize_event_field_for_strategy "space_topology_refresh" "full_rebuild" "build_ms" 2>/dev/null || true)"
        if [ -n "$full_rebuild_build_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$full_rebuild_build_stats"
            echo "      build: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
        full_rebuild_decision_stats="$(summarize_event_field_for_strategy "space_topology_refresh" "full_rebuild" "decision_ms" 2>/dev/null || true)"
        if [ -n "$full_rebuild_decision_stats" ]; then
            local phase_count phase_avg phase_last
            read -r phase_count phase_avg phase_last <<< "$full_rebuild_decision_stats"
            echo "      decision: ${phase_count} (avg ${phase_avg}ms, last ${phase_last}ms)"
        fi
    fi
    local overhead_stats
    overhead_stats="$(summarize_event "space_refresh_overhead" 2>/dev/null || true)"
    if [ -n "$overhead_stats" ]; then
        local overhead_count overhead_avg overhead_last
        read -r overhead_count overhead_avg overhead_last <<< "$overhead_stats"
        echo "  Space refresh overhead: ${overhead_count} (avg ${overhead_avg}ms, last ${overhead_last}ms)"
    fi
    local visual_stats
    visual_stats="$(summarize_event "space_visual_refresh" 2>/dev/null || true)"
    if [ -n "$visual_stats" ]; then
        local visual_count visual_avg visual_last
        read -r visual_count visual_avg visual_last <<< "$visual_stats"
        echo "  Space visual refreshes: ${visual_count} (avg ${visual_avg}ms, last ${visual_last}ms)"
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
    show|stats)
        show_stats
        ;;
    reset)
        rm -f "$STATS_FILE" "$LOG_FILE"
        echo "Statistics reset."
        ;;
    *)
        echo "Usage: $0 {reload|reload-time <ms>|update <widget>|event <name> <duration_ms> [details]|events-batch|show|reset}"
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
