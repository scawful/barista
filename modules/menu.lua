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

local function apply_menu_template(value, ctx)
  if type(value) ~= "string" then
    return value
  end
  local config_dir = (ctx.paths and ctx.paths.config_dir) or (os.getenv("BARISTA_CONFIG_DIR") or (os.getenv("HOME") .. "/.config/sketchybar"))
  local code_dir = (ctx.paths and ctx.paths.code_dir) or (os.getenv("BARISTA_CODE_DIR") or (os.getenv("HOME") .. "/src"))
  local expanded = value:gsub("%%CONFIG%%", config_dir)
  expanded = expanded:gsub("%%CODE%%", code_dir)
  return expanded
end

local function path_exists(path, want_dir)
  if not path or path == "" then
    return false
  end
  local flag = want_dir and "-d" or "-e"
  local ok = os.execute(string.format("test %s %q", flag, path))
  return ok == true or ok == 0
end

local function open_terminal(command)
  if not command or command == "" then
    return ""
  end
  return string.format("osascript -e 'tell application \"Terminal\" to do script %q'", command)
end

local function menu_entry_from_data(ctx, entry, prefix)
  if type(entry) ~= "table" then
    return nil
  end
  local id = entry.id or entry.name or entry.label or entry.title or "item"
  local name = string.format("%s.%s", prefix, tostring(id):gsub("%s+", "_"))
  local label = entry.label or entry.title or tostring(id)
  local icon = entry.icon or ""
  local action = nil

  if entry.action == "help_center" then
    action = ctx.open_path(ctx.helpers.help_center)
  elseif entry.path_key and ctx.paths and ctx.paths[entry.path_key] then
    action = ctx.open_path(ctx.paths[entry.path_key])
  elseif entry.command then
    action = apply_menu_template(entry.command, ctx)
  end

  if not action or action == "" then
    return nil
  end

  return { type = "item", name = name, icon = icon, label = label, action = action }
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
  if not path_exists(yaze_repo, true) then
    return {{ type = "item", name = "menu.rom.missing", icon = "⚠️", label = "Yaze Repo Missing", action = ctx.open_path(ctx.paths.whichkey_plan) }}
  end
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
  local code_dir = (ctx.paths and ctx.paths.code_dir) or (os.getenv("BARISTA_CODE_DIR") or (os.getenv("HOME") .. "/src"))
  return {
    { type = "item", name = "menu.emacs.launch", icon = "", label = "Launch Emacs", action = "open -a Emacs" },
    { type = "item", name = "menu.emacs.tasks", icon = "󰩹", label = "Tasks.org", action = ctx.open_path(code_dir .. "/docs/workflow/tasks.org") },
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
  local custom = load_menu_section(ctx, "menu_help")
  if custom then
    local items = {}
    for _, entry in ipairs(custom) do
      local item = menu_entry_from_data(ctx, entry, "menu.help")
      if item then
        table.insert(items, item)
      end
    end
    if #items > 0 then
      return items
    end
  end

  return {
    { type = "item", name = "menu.help.center", icon = "󰘥", label = "Open Help Center", action = ctx.open_path(ctx.helpers.help_center) },
    { type = "item", name = "menu.help.handoff", icon = "󰣖", label = "Open HANDOFF Notes", action = ctx.open_path(ctx.paths.handoff) },
  }
end

-- === MAIN RENDER FUNCTION === --

function menu.render_all_menus(ctx)
  local appearance = ctx.appearance or {}
  local popup_border_width = appearance.popup_border_width or 2
  local popup_corner_radius = appearance.popup_corner_radius or 4
  local popup_border_color = appearance.popup_border_color or ctx.theme.WHITE
  local popup_bg_color = appearance.popup_bg_color or ctx.theme.bar.bg

  -- Use enhanced apple menu if available
  local ok, apple_menu_enhanced = pcall(require, "apple_menu_enhanced")
  if ok then
    -- Enhanced apple menu handles its own rendering
    local HOME = os.getenv("HOME")
    local CONFIG_DIR = os.getenv("BARISTA_CONFIG_DIR") or (HOME .. "/.config/sketchybar")
    local scripts_dir = (ctx.scripts and ctx.scripts.yabai_control and ctx.scripts.yabai_control:match("^(.+)/[^/]+$")) or (CONFIG_DIR .. "/scripts")

    apple_menu_enhanced.setup({
      sbar = ctx.sbar,
      theme = ctx.theme,
      settings = ctx.settings,
      appearance = ctx.appearance,
      widget_height = ctx.widget_height,
      font_string = ctx.font_string,
      attach_hover = ctx.attach_hover,
      subscribe_mouse_exit = ctx.subscribe_popup_autoclose,
      icon_for = ctx.icon_for,
      call_script = ctx.call_script,
      scripts_dir = scripts_dir,
      config_dir = CONFIG_DIR,
      associated_displays = ctx.associated_displays,
      yabai_control_script = ctx.scripts.yabai_control,
    })
    return
  end

  -- Fallback to standard menu rendering
  local renderer = menu_renderer.create(ctx)
  local render_menu_items = renderer.render
  local sbar = ctx.sbar
  local theme = ctx.theme
  local widget_height = ctx.widget_height
  local associated_displays = ctx.associated_displays or "all"
  
  -- 1. System Menu (Apple Icon)
  sbar.add("item", "apple_menu", {
    position = "left",
    icon = ctx.icon_for and ctx.icon_for("apple", "") or "",
    label = { drawing = false },
    associated_display = associated_displays,
    associated_space = "all",
    background = {
        color = "0x00000000",
        corner_radius = 4,
        height = widget_height,
        padding_left = 4,
        padding_right = 4
    },
    click_script = "sketchybar -m --set $NAME popup.drawing=toggle",
    popup = {
      background = {
        border_width = popup_border_width,
        corner_radius = popup_corner_radius,
        border_color = popup_border_color,
        color = popup_bg_color,
      }
    }
  })
  ctx.subscribe_popup_autoclose("apple_menu")
  
  local system_items = {
    { type = "header", name = "sys.header", label = "System" },
    { type = "item", name = "sys.about", icon = "󰋗", label = "About This Mac", action = "open -a 'System Information'" },
    { type = "item", name = "sys.settings", icon = "", label = "System Settings…", action = "open -a 'System Settings'" },
    { type = "separator", name = "sys.sep1" },
    { type = "item", name = "sys.lock", icon = "󰷛", label = "Lock Screen", action = "pmset displaysleepnow" },
    { type = "item", name = "sys.logout", icon = "󰍃", label = "Log Out...", action = "osascript -e 'tell application \"System Events\" to log out'" },
    { type = "header", name = "sys.quick", label = "Quick Actions" },
    { type = "item", name = "sys.reload", icon = "󰑐", label = "Reload Bar", action = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload" },
    { type = "item", name = "sys.panel", icon = "󰒓", label = "Control Panel", action = ctx.call_script(ctx.paths.apple_launcher, "--panel") },
  }
  local agent_ops_items = {}
  local function add_agent_item(item)
    table.insert(agent_ops_items, item)
  end

  if ctx.integrations and ctx.integrations.cortex then
    if ctx.paths and path_exists(ctx.paths.afs, true) then
      local afs_cmd = string.format("cd %q && python3 -m tui.app", ctx.paths.afs)
      add_agent_item({ type = "item", name = "sys.afs.tui", icon = "󰒓", label = "Launch AFS TUI", action = open_terminal(afs_cmd) })
      add_agent_item({ type = "item", name = "sys.afs.repo", icon = "󰈙", label = "Open AFS Repo", action = ctx.open_path(ctx.paths.afs) })
    end
    if ctx.paths and path_exists(ctx.paths.cortex, true) then
      add_agent_item({ type = "item", name = "sys.cortex.repo", icon = "󰈙", label = "Open Cortex Repo", action = ctx.open_path(ctx.paths.cortex) })
    end
  end

  if ctx.integrations and ctx.integrations.halext then
    if ctx.paths and path_exists(ctx.paths.halext_org, true) then
      add_agent_item({ type = "item", name = "sys.halext.repo", icon = "󰈙", label = "Open halext-org Repo", action = ctx.open_path(ctx.paths.halext_org) })
    end
    if ctx.paths and path_exists(ctx.paths.halext_windows, false) then
      add_agent_item({ type = "item", name = "sys.win.doc", icon = "󰈙", label = "Windows Node Setup Doc", action = ctx.open_path(ctx.paths.halext_windows) })
    end
  end

  if ctx.integrations and ctx.integrations.cortex and ctx.integrations.cortex.create_menu_items then
    local cortex_items = ctx.integrations.cortex.create_menu_items(ctx)
    if cortex_items and #cortex_items > 0 then
      for _, item in ipairs(cortex_items) do
        add_agent_item(item)
      end
    end
  end

  if #agent_ops_items > 0 then
    table.insert(system_items, { type = "header", name = "sys.agents", label = "Agent Ops" })
    for _, item in ipairs(agent_ops_items) do
      table.insert(system_items, item)
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
