-- Syshelp Integration Module
-- Integration with the Syshelp System Intelligence & Control CLI

local syshelp = {}

local HOME = os.getenv("HOME")
local SYSHELP_BIN = HOME .. "/.local/bin/syshelp"

-- Configuration
syshelp.config = {
  binary_path = SYSHELP_BIN,
}

-- Check if Syshelp is installed
function syshelp.is_installed()
  local file = io.open(syshelp.config.binary_path, "r")
  if file then
    file:close()
    return true
  end
  return false
end

-- Launch Syshelp Dashboard
function syshelp.launch_dashboard()
  if not syshelp.is_installed() then
    return false, "Syshelp not found at " .. syshelp.config.binary_path
  end

  local cmd = string.format("open -a Terminal %q", syshelp.config.binary_path)
  os.execute(cmd)
  return true
end

-- Run Syshelp command
function syshelp.run_command(command)
  if not syshelp.is_installed() then
    return false, "Syshelp not found"
  end

  local cmd = string.format("open -a Terminal '%s %s'", syshelp.config.binary_path, command)
  os.execute(cmd)
  return true
end

-- Create menu items for Syshelp integration
function syshelp.create_menu_items(ctx)
  local items = {}

  if not syshelp.is_installed() then
    return items
  end

  -- Header
  table.insert(items, {
    type = "header",
    name = "syshelp.header",
    label = "System Intelligence",
  })

  -- Dashboard
  table.insert(items, {
    type = "item",
    name = "syshelp.dashboard",
    icon = "🚀",
    label = "Syshelp Dashboard",
    action = string.format("open -a Terminal %q", syshelp.config.binary_path),
  })

  -- Quick Actions
  table.insert(items, {
    type = "item",
    name = "syshelp.doctor",
    icon = "󰆑",
    label = "System Doctor",
    action = string.format("open -a Terminal '%s doctor'", syshelp.config.binary_path),
  })

  table.insert(items, {
    type = "item",
    name = "syshelp.clean",
    icon = "󰃢",
    label = "Clean System",
    action = string.format("open -a Terminal '%s clean'", syshelp.config.binary_path),
  })
  
  table.insert(items, {
    type = "item",
    name = "syshelp.eval",
    icon = "󰚩",
    label = "AI Eval",
    action = string.format("open -a Terminal '%s eval'", syshelp.config.binary_path),
  })

  return items
end

-- Get status text for display (optional, for widget)
function syshelp.get_status_text()
  return "Syshelp Ready"
end

return syshelp
