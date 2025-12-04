-- popup_action.lua
-- Handles popup-based actions instead of nested submenus
-- This provides a simpler, more reliable UX without race conditions

local popup_action = {}

local function sketchybar_exec(cmd)
  os.execute("/opt/homebrew/opt/sketchybar/bin/sketchybar " .. cmd)
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
    action = function(ctx)
      -- Launch the unified config window
      local script = ctx.scripts.open_control_panel or ctx.paths.apple_launcher
      os.execute(script .. " --panel &")
    end
  }
}

-- Render a popup
function popup_action.render_popup(popup_id, ctx)
  local def = popup_definitions[popup_id]
  if not def then
    return false
  end

  -- If popup has direct action, execute it
  if def.action then
    def.action(ctx)
    return true
  end

  -- Otherwise, render popup items
  local items = def.items and def.items(ctx) or {}
  
  -- Create popup container
  sketchybar_exec(string.format(
    "--add item %s popup.control_center",
    def.name
  ))
  
  sketchybar_exec(string.format(
    "--set %s popup.drawing=off popup.background.color=0xC021162F popup.background.corner_radius=6",
    def.name
  ))

  -- Add items to popup
  for i, item in ipairs(items) do
    if item.type == "item" then
      local item_name = def.name .. "." .. item.name
      sketchybar_exec(string.format(
        "--add item %s popup.%s",
        item_name, def.name
      ))
      
      local icon = item.icon and string.format('icon="%s"', item.icon) or ""
      local label = item.label and string.format('label="%s"', item.label) or ""
      local action = item.action and string.format('click_script="%s"', item.action) or ""
      
      sketchybar_exec(string.format(
        "--set %s %s %s %s",
        item_name, icon, label, action
      ))
    elseif item.type == "separator" then
      -- Add separator
      sketchybar_exec(string.format(
        "--add item %s.sep%d popup.%s",
        def.name, i, def.name
      ))
      sketchybar_exec(string.format(
        "--set %s.sep%d drawing=off",
        def.name, i
      ))
    end
  end

  -- Show popup
  sketchybar_exec(string.format("--set %s popup.drawing=on", def.name))
  
  return true
end

-- Open popup action handler
function popup_action.open_popup(popup_id, ctx)
  return popup_action.render_popup(popup_id, ctx)
end

-- Close all popups
function popup_action.close_all()
  for popup_id, def in pairs(popup_definitions) do
    sketchybar_exec(string.format("--set %s popup.drawing=off", def.name))
  end
end

return popup_action

