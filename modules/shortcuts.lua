-- Keyboard Shortcut Management Module
-- Centralized shortcut definitions
-- Non-conflicting shortcuts for global operations

local shortcuts = {}
local HOME = os.getenv("HOME")
local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")

local function expand_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  end
  return path
end

local function read_state_scripts_dir()
  local ok, json = pcall(require, "json")
  if not ok then
    return nil
  end

  local state_file = CONFIG_DIR .. "/state.json"
  local file = io.open(state_file, "r")
  if not file then
    return nil
  end

  local contents = file:read("*a")
  file:close()

  local ok_decode, data = pcall(json.decode, contents)
  if not ok_decode or type(data) ~= "table" then
    return nil
  end

  if type(data.paths) ~= "table" then
    return nil
  end

  local candidate = data.paths.scripts_dir or data.paths.scripts
  return expand_path(candidate)
end

local function read_state_code_dir()
  local ok, json = pcall(require, "json")
  if not ok then
    return nil
  end

  local state_file = CONFIG_DIR .. "/state.json"
  local file = io.open(state_file, "r")
  if not file then
    return nil
  end

  local contents = file:read("*a")
  file:close()

  local ok_decode, data = pcall(json.decode, contents)
  if not ok_decode or type(data) ~= "table" then
    return nil
  end

  if type(data.paths) ~= "table" then
    return nil
  end

  local candidate = data.paths.code_dir or data.paths.code
  return expand_path(candidate)
end

local function command_path(command)
  if not command or command == "" then
    return nil
  end
  local handle = io.popen(string.format("command -v %q 2>/dev/null", command))
  if not handle then
    return nil
  end
  local result = handle:read("*a") or ""
  handle:close()
  result = result:gsub("%s+$", "")
  if result == "" then
    return nil
  end
  return result
end

local function path_is_executable(path)
  if not path or path == "" then
    return false
  end
  local ok = os.execute(string.format("test -x %q", path))
  return ok == true or ok == 0
end

local function path_exists(path, want_dir)
  if not path or path == "" then
    return false
  end
  local flag = want_dir and "-d" or "-e"
  local ok = os.execute(string.format("test %s %q", flag, path))
  return ok == true or ok == 0
end

local function shell_quote(value)
  return string.format("%q", tostring(value))
end

local function open_terminal(command)
  if not command or command == "" then
    return ""
  end
  return string.format("osascript -e 'tell application \"Terminal\" to do script %q'", command)
end

local function resolve_code_dir()
  local candidate = read_state_code_dir() or os.getenv("BARISTA_CODE_DIR") or (HOME .. "/src")
  candidate = expand_path(candidate) or (HOME .. "/src")
  local fallback = HOME .. "/src"
  if candidate and candidate:match("/Code/?$") and path_exists(fallback, true) then
    return fallback
  end
  if candidate and not path_exists(candidate, true) and path_exists(fallback, true) then
    return fallback
  end
  if candidate and not path_exists(candidate .. "/lab", true) and path_exists(fallback .. "/lab", true) then
    return fallback
  end
  return candidate
end

local function resolve_path(candidates, want_dir)
  local fallback = nil
  local max_index = 0
  for index in pairs(candidates or {}) do
    if type(index) == "number" and index > max_index then
      max_index = index
    end
  end
  for i = 1, max_index do
    local candidate = candidates[i]
    if candidate and candidate ~= "" then
      candidate = expand_path(candidate)
      fallback = fallback or candidate
      if path_exists(candidate, want_dir) then
        return candidate, true
      end
    end
  end
  return fallback, false
end

local function resolve_executable_path(candidates)
  local fallback = nil
  local max_index = 0
  for index in pairs(candidates or {}) do
    if type(index) == "number" and index > max_index then
      max_index = index
    end
  end
  for i = 1, max_index do
    local candidate = candidates[i]
    if candidate and candidate ~= "" then
      candidate = expand_path(candidate)
      fallback = fallback or candidate
      if path_is_executable(candidate) then
        return candidate, true
      end
    end
  end
  return fallback, false
end

local function resolve_afs_root(code_dir)
  return resolve_path({
    os.getenv("AFS_ROOT"),
    code_dir and (code_dir .. "/lab/afs") or nil,
    code_dir and (code_dir .. "/afs") or nil,
  }, true)
end

local function resolve_afs_studio_root(code_dir, afs_root)
  return resolve_path({
    os.getenv("AFS_STUDIO_ROOT"),
    afs_root and (afs_root .. "/apps/studio") or nil,
    code_dir and (code_dir .. "/lab/afs/apps/studio") or nil,
    code_dir and (code_dir .. "/lab/afs_studio") or nil,
    code_dir and (code_dir .. "/afs/apps/studio") or nil,
    code_dir and (code_dir .. "/afs_studio") or nil,
  }, true)
end

local function resolve_afs_browser_app(code_dir)
  return resolve_path({
    os.getenv("AFS_BROWSER_APP"),
    code_dir and (code_dir .. "/lab/afs_suite/build/apps/browser/afs-browser.app") or nil,
    code_dir and (code_dir .. "/lab/afs_suite/build_ai/apps/browser/afs-browser.app") or nil,
    code_dir and (code_dir .. "/lab/afs_suite/build/apps/browser/Debug/afs-browser.app") or nil,
    code_dir and (code_dir .. "/lab/afs_suite/build/apps/browser/Release/afs-browser.app") or nil,
  }, true)
end

local function resolve_stemforge_app(code_dir)
  return resolve_path({
    os.getenv("STEMFORGE_APP"),
    code_dir and (code_dir .. "/tools/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app") or nil,
    code_dir and (code_dir .. "/tools/stemforge/build/StemForge_artefacts/Debug/Standalone/StemForge.app") or nil,
    code_dir and (code_dir .. "/lab/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app") or nil,
    code_dir and (code_dir .. "/stemforge/build/StemForge_artefacts/Release/Standalone/StemForge.app") or nil,
    HOME .. "/Applications/StemForge.app",
    "/Applications/StemForge.app",
  }, true)
end

local function resolve_stem_sampler_app(code_dir)
  return resolve_path({
    os.getenv("STEM_SAMPLER_APP"),
    code_dir and (code_dir .. "/tools/stemsampler/StemSampler.app") or nil,
    code_dir and (code_dir .. "/tools/stem_sampler/StemSampler.app") or nil,
    HOME .. "/Applications/StemSampler.app",
    "/Applications/StemSampler.app",
  }, true)
end

local function resolve_yaze_app(code_dir)
  return resolve_path({
    code_dir and (code_dir .. "/hobby/yaze/build/bin/yaze.app") or nil,
    code_dir and (code_dir .. "/yaze/build/bin/yaze.app") or nil,
  }, true)
end

local function resolve_sys_manual_binary(code_dir)
  return resolve_executable_path({
    code_dir and (code_dir .. "/lab/sys_manual/build/sys_manual") or nil,
    code_dir and (code_dir .. "/sys_manual/build/sys_manual") or nil,
    "/Applications/sys_manual.app/Contents/MacOS/sys_manual",
  })
end

local function resolve_sys_manual_doc(code_dir)
  return resolve_path({
    code_dir and (code_dir .. "/lab/sys_manual/README.md") or nil,
    code_dir and (code_dir .. "/sys_manual/README.md") or nil,
  }, false)
end

local function resolve_help_center_bin()
  return resolve_executable_path({
    CONFIG_DIR .. "/gui/bin/help_center",
    CONFIG_DIR .. "/build/bin/help_center",
  })
end

local function resolve_icon_browser_bin()
  return resolve_executable_path({
    CONFIG_DIR .. "/gui/bin/icon_browser",
    CONFIG_DIR .. "/build/bin/icon_browser",
  })
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

local function resolve_cortex_cli()
  local override = os.getenv("CORTEX_CLI") or os.getenv("CORTEX_CLI_PATH")
  if override and override ~= "" then
    override = expand_path(override)
    if path_is_executable(override) then
      return override
    end
  end

  local resolved = command_path("cortex-cli")
  if resolved then
    return resolved
  end

  local code_dir = resolve_code_dir()
  local candidates = {
    code_dir .. "/lab/cortex/bin/cortex-cli",
    code_dir .. "/cortex/bin/cortex-cli",
    HOME .. "/.local/bin/cortex-cli",
  }
  for _, candidate in ipairs(candidates) do
    if path_is_executable(candidate) then
      return candidate
    end
  end

  return nil
end

local function scripts_available(path)
  if not path or path == "" then
    return false
  end
  local probe = io.open(path .. "/yabai_control.sh", "r")
  if probe then
    probe:close()
    return true
  end
  probe = io.open(path .. "/toggle_shortcuts.sh", "r")
  if probe then
    probe:close()
    return true
  end
  return false
end

local function resolve_scripts_dir()
  local override = os.getenv("BARISTA_SCRIPTS_DIR")
  if override and override ~= "" then
    return expand_path(override)
  end

  local state_override = read_state_scripts_dir()
  if state_override and state_override ~= "" and scripts_available(state_override) then
    return state_override
  end
  local config_scripts = CONFIG_DIR .. "/scripts"
  if scripts_available(config_scripts) then
    return config_scripts
  end
  local legacy_scripts = HOME .. "/.config/scripts"
  if scripts_available(legacy_scripts) then
    return legacy_scripts
  end
  return config_scripts
end

local SCRIPTS_DIR = resolve_scripts_dir()
local CORTEX_CLI = resolve_cortex_cli() or "cortex-cli"
local CODE_DIR = resolve_code_dir()
local AFS_ROOT = select(1, resolve_afs_root(CODE_DIR))
local AFS_STUDIO_ROOT = select(1, resolve_afs_studio_root(CODE_DIR, AFS_ROOT))
local AFS_BROWSER_APP = select(1, resolve_afs_browser_app(CODE_DIR))
local STEMFORGE_APP = select(1, resolve_stemforge_app(CODE_DIR))
local STEM_SAMPLER_APP = select(1, resolve_stem_sampler_app(CODE_DIR))
local YAZE_APP = select(1, resolve_yaze_app(CODE_DIR))
local SYS_MANUAL_BIN, SYS_MANUAL_OK = resolve_sys_manual_binary(CODE_DIR)
local SYS_MANUAL_DOC = select(1, resolve_sys_manual_doc(CODE_DIR))
local HELP_CENTER_BIN, HELP_CENTER_OK = resolve_help_center_bin()
local ICON_BROWSER_BIN, ICON_BROWSER_OK = resolve_icon_browser_bin()

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
  if path_exists(fallback_doc, false) then
    return open_path_command(fallback_doc)
  end
  return ""
end

local function icon_browser_action()
  if ICON_BROWSER_OK and ICON_BROWSER_BIN then
    return shell_quote(ICON_BROWSER_BIN)
  end
  local fallback_doc = CONFIG_DIR .. "/docs/features/ICON_REFERENCE.md"
  if path_exists(fallback_doc, false) then
    return open_path_command(fallback_doc)
  end
  return ""
end

local function sys_manual_action()
  if SYS_MANUAL_OK and SYS_MANUAL_BIN then
    return shell_quote(SYS_MANUAL_BIN)
  end
  if SYS_MANUAL_DOC then
    return open_path_command(SYS_MANUAL_DOC)
  end
  return ""
end

local function afs_browser_command()
  if not AFS_ROOT or AFS_ROOT == "" then
    return ""
  end
  return string.format("cd %s && python3 -m tui.app", shell_quote(AFS_ROOT))
end

local function afs_studio_command()
  if AFS_ROOT then
    return afs_cli(AFS_ROOT, "studio run --build")
  end
  if AFS_STUDIO_ROOT then
    return string.format(
      "cd %s && cmake --build build --target afs_studio && ./build/afs_studio",
      shell_quote(AFS_STUDIO_ROOT)
    )
  end
  return ""
end

local function afs_labeler_command()
  local studio_root = AFS_STUDIO_ROOT
  if not studio_root or studio_root == "" then
    studio_root = select(1, resolve_afs_studio_root(CODE_DIR, AFS_ROOT))
  end
  local labeler_bin, labeler_bin_ok = resolve_path({
    studio_root and (studio_root .. "/build/afs_labeler") or nil,
    studio_root and (studio_root .. "/build/bin/afs_labeler") or nil,
  }, false)
  local labeler_csv = os.getenv("AFS_LABELER_CSV")
  local labeler_cmd = ""
  if labeler_bin_ok and labeler_bin then
    labeler_cmd = shell_quote(labeler_bin)
  elseif studio_root then
    labeler_cmd = string.format(
      "cd %s && cmake --build build --target afs_labeler && ./build/afs_labeler",
      shell_quote(studio_root)
    )
  end
  if labeler_cmd ~= "" and labeler_csv and labeler_csv ~= "" then
    labeler_cmd = labeler_cmd .. " --csv " .. shell_quote(labeler_csv)
  end
  return labeler_cmd
end

local function afs_studio_action()
  local studio_bin, studio_bin_ok = resolve_path({
    AFS_STUDIO_ROOT and (AFS_STUDIO_ROOT .. "/build/afs_studio") or nil,
    AFS_STUDIO_ROOT and (AFS_STUDIO_ROOT .. "/build/bin/afs_studio") or nil,
  }, false)
  if studio_bin_ok and studio_bin then
    return shell_quote(studio_bin)
  end
  local cmd = afs_studio_command()
  if cmd ~= "" then
    return open_terminal(cmd)
  end
  return ""
end

local function afs_labeler_action()
  local studio_root = AFS_STUDIO_ROOT
  if not studio_root or studio_root == "" then
    studio_root = select(1, resolve_afs_studio_root(CODE_DIR, AFS_ROOT))
  end
  local labeler_bin, labeler_bin_ok = resolve_path({
    studio_root and (studio_root .. "/build/afs_labeler") or nil,
    studio_root and (studio_root .. "/build/bin/afs_labeler") or nil,
  }, false)
  if labeler_bin_ok and labeler_bin then
    return shell_quote(labeler_bin)
  end
  local cmd = afs_labeler_command()
  if cmd ~= "" then
    return open_terminal(cmd)
  end
  return ""
end

local AFS_BROWSER_ACTION = open_app_command(AFS_BROWSER_APP, "")
local AFS_STUDIO_ACTION = afs_studio_action()
local AFS_LABELER_ACTION = afs_labeler_action()
local STEMFORGE_ACTION = open_app_command(STEMFORGE_APP, "StemForge")
local STEM_SAMPLER_ACTION = open_app_command(STEM_SAMPLER_APP, "StemSampler")
local YAZE_ACTION = open_app_command(YAZE_APP, "Yaze")

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
    key = "c",
    action = "toggle_cortex",
    desc = "Toggle Cortex",
    symbol = "⌘⌥C"
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
    key = "k",
    action = "open_help_center",
    desc = "Open Help Center",
    symbol = "⌘⌥K"
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
    symbol = "⌘⌥Y"
  },

  -- Workspace Apps
  {
    mods = {"cmd", "alt"},
    key = "b",
    action = "launch_afs_browser",
    desc = "Launch AFS Browser",
    symbol = "⌘⌥B"
  },
  {
    mods = {"cmd", "alt"},
    key = "s",
    action = "launch_afs_studio",
    desc = "Launch AFS Studio",
    symbol = "⌘⌥S"
  },
  {
    mods = {"cmd", "alt"},
    key = "l",
    action = "launch_afs_labeler",
    desc = "Launch AFS Labeler",
    symbol = "⌘⌥L"
  },
  {
    mods = {"cmd", "alt"},
    key = "f",
    action = "launch_stemforge",
    desc = "Launch StemForge",
    symbol = "⌘⌥F"
  },
  {
    mods = {"cmd", "alt"},
    key = "m",
    action = "launch_stem_sampler",
    desc = "Launch StemSampler",
    symbol = "⌘⌥M"
  },
  {
    mods = {"cmd", "alt"},
    key = "z",
    action = "launch_yaze",
    desc = "Launch Yaze",
    symbol = "⌘⌥Z"
  },
  {
    mods = {"cmd", "alt"},
    key = "d",
    action = "open_sys_manual",
    desc = "Open Sys Manual",
    symbol = "⌘⌥D"
  },

  -- Space Navigation (ctrl + arrows)
  {
    mods = {"ctrl"},
    key = "left",
    action = "space_prev",
    desc = "Previous Space",
    symbol = "⌃←"
  },
  {
    mods = {"ctrl"},
    key = "right",
    action = "space_next",
    desc = "Next Space",
    symbol = "⌃→"
  },

  -- Display Movement (cmd + alt + shift)
  {
    mods = {"cmd", "alt", "shift"},
    key = "left",
    action = "window_display_prev",
    desc = "Send to Prev Display",
    symbol = "⌘⌥⇧←"
  },
  {
    mods = {"cmd", "alt", "shift"},
    key = "right",
    action = "window_display_next",
    desc = "Send to Next Display",
    symbol = "⌘⌥⇧→"
  },

  -- Layout modes (ctrl+shift)
  {
    mods = {"ctrl", "shift"},
    key = "f",
    action = "set_layout_float",
    desc = "Set Float Layout",
    symbol = "⌃⇧F"
  },
  {
    mods = {"ctrl", "shift"},
    key = "b",
    action = "set_layout_bsp",
    desc = "Set BSP Layout",
    symbol = "⌃⇧B"
  },
  {
    mods = {"ctrl", "shift"},
    key = "s",
    action = "set_layout_stack",
    desc = "Set Stack Layout",
    symbol = "⌃⇧S"
  },
}

-- Action handlers (maps action names to actual commands)
shortcuts.actions = {
  -- SketchyBar
  reload_sketchybar = CONFIG_DIR .. "/bin/rebuild_sketchybar.sh --reload-only",
  rebuild_and_reload = CONFIG_DIR .. "/bin/rebuild_sketchybar.sh",
  open_control_panel = CONFIG_DIR .. "/bin/open_control_panel.sh",
  toggle_control_center = "/opt/homebrew/opt/sketchybar/bin/sketchybar --set control_center popup.drawing=toggle",
  open_help_center = help_center_action(),
  open_icon_browser = icon_browser_action(),
  open_sys_manual = sys_manual_action(),
  toggle_cortex = string.format("%q toggle", CORTEX_CLI),

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
  space_prev = SCRIPTS_DIR .. "/yabai_control.sh space-prev",
  space_next = SCRIPTS_DIR .. "/yabai_control.sh space-next",
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
  for _, shortcut in ipairs(shortcuts.global) do
    table.insert(list, shortcut)
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
