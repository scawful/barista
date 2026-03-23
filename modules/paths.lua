-- paths.lua - Path resolution for Barista
-- Extracted from main.lua to centralise path logic.

local shell_utils = require("shell_utils")
local locator = require("tool_locator")

local HOME = os.getenv("HOME")

local M = {}

--- Expand a leading "~/" to $HOME.
function M.expand_path(path)
  return locator.expand_path(path)
end

--- Resolve the scripts directory.
--- Priority: BARISTA_SCRIPTS_DIR env > state.paths.scripts_dir > CONFIG_DIR/scripts > legacy ~/.config/scripts.
function M.resolve_scripts_dir(config_dir, state)
  local override = os.getenv("BARISTA_SCRIPTS_DIR")
  if override and override ~= "" then
    return M.expand_path(override)
  end
  if state and type(state.paths) == "table" then
    local candidate = state.paths.scripts_dir or state.paths.scripts
    candidate = M.expand_path(candidate)
    if candidate and candidate ~= "" then
      local probe = io.open(candidate .. "/yabai_control.sh", "r")
      if probe then
        probe:close()
        return candidate
      end
    end
  end
  local config_scripts = config_dir .. "/scripts"
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

--- Resolve the user's source code directory.
function M.resolve_code_dir(state)
  return locator.resolve_code_dir({
    state = state,
    code_dir = state and state.paths and (state.paths.code_dir or state.paths.code) or nil,
  })
end

--- Resolve the menu_action binary/script.
function M.resolve_menu_action_script(config_dir, plugin_dir)
  local candidates = {
    config_dir .. "/bin/menu_action",
    config_dir .. "/helpers/menu_action",
    plugin_dir .. "/menu_action.sh",
  }
  for _, candidate in ipairs(candidates) do
    if shell_utils.file_exists(candidate) then
      return candidate
    end
  end
  return ""
end

--- Build the standard paths table used by menus and integrations.
function M.build_paths_table(config_dir, code_dir, profile_paths)
  local paths = {
    config_dir     = config_dir,
    code_dir       = code_dir,
    menu_data      = config_dir .. "/data",
    workflow_data  = config_dir .. "/data/workflow_shortcuts.json",
    rom_doc        = code_dir .. "/docs/workflow/rom-hacking.org",
    yaze           = code_dir .. "/yaze",
    afs            = code_dir .. "/afs",
    cortex         = code_dir .. "/cortex",
    halext_org     = code_dir .. "/halext-org",
    halext_windows = code_dir .. "/halext-org/docs/BACKGROUND_AGENTS.md",
    whichkey_plan  = config_dir .. "/docs/features/WHICHKEY_PLAN.md",
    readme         = config_dir .. "/README.md",
    sharing        = config_dir .. "/docs/dev/SHARING.md",
    handoff        = config_dir .. "/docs/guides/HANDOFF.md",
    apple_launcher = config_dir .. "/bin/open_control_panel.sh",
  }
  if profile_paths then
    for k, v in pairs(profile_paths) do
      paths[k] = v
    end
  end
  return paths
end

--- Build the standard scripts table.
function M.build_scripts_table(config_dir, scripts_dir, plugin_dir)
  return {
    menu_action        = M.resolve_menu_action_script(config_dir, plugin_dir),
    set_appearance     = scripts_dir .. "/set_appearance.sh",
    space_mode         = plugin_dir .. "/space_mode.sh",
    logs               = config_dir .. "/plugins/bar_logs.sh",
    yabai_control      = scripts_dir .. "/yabai_control.sh",
    accessibility      = scripts_dir .. "/yabai_accessibility_fix.sh",
    open_control_panel = config_dir .. "/bin/open_control_panel.sh",
    halext_menu        = config_dir .. "/plugins/halext_menu.sh",
    ssh_sync           = config_dir .. "/helpers/ssh_sync.sh",
    cpp_project_switch = config_dir .. "/helpers/cpp_project_switch.sh",
  }
end

return M
