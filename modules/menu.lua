local menu = {}
local json = require("json")
local menu_renderer = require("menu_renderer")

local unpack = table.unpack or _G.unpack

local function load_menu_section(ctx, name)
  if not ctx.paths or not ctx.paths.menu_data then
    return nil
  end
  local path = string.format("%s/%s.json", ctx.paths.menu_data, name)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local contents = file:read("*a")
  file:close()
  local ok, data = pcall(json.decode, contents)
  if ok and type(data) == "table" then
    return data
  end
  return nil
end

local function focus_emacs_action(ctx)
  -- Check if Emacs is running
  local check_cmd = "pgrep -x Emacs > /dev/null"
  local emacs_running = os.execute(check_cmd) == 0
  
  if emacs_running then
    return ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs")
  else
    return "osascript -e 'display notification \"Emacs is not running\" with title \"Focus Emacs\"'"
  end
end

local function rom_hacking_items(ctx)
  if ctx.integration_flags and ctx.integration_flags.yaze == false then
    return {
      { type = "item", name = "menu.rom.customize", icon = "󰈙", label = "Customize Workflow (docs/SHARING.md)", action = ctx.open_path(ctx.paths.whichkey_plan) },
    }
  end
  -- Use Yaze integration if available
  if ctx.integrations and ctx.integrations.yaze then
    return ctx.integrations.yaze.create_menu_items(ctx)
  end

  -- Fallback to static items
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
    return {
      { type = "item", name = "menu.emacs.customize", icon = "󰈙", label = "Bring your own workflow", action = ctx.open_path(ctx.paths.whichkey_plan) },
    }
  end
  -- Use Emacs integration if available
  if ctx.integrations and ctx.integrations.emacs then
    return ctx.integrations.emacs.create_menu_items(ctx)
  end

  -- Fallback to static items
  return {
    { type = "item", name = "menu.emacs.launch", icon = "", label = "Launch Emacs", action = "open -a Emacs" },
    { type = "item", name = "menu.emacs.tasks", icon = "󰩹", label = "Tasks.org", action = ctx.open_path(os.getenv("HOME") .. "/Code/docs/workflow/tasks.org") },
    { type = "item", name = "menu.emacs.focus", icon = "󰘔", label = "Focus Emacs Space", action = focus_emacs_action(ctx) },
  }
end

local function halext_items(ctx)
  -- halext-org integration menu items with room for future expansion
  if ctx.integration_flags and ctx.integration_flags.halext == false then
    return {
      { type = "item", name = "menu.halext.configure", icon = "", label = "Configure halext-org", action = ctx.call_script(ctx.scripts.halext_menu, "configure") },
    }
  end

  -- Use halext integration if available
  if ctx.integrations and ctx.integrations.halext then
    return ctx.integrations.halext.create_menu_items(ctx)
  end

  -- Dynamic items based on halext state
  local halext_script = ctx.scripts.halext_menu or ""

  return {
    { type = "header", name = "menu.halext.header", label = "halext-org" },
    { type = "item", name = "menu.halext.tasks", icon = "", label = "View Tasks", action = ctx.call_script(halext_script, "open_tasks") },
    { type = "item", name = "menu.halext.calendar", icon = "", label = "View Calendar", action = ctx.call_script(halext_script, "open_calendar") },
    { type = "item", name = "menu.halext.suggestions", icon = "󰚩", label = "LLM Suggestions", action = ctx.call_script(halext_script, "open_suggestions") },
    { type = "separator", name = "menu.halext.sep1" },
    { type = "item", name = "menu.halext.refresh", icon = "󰑐", label = "Refresh Data", action = ctx.call_script(halext_script, "refresh") },
    { type = "item", name = "menu.halext.configure", icon = "", label = "Configure Integration", action = ctx.call_script(halext_script, "configure") },
  }
end

local function syshelp_items(ctx)
  -- Use Syshelp integration if available
  if ctx.integrations and ctx.integrations.syshelp then
    return ctx.integrations.syshelp.create_menu_items(ctx)
  end
  return {}
end

local function help_items(ctx)
  local data = load_menu_section(ctx, "menu_help")
  local items = {}
  local help_center_action
  if ctx.helpers and ctx.helpers.help_center then
    help_center_action = ctx.open_path(ctx.helpers.help_center)
  else
    help_center_action = [[osascript -e 'display alert "Help Center binary missing" message "Run `cd ~/.config/sketchybar/gui && make help`"']]
  end
  local function expand_command(cmd)
    if not cmd or cmd == "" then return nil end
    if ctx.paths then
      if ctx.paths.home then
        cmd = cmd:gsub("%%HOME%%", ctx.paths.home)
      end
      if ctx.paths.config then
        cmd = cmd:gsub("%%CONFIG%%", ctx.paths.config)
      end
    end
    return cmd
  end
  if data and #data > 0 then
    for index, entry in ipairs(data) do
      local action
      if entry.action == "help_center" then
        action = help_center_action
      elseif entry.command then
        action = expand_command(entry.command)
      elseif entry.path_key and ctx.paths[entry.path_key] then
        action = ctx.open_path(ctx.paths[entry.path_key])
      elseif entry.path then
        local expanded = entry.path
        if expanded:sub(1, 1) == "~" and ctx.paths.home then
          expanded = ctx.paths.home .. expanded:sub(2)
        elseif expanded:sub(1, 1) ~= "/" and ctx.paths.home then
          expanded = ctx.paths.home .. "/" .. expanded
        end
        action = ctx.open_path(expanded)
      end
      if action then
        table.insert(items, {
          type = "item",
          name = entry.id or string.format("menu.help.dynamic.%d", index),
          icon = entry.icon or "",
          label = entry.label or entry.id or "",
          action = action,
        })
      end
    end
  end
  if #items == 0 then
    items = {
      { type = "item", name = "menu.help.center", icon = "󰘥", label = "Open Help Center", action = help_center_action },
      { type = "item", name = "menu.help.whichkey", icon = "󰌌", label = "WhichKey HUD", action = "sketchybar --trigger whichkey_toggle" },
      { type = "item", name = "menu.help.plan", icon = "󰈙", label = "WhichKey Plan", action = ctx.open_path(ctx.paths.whichkey_plan) },
      { type = "item", name = "menu.help.handoff", icon = "󰣖", label = "Open HANDOFF Notes", action = ctx.open_path(ctx.paths.handoff) },
    }
  end
  return items
end

function menu.render_control_center(ctx)
  local renderer = menu_renderer.create(ctx)
  local render_menu_items = renderer.render
  local appearance_action = renderer.appearance_action

  local style_items = {
    { type = "item", name = "menu.sketchybar.opacity.liquid", icon = "󰔚", label = "Liquid Glass", action = appearance_action("0xC021162F", 45) },
    { type = "item", name = "menu.sketchybar.opacity.tinted", icon = "󰔙", label = "Tinted Glass", action = appearance_action("0xD02D1F3A", 38) },
    { type = "item", name = "menu.sketchybar.opacity.classic", icon = "󰔙", label = "Classic Glass", action = appearance_action("0xB04C3B52", 30) },
    { type = "item", name = "menu.sketchybar.opacity.solid", icon = "󰔘", label = "Matte Solid", action = appearance_action("0xFF4C3B52", 0) },
  }

  local sketchybar_tool_items = {
    { type = "item", name = "menu.sketchybar.panel", icon = "󰒓", label = "Control Panel…", action = ctx.call_script(ctx.paths.apple_launcher, "--panel") },
    { type = "item", name = "menu.sketchybar.reload", icon = "󰑐", label = "Reload Bar", action = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload" },
    { type = "item", name = "menu.sketchybar.logs", icon = "󰍛", label = "Follow Logs (Terminal)", action = string.format("open -a Terminal %q", ctx.scripts.logs .. " sketchybar --follow") },
    { type = "item", name = "menu.sketchybar.accessibility", icon = "󰈈", label = "Repair Accessibility", action = ctx.call_script(ctx.scripts.accessibility) },
    { type = "item", name = "menu.sketchybar.shortcuts", icon = "󰌌", label = "Toggle Yabai Shortcuts", action = ctx.call_script(ctx.scripts.toggle_shortcuts, "toggle"), shortcut = "⌃⌥Y" },
  }

  local app_tool_items = {
    { type = "item", name = "menu.apps.appstore", icon = "󰓇", label = "App Store…", action = "open -a 'App Store'" },
    { type = "item", name = "menu.apps.terminal", icon = "", label = "Terminal", action = "open -a Terminal", shortcut = "⌃⌥T" },
    { type = "item", name = "menu.apps.finder", icon = "", label = "Finder", action = "open -a Finder" },
    { type = "item", name = "menu.apps.vscode", icon = "󰨞", label = "VS Code", action = "open -a 'Visual Studio Code'" },
    { type = "item", name = "menu.apps.activity", icon = "󰨇", label = "Activity Monitor", action = "open -a 'Activity Monitor'" },
    { type = "item", name = "menu.apps.yaze", icon = "󰯙", label = "Yaze (ROM Toolkit)", action = string.format("open -a %q", ctx.paths.yaze .. "/build/bin/yaze.app") },
    { type = "item", name = "menu.apps.mesen", icon = "󰺷", label = "Mesen", action = "open -a mesen" },
  }

  local dev_tool_items = {
    { type = "item", name = "menu.dev.ollama", icon = "󰚩", label = "Ask Ollama", action = ctx.call_script(ctx.scripts.ollama_prompt) },
    { type = "item", name = "menu.dev.z3ed", icon = "󰘦", label = "Launch z3ed", action = ctx.call_script(ctx.scripts.z3_launcher) },
    { type = "item", name = "menu.dev.profile.shared", icon = "󰒓", label = "Apply Shared Profile", action = ctx.call_script(ctx.scripts.apply_profile, "shared") },
    { type = "item", name = "menu.dev.profile.full", icon = "󰑈", label = "Restore Full Profile", action = ctx.call_script(ctx.scripts.apply_profile, "full") },
  }

  local function agent_action(script, ...)
    if not script or script == "" then
      return ""
    end
    return ctx.call_script(script, ...)
  end

  local function get_agent_status_items(ctx)
    local items = {}
    local cmd = string.format("%s list", ctx.scripts.launch_agent_helper)
    local handle = io.popen(cmd)
    if not handle then return {} end
    local result = handle:read("*a")
    handle:close()

    local agent_data = {}
    local ok, decoded = pcall(json.decode, result)
    if ok and type(decoded) == "table" then
      for _, agent in ipairs(decoded) do
        agent_data[agent.label] = agent
      end
    end

    local tracked_agents = {
      { label = "homebrew.mxcl.sketchybar", name = "SketchyBar", icon = "󰑓" },
      { label = "org.nbirrell.yabai", name = "Yabai", icon = "󱂬" },
      { label = "org.nbirrell.skhd", name = "skhd", icon = "󰚌" },
    }

    for _, agent in ipairs(tracked_agents) do
      local info = agent_data[agent.label]
      local status_icon = "🔴"
      local status_text = "Stopped"
      local pid_text = ""
      
      if info and info.running then
        status_icon = "🟢"
        status_text = "Running"
        if info.pid then
          pid_text = string.format(" (PID: %d)", info.pid)
        end
      elseif info and info.status and info.status ~= 0 then
        status_icon = "⚠️"
        status_text = string.format("Error: %s", info.status)
      end

      table.insert(items, {
        type = "item",
        name = "menu.agents.status." .. agent.name,
        icon = agent.icon,
        label = string.format("%s  %s%s", status_icon, status_text, pid_text),
        action = "",
        color = info and info.running and ctx.theme.GREEN or ctx.theme.RED
      })
    end
    
    if #items > 0 then
        table.insert(items, { type = "separator", name = "menu.agents.status_sep" })
    end
    
    return items
  end

  local launch_agent_items = {
    { type = "item", name = "menu.agents.open_panel", icon = "󰘦", label = "Launch Agents Tab", action = ctx.call_script(ctx.scripts.open_control_panel) },
    { type = "separator", name = "menu.agents.sep0" },
    { type = "item", name = "menu.agents.status.placeholder", icon = "󰑐", label = "Status: Load in Control Panel", action = ctx.call_script(ctx.scripts.open_control_panel), color = ctx.theme.DARK_WHITE },
  }

  -- Performance optimization: Removed synchronous agent status check (get_agent_status_items) during startup
  -- Use Control Panel to view real-time status

  -- Add control items
  local control_items = {
    { type = "item", name = "menu.agents.sketchybar.restart", icon = "󰑓", label = "Restart SketchyBar", action = agent_action(ctx.scripts.launch_agent_helper, "restart", "homebrew.mxcl.sketchybar") or agent_action(ctx.scripts.rebuild_sketchybar, "--reload-only") },
    { type = "item", name = "menu.agents.sketchybar.stop", icon = "󰅘", label = "Stop SketchyBar", action = agent_action(ctx.scripts.launch_agent_helper, "stop", "homebrew.mxcl.sketchybar") },
    { type = "item", name = "menu.agents.sketchybar.start", icon = "󰅂", label = "Start SketchyBar", action = agent_action(ctx.scripts.launch_agent_helper, "start", "homebrew.mxcl.sketchybar") },
    { type = "separator", name = "menu.agents.sep1" },
    { type = "item", name = "menu.agents.yabai.restart", icon = "󱂬", label = "Restart Yabai", action = agent_action(ctx.scripts.launch_agent_helper, "restart", "org.nbirrell.yabai") },
    { type = "item", name = "menu.agents.skhd.restart", icon = "󰚌", label = "Restart skhd", action = agent_action(ctx.scripts.launch_agent_helper, "restart", "org.nbirrell.skhd") },
  }

  for _, item in ipairs(control_items) do
    table.insert(launch_agent_items, item)
  end

  local debug_tool_items = {
    { type = "item", name = "menu.debug.rebuild", icon = "󰑓", label = "Rebuild + Reload (⌃⌥⇧R)", action = agent_action(ctx.scripts.rebuild_sketchybar) },
    { type = "item", name = "menu.debug.reload", icon = "󰑐", label = "Reload SketchyBar", action = agent_action(ctx.scripts.rebuild_sketchybar, "--reload-only") },
    { type = "item", name = "menu.debug.panel", icon = "󰘦", label = "Open Control Panel (⌃⌥P)", action = agent_action(ctx.scripts.open_control_panel) },
    { type = "item", name = "menu.debug.logs", icon = "󰍛", label = "Follow Logs (Terminal)", action = agent_action(ctx.scripts.logs, "sketchybar", "80") },
    { type = "item", name = "menu.debug.control_center", icon = "󰤘", label = "Toggle Control Center", action = "/opt/homebrew/opt/sketchybar/bin/sketchybar --set control_center popup.drawing=toggle" },
  }

  local control_center_items = {
    { type = "header", name = "menu.system.header", label = "System" },
    { type = "item", name = "menu.system.about", icon = "󰋗", label = "About This Mac", action = "open -a 'System Information'" },
    { type = "item", name = "menu.system.settings", icon = "", label = "System Settings…", action = "open -a 'System Settings'", shortcut = "⌘," },
    { type = "item", name = "menu.system.forcequit", icon = "󰜏", label = "Force Quit…", action = [[osascript -e 'tell application "System Events" to key code 53 using {command down, option down}']], shortcut = "⌘⌥⎋" },
    { type = "separator", name = "menu.system.sep1" },
    { type = "item", name = "menu.system.sleep", icon = "󰒲", label = "Sleep Display", action = "pmset displaysleepnow" },
    { type = "item", name = "menu.system.lock", icon = "󰷛", label = "Lock Screen", action = [[osascript -e 'tell application "System Events" to keystroke "q" using {control down, command down}']], shortcut = "⌃⌘Q" },
    { type = "separator", name = "menu.system.sep2" },
    { type = "header", name = "menu.quick.header", label = "Quick Actions" },
    { type = "item", name = "menu.quick.panel", icon = "󰒓", label = "Control Panel…", action = ctx.call_script(ctx.paths.apple_launcher, "--panel") },
    { type = "item", name = "menu.quick.reload", icon = "󰑐", label = "Reload Bar", action = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload" },
    { type = "item", name = "menu.quick.logs", icon = "󰍛", label = "Follow Logs", action = string.format("open -a Terminal %q", ctx.scripts.logs .. " sketchybar --follow") },
    { type = "separator", name = "menu.quick.sep1" },
    { type = "header", name = "menu.workspaces.header", label = "Workspaces" },
    { type = "item", name = "menu.rom.popup", icon = "󰊕", label = "ROM Hacking…", popup = "rom_hacking", items = rom_hacking_items(ctx) },
    { type = "item", name = "menu.emacs.popup", icon = "󰘔", label = "Emacs Workspace…", popup = "emacs_workspace", items = emacs_items(ctx) },
    { type = "item", name = "menu.halext.popup", icon = "󱓷", label = "halext-org…", popup = "halext_org", items = halext_items(ctx) },
    { type = "item", name = "menu.syshelp.popup", icon = "🚀", label = "System Intelligence…", popup = "syshelp", items = syshelp_items(ctx) },
    { type = "separator", name = "menu.workspaces.sep1" },
    { type = "header", name = "menu.apps.header", label = "Apps" },
    { type = "item", name = "menu.apps.popup", icon = "󰖟", label = "Apps & Tools…", popup = "apps_tools", items = app_tool_items },
    { type = "item", name = "menu.dev.popup", icon = "󰙨", label = "Dev Utilities…", popup = "dev_utilities", items = dev_tool_items },
    { type = "separator", name = "menu.apps.sep1" },
    { type = "header", name = "menu.help.header", label = "Help" },
    { type = "item", name = "menu.help.popup", icon = "󰋖", label = "Help & Tips…", popup = "help_tips", items = help_items(ctx) },
    { type = "item", name = "menu.agents.popup", icon = "󰳟", label = "Launch Agents…", popup = "launch_agents", items = launch_agent_items },
    { type = "item", name = "menu.debug.popup", icon = "󰃤", label = "Debug Tools…", popup = "debug_tools", items = debug_tool_items },
  }

  menu.halext_items = halext_items
  menu.syshelp_items = syshelp_items
  menu.help_items = help_items
  menu.app_tool_items = function(ctx) return app_tool_items end

  render_menu_items("control_center", control_center_items)
end

return menu
