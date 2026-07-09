#!/bin/bash

# Modern Calendar - Enhanced with moon phases, better layout, and features

set -euo pipefail

export LC_ALL="${LC_ALL:-en_US.UTF-8}"
export LANG="${LANG:-en_US.UTF-8}"

SKETCHYBAR_BIN="${BARISTA_SKETCHYBAR_BIN:-${SKETCHYBAR_BIN:-$(command -v sketchybar 2>/dev/null || true)}}"
[ -n "$SKETCHYBAR_BIN" ] || SKETCHYBAR_BIN="/opt/homebrew/bin/sketchybar"

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
  "clock.calendar.tasks.today"
  "clock.calendar.tasks.next"
  "clock.calendar.tasks.blocked"
  "clock.calendar.weekend"
  "clock.calendar.progress"
  "clock.calendar.footer"
)

# Generate enhanced calendar with Python
CAL_LINES=()
while IFS= read -r line; do
  CAL_LINES+=("$line")
done < <(python3 <<'PY'
import calendar
import datetime
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

# Compact local-task summary. Keep this popup status-only: no repo/doc links.
DEFAULT_TASK_SOURCES = [
    "~/src/docs/workflow/tasks.org",
    "~/src/hobby/oracle-of-secrets/Docs/oracle.org",
    "~/src/folio/tasks/inbox.org",
]

def clean_title(title):
    title = re.sub(r"\s+:[\w:@#%]+:\s*$", "", title or "").strip()
    title = re.sub(r"^\[#.\]\s+", "", title).strip()
    return title

def truncate(value, limit=28):
    value = value or ""
    if len(value) <= limit:
        return value
    return value[: max(0, limit - 1)] + "…"

def task_sources():
    raw = os.environ.get("BARISTA_CALENDAR_TASK_SOURCES") or os.environ.get("BARISTA_TASK_SOURCES")
    entries = raw.split(":") if raw else DEFAULT_TASK_SOURCES
    seen = set()
    for entry in entries:
        entry = entry.strip()
        if not entry:
            continue
        path = os.path.expanduser(entry)
        if path not in seen:
            seen.add(path)
            yield path

def read_local_tasks():
    buckets = dict(today=[], next=[], blocked=[])
    heading_re = re.compile(r"^\*+\s+(TODO|NEXT|DOING|STARTED|WAITING|BLOCKED)\s+(.*)$", re.I)
    date_re = re.compile(r"<(\d{4}-\d{2}-\d{2})")

    def add(bucket, title):
        title = clean_title(title)
        if title and title not in buckets[bucket]:
            buckets[bucket].append(title)

    for path in task_sources():
        if not os.path.exists(path):
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as handle:
                current = None
                for raw_line in handle:
                    line = raw_line.rstrip("\n")
                    match = heading_re.match(line)
                    if match:
                        status = match.group(1).upper()
                        title = match.group(2)
                        current = (status, title)
                        if status in ("BLOCKED", "WAITING"):
                            add("blocked", title)
                        elif status == "NEXT":
                            add("next", title)
                        else:
                            add("today", title)
                        continue
                    if current and ("SCHEDULED:" in line or "DEADLINE:" in line):
                        date_match = date_re.search(line)
                        if date_match:
                            try:
                                item_date = datetime.date.fromisoformat(date_match.group(1))
                            except ValueError:
                                item_date = None
                            if item_date and item_date <= today:
                                add("today", current[1])
        except OSError:
            continue
    return buckets

tasks = read_local_tasks()
today_task = truncate(tasks["today"][0]) if tasks["today"] else "No local tasks"
next_task = truncate(tasks["next"][0]) if tasks["next"] else "—"
blocked_task = truncate(tasks["blocked"][0]) if tasks["blocked"] else "Clear"
lines.append(f"󰄱 Today: {today_task}".rstrip())
lines.append(f"󰒭 Next: {next_task}".rstrip())
lines.append(f"󰅖 Blocked: {blocked_task}".rstrip())

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

# Update calendar items
for idx in "${!CALENDAR_ITEMS[@]}"; do
  item_name="${CALENDAR_ITEMS[$idx]}"
  line="${CAL_LINES[$idx]:-}"
  if [ -n "$line" ]; then
    "$SKETCHYBAR_BIN" --set "$item_name" label="$line" drawing=on
  else
    "$SKETCHYBAR_BIN" --set "$item_name" label="" drawing=off
  fi
done
