-- popup_action.lua
-- Handles popup-based actions instead of nested submenus
-- This provides a simpler, more reliable UX without race conditions

local popup_action = {}
local binary_resolver = require("binary_resolver")
local SKETCHYBAR_BIN = binary_resolver.resolve_sketchybar_bin()
local DEFAULT_CONTROL_CENTER_ITEM_NAME = "control_center"

local function shell_quote(value)
  return string.format("%q", tostring(value))
end

local function run_command(command, opts)
  local runner = opts and opts.exec or os.execute
  return runner(command)
end

local function sketchybar_exec(cmd, opts)
  local sketchybar_bin = (opts and opts.sketchybar_bin) or SKETCHYBAR_BIN
  return run_command(shell_quote(sketchybar_bin) .. " " .. cmd, opts)
end

-- Popup definitions
local popup_definitions = {
  rom_hacking = {
    name = "popup.rom_hacking",
    icon = "󰊕",
    label = "ROM Hacking",
    items = function(ctx)
      -- Reuse existing rom_hacking_items function
      return require("menu").rom_hacking_items(ctx)
    end
  },
  emacs_workspace = {
    name = "popup.emacs_workspace",
    icon = "󰘔",
    label = "Emacs Workspace",
    items = function(ctx)
      return require("menu").emacs_items(ctx)
    end
  },
  halext_org = {
    name = "popup.halext_org",
    icon = "󱓷",
    label = "halext-org",
    items = function(ctx)
      return require("menu").halext_items(ctx)
    end
  },
  apps_tools = {
    name = "popup.apps_tools",
    icon = "󰖟",
    label = "Apps & Tools",
    items = function(ctx)
      return require("menu").app_tool_items(ctx)
    end
  },
  dev_utilities = {
    name = "popup.dev_utilities",
    icon = "󰙨",
    label = "Dev Utilities",
    items = function(ctx)
      return require("menu").dev_tool_items(ctx)
    end
  },
  help_tips = {
    name = "popup.help_tips",
    icon = "󰋖",
    label = "Help & Tips",
    items = function(ctx)
      return require("menu").help_items(ctx)
    end
  },
  launch_agents = {
    name = "popup.launch_agents",
    icon = "󰳟",
    label = "Launch Agents",
    items = function(ctx)
      return require("menu").launch_agent_items(ctx)
    end
  },
  debug_tools = {
    name = "popup.debug_tools",
    icon = "󰃤",
    label = "Debug Tools",
    items = function(ctx)
      return require("menu").debug_tool_items(ctx)
    end
  },
  control_panel = {
    name = "popup.control_panel",
    icon = "󰒓",
    label = "Control Panel",
    action = function(ctx, opts)
      -- Launch the unified config window
      local script = (ctx and ctx.scripts and ctx.scripts.open_control_panel)
        or (ctx and ctx.paths and ctx.paths.apple_launcher)
      if not script or script == "" then
        return false
      end
      run_command(string.format("%s --panel &", shell_quote(script)), opts)
      return true
    end
  }
}

function popup_action.resolve_control_center_item_name(ctx, getenv_fn)
  if ctx and ctx.control_center_item_name and ctx.control_center_item_name ~= "" then
    return ctx.control_center_item_name
  end

  local getenv = getenv_fn or os.getenv
  local env_name = getenv and getenv("BARISTA_CONTROL_CENTER_ITEM_NAME") or nil
  if env_name and env_name ~= "" then
    return env_name
  end

  local state = ctx and ctx.state
  local integrations = state and state.integrations
  local control_center = type(integrations) == "table" and integrations.control_center or nil
  local state_name = type(control_center) == "table" and (control_center.item_name or control_center.name) or nil
  if state_name and state_name ~= "" then
    return state_name
  end

  return DEFAULT_CONTROL_CENTER_ITEM_NAME
end

function popup_action.resolve_popup_parent(ctx, getenv_fn)
  return "popup." .. popup_action.resolve_control_center_item_name(ctx, getenv_fn)
end

-- Render a popup
function popup_action.render_popup(popup_id, ctx, opts)
  opts = type(opts) == "table" and opts or {}
  local definitions = opts.definitions or popup_definitions
  local def = definitions[popup_id]
  if not def then
    return false
  end

  -- If popup has direct action, execute it
  if def.action then
    return def.action(ctx, opts) ~= false
  end

  -- Otherwise, render popup items
  local items = def.items and def.items(ctx) or {}
  local popup_parent = popup_action.resolve_popup_parent(ctx, opts.getenv)
  
  -- Create popup container
  sketchybar_exec(string.format(
    "--add item %q %q",
    def.name,
    popup_parent
  ), opts)
  
  sketchybar_exec(string.format(
    "--set %q popup.drawing=off popup.background.color=0xC021162F popup.background.corner_radius=6",
    def.name
  ), opts)

  -- Add items to popup
  for i, item in ipairs(items) do
    if item.type == "item" then
      local item_name = def.name .. "." .. item.name
      sketchybar_exec(string.format(
        "--add item %q %q",
        item_name,
        "popup." .. def.name
      ), opts)
      
      local icon = item.icon and string.format('icon="%s"', item.icon) or ""
      local label = item.label and string.format('label="%s"', item.label) or ""
      local action = item.action and string.format('click_script="%s"', item.action) or ""
      
      sketchybar_exec(string.format(
        "--set %q %s %s %s",
        item_name, icon, label, action
      ), opts)
    elseif item.type == "separator" then
      -- Add separator
      sketchybar_exec(string.format(
        "--add item %q %q",
        string.format("%s.sep%d", def.name, i),
        "popup." .. def.name
      ), opts)
      sketchybar_exec(string.format(
        "--set %q drawing=off",
        string.format("%s.sep%d", def.name, i)
      ), opts)
    end
  end

  -- Show popup
  sketchybar_exec(string.format("--set %q popup.drawing=on", def.name), opts)
  
  return true
end

-- Open popup action handler
function popup_action.open_popup(popup_id, ctx, opts)
  return popup_action.render_popup(popup_id, ctx, opts)
end

-- Close all popups
function popup_action.close_all(opts)
  opts = type(opts) == "table" and opts or {}
  local definitions = opts.definitions or popup_definitions
  for _, def in pairs(definitions) do
    sketchybar_exec(string.format("--set %q popup.drawing=off", def.name), opts)
  end
end

return popup_action
