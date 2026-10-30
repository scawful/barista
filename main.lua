local STARTUP_TRACE = os.getenv("BARISTA_STARTUP_TRACE") or rawget(_G, "BARISTA_STARTUP_TRACE")
local RELOAD_START_MS = tonumber(rawget(_G, "BARISTA_RELOAD_START_MS"))

local function trace_startup(message)
  if not STARTUP_TRACE or STARTUP_TRACE == "" then
    return
  end
  local file = io.open(STARTUP_TRACE, "a")
  if not file then
    return
  end
  file:write(os.date("%Y-%m-%d %H:%M:%S "), message, "\n")
  file:close()
end

trace_startup("main:file_loaded")

-- SketchyBar Configuration
-- Modular, modern macOS status bar with Yabai integration

trace_startup("main:require_sketchybar")
local sbar = require("sketchybar")
trace_startup("main:require_theme")
local theme = require("theme")
trace_startup("main:require_utf8")
local utf8 = require("utf8")
local unpack = table.unpack or _G.unpack

trace_startup("main:start")

-- Load modules
local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
package.path = package.path .. ";" .. CONFIG_DIR .. "/modules/?.lua"
package.path = package.path .. ";" .. CONFIG_DIR .. "/modules/integrations/?.lua"
package.path = package.path .. ";" .. CONFIG_DIR .. "/?.lua"

-- Core modules
local state_module   = require("state")
local profile_module = require("profile")
local bar_config     = require("bar_config")
local icons_module   = require("icons")
local icon_manager   = require("icon_manager")
local shortcuts      = require("shortcuts")
local widgets_module = require("widgets")
local menu_module    = require("menu")
local yaze_module    = require("yaze")
local oracle_module  = require("oracle")
local music_module   = require("music")
local emacs_module   = require("emacs")

-- Extracted utility modules
local shell_utils      = require("shell_utils")
local paths_module     = require("paths")
local binary_resolver  = require("binary_resolver")
local runtime_daemon   = require("runtime_daemon")
local runtime_startup  = require("runtime_startup")
local ui_builder       = require("ui_builder")
local submenu_registry = require("submenu_registry")
local post_config_queue = runtime_startup.new_post_config_queue()
local POPUP_TOPOLOGY_TOKEN = submenu_registry.new_topology_token()
if type(shortcuts.set_popup_topology_token) == "function" then
  shortcuts.set_popup_topology_token(POPUP_TOPOLOGY_TOKEN)
end

local function enqueue_post_config_command(command, opts)
  return post_config_queue:enqueue_command(command, opts)
end

local function report_native_delay_error(err)
  print("Barista: native startup delay unavailable; running queued actions immediately: " .. tostring(err))
end

local function report_post_config_action_error(kind, err)
  print("Barista: post-config " .. tostring(kind) .. " failed; continuing startup: " .. tostring(err))
end

-- Initialize component switcher for C/Lua hybrid architecture
local component_switcher = require("component_switcher")

-- Runtime backend selection: environment overrides state, which lets managed
-- machines persist a Lua-only fallback without depending on shell env.
local runtime_backend = binary_resolver.resolve_runtime_backend(
  binary_resolver.read_runtime_backend_from_state(CONFIG_DIR)
)
local LUA_ONLY = runtime_backend == "lua"
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

local function publish_runtime_marker_or_warn(mode)
  local ok, err = binary_resolver.ensure_resolved_runtime_backend(CONFIG_DIR, mode)
  if not ok then
    print("Barista: unable to publish resolved runtime backend: " .. tostring(err))
  end
end

if LUA_ONLY then
  publish_runtime_marker_or_warn("lua")
end

component_switcher.init()
component_switcher.set_mode(LUA_ONLY and "lua" or "auto")

if not LUA_ONLY and c_bridge then
  c_bridge.init()
else
  c_bridge = c_bridge or { init = function() end }
  if runtime_backend == "lua" then
    print("Barista: runtime_backend=lua; running in Lua-only mode")
  else
    print("Barista: running in Lua-only mode (no compiled helpers)")
  end
end

-- Import existing icons into icon_manager for backwards compatibility
icon_manager.import_from_module(icons_module)

-- Resolve paths
local PLUGIN_DIR = CONFIG_DIR .. "/plugins"
local EVENT_DIR  = CONFIG_DIR .. "/helpers/event_providers"

-- Load state and profile
local state = state_module.load()
local user_config_path = CONFIG_DIR .. "/barista_config.lua"

local function load_user_config(path)
  local chunk = loadfile(path)
  if not chunk then
    return nil
  end

  local ok, user_config = pcall(chunk)
  if not ok then
    print("Warning: Error executing barista_config.lua: " .. tostring(user_config))
    return nil
  end

  if type(user_config) == "table" then
    return user_config
  end

  print("Warning: barista_config.lua did not return a table")
  return nil
end

local user_config = load_user_config(user_config_path)
local profile_name = profile_module.get_selected_profile(state, { config = user_config })
local user_profile = profile_module.load(profile_name)

if user_profile then
  state = profile_module.merge_config(state, user_profile)
  print("Loaded profile: " .. user_profile.name)
end

-- Load user configuration overrides if they exist
if user_config then
  print("Applying user configuration from barista_config.lua")
  local function merge_tables(target, source)
    for k, v in pairs(source) do
      if type(v) == "table" and type(target[k]) == "table" then
        merge_tables(target[k], v)
      else
        target[k] = v
      end
    end
  end
  merge_tables(state, user_config)
end

-- Resolve directories and binaries
local CODE_DIR    = paths_module.resolve_code_dir(state)
local SCRIPTS_DIR = paths_module.resolve_scripts_dir(CONFIG_DIR, state)

local SKETCHYBAR_BIN = binary_resolver.resolve_sketchybar_bin()
local YABAI_BIN      = binary_resolver.resolve_yabai_bin()

-- The Barista SketchyBar fork draws background.hover_color itself, so hover
-- needs no event script, and it can stretch popup rows to the menu width.
-- appearance.native_hover = false keeps the scripts and content-width rows.
local function detect_native_features()
  local setting = state_module.get_appearance(state, "native_hover", "auto")
  if setting == false or setting == "off" then return false, false end
  if setting == true or setting == "on" then return true, true end
  -- A busy server can answer with nothing, so ask twice before giving up.
  for _ = 1, 2 do
    local handle = io.popen(string.format("%q --query defaults 2>/dev/null", SKETCHYBAR_BIN))
    if not handle then return false, false end
    local output = handle:read("*a") or ""
    handle:close()
    if output ~= "" then
      return output:find('"hover_color"', 1, true) ~= nil,
        output:find('"stretch"', 1, true) ~= nil
    end
  end
  return false, false
end
local NATIVE_HOVER, POPUP_STRETCH = detect_native_features()
-- Shell plugins read this marker instead of querying SketchyBar themselves.
do
  local marker = io.open(CONFIG_DIR .. "/cache/native_hover", "w")
  if not marker then
    -- First run: cache/ does not exist yet, and later markers need it too.
    os.execute(string.format("mkdir -p %q", CONFIG_DIR .. "/cache"))
    marker = io.open(CONFIG_DIR .. "/cache/native_hover", "w")
  end
  if marker then
    marker:write(NATIVE_HOVER and "1\n" or "0\n")
    marker:close()
  end
end

local POST_CONFIG_DELAY = 1.0
local SPACE_POST_CONFIG_DELAY = 0.2
local SPACE_STARTUP_SYNC_DELAY = 0.8
local NET_INTERFACE = os.getenv("SKETCHYBAR_NET_INTERFACE") or "en0"

-- Convenience wrappers that close over resolved state
local function compiled_script(binary_name, fallback)
  return binary_resolver.compiled_script(CONFIG_DIR, LUA_ONLY, binary_name, fallback)
end

local HOVER_SCRIPT         = compiled_script("popup_hover",    PLUGIN_DIR .. "/popup_hover.sh")
local POPUP_ANCHOR_SCRIPT  = compiled_script("popup_anchor",   PLUGIN_DIR .. "/popup_anchor.sh")
local SUBMENU_HOVER_SCRIPT = compiled_script("submenu_hover",  PLUGIN_DIR .. "/submenu_hover.sh")
local POPUP_MANAGER_SCRIPT = compiled_script("popup_manager",  PLUGIN_DIR .. "/popup_manager.sh")
local POPUP_SWITCH_SCRIPT  = binary_resolver.resolve_popup_switch(
  CONFIG_DIR,
  LUA_ONLY,
  PLUGIN_DIR .. "/popup_manager.sh"
)
local POPUP_MANAGER_SCRIPT_CMD = shell_utils.env_prefix({
  BARISTA_SKETCHYBAR_BIN = SKETCHYBAR_BIN,
  DISMISS_ON_APP_SWITCH = "0",
}) .. POPUP_MANAGER_SCRIPT
local POPUP_GUARD_SCRIPT   = compiled_script("popup_guard",    PLUGIN_DIR .. "/popup_guard.sh")
local WIDGET_MANAGER_BIN   = compiled_script("widget_manager", "")
local SPACE_VISUALS_SCRIPT = PLUGIN_DIR .. "/space_visuals.sh"
local STATS_BIN            = CONFIG_DIR .. "/bin/barista-stats.sh"
local RUNTIME_CONTEXT_SCRIPT = SCRIPTS_DIR .. "/runtime_context.sh"
local SPACE_VISUAL_AUTHORITATIVE_MARKER =
  CONFIG_DIR .. "/cache/space_visuals/last_authoritative_refresh_ms"
local SPACE_VISUAL_SELECTED_CONTEXT =
  CONFIG_DIR .. "/cache/space_visuals/last_selected_context"
local SPACE_VISUAL_LEGACY_SELECTION =
  CONFIG_DIR .. "/cache/space_visuals/last_selected_space"

-- Startup must not combine a previous bar generation's selection context with
-- a new authoritative marker. The first early active event will therefore
-- perform a full visual pass until this runtime publishes its own context.
os.remove(SPACE_VISUAL_AUTHORITATIVE_MARKER)
os.remove(SPACE_VISUAL_SELECTED_CONTEXT)
os.remove(SPACE_VISUAL_LEGACY_SELECTION)

-- Yabai availability (cached)
local yabai_available_cache = nil
local function yabai_available()
  if yabai_available_cache == nil then
    if not YABAI_BIN or YABAI_BIN == "" then
      YABAI_BIN = binary_resolver.resolve_yabai_bin()
    end
    yabai_available_cache = (YABAI_BIN ~= nil and YABAI_BIN ~= "")
  end
  return yabai_available_cache
end

local WINDOW_MANAGER_MODE = binary_resolver.resolve_window_manager_mode(state_module, state)

-- Icon helpers
local function safe_icon(value)
  if type(value) ~= "string" then return nil end
  local ok = pcall(function() utf8.len(value) end)
  return ok and value or nil
end

local function icon_for(name, fallback)
  local from_state = safe_icon(state_module.get_icon(state, name, nil))
  if type(from_state) == "string" and from_state ~= "" then return from_state end
  local from_manager = safe_icon(icon_manager.get_char(name, nil))
  if type(from_manager) == "string" and from_manager ~= "" then return from_manager end
  local from_icons = safe_icon(icons_module.find(name))
  if type(from_icons) == "string" and from_icons ~= "" then return from_icons end
  return fallback or ""
end

_G.icon_for = icon_for

-- Integration flags
local function integration_enabled(name)
  local entry = state_module.get_integration(state, name)
  if type(entry) ~= "table" then return false end
  if entry.enabled == nil then return false end
  return entry.enabled ~= false
end

local yaze_enabled   = integration_enabled("yaze")
local oracle_enabled = integration_enabled("oracle")
local music_enabled  = integration_enabled("music")
local emacs_enabled  = integration_enabled("emacs")
local halext_enabled = integration_enabled("halext")
local halext_module  = halext_enabled and require("halext") or nil

local premia_enabled = integration_enabled("premia")
local premia_module  = nil
if premia_enabled then
  local ok, mod = pcall(require, "premia")
  if ok then premia_module = mod
  else print("Barista: premia integration enabled but module not found") end
end

local control_center_enabled = integration_enabled("control_center")
local control_center_module = nil
if control_center_enabled then
  local ok, mod = pcall(require, "control_center")
  if ok then control_center_module = mod
  else print("Barista: control_center module not found") end
end
local control_center_item_name = nil
if control_center_module and type(control_center_module.get_item_name) == "function" then
  control_center_item_name = control_center_module.get_item_name({
    state = state,
    config_dir = CONFIG_DIR,
  })
elseif control_center_module then
  control_center_item_name = "control_center"
end
local widget_daemon_enabled = runtime_daemon.should_enable_widget_daemon(state, {
  binary_path = WIDGET_MANAGER_BIN,
  lua_only = LUA_ONLY,
})

local function direct_popup_toggle(item_name, opts)
  return ui_builder.toggle(item_name, {
    sketchybar_bin = SKETCHYBAR_BIN,
    popup_manager_script = POPUP_SWITCH_SCRIPT,
    popup_topology_token = POPUP_TOPOLOGY_TOKEN,
    popup_scope = opts and opts.origin == "submenu" and "submenu" or nil,
  })
end

local function popup_toggle_action(item_name, opts)
  return direct_popup_toggle(item_name, opts)
end

-- Hover helpers
local function enqueue_hover_subscription(name)
  return post_config_queue:enqueue_command(
    string.format("sleep %.1f; %s --subscribe %s mouse.entered mouse.exited", POST_CONFIG_DELAY, SKETCHYBAR_BIN, name),
    { background = true, dedupe_key = "hover:" .. tostring(name) }
  )
end

-- Set once the bar config is computed.
local native_row_background = nil

local function attach_hover(name)
  if NATIVE_HOVER then
    if native_row_background then
      sbar.set(name, { background = native_row_background })
    end
    return
  end
  enqueue_hover_subscription(name)
end

local function subscribe_popup_autoclose(name)
  -- Do not subscribe popup anchors to mouse.exited.global by default. On the
  -- live bar, SketchyBar can emit a global-exit event during/just after a
  -- click as focus moves between the bar window and the popup surface; that
  -- makes the popup appear to ignore clicks by opening and immediately closing.
  -- Keep hover enter/exit for visual feedback and let explicit second-click,
  -- popup actions, and space/display/wake events dismiss popups. Native hover
  -- needs neither event.
  if NATIVE_HOVER then return end
  enqueue_hover_subscription(name)
end

-- Spaces module
local spaces_module = require("spaces")
local space_fns = spaces_module.create(
  CONFIG_DIR,
  PLUGIN_DIR,
  SKETCHYBAR_BIN,
  YABAI_BIN,
  shell_utils.shell_exec,
  yabai_available,
  LUA_ONLY
)
local associated_displays = space_fns.get_associated_displays()
print("Associated displays target: " .. associated_displays)
local associated_spaces = space_fns.get_associated_spaces()
print("Associated spaces target: " .. associated_spaces)

-- Bar appearance from bar_config module
local bc = bar_config.compute(state, theme, state_module, associated_displays)
-- plugins/simple_spaces.sh draws the space chips; this marker gives them the
-- widget chips' height, radius, and corners without a query.
do
  local marker = io.open(CONFIG_DIR .. "/cache/chip_style", "w")
  if marker then
    marker:write(string.format("%d %d %s\n",
      math.floor(bc.widget_height), math.floor(bc.widget_corner_radius),
      NATIVE_HOVER and bc.widget_corners or "all"))
    marker:close()
  end
end
if NATIVE_HOVER then
  -- Every popup, submenus included, inherits this from the defaults.
  bc.defaults["popup.background.corners"] = bc.popup_corners
  if POPUP_STRETCH then bc.defaults["popup.stretch"] = "on" end
  native_row_background = { hover_color = bc.hover_color }
  -- Every clickable popup row highlights under the pointer; native hover
  -- costs no script, so rows need not opt in with hover = true.
  local style_popup_row = bc.style_popup_row
  bc.style_popup_row = function(props)
    props = style_popup_row(props)
    if type(props) == "table" and type(props.position) == "string"
      and props.position:match("^popup%.")
      and type(props.click_script) == "string" and props.click_script ~= "" then
      if type(props.background) ~= "table" then
        props.background = {}
      end
      if props.background.hover_color == nil then
        props.background.hover_color = bc.hover_color
      end
    end
    return props
  end
end
if bc.display_density and bc.display_density ~= "" then
  print(string.format(
    "Display density: %s (min_width=%s wide=%s fingerprint=%s)",
    tostring(bc.display_density),
    tostring(bc.display_profile and bc.display_profile.min_width or ""),
    tostring(bc.wide_displays or ""),
    tostring(bc.density_fingerprint or "")
  ))
end
do
  local fingerprint = bc.density_fingerprint
  if type(fingerprint) == "string" and fingerprint ~= "" then
    local path = CONFIG_DIR .. "/cache/display_density_fingerprint"
    os.execute(string.format("mkdir -p %q", CONFIG_DIR .. "/cache"))
    local handle = io.open(path, "w")
    if handle then
      handle:write(fingerprint)
      handle:close()
    end
  end
end

-- Build hover environment strings
local hover_script_cmd = shell_utils.env_prefix({
  POPUP_HOVER_COLOR            = tostring(bc.hover_color),
  POPUP_HOVER_BORDER_COLOR     = tostring(bc.hover_border_color),
  POPUP_HOVER_BORDER_WIDTH     = tostring(bc.hover_border_width),
  POPUP_HOVER_ANIMATION_CURVE  = tostring(bc.hover_animation_curve),
  POPUP_HOVER_ANIMATION_DURATION = tostring(bc.hover_animation_duration),
}) .. HOVER_SCRIPT

local fast_hover_duration = bc.fast_hover_duration
local triforce_hover_script_cmd = shell_utils.env_prefix({
  POPUP_HOVER_COLOR              = tostring(bc.hover_color),
  POPUP_HOVER_BORDER_COLOR       = tostring(bc.hover_border_color),
  POPUP_HOVER_BORDER_WIDTH       = tostring(bc.hover_border_width),
  POPUP_HOVER_ANIMATION_CURVE    = tostring(bc.hover_animation_curve),
  POPUP_HOVER_ANIMATION_DURATION = tostring(fast_hover_duration),
}) .. HOVER_SCRIPT

local submenu_hover_script_cmd = shell_utils.env_prefix({
  SUBMENU_HOVER_BG             = tostring(bc.submenu_hover_color),
  SUBMENU_IDLE_BG              = tostring(bc.submenu_idle_color),
  SUBMENU_CLOSE_DELAY          = tostring(bc.submenu_close_delay),
  SUBMENU_ANIMATION_CURVE      = tostring(bc.hover_animation_curve),
  SUBMENU_ANIMATION_DURATION   = tostring(bc.hover_animation_duration),
}) .. SUBMENU_HOVER_SCRIPT

-- Build paths / scripts tables
local profile_paths = profile_module.get_paths(user_profile)
local paths   = paths_module.build_paths_table(CONFIG_DIR, CODE_DIR, profile_paths)
local scripts = paths_module.build_scripts_table(CONFIG_DIR, SCRIPTS_DIR, PLUGIN_DIR)
local helpers = { help_center = CONFIG_DIR .. "/gui/bin/help_center" }

local integrations = {
  yaze   = yaze_enabled   and yaze_module   or nil,
  oracle = oracle_enabled and oracle_module or nil,
  music  = music_enabled  and music_module  or nil,
  emacs  = emacs_enabled  and emacs_module  or nil,
  halext = halext_enabled  and halext_module or nil,
  premia = premia_module,
  control_center = control_center_module,
}

-- Configure yaze integration
if yaze_module and type(yaze_module.configure) == "function" then
  yaze_module.configure({ repo_path = paths.yaze, rom_workflow_doc = paths.rom_doc })
end

-----------------------------------------------------------------------
-- Unified context – passed to menus, items_left, items_right, etc.
-----------------------------------------------------------------------
local barista_context = {
  -- Core
  sbar     = sbar,
  theme    = theme,
  settings = bc.settings,
  state    = state,

  -- Bar geometry
  widget_height        = bc.widget_height,
  widget_corner_radius = bc.widget_corner_radius,
  widget_corners = NATIVE_HOVER and bc.widget_corners or nil,
  popup_background     = bc.popup_background,
  style_popup_row      = bc.style_popup_row,
  font_string          = bc.font_string,
  group_bg_color       = bc.group_bg_color,
  group_border_color   = bc.group_border_color,
  group_border_width   = bc.group_border_width,
  group_corner_radius  = bc.group_corner_radius,
  -- Native hover makes every bar item its own pill in the group colors.
  native_hover              = NATIVE_HOVER,
  popup_stretch             = POPUP_STRETCH,
  anchor_idle_bg            = NATIVE_HOVER and bc.group_bg_color or nil,
  anchor_idle_border_color  = NATIVE_HOVER and bc.group_border_color or nil,
  anchor_idle_border_width  = NATIVE_HOVER and bc.widget_border_width or nil,
  anchor_hover_bg           = NATIVE_HOVER and bc.widget_hover_color or nil,
  anchor_hover_border_color = NATIVE_HOVER and bc.widget_hover_border_color or nil,
  hover_color               = bc.hover_color,
  hover_border_color        = bc.hover_border_color,
  hover_border_width        = bc.hover_border_width,
  hover_animation_curve     = bc.hover_animation_curve,
  hover_animation_duration  = bc.hover_animation_duration,

  -- Scripts & hover
  HOVER_SCRIPT         = hover_script_cmd,
  SUBMENU_HOVER_SCRIPT = submenu_hover_script_cmd,
  hover_script_cmd     = hover_script_cmd,
  triforce_hover_script_cmd = triforce_hover_script_cmd,

  -- Helpers & shell
  shell_exec               = shell_utils.shell_exec,
  shell_exec_background    = shell_utils.shell_exec_background,
  post_config_exec         = enqueue_post_config_command,
  call_script              = shell_utils.call_script,
  shell_quote              = shell_utils.shell_quote,
  open_path                = shell_utils.open_path,
  open_url                 = shell_utils.open_url,
  env_prefix               = shell_utils.env_prefix,
  attach_hover             = attach_hover,
  subscribe_popup_autoclose = subscribe_popup_autoclose,
  popup_toggle_action      = popup_toggle_action,
  ui_builder               = ui_builder,
  popup_toggle_script      = nil,
  popup_anchor_script      = POPUP_ANCHOR_SCRIPT,
  POPUP_MANAGER_SCRIPT     = POPUP_SWITCH_SCRIPT,
  popup_manager_script     = POPUP_SWITCH_SCRIPT,
  POPUP_TOPOLOGY_TOKEN     = POPUP_TOPOLOGY_TOKEN,
  popup_topology_token     = POPUP_TOPOLOGY_TOKEN,

  -- Directories & binaries
  CONFIG_DIR      = CONFIG_DIR,
  PLUGIN_DIR      = PLUGIN_DIR,
  SCRIPTS_DIR     = SCRIPTS_DIR,
  RUNTIME_CONTEXT_SCRIPT = RUNTIME_CONTEXT_SCRIPT,
  CODE_DIR        = CODE_DIR,
  SKETCHYBAR_BIN  = SKETCHYBAR_BIN,
  sketchybar_bin  = SKETCHYBAR_BIN,
  POST_CONFIG_DELAY = POST_CONFIG_DELAY,
  SPACE_POST_CONFIG_DELAY = SPACE_POST_CONFIG_DELAY,
  associated_displays = associated_displays,
  associated_spaces = associated_spaces,
  display_density = bc.display_density,
  density_fingerprint = bc.density_fingerprint,
  hide_anchor_labels = bc.hide_anchor_labels,
  optional_wide_only = bc.optional_wide_only,
  narrow_status_strip = bc.narrow_status_strip,
  split_layout = bc.split_layout,
  clock_style = bc.clock_style,
  wide_displays = bc.wide_displays,
  narrow_displays = bc.narrow_displays,
  compiled_script = compiled_script,
  current_time_ms = runtime_startup.current_time_ms,
  widget_daemon_enabled = widget_daemon_enabled,
  lua_only = LUA_ONLY,

  -- Paths, scripts, helpers, integrations
  paths       = paths,
  scripts     = scripts,
  helpers     = helpers,
  integrations = integrations,
  integration_flags = profile_module.get_integration_flags(user_profile),

  -- Icons
  icon_for = icon_for,

  -- State helpers
  state_module = state_module,

  -- Spaces
  refresh_spaces = space_fns.refresh_spaces,
  watch_spaces   = space_fns.watch_spaces,

  -- Window management
  yabai_available     = yabai_available,
  WINDOW_MANAGER_MODE = WINDOW_MANAGER_MODE,
  control_center_module = control_center_module,
  control_center_item_name = control_center_item_name,

  -- Appearance
  appearance = state.appearance,

  -- Specific scripts (consumed by items_left)
  FRONT_APP_ACTION_SCRIPT = SCRIPTS_DIR .. "/front_app_action.sh",
  YABAI_CONTROL_SCRIPT    = SCRIPTS_DIR .. "/yabai_control.sh",

  -- Widget factory (set below)
  widget_factory = nil,
}

barista_context.widget_factory = widgets_module.create_factory(sbar, theme, bc.settings, state, bc)
barista_context.prepared_menus = menu_module.prepare(barista_context)

-----------------------------------------------------------------------
-- Begin configuration
-----------------------------------------------------------------------
local reload_prep_end_wall_ms = runtime_startup.wall_time_ms()
local daemon_stop_start_wall_ms = reload_prep_end_wall_ms
runtime_daemon.stop_widget_daemon({ trace = trace_startup, config_dir = CONFIG_DIR, binary_path = WIDGET_MANAGER_BIN })
runtime_daemon.stop_runtime_context_daemon({ trace = trace_startup, config_dir = CONFIG_DIR, script_path = RUNTIME_CONTEXT_SCRIPT })
local daemon_stop_duration_ms = runtime_startup.wall_time_ms() - daemon_stop_start_wall_ms

local config_build_start_ms = runtime_startup.current_time_ms()
local config_build_start_wall_ms = runtime_startup.wall_time_ms()
local menu_render_duration_ms = 0
local left_layout_duration_ms = 0
local left_layout_build_duration_ms = 0
local left_layout_apply_duration_ms = 0
local left_layout_metrics = {}
local right_layout_duration_ms = 0
local right_layout_build_duration_ms = 0
local right_layout_apply_duration_ms = 0
local registry_duration_ms = 0
sbar.begin_config()
trace_startup("main:begin_config")
for _, event_name in ipairs({
  "space_change",
  "space_active_refresh",
  "space_mode_refresh",
  "space_visual_refresh",
  "display_changed",
  "display_added",
  "display_removed",
  "task_state_changed",
}) do
  sbar.add("event", event_name)
end

-- Global popup manager (invisible item that handles popup dismissal)
sbar.add("item", "popup_manager", {
  position = "left",
  drawing = false,
  script = POPUP_MANAGER_SCRIPT_CMD,
})

-- Space runtime coordinator (single batch updater for all space visuals)
local space_visuals_script_cmd = shell_utils.env_prefix({
  BARISTA_LUA_ONLY = LUA_ONLY and "1" or nil,
}) .. SPACE_VISUALS_SCRIPT
sbar.add("item", "space_runtime", {
  position = "left",
  drawing = false,
  -- Hidden coordinators still need event delivery; zero frequency prevents polling.
  updates = true,
  update_freq = 0,
  script = space_visuals_script_cmd,
})

-- Display density watcher: reload when rotation/resolution changes density mode.
-- Without auto density there is no fingerprint to compare, so no watcher.
local density_watch = type(bc.density_fingerprint) == "string" and bc.density_fingerprint ~= ""
if density_watch then
  local display_density_script = shell_utils.env_prefix({
    BARISTA_CONFIG_DIR = CONFIG_DIR,
    BARISTA_SKETCHYBAR_BIN = SKETCHYBAR_BIN,
  }) .. PLUGIN_DIR .. "/display_density.sh"
  sbar.add("item", "display_density", {
    position = "left",
    drawing = false,
    updates = true,
    update_freq = 0,
    script = display_density_script,
  })
end

-- Bar configuration
sbar.bar(bc.bar)

-- Update external bar (yabai)
if yabai_available() then
  enqueue_post_config_command(string.format("%s/update_external_bar.sh %d", SCRIPTS_DIR, bc.bar_height))
end

-- Defaults
sbar.default(bc.defaults)

-- Render All Menus (System, Workspace, Window)
local menu_render_start_ms = runtime_startup.current_time_ms()
local menu_metadata = menu_module.render_all_menus(barista_context) or {}
menu_render_duration_ms = runtime_startup.current_time_ms() - menu_render_start_ms
trace_startup("main:menus_rendered")

-- Register left and right bar items
-----------------------------------------------------------------------
-- Layout Processing
-----------------------------------------------------------------------
-- deferred_brackets, when given, collects bracket entries instead of adding
-- them, for brackets whose members a later layout creates.
local function process_layout(layout, ctx, deferred_brackets)
  local sbar = ctx.sbar
  for _, entry in ipairs(layout) do
    if entry.type == "item" then
      sbar.add("item", entry.name, bc.style_popup_row(entry.props))
      if entry.attach_hover then
        ctx.attach_hover(entry.name)
      end
    elseif entry.type == "bracket" and deferred_brackets then
      table.insert(deferred_brackets, entry)
    elseif entry.type == "bracket" then
      sbar.add("bracket", entry.children or entry.name, entry.props)
    elseif entry.type == "set" then
      sbar.set(entry.name, entry.props)
    elseif entry.action == "exec" then
      post_config_queue:enqueue_command(entry.cmd, {
        background = type(entry.cmd) == "string"
          and entry.cmd:match("^sleep%s") ~= nil
          and type(ctx.shell_exec_background) == "function",
      })
    elseif entry.action == "call" then
      if type(entry.fn) == "function" then
        entry.fn()
      else
        print(string.format(
          "Barista: skipped layout call with missing fn (name=%s)",
          tostring(entry.name or "(unnamed)")
        ))
      end
    elseif entry.action == "post_config_call" then
      post_config_queue:enqueue_call(entry.fn)
    elseif entry.action == "subscribe_popup_autoclose" then
      ctx.subscribe_popup_autoclose(entry.name)
    elseif entry.action == "attach_hover" then
      -- Bar widgets carry native hover colors in their pill props.
      if not ctx.native_hover then
        ctx.attach_hover(entry.name)
      end
    end
  end
end

local items_left  = require("items_left")
local items_right = require("items_right")

local left_layout_build_start_ms = runtime_startup.current_time_ms()
local left_layout
local left_layout_metadata
left_layout, left_layout_metrics, left_layout_metadata = items_left.get_layout(barista_context)
left_layout_build_duration_ms = runtime_startup.current_time_ms() - left_layout_build_start_ms
local left_layout_apply_start_ms = runtime_startup.current_time_ms()
-- left_group includes the agents widget, which items_right creates.
local left_brackets = {}
process_layout(left_layout, barista_context, left_brackets)
left_layout_apply_duration_ms = runtime_startup.current_time_ms() - left_layout_apply_start_ms
left_layout_duration_ms = left_layout_build_duration_ms + left_layout_apply_duration_ms
trace_startup("main:left_layout_processed")
local right_layout_build_start_ms = runtime_startup.current_time_ms()
local right_layout, _, right_layout_metadata = items_right.get_layout(barista_context)
right_layout_build_duration_ms = runtime_startup.current_time_ms() - right_layout_build_start_ms
local right_layout_apply_start_ms = runtime_startup.current_time_ms()
process_layout(right_layout, barista_context)
process_layout(left_brackets, barista_context)
right_layout_apply_duration_ms = runtime_startup.current_time_ms() - right_layout_apply_start_ms
right_layout_duration_ms = right_layout_build_duration_ms + right_layout_apply_duration_ms
trace_startup("main:right_layout_processed")

-- Write dynamic popup/submenu lists for C helpers (replaces hardcoded lists)
local popup_manager_items = {
  "front_app",
  "clock",
  "system_info",
  "volume",
  "battery",
  unpack(menu_metadata.popup_parents or {}),
}
if type(state.widgets) == "table" and state.widgets.agents == true then
  table.insert(popup_manager_items, "agents")
end
for _, item_name in ipairs((left_layout_metadata and left_layout_metadata.popup_parents) or {}) do
  table.insert(popup_manager_items, item_name)
end
local submenu_manager_items = { unpack(menu_metadata.submenu_parents or {}) }
for _, metadata in ipairs({ left_layout_metadata, right_layout_metadata }) do
  for _, item_name in ipairs((metadata and metadata.submenu_parents) or {}) do
    table.insert(submenu_manager_items, item_name)
  end
end
local registry_start_ms = runtime_startup.current_time_ms()
local popup_registry_ok = submenu_registry.register(
  -- Popup parents (items with popup.drawing=toggle)
  popup_manager_items,
  -- Submenu sections (items inside menu popups that have their own popups)
  submenu_manager_items,
  nil,
  menu_metadata.submenu_ancestors or {},
  POPUP_TOPOLOGY_TOKEN
)
if not popup_registry_ok then
  print("Barista: popup registry publication failed; this click generation will use target-only fallback")
end
registry_duration_ms = runtime_startup.current_time_ms() - registry_start_ms

post_config_queue:enqueue_command(string.format(
  "sleep %.1f; %s --subscribe popup_manager space_change display_change display_changed display_added display_removed system_woke",
  POST_CONFIG_DELAY,
  SKETCHYBAR_BIN
))
if density_watch then
  post_config_queue:enqueue_command(string.format(
    "sleep %.1f; %s --subscribe display_density display_change display_changed display_added display_removed system_woke; CONFIG_DIR=%q BARISTA_SKETCHYBAR_BIN=%q %q",
    POST_CONFIG_DELAY,
    SKETCHYBAR_BIN,
    CONFIG_DIR,
    SKETCHYBAR_BIN,
    PLUGIN_DIR .. "/display_density.sh"
  ))
end

-- End configuration
sbar.end_config()
trace_startup("main:end_config")
if not LUA_ONLY then
  publish_runtime_marker_or_warn("compiled")
end
local config_build_duration_ms = runtime_startup.current_time_ms() - config_build_start_ms
local config_build_wall_duration_ms = runtime_startup.wall_time_ms() - config_build_start_wall_ms
local stats_flush_start_wall_ms = runtime_startup.wall_time_ms()
runtime_startup.record_duration_events(STATS_BIN, {
  { name = "reload_prep_time", duration_ms = math.max(0, reload_prep_end_wall_ms - (RELOAD_START_MS or reload_prep_end_wall_ms)), trace_label = "main:reload_prep_ms" },
  { name = "reload_daemon_stop_time", duration_ms = math.max(0, daemon_stop_duration_ms), trace_label = "main:reload_daemon_stop_ms" },
  { name = "config_build_time", duration_ms = config_build_duration_ms, trace_label = "main:config_build_ms" },
  { name = "config_build_wall_time", duration_ms = config_build_wall_duration_ms, trace_label = "main:config_build_wall_ms" },
  { name = "config_menu_render_time", duration_ms = menu_render_duration_ms, trace_label = "main:config_menu_render_ms" },
  { name = "config_left_layout_time", duration_ms = left_layout_duration_ms, trace_label = "main:config_left_layout_ms" },
  { name = "config_left_layout_build_time", duration_ms = left_layout_build_duration_ms, trace_label = "main:config_left_layout_build_ms" },
  { name = "config_left_layout_apply_time", duration_ms = left_layout_apply_duration_ms, trace_label = "main:config_left_layout_apply_ms" },
  { name = "config_left_layout_front_app_time", duration_ms = left_layout_metrics.front_app_ms or 0, trace_label = "main:config_left_layout_front_app_ms" },
  { name = "config_left_layout_triforce_time", duration_ms = left_layout_metrics.triforce_ms or 0, trace_label = "main:config_left_layout_triforce_ms" },
  { name = "config_left_layout_spaces_time", duration_ms = left_layout_metrics.spaces_ms or 0, trace_label = "main:config_left_layout_spaces_ms" },
  { name = "config_left_layout_control_center_time", duration_ms = left_layout_metrics.control_center_ms or 0, trace_label = "main:config_left_layout_control_center_ms" },
  { name = "config_left_layout_group_time", duration_ms = left_layout_metrics.group_ms or 0, trace_label = "main:config_left_layout_group_ms" },
  { name = "config_right_layout_time", duration_ms = right_layout_duration_ms, trace_label = "main:config_right_layout_ms" },
  { name = "config_right_layout_build_time", duration_ms = right_layout_build_duration_ms, trace_label = "main:config_right_layout_build_ms" },
  { name = "config_right_layout_apply_time", duration_ms = right_layout_apply_duration_ms, trace_label = "main:config_right_layout_apply_ms" },
  { name = "config_registry_time", duration_ms = registry_duration_ms, trace_label = "main:config_registry_ms" },
}, {
  trace = trace_startup,
})
local stats_flush_duration_ms = runtime_startup.wall_time_ms() - stats_flush_start_wall_ms
runtime_startup.record_duration_event(STATS_BIN, "reload_stats_flush_time", stats_flush_duration_ms, {
  trace = trace_startup,
  trace_label = "main:reload_stats_flush_ms",
})
runtime_startup.record_reload_metrics(STATS_BIN, RELOAD_START_MS, { trace = trace_startup })

if widget_daemon_enabled then
  local widget_daemon_env = shell_utils.env_prefix({
    BARISTA_CLOCK_STYLE = bc.clock_style or "full",
    BARISTA_BATTERY_LABEL_MODE = bc.hide_anchor_labels and "icon" or "percent",
  })
  runtime_daemon.ensure_widget_daemon(WIDGET_MANAGER_BIN, {
    trace = trace_startup,
    force_restart = true,
    env_prefix = widget_daemon_env,
  })
else
  runtime_daemon.stop_widget_daemon({ trace = trace_startup, config_dir = CONFIG_DIR, binary_path = WIDGET_MANAGER_BIN })
end

if shell_utils.file_exists(RUNTIME_CONTEXT_SCRIPT) then
  runtime_daemon.ensure_runtime_context_daemon(RUNTIME_CONTEXT_SCRIPT, {
    trace = trace_startup,
    config_dir = CONFIG_DIR,
    force_restart = true,
    lua_only = LUA_ONLY,
  })
else
  runtime_daemon.stop_runtime_context_daemon({ trace = trace_startup, config_dir = CONFIG_DIR, script_path = RUNTIME_CONTEXT_SCRIPT })
end

-- SbarLua temporarily restores SIGCHLD's default disposition while
-- os.execute() waits for its own child. Dispatch asynchronous sbar.exec work
-- only after the synchronous stats/daemon startup work above, so completed
-- post-config clients cannot become unreaped children during that window.
local post_config_action_count = post_config_queue:flush({
  exec = shell_utils.shell_exec,
  exec_background = shell_utils.shell_exec_background,
  delay = function(seconds, callback)
    sbar.delay(seconds, callback)
  end,
  on_delay_error = report_native_delay_error,
  on_action_error = report_post_config_action_error,
})
trace_startup("main:post_config_actions " .. tostring(post_config_action_count))

post_config_queue:enqueue_command(runtime_startup.build_space_runtime_subscription(SPACE_POST_CONFIG_DELAY, SKETCHYBAR_BIN))
post_config_queue:enqueue_command(runtime_startup.build_space_visual_refresh(
  SPACE_STARTUP_SYNC_DELAY,
  SPACE_VISUALS_SCRIPT,
  CONFIG_DIR,
  SCRIPTS_DIR,
  LUA_ONLY
))
local late_post_config_action_count = post_config_queue:flush({
  exec = shell_utils.shell_exec,
  exec_background = shell_utils.shell_exec_background,
  delay = function(seconds, callback)
    sbar.delay(seconds, callback)
  end,
  on_delay_error = report_native_delay_error,
  on_action_error = report_post_config_action_error,
})
trace_startup("main:late_post_config_actions " .. tostring(late_post_config_action_count))

print("main.lua finished loading!")
trace_startup("main:event_loop")
sbar.event_loop()
