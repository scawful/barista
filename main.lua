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
local function expand_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  end
  return path
end

local function resolve_scripts_dir(state)
  local override = os.getenv("BARISTA_SCRIPTS_DIR")
  if override and override ~= "" then
    return expand_path(override)
  end
  if state and type(state.paths) == "table" then
    local candidate = state.paths.scripts_dir or state.paths.scripts
    candidate = expand_path(candidate)
    if candidate and candidate ~= "" then
      return candidate
    end
  end
  local config_scripts = CONFIG_DIR .. "/scripts"
  local probe = io.open(config_scripts .. "/yabai_control.sh", "r")
  if probe then
    probe:close()
    return config_scripts
  end
  local legacy_scripts = HOME .. "/.config/scripts"
  local legacy_probe = io.open(legacy_scripts .. "/yabai_control.sh", "r")
  if legacy_probe then
    legacy_probe:close()
    return legacy_scripts
  end
  return config_scripts
end

local function resolve_code_dir(state)
  local override = os.getenv("BARISTA_CODE_DIR")
  if override and override ~= "" then
    return expand_path(override)
  end
  if state and type(state.paths) == "table" then
    local candidate = state.paths.code_dir or state.paths.code
    candidate = expand_path(candidate)
    if candidate and candidate ~= "" then
      return candidate
    end
  end
  return HOME .. "/src"
end

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

local CODE_DIR = resolve_code_dir(state)

local SCRIPTS_DIR = resolve_scripts_dir(state)

-- Scripts
local YABAI_CONTROL_SCRIPT = SCRIPTS_DIR .. "/yabai_control.sh"
local SKHD_CONTROL_SCRIPT = SCRIPTS_DIR .. "/skhd_control.sh"
local FRONT_APP_ACTION_SCRIPT = SCRIPTS_DIR .. "/front_app_action.sh"

local function integration_enabled(name)
  local entry = state_module.get_integration(state, name)
  if type(entry) ~= "table" then
    return false
  end
  if entry.enabled == nil then
    return false
  end
  return entry.enabled ~= false
end

local yaze_enabled = integration_enabled("yaze")
local oracle_enabled = integration_enabled("oracle")
local emacs_enabled = integration_enabled("emacs")
local halext_enabled = integration_enabled("halext")
local halext_module = halext_enabled and require("halext") or nil
local cortex_enabled = integration_enabled("cortex")
local cortex_module = nil
if cortex_enabled then
  local ok, mod = pcall(require, "cortex")
  if ok then
    cortex_module = mod
  else
    print("Barista: cortex integration enabled but module not found")
  end
end

-- Control Center module (replaces/augments cortex widget)
local control_center_enabled = integration_enabled("control_center") or cortex_enabled
local control_center_module = nil
if control_center_enabled then
  local ok, mod = pcall(require, "control_center")
  if ok then
    control_center_module = mod
  else
    print("Barista: control_center module not found, falling back to cortex")
  end
end

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

local function open_url(url)
  return string.format("open %q", url)
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

local function icon_for(name, fallback)
  local from_state = safe_icon(state_module.get_icon(state, name, nil))
  if type(from_state) == "string" and from_state ~= "" then
    return from_state
  end
  local from_manager = safe_icon(icon_manager.get_char(name, nil))
  if type(from_manager) == "string" and from_manager ~= "" then
    return from_manager
  end
  local from_icons = safe_icon(icons_module.find(name))
  if type(from_icons) == "string" and from_icons ~= "" then
    return from_icons
  end
  return fallback or ""
end

_G.icon_for = icon_for

local function env_prefix(vars)
  local keys = {}
  for key, value in pairs(vars or {}) do
    if type(value) == "string" and value ~= "" then
      table.insert(keys, key)
    end
  end
  if #keys == 0 then
    return ""
  end
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    table.insert(parts, string.format("%s=%q", key, vars[key]))
  end
  return "env " .. table.concat(parts, " ") .. " "
end

local function attach_hover(name)
  -- Hover script is now integrated into the widgets' own scripts for better performance
  -- Small delay avoids "item not found" when subscribing right after creation
  shell_exec(string.format("sleep 0.1; sketchybar --subscribe %s mouse.entered mouse.exited", name))
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
-- mirrors render instead of relying on the "all" sentinel mask.
local function get_associated_displays()
  local function read_display_list(cmd)
    local handle = io.popen(cmd)
    if not handle then
      return nil
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
      return nil
    end
    return table.concat(targets, ",")
  end

  local list = read_display_list([[sketchybar --query displays 2>/dev/null | jq -r '.[]."arrangement-id"']])
  if list then
    return list
  end

  if yabai_available() then
    list = read_display_list([[yabai -m query --displays 2>/dev/null | jq -r '.[].index']])
    if list then
      return list
    end
  end

  return "active"
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
  local change_action = "sketchybar --trigger space_change; sketchybar --trigger space_mode_refresh"
  
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
  config_dir     = CONFIG_DIR,
  code_dir       = CODE_DIR,
  menu_data      = CONFIG_DIR .. "/data",
  workflow_data  = CONFIG_DIR .. "/data/workflow_shortcuts.json",
  rom_doc        = CODE_DIR .. "/docs/workflow/rom-hacking.org",
  yaze           = CODE_DIR .. "/yaze",
  afs           = CODE_DIR .. "/afs",
  cortex         = CODE_DIR .. "/cortex",
  halext_org     = CODE_DIR .. "/halext-org",
  halext_windows = CODE_DIR .. "/halext-org/docs/BACKGROUND_AGENTS.md",
  whichkey_plan  = CONFIG_DIR .. "/docs/WHICHKEY_PLAN.md",
  readme         = CONFIG_DIR .. "/README.md",
  sharing        = CONFIG_DIR .. "/docs/dev/SHARING.md",
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
  cortex = cortex_module,
  control_center = control_center_module,
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
  open_url = open_url,
  icon_for = icon_for,
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

-- Front App indicator
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

-- Front App popup items
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


-- Spaces: Refresh after all left items are added
-- This allows spaces to be appended to the end of the left stack
refresh_spaces()
if yabai_available() then
  watch_spaces()
end
shell_exec("sketchybar --trigger space_change")
shell_exec("sketchybar --trigger space_mode_refresh")
shell_exec(string.format("sleep 1.2; CONFIG_DIR=%s %s/refresh_spaces.sh", CONFIG_DIR, PLUGIN_DIR))

-- Create widget factory
local widget_factory = widgets_module.create_factory(sbar, theme, settings, state)

-- Control Center widget (left side, replaces space_mode)
local control_center_item_name = nil
if control_center_module then
  local cc_widget = control_center_module.create_widget({
    position = "left",  -- Left side near front_app
    icon_font = { family = settings.font.icon, size = settings.font.sizes.icon },
    label_font = font_string(settings.font.text, settings.font.style_map["Bold"], 11),
    label_color = "0xffcdd6f4",
    show_label = true,
    update_freq = 30,
    script_path = PLUGIN_DIR .. "/control_center.sh",
    height = widget_height,
  })

  control_center_item_name = cc_widget.name or "control_center"
  cc_widget.name = nil
  sbar.add("item", control_center_item_name, cc_widget)

  -- Position before front_app (delay to ensure front_app exists)
  sbar.exec("sleep 0.3; sketchybar --move control_center before front_app 2>/dev/null || true")

  -- Prime the widget immediately
  if cc_widget.script and cc_widget.script ~= "" then
    sbar.exec(string.format("NAME=%s %s", control_center_item_name, cc_widget.script))
  end

  -- Add popup items for the control center
  local cc_popup_items = control_center_module.create_popup_items(sbar, theme, font_string, settings)
  for _, popup_item in ipairs(cc_popup_items) do
    local item_name = popup_item.name
    popup_item.name = nil
    sbar.add("item", item_name, popup_item)
  end

  -- Subscribe to relevant events (includes space_mode_refresh for layout changes)
  sbar.exec("sleep 0.1; sketchybar --subscribe control_center mouse.entered mouse.exited space_change space_mode_refresh system_woke")
  subscribe_popup_autoclose("control_center")
  attach_hover("control_center")
  sbar.exec("sleep 0.1; sketchybar --set control_center associated_display=active associated_space=all")

  -- Visual grouping: Control Center & Front App on left
  sbar.add("bracket", { "control_center", "front_app" }, {
    background = {
      color = "0x30313244",
      corner_radius = math.max(widget_corner_radius, 4),
      height = math.max(widget_height + 2, 18),
      border_width = 1,
      border_color = "0x20585b70",
    }
  })
end

-- Clock widget (uses C component if available, falls back to shell script)
widget_factory.create_clock({
  icon = icon_for("clock", "󰥔"),
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
local system_info_env = env_prefix({
  BARISTA_ICON_CPU = state_module.get_icon(state, "cpu", ""),
  BARISTA_ICON_MEM = state_module.get_icon(state, "memory", ""),
  BARISTA_ICON_DISK = state_module.get_icon(state, "disk", ""),
  BARISTA_ICON_WIFI = state_module.get_icon(state, "wifi", ""),
  BARISTA_ICON_WIFI_OFF = state_module.get_icon(state, "wifi_off", ""),
})
local system_info_script = system_info_env .. PLUGIN_DIR .. "/system_info.sh"
widget_factory.create_system_info({
  script = system_info_script,
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
if info_enabled("mem") then
  table.insert(system_info_items, { name = "system_info.mem", icon = "", label = "Mem …" })
end
if info_enabled("disk") then
  table.insert(system_info_items, { name = "system_info.disk", icon = "", label = "Disk …" })
end
if info_enabled("net") then
  table.insert(system_info_items, { name = "system_info.net", icon = icon_for("wifi", "󰖩"), label = "Wi-Fi …" })
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

-- Visual grouping: Clock & System Info
sbar.add("bracket", { "clock", "system_info" }, {
  background = {
    color = "0x30313244",  -- Subtle surface color for grouping
    corner_radius = math.max(widget_corner_radius, 4),
    height = math.max(widget_height + 2, 18),
    border_width = 1,
    border_color = "0x20585b70",  -- Very subtle border
  }
})

-- Volume widget (click to open Sound preferences)
local volume_env = env_prefix({
  BARISTA_ICON_VOLUME = state_module.get_icon(state, "volume", ""),
})
local volume_script = volume_env .. PLUGIN_DIR .. "/volume.sh"
widget_factory.create_volume({
  script = volume_script,
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
local battery_env = env_prefix({
  BARISTA_ICON_BATTERY = state_module.get_icon(state, "battery", ""),
})
widget_factory.create_battery({
  script = battery_env .. PLUGIN_DIR .. "/battery.sh '" .. theme.GREEN .. "' '" .. theme.YELLOW .. "' '" .. theme.RED .. "' '" .. theme.BLUE .. "'",
  update_freq = 120,
})
sbar.exec("sketchybar --subscribe battery system_woke power_source_change")
attach_hover("battery")

-- Visual grouping: Volume & Battery
sbar.add("bracket", { "volume", "battery" }, {
  background = {
    color = "0x30313244",
    corner_radius = math.max(widget_corner_radius, 4),
    height = math.max(widget_height + 2, 18),
    border_width = 1,
    border_color = "0x20585b70",
  }
})

-- Trigger initial updates for reactive widgets (batched for performance)
sbar.exec("sketchybar --trigger volume_change && sketchybar --update volume && sketchybar --update battery")

-- End configuration
sbar.end_config()

print("main.lua finished loading!")
sbar.event_loop()
