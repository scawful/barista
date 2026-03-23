-- Janice Studio Integration Module for Barista
-- Simple launcher for the Janice Studio macOS app (AI model hub)
--
-- Install: Copy to ~/.config/sketchybar/modules/integrations/janice.lua
-- Or symlink: ln -sf ~/src/lab/barista/modules/integrations/janice.lua ~/.config/sketchybar/modules/integrations/

local janice = {}

local HOME = os.getenv("HOME")
local CODE_DIR = os.getenv("BARISTA_CODE_DIR") or (HOME .. "/src")

-- Configuration
janice.config = {
  app_name = "ModelHub",
  bundle_id = "com.scawful.ModelHub.mac",
  repo_path = CODE_DIR .. "/lab/janice-studio",
}

-- Check if Janice Studio is running
function janice.is_running()
  local handle = io.popen("pgrep -x ModelHub >/dev/null 2>&1 && echo 1 || echo 0")
  if not handle then return false end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("1")
end

-- Get status for bar widgets
function janice.get_status()
  if janice.is_running() then
    return "running", "󰚩", "0xffa6e3a1"  -- green
  else
    return "stopped", "󰚩", "0xff6c7086"  -- gray
  end
end

-- Open the app
function janice.open_app()
  os.execute("open -b " .. janice.config.bundle_id)
  return true
end

-- Create menu items for barista
function janice.create_menu_items(ctx)
  local items = {}
  local running = janice.is_running()
  local status_icon = running and "󰚩" or "󰚩"
  local status_color = running and "0xffa6e3a1" or "0xff6c7086"

  -- Header
  table.insert(items, {
    type = "header",
    name = "janice.header",
    label = "Janice Studio",
    icon = status_icon,
    icon_color = status_color,
  })

  -- Open App
  table.insert(items, {
    type = "item",
    name = "janice.open",
    icon = "󰏗",
    label = running and "Show Janice Studio" or "Launch Janice Studio",
    action = "open -b " .. janice.config.bundle_id,
  })

  if running then
    table.insert(items, { type = "separator", name = "janice.sep1" })

    -- Open Repo
    table.insert(items, {
      type = "item",
      name = "janice.repo",
      icon = "󰋜",
      label = "Open Repository",
      action = string.format("open %q", janice.config.repo_path),
    })
  end

  return items
end

return janice
