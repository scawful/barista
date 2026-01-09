#!/usr/bin/env lua

local HOME = os.getenv("HOME") or ""
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")

package.path = table.concat({
  package.path,
  CONFIG_DIR .. "/?.lua",
  CONFIG_DIR .. "/modules/?.lua",
  CONFIG_DIR .. "/helpers/lib/?.lua",
}, ";")

local function usage(message)
  if message and message ~= "" then
    io.stderr:write(message .. "\n")
  end
  io.stderr:write("Commands:\n")
  io.stderr:write("  widget-color <widget> <color>\n")
  io.stderr:write("  widget-toggle <widget> <on|off>\n")
  io.stderr:write("  theme <name>\n")
  io.stderr:write("  bar-height <height>\n")
  io.stderr:write("  bar-color <color> [blur]\n")
  io.stderr:write("  icon <name> <glyph|none>\n")
  io.stderr:write("  space-icon <space> <glyph|none>\n")
  os.exit(1)
end

local ok, state = pcall(require, "state")
if not ok then
  usage("Failed to load state module; ensure BARISTA_CONFIG_DIR points to the barista config.")
end

local command = arg[1]
if not command or command == "" then
  usage()
end

local data = state.load()

local function normalize_bool(value)
  if not value then
    return false
  end
  local lowered = tostring(value):lower()
  return lowered == "1" or lowered == "true" or lowered == "on" or lowered == "yes"
end

if command == "widget-color" then
  local widget = arg[2]
  local color = arg[3]
  if not widget or not color then
    usage("widget-color requires <widget> <color>")
  end
  data.widget_colors = data.widget_colors or {}
  data.widget_colors[widget] = color
elseif command == "widget-toggle" then
  local widget = arg[2]
  local value = arg[3]
  if not widget or not value then
    usage("widget-toggle requires <widget> <on|off>")
  end
  data.widgets = data.widgets or {}
  data.widgets[widget] = normalize_bool(value)
elseif command == "theme" then
  local theme = arg[2]
  if not theme then
    usage("theme requires <name>")
  end
  data.appearance = data.appearance or {}
  data.appearance.theme = theme
elseif command == "bar-height" then
  local height = tonumber(arg[2] or "")
  if not height then
    usage("bar-height requires <height>")
  end
  data.appearance = data.appearance or {}
  data.appearance.bar_height = height
elseif command == "bar-color" then
  local color = arg[2]
  if not color then
    usage("bar-color requires <color> [blur]")
  end
  data.appearance = data.appearance or {}
  data.appearance.bar_color = color
  if arg[3] then
    local blur = tonumber(arg[3])
    if not blur then
      usage("bar-color blur must be an integer")
    end
    data.appearance.blur_radius = blur
  end
elseif command == "icon" then
  local name = arg[2]
  local glyph = arg[3]
  if not name or not glyph then
    usage("icon requires <name> <glyph|none>")
  end
  data.icons = data.icons or {}
  if glyph == "" or glyph == "none" then
    data.icons[name] = nil
  else
    data.icons[name] = glyph
  end
elseif command == "space-icon" then
  local space = arg[2]
  local glyph = arg[3]
  if not space or not glyph then
    usage("space-icon requires <space> <glyph|none>")
  end
  data.space_icons = data.space_icons or {}
  if glyph == "" or glyph == "none" then
    data.space_icons[tostring(space)] = nil
  else
    data.space_icons[tostring(space)] = glyph
  end
else
  usage("Unknown command: " .. tostring(command))
end

state.save(data, true)

os.execute("command -v sketchybar >/dev/null 2>&1 && sketchybar --reload >/dev/null 2>&1 || true")
