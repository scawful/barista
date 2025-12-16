-- SketchyBar Configuration
-- Modular, modern macOS status bar with Yabai integration

local sbar = require("sketchybar")
local theme = require("theme")
local json = require("json")
local utf8 = require("utf8")

-- Load modules
local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
package.path = package.path .. ";" .. CONFIG_DIR .. "/modules/?.lua"
package.path = package.path .. ";" .. CONFIG_DIR .. "/modules/integrations/?.lua"
package.path = package.path .. ";" .. CONFIG_DIR .. "/?.lua"

local state_module = require("state")
local profile_module = require("profile")
local icons_module = require("icons")
local icon_manager = require("icon_manager")  -- Centralized icon management with multi-font support
local shortcuts = require("shortcuts")  -- Keyboard shortcut management
local widgets_module = require("widgets")
local menu_module = require("menu")
local yaze_module = require("yaze")
local oracle_module = require("oracle")
local emacs_module = require("emacs")
local whichkey_module = require("whichkey")

-- Initialize component switcher for C/Lua hybrid architecture
local component_switcher = require("component_switcher")

-- Lua-only mode: for environments without compiled helpers (no CMake) or when explicitly requested
local LUA_ONLY = (os.getenv("BARISTA_LUA_ONLY") == "1") or (os.getenv("BARISTA_NO_CMAKE") == "1")
local c_bridge = nil

if not LUA_ONLY then
  local ok, mod = pcall(require, "c_bridge")
  if ok then
    c_bridge = mod
    if c_bridge.check_components then
      local status = c_bridge.check_components()
      if status and not status.all_present then
        print(string.format("Barista: missing C helpers (%s); switching to Lua-only fallback", table.concat(status.missing, ", ")))
        LUA_ONLY = true
      end
    end
  else
    print("Barista: c_bridge unavailable; switching to Lua-only fallback")
    LUA_ONLY = true
  end
end

component_switcher.init()
component_switcher.set_mode(LUA_ONLY and "lua" or "auto")  -- Auto-select C when available, force Lua in fallback

if not LUA_ONLY and c_bridge then
  c_bridge.init()  -- Pre-cache common operations
else
  c_bridge = c_bridge or { init = function() end }
  print("Barista: running in Lua-only mode (no compiled helpers)")
end

-- Import existing icons into icon_manager for backwards compatibility
icon_manager.import_from_module(icons_module)

-- Paths (configurable via environment variables)
local PLUGIN_DIR = CONFIG_DIR .. "/plugins"
local EVENT_DIR = CONFIG_DIR .. "/helpers/event_providers"
local SCRIPTS_DIR = os.getenv("BARISTA_SCRIPTS_DIR") or (HOME .. "/.config/scripts")
local CODE_DIR = os.getenv("BARISTA_CODE_DIR") or (HOME .. "/Code")

-- Scripts
local YABAI_CONTROL_SCRIPT = SCRIPTS_DIR .. "/yabai_control.sh"
local SKHD_CONTROL_SCRIPT = SCRIPTS_DIR .. "/skhd_control.sh"
local FRONT_APP_ACTION_SCRIPT = SCRIPTS_DIR .. "/front_app_action.sh"
local function compiled_script(binary_name, fallback)
  if LUA_ONLY then
    return fallback
  end
  local path = string.format("%s/bin/%s", CONFIG_DIR, binary_name)
  local file = io.open(path, "r")
  if file then
    file:close()
    return path
  end
  print("WARNING: Binary not found: " .. path)
  return fallback
end

local HOVER_SCRIPT = compiled_script("popup_hover", PLUGIN_DIR .. "/popup_hover.sh")
local POPUP_ANCHOR_SCRIPT = compiled_script("popup_anchor", PLUGIN_DIR .. "/popup_anchor.sh")
local SUBMENU_HOVER_SCRIPT = compiled_script("submenu_hover", PLUGIN_DIR .. "/submenu_hover.sh")
local POPUP_MANAGER_SCRIPT = compiled_script("popup_manager", PLUGIN_DIR .. "/popup_manager.sh")
local POPUP_GUARD_SCRIPT = compiled_script("popup_guard", PLUGIN_DIR .. "/popup_guard.sh")

-- Environment
local NET_INTERFACE = os.getenv("SKETCHYBAR_NET_INTERFACE") or "en0"

-- Load state and profile
local state = state_module.load()
local profile_name = profile_module.get_selected_profile(state)
local user_profile = profile_module.load(profile_name)

-- Merge profile configuration with state
if user_profile then
  state = profile_module.merge_config(state, user_profile)
  print("Loaded profile: " .. user_profile.name)
end

local function integration_enabled(name)
  local entry = state_module.get_integration(state, name)
  if type(entry) ~= "table" then
    return true
  end
  if entry.enabled == nil then
    return true
  end
  return entry.enabled ~= false
end

local yaze_enabled = integration_enabled("yaze")
local oracle_enabled = integration_enabled("oracle")
local emacs_enabled = integration_enabled("emacs")
local halext_enabled = integration_enabled("halext")
local halext_module = halext_enabled and require("halext") or nil

-- Utility functions
local function clamp(value, min_value, max_value)
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function font_string(family, style, size)
  return string.format("%s:%s:%0.1f", family, style, size)
end

local function shell_exec(cmd)
  sbar.exec(string.format("bash -lc %q", cmd))
end

local function open_path(path)
  return string.format("open %q", path)
end

local function call_script(script_path, ...)
  if not script_path or script_path == "" then
    return ""
  end
  local cmd = string.format("bash %q", script_path)
  local args = { ... }
  if #args > 0 then
    local parts = {}
    for _, arg in ipairs(args) do
      table.insert(parts, string.format("%q", tostring(arg)))
    end
    cmd = string.format("%s %s", cmd, table.concat(parts, " "))
  end
  return cmd
end

-- Cache yabai availability check (performance optimization)
local yabai_available_cache = nil
local function yabai_available()
  if yabai_available_cache == nil then
    local handle = io.popen("command -v yabai >/dev/null 2>&1 && echo 1 || echo 0")
    if not handle then 
      yabai_available_cache = false
      return false 
    end
    local result = handle:read("*a")
    handle:close()
    yabai_available_cache = result and result:match("1")
  end
  return yabai_available_cache
end

local function safe_icon(value)
  if type(value) ~= "string" then
    return nil
  end
  local ok = pcall(function()
    utf8.len(value)
  end)
  if ok then
    return value
  end
  return nil
end

_G.icon_for = icon_for

local function attach_hover(name)
  -- Hover script is now integrated into the widgets' own scripts for better performance
  -- We only need to subscribe to mouse events
  shell_exec(string.format("sketchybar --subscribe %s mouse.entered mouse.exited", name))
end

local function subscribe_popup_autoclose(name)
  -- OPTIMIZED: Reduced delay from 0.4s to 0.1s (item creation is fast)
  local cmd = string.format("sleep 0.1; sketchybar --subscribe %s mouse.entered mouse.exited mouse.exited.global", name)
  shell_exec(cmd)
end

local function parse_color(value)
  if type(value) == "string" then
    local num = tonumber(value)
    if num then
      return num
    end
  end
  return value
end

-- Spaces management with display state caching
local last_display_state = nil
local display_refresh_pending = false

local function get_display_state()
  if not yabai_available() then
    return nil
  end
  local handle = io.popen("yabai -m query --displays 2>/dev/null | jq -r '[.[] | .index] | sort | join(\",\")'")
  if not handle then return nil end
  local result = handle:read("*a")
  handle:close()
  return result and result:gsub("%s+", "") or nil
end

-- Build a concrete associated_display list (e.g. "1,2,3") so DisplayLink
-- mirrors render instead of relying on the "all" sentinel mask
local function get_associated_displays()
  if not yabai_available() then
    return "all"
  end

  local handle = io.popen([[yabai -m query --displays 2>/dev/null | jq -r '.[].index']])
  if not handle then
    return "all"
  end

  local output = handle:read("*a") or ""
  handle:close()

  local targets = {}
  for line in output:gmatch("[^\r\n]+") do
    local num = tonumber(line)
    if num then
      table.insert(targets, tostring(num))
    end
  end

  if #targets == 0 then
    return "all"
  end

  return table.concat(targets, ",")
end

local associated_displays = get_associated_displays()
print("Associated displays target: " .. associated_displays)

local function refresh_spaces()
  local cmd = string.format("CONFIG_DIR=%s %s/refresh_spaces.sh", CONFIG_DIR, PLUGIN_DIR)
  shell_exec(cmd)
end

-- Debounced display refresh (only refresh if display state actually changed)
local function refresh_spaces_if_needed()
  local current_state = get_display_state()
  if current_state and current_state ~= last_display_state then
    last_display_state = current_state
    refresh_spaces()
    display_refresh_pending = false
  else
    display_refresh_pending = false
  end
end

local function watch_spaces()
  local refresh_action = string.format("CONFIG_DIR=%s %s/refresh_spaces.sh", CONFIG_DIR, PLUGIN_DIR)
  local change_action = "sketchybar --trigger space_change"
  
  -- Batch signal removal commands
  local remove_cmds = {
    "yabai -m signal --remove sketchybar_space_change",
    "yabai -m signal --remove sketchybar_space_created",
    "yabai -m signal --remove sketchybar_space_destroyed",
    "yabai -m signal --remove sketchybar_display_changed",
    "yabai -m signal --remove sketchybar_display_added",
    "yabai -m signal --remove sketchybar_display_removed"
  }
  for _, cmd in ipairs(remove_cmds) do
    shell_exec(cmd .. " >/dev/null 2>&1 || true")
  end
  
  -- Use debounced refresh for display events to prevent rapid reloads
  local debounced_refresh = string.format("CONFIG_DIR=%s %s/refresh_spaces.sh", CONFIG_DIR, PLUGIN_DIR)
  
  shell_exec(string.format("yabai -m signal --add event=space_changed label=sketchybar_space_change action=%q", change_action))
  shell_exec(string.format("yabai -m signal --add event=space_created label=sketchybar_space_created action=%q", refresh_action))
  shell_exec(string.format("yabai -m signal --add event=space_destroyed label=sketchybar_space_destroyed action=%q", refresh_action))
  -- Use immediate refresh for display events (they're already infrequent)
  shell_exec(string.format("yabai -m signal --add event=display_changed label=sketchybar_display_changed action=%q", refresh_action))
  shell_exec(string.format("yabai -m signal --add event=display_added label=sketchybar_display_added action=%q", refresh_action))
  shell_exec(string.format("yabai -m signal --add event=display_removed label=sketchybar_display_removed action=%q", refresh_action))
  
  -- Cache initial display state
  last_display_state = get_display_state()
end

-- Calculate appearance values
local bar_height = state_module.get_appearance(state, "bar_height", 28)
local bar_corner_radius = state_module.get_appearance(state, "corner_radius", 0)
local bar_color = parse_color(state_module.get_appearance(state, "bar_color", theme.bar.bg))
local bar_blur_radius = tonumber(state_module.get_appearance(state, "blur_radius", 30))
local clock_font_style = state_module.get_appearance(state, "clock_font_style", "Semibold")
local widget_scale = tonumber(state_module.get_appearance(state, "widget_scale", 1.0)) or 1.0
widget_scale = clamp(widget_scale, 0.85, 1.25)

local widget_corner_radius = state.appearance.widget_corner_radius
if type(widget_corner_radius) ~= "number" then
  if bar_corner_radius and bar_corner_radius > 0 then
    widget_corner_radius = math.max(bar_corner_radius - 1, 4)
  else
    widget_corner_radius = 6
  end
end

local function scaled(value)
  return math.floor(value * widget_scale + 0.5)
end

local icon_font_size = clamp(scaled(16), 12, 20)
local label_font_size = clamp(scaled(14), 11, 18)
local number_font_size = clamp(scaled(14), 11, 20)
local small_font_size = clamp(scaled(13), 10, 16)
local icon_padding = clamp(scaled(4), 3, 8)
local label_padding = clamp(scaled(4), 3, 8)
local item_padding = clamp(scaled(5), 4, 9)
local base_widget_height = math.max(bar_height - 5, 18)
local widget_height = clamp(
  math.floor(base_widget_height * widget_scale + 0.5),
  16,
  math.max(bar_height - 2, base_widget_height + 4)
)

-- Font families (customizable via state.appearance)
local font_icon_family = state_module.get_appearance(state, "font_icon", "Hack Nerd Font")
local font_text_family = state_module.get_appearance(state, "font_text", "Source Code Pro")
local font_numbers_family = state_module.get_appearance(state, "font_numbers", "SF Mono")

-- Settings object
local settings = {
  font = {
    icon = font_icon_family,
    text = font_text_family,
    numbers = font_numbers_family,
    style_map = {
      Regular = "Regular",
      Medium = "Medium",
      Semibold = "Semibold",
      Bold = "Bold",
      Heavy = "Heavy"
    },
    sizes = {
      icon = icon_font_size,
      text = label_font_size,
      numbers = number_font_size,
      small = small_font_size,
    }
  },
  paddings = item_padding
}

-- Build shared context for menus/whichkey/popups
local profile_paths = profile_module.get_paths(user_profile)
local paths = {
  menu_data      = CONFIG_DIR .. "/data",
  workflow_data  = CONFIG_DIR .. "/data/workflow_shortcuts.json",
  rom_doc        = CODE_DIR .. "/docs/workflow/rom-hacking.org",
  yaze           = CODE_DIR .. "/yaze",
  whichkey_plan  = CONFIG_DIR .. "/docs/WHICHKEY_PLAN.md",
  handoff        = CONFIG_DIR .. "/docs/HANDOFF_POPUP_FIXES.md",
  apple_launcher = CONFIG_DIR .. "/bin/open_control_panel.sh",
}
-- Overlay profile-specific paths when provided
if profile_paths then
  for k, v in pairs(profile_paths) do
    paths[k] = v
  end
end

local scripts = {
  menu_action        = CONFIG_DIR .. "/helpers/menu_action",
  set_appearance     = SCRIPTS_DIR .. "/set_appearance.sh",
  space_mode         = PLUGIN_DIR .. "/space_mode.sh",
  logs               = CONFIG_DIR .. "/plugins/bar_logs.sh",
  yabai_control      = YABAI_CONTROL_SCRIPT,
  accessibility      = SCRIPTS_DIR .. "/yabai_accessibility_fix.sh",
  open_control_panel = CONFIG_DIR .. "/bin/open_control_panel.sh",
  halext_menu        = CONFIG_DIR .. "/plugins/halext_menu.sh",
  ssh_sync           = CONFIG_DIR .. "/helpers/ssh_sync.sh",
  ci_status          = CONFIG_DIR .. "/helpers/ci_status.sh",
  cpp_project_switch = CONFIG_DIR .. "/helpers/cpp_project_switch.sh",
}

local helpers = {
  help_center = CONFIG_DIR .. "/build/bin/help_center",
}

local integrations = {
  yaze   = yaze_enabled   and yaze_module   or nil,
  oracle = oracle_enabled and oracle_module or nil,
  emacs  = emacs_enabled  and emacs_module  or nil,
  halext = halext_enabled and halext_module or nil,
}

local menu_context = {
  sbar = sbar,
  theme = theme,
  settings = settings,
  widget_height = widget_height,
  attach_hover = attach_hover,
  subscribe_popup_autoclose = subscribe_popup_autoclose,
  shell_exec = shell_exec,
  call_script = call_script,
  open_path = open_path,
  associated_displays = associated_displays,
  paths = paths,
  scripts = scripts,
  helpers = helpers,
  HOVER_SCRIPT = HOVER_SCRIPT,
  integration_flags = profile_module.get_integration_flags(user_profile),
  integrations = integrations,
}

-- Begin configuration
sbar.begin_config()
sbar.exec("sketchybar --add event space_change >/dev/null 2>&1 || true")
sbar.exec("sketchybar --add event space_mode_refresh >/dev/null 2>&1 || true")
sbar.exec("sketchybar --add event whichkey_toggle >/dev/null 2>&1 || true")

-- Global popup manager (invisible item that handles popup dismissal)
sbar.add("item", "popup_manager", {
  position = "left",
  drawing = false,
  script = POPUP_MANAGER_SCRIPT,
})
-- OPTIMIZED: Reduced delay from 0.3s; small delay avoids startup "item not found" noise
sbar.exec("sleep 0.2; sketchybar --subscribe popup_manager space_change display_changed display_added display_removed system_woke front_app_switched")

-- Bar configuration
sbar.bar({
  position = "top",
  height = bar_height,
  blur_radius = bar_blur_radius,
  color = bar_color,
  margin = 0,
  padding_left = 14,
  padding_right = 14,
  corner_radius = bar_corner_radius,
  y_offset = 0,
  display = "all",
})

-- Update external bar (yabai)
local function update_external_bar()
  local script = string.format("%s/update_external_bar.sh %d", SCRIPTS_DIR, bar_height)
  shell_exec(script)
end
update_external_bar()

-- Defaults
sbar.default({
  updates = "when_shown",
  padding_left = item_padding,
  padding_right = item_padding,
  ignore_association = true,
  associated_display = associated_displays,
  associated_space = "all",
  ["icon.font"] = font_string(settings.font.icon, settings.font.style_map["Bold"], settings.font.sizes.icon),
  ["icon.color"] = theme.WHITE,
  ["icon.padding_left"] = icon_padding,
  ["icon.padding_right"] = icon_padding,
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.text),
  ["label.color"] = theme.WHITE,
  ["label.padding_left"] = label_padding,
  ["label.padding_right"] = label_padding,
  background = {
    color = bar_color,
    corner_radius = widget_corner_radius,
    height = widget_height,
  },
})

-- Render All Menus (System, Workspace, Window)
menu_module.render_all_menus(menu_context)

-- Spaces
local function init_spaces()
  -- OPTIMIZED: Reduced wait loop iterations and delay (was 20 x 0.5s = 10s max, now 10 x 0.2s = 2s max)
  -- Also removed debug logging to /tmp
  local wait_cmd = [[
    path_to_yabai=$(which yabai)
    i=0
    while [ $i -lt 10 ]; do
      "$path_to_yabai" -m query --spaces >/dev/null 2>&1 && break
      sleep 0.2
      i=$((i+1))
    done
    sketchybar --trigger space_change
    sketchybar --trigger space_mode_refresh
  ]]

  sbar.exec(wait_cmd)

  -- Setup signals (these don't need to wait, they just listen)
  if yabai_available() then
    watch_spaces()
  end
end

init_spaces()

print("Setting up WhichKey...")
-- Setup WhichKey after spaces to ensure correct visual order on the left
whichkey_module.setup(menu_context)
print("WhichKey setup complete")

-- Space Mode Indicator
sbar.add("item", "space_mode", {
  position = "left",
  icon = { font = { size = 14.0 } },
  label = { font = { size = 11.0, style = "Bold" } },
  script = PLUGIN_DIR .. "/space_mode.sh",
  click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
  padding_right = 8,
  background = {
    color = "0x00000000",
    corner_radius = widget_corner_radius,
    height = widget_height,
  },
  popup = {
    align = "left",
    background = {
      border_width = 2,
      corner_radius = 6,
      border_color = theme.WHITE,
      color = theme.bar.bg,
      padding_left = 8,
      padding_right = 8
    }
  }
})
-- OPTIMIZED: Reduced delay from 0.3s to 0.1s
sbar.exec("sleep 0.1; sketchybar --subscribe space_mode space_change space_mode_refresh")
sbar.exec("sleep 0.1; sketchybar --set space_mode associated_display=active associated_space=all")
sbar.exec("sketchybar --trigger space_mode_refresh") -- Initial update
subscribe_popup_autoclose("space_mode")
attach_hover("space_mode")

-- Front App indicator (actions handled in control_center)
sbar.add("item", "front_app", {
  position = "left",
  icon = { drawing = true },
  label = { drawing = true },
  script = PLUGIN_DIR .. "/front_app.sh",
  click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
  background = {
    color = "0x00000000",
    corner_radius = widget_corner_radius,
    height = widget_height,
  },
  popup = {
    align = "left",
    background = {
      border_width = 2,
      corner_radius = 6,
      border_color = theme.WHITE,
      color = theme.bar.bg,
      padding_left = 8,
      padding_right = 8
    }
  }
})
-- OPTIMIZED: Reduced delay from 0.3s to 0.1s
sbar.exec("sleep 0.2; sketchybar --subscribe front_app front_app_switched")
subscribe_popup_autoclose("front_app")
attach_hover("front_app")
sbar.exec("sleep 0.1; sketchybar --set front_app associated_display=active associated_space=all")

local function add_front_app_popup_item(id, props)
  local defaults = {
    position = "popup.front_app",
    script = HOVER_SCRIPT,
    ["icon.padding_left"] = 6,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 8,
    ["label.padding_right"] = 8,
    background = { drawing = false },
  }
  for k, v in pairs(props) do
    defaults[k] = v
  end
  sbar.add("item", id, defaults)
end

local font_small = font_string(settings.font.text, settings.font.style_map["Semibold"], settings.font.sizes.small)

local function add_space_mode_popup_item(id, props)
  local defaults = {
    position = "popup.space_mode",
    script = HOVER_SCRIPT,
    ["icon.padding_left"] = 6,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 8,
    ["label.padding_right"] = 8,
    background = { drawing = false },
  }
  for k, v in pairs(props) do
    defaults[k] = v
  end
  sbar.add("item", id, defaults)
end

add_space_mode_popup_item("space_mode.header", {
  icon = "",
  label = "Space Layout",
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
  background = { drawing = false },
})

local layout_actions = {
  { name = "space_mode.float", icon = "󰒄", label = "Float (default)", action = call_script(CONFIG_DIR .. "/plugins/set_space_mode.sh", "current", "float") },
  { name = "space_mode.bsp",   icon = "󰆾", label = "BSP Tiling", action = call_script(CONFIG_DIR .. "/plugins/set_space_mode.sh", "current", "bsp") },
  { name = "space_mode.stack", icon = "󰓩", label = "Stack Tiling", action = call_script(CONFIG_DIR .. "/plugins/set_space_mode.sh", "current", "stack") },
}
for _, entry in ipairs(layout_actions) do
  add_space_mode_popup_item(entry.name, {
    icon = entry.icon,
    label = entry.label,
    click_script = entry.action,
    ["label.font"] = font_small,
  })
end

add_space_mode_popup_item("space_mode.sep", {
  icon = "",
  label = "───────────────",
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Regular"], settings.font.sizes.small),
  ["label.color"] = theme.DARK_WHITE,
  background = { drawing = false },
})

add_space_mode_popup_item("space_mode.window.header", {
  icon = "",
  label = "Window Ops",
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
  background = { drawing = false },
})

local layout_ops = {
  { name = "space_mode.balance", icon = "󰓅", label = "Balance Windows", action = call_script(YABAI_CONTROL_SCRIPT, "balance") },
  { name = "space_mode.rotate",  icon = "󰑞", label = "Rotate Layout", action = call_script(YABAI_CONTROL_SCRIPT, "space-rotate") },
  { name = "space_mode.toggle",  icon = "󱂬", label = "Toggle BSP/Stack", action = call_script(YABAI_CONTROL_SCRIPT, "toggle-layout") },
  { name = "space_mode.flipx",   icon = "󰯌", label = "Flip Horizontal", action = call_script(YABAI_CONTROL_SCRIPT, "space-mirror-x") },
  { name = "space_mode.flipy",   icon = "󰯎", label = "Flip Vertical", action = call_script(YABAI_CONTROL_SCRIPT, "space-mirror-y") },
}
for _, entry in ipairs(layout_ops) do
  add_space_mode_popup_item(entry.name, {
    icon = entry.icon,
    label = entry.label,
    click_script = entry.action,
    ["label.font"] = font_small,
  })
end

add_front_app_popup_item("front_app.header", {
  icon = "",
  label = "Application Controls",
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
  background = { drawing = false },
})

local app_actions = {
  { name = "front_app.show", icon = "󰓇", label = "Bring to Front", action = call_script(FRONT_APP_ACTION_SCRIPT, "show"), shortcut = "⌘⇥" },
  { name = "front_app.hide", icon = "󰘔", label = "Hide App", action = call_script(FRONT_APP_ACTION_SCRIPT, "hide"), shortcut = "⌘H" },
  { name = "front_app.quit", icon = "󰅘", label = "Quit App", action = call_script(FRONT_APP_ACTION_SCRIPT, "quit"), shortcut = "⌘Q" },
  { name = "front_app.force_quit", icon = "󰜏", label = "Force Quit", action = call_script(FRONT_APP_ACTION_SCRIPT, "force-quit") },
}

for _, entry in ipairs(app_actions) do
  add_front_app_popup_item(entry.name, {
    icon = entry.icon,
    label = entry.label,
    click_script = entry.action,
    ["label.font"] = font_small,
  })
end

-- Folded Yabai Menu Items into Front App
add_front_app_popup_item("front_app.yabai.sep1", {
  icon = "",
  label = "───────────────",
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Regular"], settings.font.sizes.small),
  ["label.color"] = theme.DARK_WHITE,
  background = { drawing = false },
})

add_front_app_popup_item("front_app.yabai.status.header", {
  icon = "",
  label = "Space Status",
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
  background = { drawing = false },
})
add_front_app_popup_item("front_app.yabai.status", {
  icon = "",
  label = "…",
  script = PLUGIN_DIR .. "/yabai_status.sh",
  update_freq = 5,
  ["label.font"] = font_small,
})

add_front_app_popup_item("front_app.yabai.mode.header", {
  icon = "",
  label = "Layout Modes",
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
  background = { drawing = false },
})
local mode_actions = {
  { name = "front_app.yabai.float", icon = "󰒄", label = "Float (default)", action = call_script(CONFIG_DIR .. "/plugins/set_space_mode.sh", "current", "float") },
  { name = "front_app.yabai.bsp", icon = "󰆾", label = "BSP Tiling", action = call_script(CONFIG_DIR .. "/plugins/set_space_mode.sh", "current", "bsp") },
  { name = "front_app.yabai.stack", icon = "󰓩", label = "Stack Tiling", action = call_script(CONFIG_DIR .. "/plugins/set_space_mode.sh", "current", "stack") },
}
for _, entry in ipairs(mode_actions) do
  add_front_app_popup_item(entry.name, {
    icon = entry.icon,
    label = entry.label,
    click_script = entry.action,
    ["label.font"] = font_small,
  })
end

add_front_app_popup_item("front_app.yabai.window.header", {
  icon = "",
  label = "Window Management",
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
  background = { drawing = false },
})

local window_actions = {
  { name = "front_app.yabai.balance", icon = "󰓅", label = "Balance Windows", action = call_script(YABAI_CONTROL_SCRIPT, "balance"), shortcut = "⌃⌥B" },
  { name = "front_app.yabai.rotate", icon = "󰑞", label = "Rotate Layout", action = call_script(YABAI_CONTROL_SCRIPT, "space-rotate"), shortcut = "⌃⌥R" },
  { name = "front_app.yabai.toggle", icon = "󱂬", label = "Toggle BSP/Stack", action = call_script(YABAI_CONTROL_SCRIPT, "toggle-layout") },
  { name = "front_app.yabai.flip_x", icon = "󰯌", label = "Flip Horizontal", action = call_script(YABAI_CONTROL_SCRIPT, "space-mirror-x") },
  { name = "front_app.yabai.flip_y", icon = "󰯎", label = "Flip Vertical", action = call_script(YABAI_CONTROL_SCRIPT, "space-mirror-y") },
}
for _, entry in ipairs(window_actions) do
  add_front_app_popup_item(entry.name, {
    icon = entry.icon,
    label = entry.label,
    click_script = entry.action,
    ["label.font"] = font_small,
  })
end

add_front_app_popup_item("front_app.yabai.nav.header", {
  icon = "",
  label = "Space Navigation",
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
  background = { drawing = false },
})

local nav_actions = {
  { name = "front_app.yabai.prev", icon = "󰆽", label = "Previous Space", action = call_script(YABAI_CONTROL_SCRIPT, "space-prev"), shortcut = "⌃⌥←" },
  { name = "front_app.yabai.next", icon = "󰆼", label = "Next Space", action = call_script(YABAI_CONTROL_SCRIPT, "space-next"), shortcut = "⌃⌥→" },
  { name = "front_app.yabai.recent", icon = "󰔰", label = "Recent Space", action = call_script(YABAI_CONTROL_SCRIPT, "space-recent"), shortcut = "⌃⌥⌫" },
  { name = "front_app.yabai.first", icon = "󰆿", label = "First Space", action = call_script(YABAI_CONTROL_SCRIPT, "space-first") },
  { name = "front_app.yabai.last", icon = "󰆾", label = "Last Space", action = call_script(YABAI_CONTROL_SCRIPT, "space-last") },
}
for _, entry in ipairs(nav_actions) do
  add_front_app_popup_item(entry.name, {
    icon = entry.icon,
    label = entry.label,
    click_script = entry.action,
    ["label.font"] = font_small,
  })
end

-- OPTIMIZED: Reduced event subscriptions - removed redundant display events (already handled by popup_manager)
sbar.exec("sleep 0.2; sketchybar --subscribe front_app.yabai.status space_change yabai_status_refresh")

-- Spaces: Refresh after all left items are added
-- This allows spaces to be appended to the end of the left stack
refresh_spaces()
if yabai_available() then
  watch_spaces()
end
shell_exec("sketchybar --trigger space_change")
shell_exec("sketchybar --trigger space_mode_refresh")

-- Create widget factory
local widget_factory = widgets_module.create_factory(sbar, theme, settings, state)

-- Clock widget (uses C component if available, falls back to shell script)
widget_factory.create_clock({
  icon = "󰥔",
  script = compiled_script("clock_widget", PLUGIN_DIR .. "/clock.sh"),
  update_freq = 30,  -- OPTIMIZED: Update every 30 seconds (was 1) - reduces CPU by 97%
  click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
  popup = {
    align = "right",
    background = {
      border_width = 2,
      corner_radius = 6,
      border_color = theme.WHITE,
      color = theme.bar.bg,
      padding_left = 12,
      padding_right = 12
    }
  }
})
subscribe_popup_autoclose("clock")
attach_hover("clock")

-- Calendar popup items
local calendar_items = {
  {
    name = "clock.calendar.header",
    icon = "",
    script = PLUGIN_DIR .. "/calendar.sh",
    update_freq = 1800,
    font_style = "Semibold",
    color = theme.LAVENDER,
    ["icon.font"] = font_string(settings.font.icon, settings.font.style_map["Bold"], settings.font.sizes.small)
  },
  {
    name = "clock.calendar.weekdays",
    icon = "",
    font_style = "Bold",
    color = theme.DARK_WHITE
  },
}

for i = 1, 6 do
  table.insert(calendar_items, {
    name = string.format("clock.calendar.week%d", i),
    icon = "",
    font_style = "Regular",
    color = theme.WHITE
  })
end

table.insert(calendar_items, {
  name = "clock.calendar.summary",
  icon = "",
  font_style = "Semibold",
  color = theme.YELLOW
})

table.insert(calendar_items, {
  name = "clock.calendar.footer",
  icon = "",
  font_style = "Regular",
  color = theme.DARK_WHITE
})

for _, item in ipairs(calendar_items) do
  local is_header = item.name == "clock.calendar.header"
  local is_summary = item.name == "clock.calendar.summary"
  local is_footer = item.name == "clock.calendar.footer"

  -- Use monospace font for calendar grid
  local item_font = settings.font.numbers
  if is_header or is_summary or is_footer then
    item_font = settings.font.text
  end

  local opts = {
    position = "popup.clock",
    icon = item.icon or "",
    label = "",
    ["label.font"] = font_string(
      item_font,
      settings.font.style_map[item.font_style or "Regular"] or settings.font.style_map["Regular"],
      is_header and settings.font.sizes.text or settings.font.sizes.small
    ),
    ["label.color"] = item.color or theme.WHITE,
    ["icon.font"] = item["icon.font"] or font_string(settings.font.icon, settings.font.style_map["Bold"], settings.font.sizes.small),
    ["icon.drawing"] = item.icon ~= "" and true or false,
    ["label.padding_left"] = 6,
    ["label.padding_right"] = 6,
    background = { drawing = false },
  }
  if item.script then
    opts.script = item.script
  end
  if item.update_freq then
    opts.update_freq = item.update_freq
  end
  sbar.add("item", item.name, opts)
end

-- System Info widget
widget_factory.create_system_info({
  script = PLUGIN_DIR .. "/system_info.sh",
  update_freq = 45,  -- Reduce refresh rate to lower CPU
  show_cpu = false,  -- Disable CPU row to save resources
})
subscribe_popup_autoclose("system_info")
attach_hover("system_info")

-- System info popup items
local info_flags = state.system_info_items or {}
local function info_enabled(key)
  local value = info_flags[key]
  if value == nil then
    return true
  end
  return value
end

local system_info_items = {}
if info_enabled("cpu") then
  table.insert(system_info_items, { name = "system_info.cpu", icon = "", label = "CPU …" })
end
if info_enabled("mem") then
  table.insert(system_info_items, { name = "system_info.mem", icon = "", label = "Mem …" })
end
if info_enabled("disk") then
  table.insert(system_info_items, { name = "system_info.disk", icon = "", label = "Disk …" })
end
if info_enabled("net") then
  table.insert(system_info_items, { name = "system_info.net", icon = "󰖩", label = "Wi-Fi …" })
end

-- Add system tools
table.insert(system_info_items, { name = "system_info.activity", icon = "󰨇", label = "Activity Monitor", action = "open -a 'Activity Monitor'" })
table.insert(system_info_items, { name = "system_info.settings", icon = "", label = "System Settings", action = "open -a 'System Settings'" })

-- System Info menu is now informational only
-- Docs and actions moved to Apple menu or removed per user request
-- if info_enabled("docs") then
--   table.insert(system_info_items, { name = "system_info.docs.tasks", icon = "󰩹", label = "Tasks.org", action = open_path(CODE_DIR .. "/docs/workflow/tasks.org") })
--   table.insert(system_info_items, { name = "system_info.docs.rom", icon = "󰊕", label = "ROM Workflow", action = open_path(CODE_DIR .. "/docs/workflow/rom-hacking.org") })
--   table.insert(system_info_items, { name = "system_info.docs.dev", icon = "", label = "Dev Workflow", action = open_path(CODE_DIR .. "/docs/workflow/development.org") })
-- end
-- if info_enabled("actions") then
--   table.insert(system_info_items, { name = "system_info.action.reload", icon = "󰑐", label = "Reload Bar", action = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload" })
--   table.insert(system_info_items, { name = "system_info.action.logs", icon = "󰍛", label = "Open Logs", action = open_path("/opt/homebrew/var/log/sketchybar") })
--   table.insert(system_info_items, { name = "system_info.action.config", icon = "󰒓", label = "Edit Config", action = "open -a 'Visual Studio Code' " .. CONFIG_DIR })
--   table.insert(system_info_items, { name = "system_info.action.help", icon = "󰋖", label = "Help & Tips", action = string.format("open -a 'Preview' %q", CONFIG_DIR .. "/README.md") })
-- end

for _, item in ipairs(system_info_items) do
  local opts = {
    position = "popup.system_info",
    icon = item.icon,
    label = item.label,
    script = HOVER_SCRIPT,
  }
  if item.action then
    opts.click_script = item.action .. "; sketchybar -m --set system_info popup.drawing=off"
  end
  sbar.add("item", item.name, opts)
  attach_hover(item.name)
end

sbar.add("bracket", { "clock", "system_info" }, {
  background = {
    color = "0x40111111",
    corner_radius = math.max(widget_corner_radius, 2),
    height = math.max(widget_height + 2, 18)
  }
})

-- Volume widget (click to open Sound preferences)
widget_factory.create_volume({
  script = PLUGIN_DIR .. "/volume.sh",
  click_script = PLUGIN_DIR .. "/volume_click.sh",
  popup = {
    align = "right",
    background = {
      border_width = 2,
      corner_radius = 6,
      border_color = theme.WHITE,
      color = theme.bar.bg,
      padding_left = 8,
      padding_right = 8
    }
  }
})
sbar.exec("sleep 0.1; sketchybar --subscribe volume volume_change")
subscribe_popup_autoclose("volume")
attach_hover("volume")

local function add_volume_popup_item(id, props)
  local defaults = {
    position = "popup.volume",
    script = HOVER_SCRIPT,
    ["icon.padding_left"] = 6,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 8,
    ["label.padding_right"] = 8,
    background = { drawing = false },
  }
  for k, v in pairs(props) do
    defaults[k] = v
  end
  sbar.add("item", id, defaults)
end

add_volume_popup_item("volume.header", {
  icon = "",
  label = "Volume Controls",
  ["label.font"] = font_string(settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
  background = { drawing = false },
})

local volume_actions = {
  { name = "volume.mute", icon = "󰖁", label = "Toggle Mute", action = "osascript -e 'set volume output muted not (output muted of (get volume settings))'" },
  { name = "volume.0", icon = "󰕿", label = "0%", action = "osascript -e 'set volume output volume 0'" },
  { name = "volume.10", icon = "󰕿", label = "10%", action = "osascript -e 'set volume output volume 10'" },
  { name = "volume.30", icon = "󰖀", label = "30%", action = "osascript -e 'set volume output volume 30'" },
  { name = "volume.50", icon = "󰖀", label = "50%", action = "osascript -e 'set volume output volume 50'" },
  { name = "volume.80", icon = "󰕾", label = "80%", action = "osascript -e 'set volume output volume 80'" },
  { name = "volume.100", icon = "󰕾", label = "100%", action = "osascript -e 'set volume output volume 100'" },
  { name = "volume.settings", icon = "", label = "Sound Settings", action = "open -b com.apple.systempreferences /System/Library/PreferencePanes/Sound.prefPane" },
}

for _, entry in ipairs(volume_actions) do
  add_volume_popup_item(entry.name, {
    icon = entry.icon,
    label = entry.label,
    click_script = entry.action,
    ["label.font"] = font_small,
  })
end

-- Battery widget
widget_factory.create_battery({
  script = PLUGIN_DIR .. "/battery.sh '" .. theme.GREEN .. "' '" .. theme.YELLOW .. "' '" .. theme.RED .. "' '" .. theme.BLUE .. "'",
  update_freq = 120,
})
sbar.exec("sketchybar --subscribe battery system_woke power_source_change")
attach_hover("battery")

-- Trigger initial updates for reactive widgets (batched for performance)
sbar.exec("sketchybar --trigger volume_change && sketchybar --update volume && sketchybar --update battery")

-- End configuration
sbar.end_config()

print("main.lua finished loading!")
sbar.event_loop()
