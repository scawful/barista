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

# Log an event
log_event() {
    local event_type="$1"
    local details="${2:-{}}"
    local timestamp=$(get_timestamp)
    
    echo "$timestamp|$event_type|$details" >> "$LOG_FILE"
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
    
    log_event "reload" "{\"count\": $reload_count, \"reloads_per_hour\": $reloads_per_hour}"
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
    
    log_event "update" "{\"widget\": \"$widget_name\"}"
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
    update)
        track_update "${2:-}"
        ;;
    show|stats)
        show_stats
        ;;
    reset)
        rm -f "$STATS_FILE" "$LOG_FILE"
        echo "Statistics reset."
        ;;
    *)
        echo "Usage: $0 {reload|update <widget>|show|reset}"
        echo ""
        echo "Commands:"
        echo "  reload          - Track a reload event"
        echo "  update <widget> - Track a widget update"
        echo "  show            - Display statistics (default)"
        echo "  reset           - Reset all statistics"
        exit 1
        ;;
esac

