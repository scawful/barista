-- Keyboard Shortcut Management Module
-- Centralized shortcut definitions
-- Non-conflicting shortcuts for global operations

local shortcuts = {}
local binary_resolver = require("binary_resolver")
local paths_module = require("paths")
local shell_utils = require("shell_utils")
local locator = require("tool_locator")
local ui = require("ui_builder")

local HOME = os.getenv("HOME") or ""
local CONFIG_DIR = locator.resolve_config_dir()

local function nonblank(value)
  return type(value) == "string" and value:match("%S") and value or nil
end

local function load_json_table(path)
  if not nonblank(path) then
    return nil
  end
  local ok_json, json = pcall(require, "json")
  if not ok_json then
    return nil
  end
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local contents = file:read("*a")
  file:close()
  local ok_decode, decoded = pcall(json.decode, contents)
  if not ok_decode or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

local state_file = nonblank(os.getenv("BARISTA_STATE_FILE"))
local runtime_state
if state_file then
  runtime_state = load_json_table(state_file) or {}
else
  runtime_state = locator.load_state(CONFIG_DIR) or {}
end

local function merge_tables(target, source)
  for key, value in pairs(source or {}) do
    if type(value) == "table" and type(target[key]) == "table" then
      merge_tables(target[key], value)
    else
      target[key] = value
    end
  end
end

local function state_directory(path)
  return type(path) == "string" and path:match("^(.+)/[^/]+$") or nil
end

local config_file = nonblank(os.getenv("BARISTA_CONFIG_FILE"))
  or ((state_file and state_directory(state_file)) or CONFIG_DIR) .. "/barista_config.lua"
local config_chunk = loadfile(config_file)
if config_chunk then
  local ok_config, user_config = pcall(config_chunk)
  if ok_config and type(user_config) == "table" then
    merge_tables(runtime_state, user_config)
  end
end
local SKETCHYBAR_BIN = binary_resolver.resolve_sketchybar_bin()
local POPUP_MANAGER_SCRIPT = binary_resolver.resolve_popup_switch(
  CONFIG_DIR,
  binary_resolver.resolve_runtime_backend(runtime_state) == "lua",
  CONFIG_DIR .. "/plugins/popup_manager.sh"
)
local POPUP_TOPOLOGY_TOKEN = nil
local DEFAULT_CONTROL_CENTER_ITEM_NAME = "control_center"

local function service_running(name)
  if not name or name == "" then
    return false
  end
  local handle = io.popen(string.format("pgrep -x %q >/dev/null 2>&1 && echo 1 || echo 0", name))
  if not handle then
    return false
  end
  local result = handle:read("*a") or ""
  handle:close()
  return result:match("1") ~= nil
end

local function shell_quote(value)
  return shell_utils.shell_quote(value)
end

function shortcuts.resolve_control_center_item_name(state, getenv_fn)
  local getenv = getenv_fn or os.getenv
  local env_name = getenv and getenv("BARISTA_CONTROL_CENTER_ITEM_NAME") or nil
  if env_name and env_name ~= "" then
    return env_name
  end

  local runtime = type(state) == "table" and state or runtime_state
  local integrations = runtime and runtime.integrations
  local control_center = type(integrations) == "table" and integrations.control_center or nil
  local state_name = type(control_center) == "table" and (control_center.item_name or control_center.name) or nil
  if state_name and state_name ~= "" then
    return state_name
  end

  return DEFAULT_CONTROL_CENTER_ITEM_NAME
end

function shortcuts.build_control_center_toggle_command(item_name, opts)
  opts = opts or {}
  local topology_token = opts.popup_topology_token or POPUP_TOPOLOGY_TOKEN
  if not topology_token then
    return shell_quote(CONFIG_DIR .. "/scripts/invoke_popup_click.sh")
      .. " "
      .. shell_quote(item_name)
  end
  return ui.toggle(item_name, {
    sketchybar_bin = opts.sketchybar_bin or SKETCHYBAR_BIN,
    popup_manager_script = opts.popup_manager_script or POPUP_MANAGER_SCRIPT,
    popup_topology_token = topology_token,
  })
end

function shortcuts.set_popup_topology_token(token)
  POPUP_TOPOLOGY_TOKEN = nonblank(token)
  if type(shortcuts.actions) == "table" then
    shortcuts.actions.toggle_control_center = shortcuts.build_control_center_toggle_command(
      shortcuts.resolve_control_center_item_name(runtime_state)
    )
  end
end

function shortcuts.build_terminal_session_command(command)
  if not command or command == "" then
    return ""
  end
  return table.concat({
    shell_quote("osascript"),
    "-e " .. shell_quote("on run argv"),
    "-e " .. shell_quote('tell application "Terminal" to do script (item 1 of argv)'),
    "-e " .. shell_quote("end run"),
    "-- " .. shell_quote(command),
  }, " ")
end

local function resolve_window_manager_mode()
  local mode = os.getenv("BARISTA_WINDOW_MANAGER_MODE")
  if not mode or mode == "" then
    mode = runtime_state.modes and runtime_state.modes.window_manager
  end
  return binary_resolver.normalize_window_manager_mode(mode)
end

local function window_manager_enabled()
  local mode = resolve_window_manager_mode()
  local has_yabai = locator.command_path("yabai") ~= nil
  if mode == "disabled" then
    return false
  end
  if mode == "optional" then
    return service_running("yabai")
  end
  if mode == "required" then
    return has_yabai
  end
  return has_yabai
end

local SCRIPTS_DIR = paths_module.resolve_scripts_dir(CONFIG_DIR, runtime_state)
local shared_opts = {
  config_dir = CONFIG_DIR,
  code_dir = runtime_state.paths and (runtime_state.paths.code_dir or runtime_state.paths.code) or nil,
  state = runtime_state,
}
local CODE_DIR = locator.resolve_code_dir(shared_opts)
shared_opts.code_dir = CODE_DIR

local function integration_flag(name)
  local integrations = runtime_state.integrations
  local entry = type(integrations) == "table" and integrations[name] or nil
  if type(entry) ~= "table" or entry.enabled == nil then
    return nil
  end
  return entry.enabled ~= false
end

local function get_yaze_dir()
  return select(1, locator.resolve_yaze_dir(shared_opts)) or (CODE_DIR .. "/hobby/yaze")
end

local function get_yaze_enabled()
  local yaze_flag = integration_flag("yaze")
  local yaze_app, yaze_ok = locator.resolve_yaze_app(shared_opts)
  local yaze_launcher = select(1, locator.resolve_yaze_launcher())
  local yaze_available = yaze_ok or (yaze_launcher and yaze_launcher ~= "")
  return (yaze_flag == nil) and yaze_available or (yaze_flag and yaze_available)
end

local function open_path_command(path)
  if not path or path == "" then
    return ""
  end
  return string.format("open %s", shell_quote(path))
end

local function task_calendar_config(state)
  local menus = type(state.menus) == "table" and state.menus or nil
  local calendar = menus and type(menus.calendar) == "table" and menus.calendar or nil
  return calendar or {}
end

local function task_sources(calendar)
  local sources = calendar and calendar.task_sources or nil
  if nonblank(sources) then
    return sources
  end
  if type(sources) == "table" then
    local values = {}
    for _, source in ipairs(sources) do
      if nonblank(source) then
        table.insert(values, source)
      end
    end
    if #values > 0 then
      return table.concat(values, ":")
    end
  end
  return nil
end

local function first_nonblank_env(getenv, ...)
  if type(getenv) ~= "function" then
    return nil
  end
  for index = 1, select("#", ...) do
    local value = nonblank(getenv(select(index, ...)))
    if value then
      return value
    end
  end
  return nil
end

function shortcuts.resolve_task_config(state, getenv_fn)
  local getenv = getenv_fn or os.getenv
  local calendar = task_calendar_config(type(state) == "table" and state or runtime_state)
  return {
    task_sources = first_nonblank_env(getenv, "BARISTA_CALENDAR_TASK_SOURCES", "BARISTA_TASK_SOURCES")
      or task_sources(calendar),
    task_provider = first_nonblank_env(getenv, "BARISTA_TASK_PROVIDER")
      or nonblank(calendar.task_provider),
    syshelp_path = first_nonblank_env(getenv, "BARISTA_SYSHELP_BIN")
      or nonblank(calendar.syshelp_path),
    capture_section = first_nonblank_env(getenv, "BARISTA_CAPTURE_SECTION")
      or nonblank(calendar.capture_section),
    capture_state = first_nonblank_env(getenv, "BARISTA_CAPTURE_STATE")
      or nonblank(calendar.capture_state),
  }
end

function shortcuts.has_task_source(state, getenv_fn)
  return shortcuts.resolve_task_config(state, getenv_fn).task_sources ~= nil
end

function shortcuts.build_task_script_action(script_name, state, getenv_fn, config_dir)
  local action = shell_quote((config_dir or CONFIG_DIR) .. "/scripts/" .. script_name)
  local task_config = shortcuts.resolve_task_config(state, getenv_fn)
  local env = {}
  if task_config.task_sources then
    table.insert(env, "BARISTA_CALENDAR_TASK_SOURCES=" .. shell_quote(task_config.task_sources))
  end
  if task_config.task_provider then
    table.insert(env, "BARISTA_TASK_PROVIDER=" .. shell_quote(task_config.task_provider))
  end
  if task_config.syshelp_path then
    table.insert(env, "BARISTA_SYSHELP_BIN=" .. shell_quote(task_config.syshelp_path))
  end
  if task_config.capture_section then
    table.insert(env, "BARISTA_CAPTURE_SECTION=" .. shell_quote(task_config.capture_section))
  end
  if task_config.capture_state then
    table.insert(env, "BARISTA_CAPTURE_STATE=" .. shell_quote(task_config.capture_state))
  end
  if #env == 0 then
    return action
  end
  return table.concat(env, " ") .. " " .. action
end

local function task_focus_action()
  return shortcuts.build_task_script_action("task_focus.sh")
end

local function task_capture_action()
  return shortcuts.build_task_script_action("task_capture.sh")
end

local function bash_literal(value)
  return "'" .. tostring(value or ""):gsub("'", "'\"'\"'") .. "'"
end

local function debounced_command(key, command)
  if not command or command == "" then
    return ""
  end
  local raw_key = tostring(key or "action"):gsub("[^%w]+", "_")
  local lock_dir = string.format("/tmp/barista_shortcut_%s.lock", raw_key)
  local wrapped = string.format(
    "lock_dir=%s; if ! mkdir \"$lock_dir\" 2>/dev/null; then exit 0; fi; trap 'rmdir \"$lock_dir\"' EXIT; %s; sleep 0.75",
    shell_quote(lock_dir),
    command
  )
  return "bash -lc " .. bash_literal(wrapped)
end

local function get_ghostty_app()
  return select(1, locator.resolve_ghostty_app(shared_opts))
end

local function terminal_app_command()
  local ghostty = get_ghostty_app()
  if ghostty and ghostty ~= "" then
    return debounced_command("open_terminal", string.format("open -na %s", shell_quote(ghostty)))
  end
  return "open -a Terminal"
end

local function terminal_session_command(key, command)
  if not command or command == "" then
    return terminal_app_command()
  end
  local ghostty = get_ghostty_app()
  if ghostty and ghostty ~= "" then
    return debounced_command(
      key or "ghostty_session",
      string.format("open -na %s --args -e /bin/zsh -lc %s", shell_quote(ghostty), shell_quote(command))
    )
  end
  return shortcuts.build_terminal_session_command(command)
end

local function open_app_command(app_path, app_name)
  if app_path and app_path ~= "" then
    return open_path_command(app_path)
  end
  if app_name and app_name ~= "" then
    return string.format("open -a %s", shell_quote(app_name))
  end
  return ""
end

local function help_center_action()
  local help_center_bin, help_center_ok = locator.resolve_help_center_bin(CONFIG_DIR)
  if help_center_ok and help_center_bin then
    return shell_quote(help_center_bin)
  end
  local fallback_doc = CONFIG_DIR .. "/docs/features/ICONS_AND_SHORTCUTS.md"
  if locator.path_exists(fallback_doc, false) then
    return open_path_command(fallback_doc)
  end
  return ""
end

local function icon_browser_action()
  local icon_browser_bin, icon_browser_ok = locator.resolve_icon_browser_bin(CONFIG_DIR)
  if icon_browser_ok and icon_browser_bin then
    return shell_quote(icon_browser_bin)
  end
  local fallback_doc = CONFIG_DIR .. "/docs/features/ICON_REFERENCE.md"
  if locator.path_exists(fallback_doc, false) then
    return open_path_command(fallback_doc)
  end
  return ""
end

local function sys_manual_action()
  local sys_manual_bin, sys_manual_ok = locator.resolve_sys_manual_binary(shared_opts)
  if sys_manual_ok and sys_manual_bin then
    return shell_quote(sys_manual_bin)
  end
  return ""
end

local function build_afs_studio_action(resolved)
  resolved = resolved or {}
  if resolved.apps_launcher_ok and resolved.apps_launcher then
    return string.format("%s launch afs_studio", shell_quote(resolved.apps_launcher))
  end

  if resolved.studio_bin_ok and resolved.studio_bin then
    if resolved.studio_bin:match("%.app/?$") then
      return open_path_command(resolved.studio_bin)
    end
    return shell_quote(resolved.studio_bin)
  end

  if resolved.studio_launcher_ok and resolved.studio_launcher then
    return shell_quote(resolved.studio_launcher)
  end
  return ""
end

shortcuts._build_afs_studio_action = build_afs_studio_action

local function afs_studio_action()
  local afs_root = select(1, locator.resolve_afs_root(shared_opts))
  local studio_root = select(1, locator.resolve_afs_studio_root(shared_opts, afs_root))
  local apps_launcher, apps_launcher_ok = locator.resolve_afs_apps_launcher(shared_opts)
  local studio_launcher, studio_launcher_ok = locator.resolve_afs_studio_launcher(shared_opts)
  local studio_bin, studio_bin_ok = locator.resolve_afs_studio_binary(studio_root)
  return build_afs_studio_action({
    apps_launcher = apps_launcher,
    apps_launcher_ok = apps_launcher_ok,
    studio_bin = studio_bin,
    studio_bin_ok = studio_bin_ok,
    studio_launcher = studio_launcher,
    studio_launcher_ok = studio_launcher_ok,
  })
end

local function afs_labeler_action()
  local afs_root = select(1, locator.resolve_afs_root(shared_opts))
  local studio_root = select(1, locator.resolve_afs_studio_root(shared_opts, afs_root))
  local labeler_bin, labeler_bin_ok = locator.resolve_afs_labeler_binary(studio_root, shared_opts)
  if labeler_bin_ok and labeler_bin then
    if labeler_bin:match("%.app/?$") then
      return open_path_command(labeler_bin)
    end
    local command = shell_quote(labeler_bin)
    local labeler_csv = os.getenv("AFS_LABELER_CSV")
    if labeler_csv and labeler_csv ~= "" then
      command = command .. " --csv " .. shell_quote(labeler_csv)
    end
    return command
  end
  return ""
end

local function get_yaze_action()
  if not get_yaze_enabled() then return "" end
  local yaze_app, yaze_ok = locator.resolve_yaze_app(shared_opts)
  if yaze_ok and yaze_app and yaze_app ~= "" then
    return open_app_command(yaze_app, "Yaze")
  end
  local yaze_launcher = select(1, locator.resolve_yaze_launcher())
  if yaze_launcher and yaze_launcher ~= "" then
    return shell_quote(yaze_launcher)
  end
  return ""
end

local z3ed_action_cache = nil
local function get_z3ed_action()
  if z3ed_action_cache ~= nil then
    return z3ed_action_cache
  end
  local z3ed_bin, z3ed_ok = locator.resolve_z3ed_launcher(shared_opts)
  if z3ed_ok and z3ed_bin and z3ed_bin ~= "" then
    local command = string.format(
      "cd %s && clear && printf 'z3ed\\n\\n' && %s --help; printf '\\n'; exec /bin/zsh -l",
      shell_quote(get_yaze_dir()),
      shell_quote(z3ed_bin)
    )
    z3ed_action_cache = terminal_session_command("launch_z3ed", command)
  else
    z3ed_action_cache = ""
  end
  return z3ed_action_cache
end

-- Modifier key symbols and their skhd representations
shortcuts.modifiers = {
  cmd = "cmd",      -- ⌘  Command
  ctrl = "ctrl",    -- ⌃  Control
  alt = "alt",      -- ⌥  Option/Alt
  shift = "shift",  -- ⇧  Shift
  hyper = "hyper",  -- ⌃⌥⇧⌘ All modifiers
}

-- Key symbols for display
shortcuts.symbols = {
  cmd = "⌘",
  ctrl = "⌃",
  alt = "⌥",
  shift = "⇧",
  return_key = "↩",
  delete = "⌫",
  escape = "⎋",
  tab = "⇥",
  space = "␣",
  up = "↑",
  down = "↓",
  left = "←",
  right = "→",
}

-- Global shortcuts (cmd/alt focused)
shortcuts.global = {
  -- Barista UI
  {
    mods = {"cmd", "alt"},
    key = "p",
    action = "open_control_panel",
    desc = "Open Barista",
    symbol = "⌘⌥P"
  },
  {
    mods = {"cmd", "alt"},
    key = "d",
    action = "open_task_focus",
    desc = "Open Task Focus",
    symbol = "⌘⌥D"
  },
  {
    mods = {"cmd", "alt"},
    key = "n",
    action = "capture_task",
    desc = "Capture Task",
    symbol = "⌘⌥N",
    requires = "task_source"
  },
  {
    mods = {"cmd", "alt"},
    key = "0x2C",
    action = "toggle_control_center",
    desc = "Toggle Control Center",
    symbol = "⌘⌥/"
  },
  {
    mods = {"cmd", "alt"},
    key = "h",
    action = "open_help_center",
    desc = "Open Help Center",
    symbol = "⌘⌥H"
  },
  {
    mods = {"cmd", "alt"},
    key = "i",
    action = "open_icon_browser",
    desc = "Open Icon Browser",
    symbol = "⌘⌥I"
  },
  {
    mods = {"cmd", "alt"},
    key = "t",
    action = "open_terminal",
    desc = "Open Terminal",
    symbol = "⌘⌥T"
  },
  {
    mods = {"cmd", "alt"},
    key = "z",
    action = "launch_z3ed",
    desc = "Launch z3ed",
    symbol = "⌘⌥Z",
    requires = "z3ed"
  },
  {
    mods = {"cmd", "alt"},
    key = "o",
    action = "toggle_keyboard_overlay",
    desc = "Toggle Keyboard Overlay",
    symbol = "⌘⌥O"
  },
  {
    mods = {"cmd", "alt"},
    key = "r",
    action = "reload_sketchybar",
    desc = "Reload SketchyBar",
    symbol = "⌘⌥R"
  },
  {
    mods = {"cmd", "alt", "shift"},
    key = "r",
    action = "rebuild_and_reload",
    desc = "Rebuild + Reload SketchyBar",
    symbol = "⌘⌥⇧R"
  },

  -- Agentic AI Launchers
  {
    mods = {"cmd", "alt"},
    key = "a",
    action = "launch_antigravity",
    desc = "Launch Antigravity",
    symbol = "⌘⌥A"
  },
  {
    mods = {"cmd", "alt"},
    key = "c",
    action = "launch_claude_code",
    desc = "Launch Claude Code",
    symbol = "⌘⌥C"
  },
  {
    mods = {"cmd", "alt"},
    key = "w",
    action = "open_workspace_navigator",
    desc = "Workspace Navigator",
    symbol = "⌘⌥W"
  },
  {
    mods = {"cmd", "alt"},
    key = "k",
    action = "stop_all_agents",
    desc = "Stop All Agents",
    symbol = "⌘⌥K"
  },

  -- Yabai Controls
  {
    mods = {"cmd", "alt"},
    key = "y",
    action = "toggle_yabai_shortcuts",
    desc = "Toggle Yabai Shortcuts",
    symbol = "⌘⌥Y",
    requires = "window_manager"
  },

  -- Space Navigation (ctrl + arrows)
  {
    mods = {"ctrl"},
    key = "left",
    action = "space_prev",
    desc = "Previous Space (wrap)",
    symbol = "⌃←",
    requires = "window_manager"
  },
  {
    mods = {"ctrl"},
    key = "right",
    action = "space_next",
    desc = "Next Space (wrap)",
    symbol = "⌃→",
    requires = "window_manager"
  },

  -- Direct Space Navigation (ctrl + 1..9, 0)
  {
    mods = {"ctrl"},
    key = "1",
    action = "focus_space_1",
    desc = "Focus Space 1",
    symbol = "⌃1",
    requires = "window_manager"
  },
  {
    mods = {"ctrl"},
    key = "2",
    action = "focus_space_2",
    desc = "Focus Space 2",
    symbol = "⌃2",
    requires = "window_manager"
  },
  {
    mods = {"ctrl"},
    key = "3",
    action = "focus_space_3",
    desc = "Focus Space 3",
    symbol = "⌃3",
    requires = "window_manager"
  },
  {
    mods = {"ctrl"},
    key = "4",
    action = "focus_space_4",
    desc = "Focus Space 4",
    symbol = "⌃4",
    requires = "window_manager"
  },
  {
    mods = {"ctrl"},
    key = "5",
    action = "focus_space_5",
    desc = "Focus Space 5",
    symbol = "⌃5",
    requires = "window_manager"
  },
  {
    mods = {"ctrl"},
    key = "6",
    action = "focus_space_6",
    desc = "Focus Space 6",
    symbol = "⌃6",
    requires = "window_manager"
  },
  {
    mods = {"ctrl"},
    key = "7",
    action = "focus_space_7",
    desc = "Focus Space 7",
    symbol = "⌃7",
    requires = "window_manager"
  },
  {
    mods = {"ctrl"},
    key = "8",
    action = "focus_space_8",
    desc = "Focus Space 8",
    symbol = "⌃8",
    requires = "window_manager"
  },
  {
    mods = {"ctrl"},
    key = "9",
    action = "focus_space_9",
    desc = "Focus Space 9",
    symbol = "⌃9",
    requires = "window_manager"
  },
  {
    mods = {"ctrl"},
    key = "0",
    action = "focus_space_10",
    desc = "Focus Space 10",
    symbol = "⌃0",
    requires = "window_manager"
  },

  -- Direct Window to Space (ctrl + shift + 1..9, 0)
  {
    mods = {"ctrl", "shift"},
    key = "1",
    action = "send_window_space_1",
    desc = "Send Window to Space 1",
    symbol = "⌃⇧1",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "2",
    action = "send_window_space_2",
    desc = "Send Window to Space 2",
    symbol = "⌃⇧2",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "3",
    action = "send_window_space_3",
    desc = "Send Window to Space 3",
    symbol = "⌃⇧3",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "4",
    action = "send_window_space_4",
    desc = "Send Window to Space 4",
    symbol = "⌃⇧4",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "5",
    action = "send_window_space_5",
    desc = "Send Window to Space 5",
    symbol = "⌃⇧5",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "6",
    action = "send_window_space_6",
    desc = "Send Window to Space 6",
    symbol = "⌃⇧6",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "7",
    action = "send_window_space_7",
    desc = "Send Window to Space 7",
    symbol = "⌃⇧7",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "8",
    action = "send_window_space_8",
    desc = "Send Window to Space 8",
    symbol = "⌃⇧8",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "9",
    action = "send_window_space_9",
    desc = "Send Window to Space 9",
    symbol = "⌃⇧9",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "0",
    action = "send_window_space_10",
    desc = "Send Window to Space 10",
    symbol = "⌃⇧0",
    requires = "window_manager"
  },

  -- Display Movement (cmd + alt + shift)
  {
    mods = {"cmd", "alt", "shift"},
    key = "left",
    action = "window_display_prev",
    desc = "Send to Prev Display",
    symbol = "⌘⌥⇧←",
    requires = "window_manager"
  },
  {
    mods = {"cmd", "alt", "shift"},
    key = "right",
    action = "window_display_next",
    desc = "Send to Next Display",
    symbol = "⌘⌥⇧→",
    requires = "window_manager"
  },

  -- Layout modes (ctrl+shift)
  {
    mods = {"ctrl", "shift"},
    key = "f",
    action = "set_layout_float",
    desc = "Set Float Layout",
    symbol = "⌃⇧F",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "b",
    action = "set_layout_bsp",
    desc = "Set BSP Layout",
    symbol = "⌃⇧B",
    requires = "window_manager"
  },
  {
    mods = {"ctrl", "shift"},
    key = "s",
    action = "set_layout_stack",
    desc = "Set Stack Layout",
    symbol = "⌃⇧S",
    requires = "window_manager"
  },
}

-- Action handlers (maps action names to actual commands)
shortcuts.actions = setmetatable({
  -- SketchyBar
  reload_sketchybar = CONFIG_DIR .. "/plugins/reload_sketchybar.sh",
  rebuild_and_reload = CONFIG_DIR .. "/bin/rebuild_sketchybar.sh",
  open_control_panel = CONFIG_DIR .. "/bin/open_control_panel.sh --tab home",
  toggle_control_center = shortcuts.build_control_center_toggle_command(shortcuts.resolve_control_center_item_name(runtime_state)),
  toggle_keyboard_overlay = CONFIG_DIR .. "/scripts/open_keyboard_overlay.sh",

  -- Yabai
  toggle_yabai_shortcuts = SCRIPTS_DIR .. "/toggle_shortcuts.sh toggle",
  toggle_layout = SCRIPTS_DIR .. "/yabai_control.sh toggle-layout",
  balance_windows = SCRIPTS_DIR .. "/yabai_control.sh balance",
  rotate_layout = SCRIPTS_DIR .. "/yabai_control.sh space-rotate",

  -- Window
  toggle_float = SCRIPTS_DIR .. "/yabai_control.sh window-toggle-float",
  toggle_fullscreen = SCRIPTS_DIR .. "/yabai_control.sh window-toggle-fullscreen",
  center_window = SCRIPTS_DIR .. "/yabai_control.sh window-center",
  minimize_window = "yabai -m window --minimize",
  maximize_window = "yabai -m window --toggle zoom-fullscreen",
  restore_window = "yabai -m window --toggle zoom-fullscreen",

  -- Display
  window_display_next = SCRIPTS_DIR .. "/yabai_control.sh window-display-next",
  window_display_prev = SCRIPTS_DIR .. "/yabai_control.sh window-display-prev",

  -- Space Navigation
  space_prev = SCRIPTS_DIR .. "/yabai_control.sh space-focus-prev-wrap",
  space_next = SCRIPTS_DIR .. "/yabai_control.sh space-focus-next-wrap",
  space_recent = SCRIPTS_DIR .. "/yabai_control.sh space-recent",

  -- Space Movement
  window_space_next = SCRIPTS_DIR .. "/yabai_control.sh window-space-next",
  window_space_prev = SCRIPTS_DIR .. "/yabai_control.sh window-space-prev",
  send_window_space_1 = SCRIPTS_DIR .. "/yabai_control.sh window-space 1",
  send_window_space_2 = SCRIPTS_DIR .. "/yabai_control.sh window-space 2",
  send_window_space_3 = SCRIPTS_DIR .. "/yabai_control.sh window-space 3",
  send_window_space_4 = SCRIPTS_DIR .. "/yabai_control.sh window-space 4",
  send_window_space_5 = SCRIPTS_DIR .. "/yabai_control.sh window-space 5",
  send_window_space_6 = SCRIPTS_DIR .. "/yabai_control.sh window-space 6",
  send_window_space_7 = SCRIPTS_DIR .. "/yabai_control.sh window-space 7",
  send_window_space_8 = SCRIPTS_DIR .. "/yabai_control.sh window-space 8",
  send_window_space_9 = SCRIPTS_DIR .. "/yabai_control.sh window-space 9",
  send_window_space_10 = SCRIPTS_DIR .. "/yabai_control.sh window-space 10",

  -- Layout Modes
  set_layout_float = SCRIPTS_DIR .. "/space_mode.sh current float",
  set_layout_bsp = SCRIPTS_DIR .. "/space_mode.sh current bsp",
  set_layout_stack = SCRIPTS_DIR .. "/space_mode.sh current stack",

  -- Window Focus (vim keys)
  focus_window_west = "yabai -m window --focus west",
  focus_window_south = "yabai -m window --focus south",
  focus_window_north = "yabai -m window --focus north",
  focus_window_east = "yabai -m window --focus east",

  -- Space Focus
  focus_space_1 = "yabai -m space --focus 1",
  focus_space_2 = "yabai -m space --focus 2",
  focus_space_3 = "yabai -m space --focus 3",
  focus_space_4 = "yabai -m space --focus 4",
  focus_space_5 = "yabai -m space --focus 5",
  focus_space_6 = "yabai -m space --focus 6",
  focus_space_7 = "yabai -m space --focus 7",
  focus_space_8 = "yabai -m space --focus 8",
  focus_space_9 = "yabai -m space --focus 9",
  focus_space_10 = "yabai -m space --focus 10",
}, {
  __index = function(t, key)
    local val = nil
    if key == "open_terminal" then
      val = terminal_app_command()
    elseif key == "open_task_focus" then
      val = task_focus_action()
    elseif key == "capture_task" then
      val = task_capture_action()
    elseif key == "open_help_center" then
      val = help_center_action()
    elseif key == "open_icon_browser" then
      val = icon_browser_action()
    elseif key == "open_sys_manual" then
      val = sys_manual_action()
    elseif key == "launch_antigravity" then
      local launcher = select(1, locator.resolve_antigravity_launcher(shared_opts))
      if launcher and launcher ~= "" then
        val = terminal_session_command("launch_antigravity", launcher)
      else
        val = ""
      end
    elseif key == "launch_claude_code" then
      local launcher = select(1, locator.resolve_claude_launcher(shared_opts))
      if launcher and launcher ~= "" then
        val = terminal_session_command("launch_claude_code", launcher)
      else
        val = ""
      end
    elseif key == "open_workspace_navigator" then
      local launcher = select(1, locator.resolve_ws_launcher(shared_opts))
      if launcher and launcher ~= "" then
        val = terminal_session_command("open_workspace_navigator", launcher)
      else
        val = ""
      end
    elseif key == "stop_all_agents" then
      local launcher = select(1, locator.resolve_stop_agents_launcher(shared_opts))
      if launcher and launcher ~= "" then
        val = terminal_session_command("stop_all_agents", launcher)
      else
        val = ""
      end
    elseif key == "launch_loom" then
      local launcher = select(1, locator.resolve_loom_launcher(shared_opts))
      if launcher and launcher ~= "" then
        val = terminal_session_command("launch_loom", launcher)
      else
        val = ""
      end
    elseif key == "open_handoff_notes" then
      local handoff_doc = CONFIG_DIR .. "/docs/guides/HANDOFF.md"
      if locator.path_exists(handoff_doc, false) then
        val = open_path_command(handoff_doc)
      else
        val = ""
      end
    elseif key == "launch_cortex" then
      local cortex_launcher, cortex_ok = locator.resolve_cortex_launcher(shared_opts)
      if cortex_ok and cortex_launcher and cortex_launcher ~= "" then
        val = open_app_command(cortex_launcher, "Cortex")
      else
        val = ""
      end
    elseif key == "launch_afs_browser" then
      local app = select(1, locator.resolve_afs_browser_app(shared_opts))
      local cmd = open_app_command(app, "")
      val = (cmd ~= "") and cmd or afs_studio_action()
    elseif key == "launch_afs_studio" then
      val = afs_studio_action()
    elseif key == "launch_afs_labeler" then
      val = afs_labeler_action()
    elseif key == "launch_stemforge" then
      local app = select(1, locator.resolve_stemforge_app(shared_opts))
      val = open_app_command(app, "StemForge")
    elseif key == "launch_stem_sampler" then
      local app = select(1, locator.resolve_stem_sampler_app(shared_opts))
      val = open_app_command(app, "StemSampler")
    elseif key == "launch_yaze" then
      val = get_yaze_action()
    elseif key == "launch_z3ed" then
      val = get_z3ed_action()
    end
    if val ~= nil then
      rawset(t, key, val)
      return val
    end
    return nil
  end
})

local function all_shortcuts()
  local list = {}
  local wm_enabled = window_manager_enabled()
  local yaze_enabled = get_yaze_enabled()
  local z3ed_available = get_z3ed_action() ~= ""
  local task_source_configured = shortcuts.has_task_source(runtime_state)
  for _, shortcut in ipairs(shortcuts.global) do
    local requires = shortcut.requires
    if not requires then
      table.insert(list, shortcut)
    elseif requires == "yaze" and yaze_enabled then
      table.insert(list, shortcut)
    elseif requires == "z3ed" and z3ed_available then
      table.insert(list, shortcut)
    elseif requires == "task_source" and task_source_configured then
      table.insert(list, shortcut)
    elseif requires == "window_manager" and wm_enabled then
      table.insert(list, shortcut)
    end
  end
  return list
end

-- Get shortcut by action name
function shortcuts.get(action_name)
  for _, shortcut in ipairs(all_shortcuts()) do
    if shortcut.action == action_name then
      return shortcut
    end
  end
  return nil
end

-- Get shortcut symbol for display
function shortcuts.get_symbol(action_name)
  local symbols = {}
  for _, shortcut in ipairs(all_shortcuts()) do
    if shortcut.action == action_name and shortcut.symbol then
      table.insert(symbols, shortcut.symbol)
    end
  end
  if #symbols == 0 then
    return ""
  end
  return table.concat(symbols, " / ")
end

-- Get command for action
function shortcuts.get_command(action_name)
  return shortcuts.actions[action_name] or ""
end

-- Format shortcut for skhd config
function shortcuts.format_for_skhd(shortcut)
  if not shortcut or not shortcut.mods or not shortcut.key then
    return nil
  end

  local mods_str = table.concat(shortcut.mods, " + ")
  local command = shortcuts.get_command(shortcut.action)

  if command == "" then
    return nil
  end

  return string.format("%s - %s : %s", mods_str, shortcut.key, command)
end

-- Generate skhd configuration
function shortcuts.generate_skhd_config()
  local lines = {
    "# SketchyBar Shortcuts",
    "# Generated by barista shortcuts module",
    "# cmd/alt focused shortcut set",
    "",
  }

  for _, shortcut in ipairs(all_shortcuts()) do
    local formatted = shortcuts.format_for_skhd(shortcut)
    if formatted then
      table.insert(lines, string.format("# %s - %s", shortcut.desc, shortcut.symbol))
      table.insert(lines, string.format("# barista-action: %s", shortcut.action))
      table.insert(lines, formatted)
      table.insert(lines, "")
    end
  end

  return table.concat(lines, "\n")
end

-- Write skhd configuration to file
function shortcuts.write_skhd_config(filepath)
  filepath = filepath or os.getenv("HOME") .. "/.config/skhd/barista_shortcuts.conf"

  local config = shortcuts.generate_skhd_config()
  local file = io.open(filepath, "w")

  if not file then
    return false, "Could not open file for writing: " .. filepath
  end

  file:write(config)
  file:close()

  return true, filepath
end

-- List all shortcuts
function shortcuts.list_all()
  local list = {}
  for _, shortcut in ipairs(all_shortcuts()) do
    table.insert(list, {
      desc = shortcut.desc,
      symbol = shortcut.symbol,
      action = shortcut.action,
      command = shortcuts.get_command(shortcut.action)
    })
  end
  return list
end

-- List the declarative shortcut catalog without machine-availability filtering.
-- Generated documentation uses this so it stays stable across Macs; skhd output
-- continues to use list_all()/all_shortcuts() and omits unavailable actions.
function shortcuts.list_declared()
  local list = {}
  for _, shortcut in ipairs(shortcuts.global) do
    table.insert(list, {
      desc = shortcut.desc,
      symbol = shortcut.symbol,
      action = shortcut.action,
      requires = shortcut.requires,
    })
  end
  return list
end

-- Check for conflicts (basic check)
function shortcuts.check_conflicts()
  local seen = {}
  local conflicts = {}

  for _, shortcut in ipairs(all_shortcuts()) do
    local key_combo = string.format("%s-%s", table.concat(shortcut.mods, "+"), shortcut.key)
    if seen[key_combo] then
      table.insert(conflicts, {
        combo = key_combo,
        actions = {seen[key_combo], shortcut.action}
      })
    else
      seen[key_combo] = shortcut.action
    end
  end

  return conflicts
end

return shortcuts
