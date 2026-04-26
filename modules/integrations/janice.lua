-- Scawfulbot integration module for Barista
-- Launcher for the Scawfulbot macOS app
--
-- Install: Copy to ~/.config/sketchybar/modules/integrations/janice.lua
-- Or symlink: ln -sf ~/src/lab/barista/modules/integrations/janice.lua ~/.config/sketchybar/modules/integrations/

local janice = {}

local HOME = os.getenv("HOME")
local CODE_DIR = os.getenv("BARISTA_CODE_DIR") or (HOME .. "/src")

-- Configuration
janice.config = {
  app_name = "Scawfulbot",
  bundle_id = "com.scawful.Scawfulbot.mac",
  repo_path = CODE_DIR .. "/lab/scawfulbot",
  app_path = CODE_DIR .. "/lab/scawfulbot/apps/apple/build-macos/Build/Products/Debug/Scawfulbot.app",
  home_app_path = HOME .. "/Applications/Scawfulbot.app",
  system_app_path = "/Applications/Scawfulbot.app",
}

local function launch_command()
  return string.format(
    "if [ -d %q ]; then open %q; elseif [ -d %q ]; then open %q; elseif [ -d %q ]; then open %q; else open -b %q; fi",
    janice.config.app_path,
    janice.config.app_path,
    janice.config.home_app_path,
    janice.config.home_app_path,
    janice.config.system_app_path,
    janice.config.system_app_path,
    janice.config.bundle_id
  )
end

-- Check if Scawfulbot is running
function janice.is_running()
  local handle = io.popen("pgrep -x Scawfulbot >/dev/null 2>&1 && echo 1 || echo 0")
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
  os.execute(launch_command())
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
    label = "Scawfulbot",
    icon = status_icon,
    icon_color = status_color,
  })

  -- Open App
  table.insert(items, {
    type = "item",
    name = "janice.open",
    icon = "󰏗",
    label = running and "Show Scawfulbot" or "Launch Scawfulbot",
    action = launch_command(),
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
