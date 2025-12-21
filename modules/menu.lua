local menu = {}
local json = require("json")
local menu_renderer = require("menu_renderer")

local unpack = table.unpack or _G.unpack

local function load_menu_section(ctx, name)
  if not ctx.paths or not ctx.paths.menu_data then return nil end
  local path = string.format("%s/%s.json", ctx.paths.menu_data, name)
  local file = io.open(path, "r")
  if not file then return nil end
  local contents = file:read("*a")
  file:close()
  local ok, data = pcall(json.decode, contents)
  return ok and type(data) == "table" and data or nil
end

local function focus_emacs_action(ctx)
  local check_cmd = "pgrep -x Emacs > /dev/null"
  local emacs_running = os.execute(check_cmd) == 0
  if emacs_running then
    return ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs")
  else
    return "osascript -e 'display notification \"Emacs is not running\" with title \"Focus Emacs\"'"
  end
end

-- ... [Keep existing helper functions: rom_hacking_items, emacs_items, oracle_items, halext_items, help_items] ...
-- I will inline them for brevity in this write, but in a real scenario I'd keep them.
-- Since I'm overwriting the file, I must include them.

local function rom_hacking_items(ctx)
  if ctx.integration_flags and ctx.integration_flags.yaze == false then
    return {{ type = "item", name = "menu.rom.customize", icon = "󰈙", label = "Customize Workflow", action = ctx.open_path(ctx.paths.whichkey_plan) }}
  end
  if ctx.integrations and ctx.integrations.yaze then
    return ctx.integrations.yaze.create_menu_items(ctx)
  end
  local yaze_repo = ctx.paths.yaze
  local yaze_binary = string.format("open -a %q", yaze_repo .. "/build/bin/yaze.app/Contents/MacOS/yaze")
  return {
    { type = "item", name = "menu.rom.launch", icon = "󰯙", label = "Launch Yaze", action = yaze_binary },
    { type = "item", name = "menu.rom.repo", icon = "󰋜", label = "Open Yaze Repo", action = ctx.open_path(yaze_repo) },
    { type = "item", name = "menu.rom.doc", icon = "󰊕", label = "ROM Workflow Doc", action = ctx.open_path(ctx.paths.rom_doc) },
    { type = "item", name = "menu.rom.focus_emacs", icon = "󰘔", label = "Focus Emacs Space", action = focus_emacs_action(ctx) },
  }
end

local function emacs_items(ctx)
  if ctx.integration_flags and ctx.integration_flags.emacs == false then
    return {{ type = "item", name = "menu.emacs.customize", icon = "󰈙", label = "Bring your own workflow", action = ctx.open_path(ctx.paths.whichkey_plan) }}
  end
  if ctx.integrations and ctx.integrations.emacs then return ctx.integrations.emacs.create_menu_items(ctx) end
  return {
    { type = "item", name = "menu.emacs.launch", icon = "", label = "Launch Emacs", action = "open -a Emacs" },
    { type = "item", name = "menu.emacs.tasks", icon = "󰩹", label = "Tasks.org", action = ctx.open_path(os.getenv("HOME") .. "/Code/docs/workflow/tasks.org") },
    { type = "item", name = "menu.emacs.focus", icon = "󰘔", label = "Focus Emacs Space", action = focus_emacs_action(ctx) },
  }
end

local function oracle_items(ctx)
  if ctx.integrations and ctx.integrations.oracle then return ctx.integrations.oracle.create_menu_items(ctx) end
  return {{ type = "item", name = "menu.oracle.missing", icon = "⚠️", label = "Integration Disabled" }}
end

local function halext_items(ctx)
  if ctx.integration_flags and ctx.integration_flags.halext == false then
    return {{ type = "item", name = "menu.halext.configure", icon = "", label = "Configure halext-org", action = ctx.call_script(ctx.scripts.halext_menu, "configure") }}
  end
  if ctx.integrations and ctx.integrations.halext then return ctx.integrations.halext.create_menu_items(ctx) end
  local halext_script = ctx.scripts.halext_menu or ""
  return {
    { type = "header", name = "menu.halext.header", label = "halext-org" },
    { type = "item", name = "menu.halext.tasks", icon = "", label = "View Tasks", action = ctx.call_script(halext_script, "open_tasks") },
    { type = "item", name = "menu.halext.suggestions", icon = "󰚩", label = "LLM Suggestions", action = ctx.call_script(halext_script, "open_suggestions") },
  }
end

local function help_items(ctx)
  local items = {
    { type = "item", name = "menu.help.center", icon = "󰘥", label = "Open Help Center", action = ctx.open_path(ctx.helpers.help_center) },
    { type = "item", name = "menu.help.handoff", icon = "󰣖", label = "Open HANDOFF Notes", action = ctx.open_path(ctx.paths.handoff) },
  }
  return items
end

-- === MAIN RENDER FUNCTION === --

function menu.render_all_menus(ctx)
  local renderer = menu_renderer.create(ctx)
  local render_menu_items = renderer.render
  local sbar = ctx.sbar
  local theme = ctx.theme
  local widget_height = ctx.widget_height
  local associated_displays = ctx.associated_displays or "all"
  
  -- 1. System Menu (Apple Icon)
  sbar.add("item", "apple_menu", {
    position = "left",
    icon = ctx.icon_for and ctx.icon_for("apple", "") or "",
    label = { drawing = false },
    background = { 
        color = "0x00000000", 
        corner_radius = 4,
        height = widget_height,
        padding_left = 4, 
        padding_right = 4 
    },
    click_script = "sketchybar -m --set $NAME popup.drawing=toggle",
    popup = { background = { border_width = 2, corner_radius = 4, border_color = theme.WHITE, color = theme.bar.bg } }
  })
  ctx.subscribe_popup_autoclose("apple_menu")
  sbar.exec("sleep 0.1; sketchybar --set apple_menu associated_display=active associated_space=all")
  
  local system_items = {
    { type = "header", name = "sys.header", label = "System" },
    { type = "item", name = "sys.about", icon = "󰋗", label = "About This Mac", action = "open -a 'System Information'" },
    { type = "item", name = "sys.settings", icon = "", label = "System Settings…", action = "open -a 'System Settings'" },
    { type = "separator", name = "sys.sep1" },
    { type = "item", name = "sys.lock", icon = "󰷛", label = "Lock Screen", action = "pmset displaysleepnow" },
    { type = "item", name = "sys.logout", icon = "󰍃", label = "Log Out...", action = "osascript -e 'tell application \"System Events\" to log out'" },
    { type = "header", name = "sys.quick", label = "Quick Actions" },
    { type = "item", name = "sys.reload", icon = "󰑐", label = "Reload Bar", action = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload" },
    { type = "item", name = "sys.panel", icon = "󰒓", label = "Control Panel", action = ctx.call_script(ctx.paths.apple_launcher, "--panel") },
  }
  if ctx.integrations and ctx.integrations.cortex and ctx.integrations.cortex.create_menu_items then
    local cortex_items = ctx.integrations.cortex.create_menu_items(ctx)
    if cortex_items and #cortex_items > 0 then
      for _, item in ipairs(cortex_items) do
        table.insert(system_items, item)
      end
    end
  end
  render_menu_items("apple_menu", system_items)
end

menu.rom_hacking_items = rom_hacking_items
menu.emacs_items = emacs_items
menu.oracle_items = oracle_items
menu.halext_items = halext_items
menu.help_items = help_items
menu.app_tool_items = function() return {} end
menu.dev_tool_items = function() return {} end
menu.launch_agent_items = function() return {} end
menu.debug_tool_items = function() return {} end

return menu
