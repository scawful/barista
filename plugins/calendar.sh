#!/bin/bash

# Modern Calendar - Enhanced with moon phases, better layout, and features

set -euo pipefail

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
  "clock.calendar.footer"
)

# Generate enhanced calendar with Python
CAL_LINES=()
while IFS= read -r line; do
  CAL_LINES+=("$line")
done < <(python3 <<'PY'
import calendar
import datetime
import math

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

# Summary line with moon phase
moon_icon = moon_phase(today)
day_name = today.strftime("%A")
lines.append(f"{moon_icon}  {day_name}, {today.strftime('%b')} {today.day}".rstrip())

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
    sketchybar --set "$item_name" label="$line" drawing=on
  else
    sketchybar --set "$item_name" label="" drawing=off
  fi
done
