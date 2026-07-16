#!/bin/bash

# Modern Calendar - Enhanced with moon phases, better layout, and features

set -euo pipefail

export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${BARISTA_CONFIG_DIR:-$ROOT_DIR}"
TASK_PROVIDER="${BARISTA_TASK_PROVIDER:-files}"
TASK_SOURCES="${BARISTA_CALENDAR_TASK_SOURCES:-${BARISTA_TASK_SOURCES:-}}"
SYSHELP_BIN="${BARISTA_SYSHELP_BIN:-syshelp}"
TASK_SNAPSHOT_SCRIPT="${BARISTA_TASK_SNAPSHOT_SCRIPT:-$CONFIG_DIR/scripts/task_snapshot.py}"
TASK_CACHE_DIR="${BARISTA_TASK_CACHE_DIR:-$CONFIG_DIR/cache/task_focus}"
TASK_SNAPSHOT_FILE="$TASK_CACHE_DIR/summary.json"
MEETING_CACHE_FILE="${BARISTA_CALENDAR_MEETING_CACHE:-}"
MEETING_CACHE_MAX_AGE_SECONDS="${BARISTA_CALENDAR_MEETING_MAX_AGE_SECONDS:-86400}"
export BARISTA_CALENDAR_MEETING_CACHE="$MEETING_CACHE_FILE"
export BARISTA_CALENDAR_MEETING_MAX_AGE_SECONDS="$MEETING_CACHE_MAX_AGE_SECONDS"

declare -a CALENDAR_ITEMS=(
  "clock.calendar.header"
  "clock.calendar.weekdays"
  "clock.calendar.week1"
  "clock.calendar.week2"
  "clock.calendar.week3"
  "clock.calendar.week4"
  "clock.calendar.week5"
  "clock.calendar.week6"
  "clock.calendar.summary"
  "clock.calendar.meeting.next"
  "clock.calendar.tasks.today"
  "clock.calendar.tasks.next"
  "clock.calendar.tasks.waiting"
  "clock.calendar.tasks.blocked"
  "clock.calendar.weekend"
  "clock.calendar.progress"
  "clock.calendar.footer"
)

mkdir -p "$TASK_CACHE_DIR"
snapshot_args=(--provider "$TASK_PROVIDER" --output "$TASK_SNAPSHOT_FILE")
if [[ -n "$TASK_SOURCES" ]]; then
  snapshot_args+=(--sources "$TASK_SOURCES")
fi
if [[ "$TASK_PROVIDER" == "syshelp" ]]; then
  snapshot_args+=(--syshelp-bin "$SYSHELP_BIN")
fi
if python3 "$TASK_SNAPSHOT_SCRIPT" "${snapshot_args[@]}" >/dev/null 2>&1; then
  export BARISTA_TASK_SNAPSHOT_FILE="$TASK_SNAPSHOT_FILE"
else
  export BARISTA_TASK_SNAPSHOT_FILE=""
fi

# Generate enhanced calendar with Python
CAL_LINES=()
while IFS= read -r line; do
  CAL_LINES+=("$line")
done < <(python3 <<'PY'
import calendar
import csv
import datetime
import json
import os
import re

today = datetime.date.today()
cal = calendar.Calendar(firstweekday=calendar.SUNDAY)
weeks = cal.monthdayscalendar(today.year, today.month)

# Pad to 6 weeks for consistent layout
while len(weeks) < 6:
    weeks.append([0] * 7)

# Moon phase calculation
def moon_phase(date):
    """Calculate moon phase (0=new, 0.25=first quarter, 0.5=full, 0.75=last quarter)"""
    diff = date - datetime.date(2000, 1, 6)  # Known new moon
    days = diff.days
    lunations = days / 29.53058867  # Synodic month
    phase = lunations % 1

    # Return icon based on phase
    if phase < 0.0625 or phase > 0.9375:
        return "󰽤"  # New moon
    elif 0.0625 <= phase < 0.1875:
        return "󰽥"  # Waxing crescent
    elif 0.1875 <= phase < 0.3125:
        return "󰽦"  # First quarter
    elif 0.3125 <= phase < 0.4375:
        return "󰽧"  # Waxing gibbous
    elif 0.4375 <= phase < 0.5625:
        return "󰽨"  # Full moon
    elif 0.5625 <= phase < 0.6875:
        return "󰽩"  # Waning gibbous
    elif 0.6875 <= phase < 0.8125:
        return "󰽪"  # Last quarter
    else:
        return "󰽫"  # Waning crescent

lines = []

# Header with month and year
month_name = today.strftime("%B %Y")
lines.append(month_name.center(24).rstrip())

# Weekday headers
lines.append(" Su  Mo  Tu  We  Th  Fr  Sa ")

# Calendar grid with better spacing
for week in weeks:
    cells = []
    for day in week:
        if day == 0:
            cells.append("   ")  # 3 spaces for empty cells
        elif day == today.day:
            # Highlight today with brackets
            cells.append(f"[{day:2d}]" if day < 10 else f"[{day}]")
        else:
            cells.append(f" {day:2d} ")
    lines.append("".join(cells).rstrip())

# Summary line with moon phase + time
moon_icon = moon_phase(today)
day_name = today.strftime("%A")
now = datetime.datetime.now().astimezone()
time_str = now.strftime("%I:%M %p").lstrip("0")
tz = now.tzname() or ""
lines.append(f"{moon_icon}  {day_name}, {today.strftime('%b')} {today.day} · {time_str} {tz}".rstrip())

def truncate(value, limit=28):
    value = re.sub(r"\s+", " ", str(value or "")).strip()
    if len(value) <= limit:
        return value
    return value[: max(0, limit - 1)] + "…"

def parse_event_date(value):
    try:
        return datetime.date.fromisoformat(str(value or "").strip())
    except ValueError:
        return None

def parse_event_time(value):
    text = str(value or "").strip()
    if not text:
        return None
    for fmt in ("%H:%M", "%H:%M:%S", "%I:%M%p", "%I:%M %p"):
        try:
            return datetime.datetime.strptime(text, fmt).time()
        except ValueError:
            continue
    return None

def cached_meeting_line():
    cache_value = os.environ.get("BARISTA_CALENDAR_MEETING_CACHE") or ""
    if not cache_value.strip():
        return ""
    cache_path = os.path.expanduser(cache_value.strip())
    try:
        max_age_seconds = int(os.environ.get("BARISTA_CALENDAR_MEETING_MAX_AGE_SECONDS") or "86400")
    except ValueError:
        max_age_seconds = 86400
    if max_age_seconds <= 0:
        max_age_seconds = 86400
    try:
        cache_stat = os.stat(cache_path)
        if cache_stat.st_size > 1024 * 1024:
            return ""
        if max(0, now.timestamp() - cache_stat.st_mtime) > max_age_seconds:
            return ""
        with open(cache_path, newline="", encoding="utf-8", errors="replace") as handle:
            reader = csv.DictReader(handle, delimiter="\t")
            required_fields = ("start_date", "start_time", "title")
            if not all(field in (reader.fieldnames or []) for field in required_fields):
                return ""
            rows = list(reader)
    except (OSError, csv.Error):
        return ""

    candidates = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        title = re.sub(r"\s+", " ", str(row.get("title") or "")).strip()
        event_date = parse_event_date(row.get("start_date"))
        if not title or event_date is None:
            continue
        raw_event_time = str(row.get("start_time") or "").strip()
        event_time = parse_event_time(raw_event_time)
        if raw_event_time and event_time is None:
            continue
        if event_time is None:
            if event_date < today:
                continue
            sort_value = datetime.datetime.combine(event_date, datetime.time.min, tzinfo=now.tzinfo)
        else:
            sort_value = datetime.datetime.combine(event_date, event_time, tzinfo=now.tzinfo)
            if sort_value < now:
                continue
        candidates.append((sort_value, event_date, event_time, title))

    if not candidates:
        return ""
    _, event_date, event_time, title = min(candidates, key=lambda entry: entry[0])
    if event_date == today:
        when = "Today"
    elif event_date == today + datetime.timedelta(days=1):
        when = "Tomorrow"
    else:
        when = event_date.strftime("%a %b %-d")
    if event_time is not None:
        when += " " + datetime.datetime.combine(event_date, event_time).strftime("%-I:%M %p")
    return f"Cached: {when} · {truncate(title, 26)}"

lines.append(cached_meeting_line())

# Compact local-task summary. The provider owns task semantics and mutation;
# the calendar popup remains a bounded, status-only renderer.
snapshot = {}
snapshot_path = os.environ.get("BARISTA_TASK_SNAPSHOT_FILE") or ""
if snapshot_path:
    try:
        with open(snapshot_path, "r", encoding="utf-8") as handle:
            snapshot = json.load(handle)
    except (OSError, json.JSONDecodeError):
        snapshot = {}

sources = snapshot.get("sources") if isinstance(snapshot.get("sources"), list) else []
available_source = any(
    isinstance(source, dict)
    and source.get("exists")
    and not source.get("error")
    for source in sources
)

def selected_title(key):
    task = snapshot.get(key)
    if not isinstance(task, dict):
        return ""
    return truncate(task.get("title"))

if not sources:
    lines.extend(["", "", "", ""])
elif not available_source:
    lines.extend(["󰄱 Focus: Task source unavailable", "󰒭 Next: —", "󰔟 Waiting: —", "󰅖 Blocked: —"])
else:
    focus_task = selected_title("focus")
    next_task = selected_title("next")
    waiting_task = selected_title("waiting")
    blocked_task = selected_title("blocked")
    lines.append(f"󰄱 Focus: {focus_task or 'No open tasks'}".rstrip())
    lines.append(f"󰒭 Next: {next_task or '—'}".rstrip())
    lines.append(f"󰔟 Waiting: {waiting_task or 'Clear'}".rstrip())
    lines.append(f"󰅖 Blocked: {blocked_task or 'Clear'}".rstrip())

# Weekend countdown
weekday = today.weekday()  # Monday = 0
days_until_weekend = (5 - weekday) % 7
if days_until_weekend == 0:
    weekend_line = "󰸗 Weekend is here"
elif days_until_weekend == 1:
    weekend_line = "󰸗 Weekend in 1 day"
else:
    weekend_line = f"󰸗 Weekend in {days_until_weekend} days"
lines.append(weekend_line.rstrip())

# Month progress
days_in_month = calendar.monthrange(today.year, today.month)[1]
days_left = days_in_month - today.day
month_progress = round((today.day / days_in_month) * 100)
lines.append(f"󰃭 {days_left} days left · {month_progress}% of month".rstrip())

# Footer with week number and day of year
week_num = today.isocalendar()[1]
day_of_year = today.timetuple().tm_yday
days_remaining = (datetime.date(today.year, 12, 31) - today).days
lines.append(f"󰸗 Week {week_num:02d}  󰔛 Day {day_of_year:03d}/{days_remaining:03d}".rstrip())

for entry in lines:
    print(entry)
PY
)

# Update all calendar rows in one SketchyBar process.
calendar_args=()
for idx in "${!CALENDAR_ITEMS[@]}"; do
  item_name="${CALENDAR_ITEMS[$idx]}"
  line="${CAL_LINES[$idx]:-}"
  if [ -n "$line" ]; then
    calendar_args+=(--set "$item_name" "label=$line" drawing=on)
  else
    calendar_args+=(--set "$item_name" label= drawing=off)
  fi
done
"$SKETCHYBAR_BIN" "${calendar_args[@]}"
