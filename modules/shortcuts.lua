-- Keyboard Shortcut Management Module
-- Centralized shortcut definitions
-- Non-conflicting shortcuts for global operations

local shortcuts = {}
local binary_resolver = require("binary_resolver")
local paths_module = require("paths")
local locator = require("tool_locator")

local HOME = os.getenv("HOME") or ""
local CONFIG_DIR = locator.resolve_config_dir()
local runtime_state = locator.load_state(CONFIG_DIR) or {}
local SKETCHYBAR_BIN = binary_resolver.resolve_sketchybar_bin()
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
  return string.format("%q", tostring(value))
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

local function build_control_center_toggle_command(item_name)
  return string.format("%q --set %q popup.drawing=toggle", SKETCHYBAR_BIN, item_name)
end

local function open_terminal(command)
  if not command or command == "" then
    return ""
  end
  return string.format("osascript -e 'tell application \"Terminal\" to do script %q'", command)
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

local function afs_cli(afs_root, args)
  local pythonpath = afs_root .. "/src"
  return string.format(
    "cd %s && AFS_ROOT=%s PYTHONPATH=%s python3 -m afs %s",
    shell_quote(afs_root),
    shell_quote(afs_root),
    shell_quote(pythonpath),
    args or ""
  )
end

local function build_suite_command(studio_root, target_name, binary_name)
  local build_dir = locator.afs_build_dir(studio_root)
  return string.format(
    "cd %s && cmake --build %s --target %s && ./%s/apps/studio/%s",
    shell_quote(studio_root),
    build_dir,
    target_name,
    build_dir,
    binary_name
  )
end

local function build_legacy_command(studio_root, target_name, binary_name)
  return string.format(
    "cd %s && cmake --build build --target %s && ./build/%s",
    shell_quote(studio_root),
    target_name,
    binary_name
  )
end

local function afs_studio_command(afs_root, studio_root)
  if afs_root then
    return afs_cli(afs_root, "studio run --build")
  end
  if not studio_root or studio_root == "" then
    return ""
  end
  if locator.afs_studio_layout(studio_root) == "suite" then
    return build_suite_command(studio_root, "afs-studio", "afs-studio")
  end
  return build_legacy_command(studio_root, "afs_studio", "afs_studio")
end

local function afs_labeler_command(studio_root)
  if not studio_root or studio_root == "" then
    return ""
  end

  local command
  if locator.afs_studio_layout(studio_root) == "suite" then
    command = build_suite_command(studio_root, "afs-labeler", "afs-labeler")
  else
    command = build_legacy_command(studio_root, "afs_labeler", "afs_labeler")
  end

  local labeler_csv = os.getenv("AFS_LABELER_CSV")
  if labeler_csv and labeler_csv ~= "" then
    command = command .. " --csv " .. shell_quote(labeler_csv)
  end
  return command
end

local SCRIPTS_DIR = paths_module.resolve_scripts_dir(CONFIG_DIR, runtime_state)
local shared_opts = {
  config_dir = CONFIG_DIR,
  code_dir = runtime_state.paths and (runtime_state.paths.code_dir or runtime_state.paths.code) or nil,
  state = runtime_state,
}
local CODE_DIR = locator.resolve_code_dir(shared_opts)
shared_opts.code_dir = CODE_DIR

local AFS_ROOT = select(1, locator.resolve_afs_root(shared_opts))
local AFS_STUDIO_ROOT = select(1, locator.resolve_afs_studio_root(shared_opts, AFS_ROOT))
local AFS_STUDIO_LAUNCHER = select(1, locator.resolve_afs_studio_launcher(shared_opts))
local AFS_BROWSER_APP = select(1, locator.resolve_afs_browser_app(shared_opts))
local STEMFORGE_APP = select(1, locator.resolve_stemforge_app(shared_opts))
local STEM_SAMPLER_APP = select(1, locator.resolve_stem_sampler_app(shared_opts))
local YAZE_APP, YAZE_OK = locator.resolve_yaze_app(shared_opts)
local YAZE_LAUNCHER = select(1, locator.resolve_yaze_launcher())
local SYS_MANUAL_BIN, SYS_MANUAL_OK = locator.resolve_sys_manual_binary(shared_opts)
local HELP_CENTER_BIN, HELP_CENTER_OK = locator.resolve_help_center_bin(CONFIG_DIR)
local ICON_BROWSER_BIN, ICON_BROWSER_OK = locator.resolve_icon_browser_bin(CONFIG_DIR)
local function integration_flag(name)
  local integrations = runtime_state.integrations
  local entry = type(integrations) == "table" and integrations[name] or nil
  if type(entry) ~= "table" or entry.enabled == nil then
    return nil
  end
  return entry.enabled ~= false
end

local YAZE_FLAG = integration_flag("yaze")
local YAZE_AVAILABLE = YAZE_OK or (YAZE_LAUNCHER and YAZE_LAUNCHER ~= "")
local YAZE_ENABLED = (YAZE_FLAG == nil) and YAZE_AVAILABLE or (YAZE_FLAG and YAZE_AVAILABLE)

local function open_path_command(path)
  if not path or path == "" then
    return ""
  end
  return string.format("open %s", shell_quote(path))
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
  if HELP_CENTER_OK and HELP_CENTER_BIN then
    return shell_quote(HELP_CENTER_BIN)
  end
  local fallback_doc = CONFIG_DIR .. "/docs/features/ICONS_AND_SHORTCUTS.md"
  if locator.path_exists(fallback_doc, false) then
    return open_path_command(fallback_doc)
  end
  return ""
end

local function icon_browser_action()
  if ICON_BROWSER_OK and ICON_BROWSER_BIN then
    return shell_quote(ICON_BROWSER_BIN)
  end
  local fallback_doc = CONFIG_DIR .. "/docs/features/ICON_REFERENCE.md"
  if locator.path_exists(fallback_doc, false) then
    return open_path_command(fallback_doc)
  end
  return ""
end

local function sys_manual_action()
  if SYS_MANUAL_OK and SYS_MANUAL_BIN then
    return shell_quote(SYS_MANUAL_BIN)
  end
  return ""
end

local function afs_studio_action()
  if AFS_STUDIO_LAUNCHER and AFS_STUDIO_LAUNCHER ~= "" then
    return shell_quote(AFS_STUDIO_LAUNCHER)
  end

  local studio_bin, studio_bin_ok = locator.resolve_afs_studio_binary(AFS_STUDIO_ROOT)
  if studio_bin_ok and studio_bin then
    if studio_bin:match("%.app/?$") then
      return open_path_command(studio_bin)
    end
    return shell_quote(studio_bin)
  end

  local command = afs_studio_command(AFS_ROOT, AFS_STUDIO_ROOT)
  if command ~= "" then
    return open_terminal(command)
  end
  return ""
end

local function afs_labeler_action()
  local labeler_bin, labeler_bin_ok = locator.resolve_afs_labeler_binary(AFS_STUDIO_ROOT)
  if labeler_bin_ok and labeler_bin then
    if labeler_bin:match("%.app/?$") then
      return open_path_command(labeler_bin)
    end
    return shell_quote(labeler_bin)
  end

  local command = afs_labeler_command(AFS_STUDIO_ROOT)
  if command ~= "" then
    return open_terminal(command)
  end
  return ""
end

local AFS_BROWSER_ACTION = open_app_command(AFS_BROWSER_APP, "")
local AFS_STUDIO_ACTION = afs_studio_action()
local AFS_LABELER_ACTION = afs_labeler_action()
local STEMFORGE_ACTION = open_app_command(STEMFORGE_APP, "StemForge")
local STEM_SAMPLER_ACTION = open_app_command(STEM_SAMPLER_APP, "StemSampler")
local YAZE_ACTION = ""
if YAZE_ENABLED then
  if YAZE_LAUNCHER and YAZE_LAUNCHER ~= "" then
    YAZE_ACTION = shell_quote(YAZE_LAUNCHER)
  else
    YAZE_ACTION = open_app_command(YAZE_APP, "Yaze")
  end
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
    desc = "Open Control Panel",
    symbol = "⌘⌥P"
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
shortcuts.actions = {
  -- SketchyBar
  reload_sketchybar = CONFIG_DIR .. "/bin/rebuild_sketchybar.sh --reload-only",
  rebuild_and_reload = CONFIG_DIR .. "/bin/rebuild_sketchybar.sh",
  open_control_panel = CONFIG_DIR .. "/bin/open_control_panel.sh",
  toggle_control_center = build_control_center_toggle_command(shortcuts.resolve_control_center_item_name(runtime_state)),
  open_help_center = help_center_action(),
  open_icon_browser = icon_browser_action(),
  open_sys_manual = sys_manual_action(),
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

  -- Layout Modes
  set_layout_float = SCRIPTS_DIR .. "/space_mode.sh current float",
  set_layout_bsp = SCRIPTS_DIR .. "/space_mode.sh current bsp",
  set_layout_stack = SCRIPTS_DIR .. "/space_mode.sh current stack",

  -- Apps
  open_terminal = "open -a Terminal",
  launch_afs_browser = AFS_BROWSER_ACTION,
  launch_afs_studio = AFS_STUDIO_ACTION,
  launch_afs_labeler = AFS_LABELER_ACTION,
  launch_stemforge = STEMFORGE_ACTION,
  launch_stem_sampler = STEM_SAMPLER_ACTION,
  launch_yaze = YAZE_ACTION,

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
}

local function all_shortcuts()
  local list = {}
  local wm_enabled = window_manager_enabled()
  for _, shortcut in ipairs(shortcuts.global) do
    local requires = shortcut.requires
    if not requires then
      table.insert(list, shortcut)
    elseif requires == "yaze" and YAZE_ENABLED then
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
