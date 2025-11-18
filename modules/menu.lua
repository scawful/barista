local menu = {}
local json = require("json")

local unpack = table.unpack or _G.unpack

local function menu_label(label, shortcut)
  if shortcut and shortcut ~= "" then
    return string.format("%-16s %s", label, shortcut)
  end
  return label
end

local function menu_entry_padding()
  return {
    icon_left = 4,
    icon_right = 6,
    label_left = 6,
    label_right = 6,
  }
end

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

local function create_renderer(ctx)
  local sbar = ctx.sbar
  local settings = ctx.settings
  local theme = ctx.theme
  local widget_height = ctx.widget_height
  local attach_hover = ctx.attach_hover
  local shell_exec = ctx.shell_exec

  local function appearance_action(color, blur)
    local args = {}
    if color then
      table.insert(args, "--color")
      table.insert(args, color)
    end
    if blur then
      table.insert(args, "--blur")
      table.insert(args, tostring(blur))
    end
    return ctx.call_script(ctx.scripts.set_appearance, unpack(args))
  end

  local function add_menu_header(popup, entry)
    local padding = menu_entry_padding()
    sbar.add("item", entry.name, {
      position = "popup." .. popup,
      icon = "",
      label = entry.label,
      ["label.font"] = string.format("%s:%s:%0.1f", settings.font.text, settings.font.style_map["Bold"], settings.font.sizes.small),
      ["label.color"] = theme.DARK_WHITE,
      ["icon.drawing"] = false,
      background = { drawing = false },
      ["label.padding_left"] = padding.label_left,
      ["label.padding_right"] = padding.label_right,
    })
  end

  local function add_menu_separator(popup, entry)
    local padding = menu_entry_padding()
    sbar.add("item", entry.name, {
      position = "popup." .. popup,
      icon = "",
      label = entry.label or "───────────────",
      ["label.font"] = string.format("%s:%s:%0.1f", settings.font.text, settings.font.style_map["Regular"], settings.font.sizes.small),
      ["label.color"] = theme.DARK_WHITE,
      ["icon.drawing"] = false,
      background = { drawing = false },
      ["label.padding_left"] = padding.label_left,
      ["label.padding_right"] = padding.label_right,
    })
  end

  local function wrap_action(entry, popup_name)
    if not entry.action or entry.action == "" then
      return ""
    end
    if ctx.scripts and ctx.scripts.menu_action then
      local target_popup = popup_name
      return string.format(
        "MENU_ACTION_CMD=%q %s %q %q",
        entry.action,
        ctx.scripts.menu_action,
        entry.name or "",
        target_popup or ""
      )
    else
      return string.format("%s; sketchybar -m --set %s popup.drawing=off", entry.action, popup_name or popup)
    end
  end

  local function add_menu_entry(popup, entry)
    local padding = menu_entry_padding()
    local label = menu_label(entry.label, entry.shortcut)
    local click = wrap_action(entry, popup)
    sbar.add("item", entry.name, {
      position = "popup." .. popup,
      icon = entry.icon or "",
      label = label,
      click_script = click,
      script = ctx.HOVER_SCRIPT,
      ["icon.padding_left"] = padding.icon_left,
      ["icon.padding_right"] = padding.icon_right,
      ["label.padding_left"] = padding.label_left,
      ["label.padding_right"] = padding.label_right,
      background = {
        drawing = false,
        corner_radius = 4,
        height = math.max(widget_height - 10, 16)
      },
      env = { SUBMENU_PARENT = popup }
    })
    attach_hover(entry.name)
  end

  local function add_submenu(popup, entry, renderer)
    local padding = menu_entry_padding()
    local parent = entry.name
    local arrow = entry.arrow_icon or "󰅂"
    sbar.add("item", parent, {
      position = "popup." .. popup,
      icon = entry.icon or "",
      label = string.format("%s  %s", entry.label, arrow),
      script = ctx.SUBMENU_HOVER_SCRIPT,
      ["icon.padding_left"] = padding.icon_left,
      ["icon.padding_right"] = padding.icon_right,
      ["label.padding_left"] = padding.label_left,
      ["label.padding_right"] = padding.label_right,
      background = {
        drawing = false,
        corner_radius = 4,
        height = math.max(widget_height - 8, 16)
      },
      popup = {
        align = "right",
        background = {
          border_width = 2,
          corner_radius = 4,
          border_color = theme.WHITE,
          color = theme.bar.bg
        }
      }
    })
    shell_exec(string.format("sketchybar --subscribe %s mouse.entered mouse.exited mouse.exited.global", parent))
    renderer(parent, entry.items or {})
  end

  local function render_menu_items(popup, entries)
    for _, entry in ipairs(entries or {}) do
      if entry.type == "header" then
        add_menu_header(popup, entry)
      elseif entry.type == "separator" then
        add_menu_separator(popup, entry)
      elseif entry.type == "submenu" then
        add_submenu(popup, entry, render_menu_items)
      else
        add_menu_entry(popup, entry)
      end
    end
  end

  return {
    render = render_menu_items,
    appearance_action = appearance_action,
  }
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
    { type = "item", name = "menu.rom.focus_emacs", icon = "󰘔", label = "Focus Emacs Space", action = ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs") },
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
    { type = "item", name = "menu.emacs.focus", icon = "󰘔", label = "Focus Emacs Space", action = ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs") },
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
    -- Future expansion placeholders:
    -- { type = "item", name = "menu.halext.notes", icon = "󰠮", label = "Quick Notes", action = "..." },
    -- { type = "item", name = "menu.halext.search", icon = "", label = "Search", action = "..." },
    -- { type = "submenu", name = "menu.halext.projects", icon = "󰉋", label = "Projects", items = {...} },
  }
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
  local renderer = create_renderer(ctx)
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

  local yabai_control_items = {
    { type = "item", name = "menu.yabai.toggle", icon = "󱂬", label = "Toggle Layout", action = ctx.call_script(ctx.scripts.yabai_control, "toggle-layout"), shortcut = "⌃⌥L" },
    { type = "item", name = "menu.yabai.balance", icon = "󰓅", label = "Balance Windows", action = ctx.call_script(ctx.scripts.yabai_control, "balance") },
    { type = "item", name = "menu.yabai.mode.float", icon = "󰒄", label = "Force Float (Default)", action = ctx.call_script(ctx.scripts.space_mode, "current", "float") },
    { type = "item", name = "menu.yabai.mode.bsp", icon = "󰆾", label = "Enable BSP Tiling", action = ctx.call_script(ctx.scripts.space_mode, "current", "bsp") },
    { type = "item", name = "menu.yabai.mode.stack", icon = "󰓩", label = "Enable Stack Tiling", action = ctx.call_script(ctx.scripts.space_mode, "current", "stack") },
    { type = "item", name = "menu.yabai.focus.emacs", icon = "󰘔", label = "Focus Emacs Space", action = ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs") },
    { type = "item", name = "menu.yabai.focus.next", icon = "󰛳", label = "Focus Next Space", action = ctx.call_script(ctx.scripts.yabai_control, "space-focus-next") },
    { type = "item", name = "menu.yabai.focus.prev", icon = "󰛶", label = "Focus Prev Space", action = ctx.call_script(ctx.scripts.yabai_control, "space-focus-prev") },
    { type = "item", name = "menu.yabai.window.space.next", icon = "󰆼", label = "Send Window → Next Space", action = ctx.call_script(ctx.scripts.yabai_control, "window-space-next") },
    { type = "item", name = "menu.yabai.window.space.prev", icon = "󰆽", label = "Send Window → Prev Space", action = ctx.call_script(ctx.scripts.yabai_control, "window-space-prev") },
    { type = "item", name = "menu.yabai.space.new", icon = "󰘔", label = "Create Space", action = ctx.call_script(ctx.scripts.yabai_control, "space-create") },
    { type = "item", name = "menu.yabai.space.destroy", icon = "󰘚", label = "Destroy Recent Space", action = ctx.call_script(ctx.scripts.yabai_control, "space-destroy") },
    { type = "item", name = "menu.yabai.restart", icon = "󰐥", label = "Restart Yabai", action = ctx.call_script(ctx.scripts.yabai_control, "restart") },
    { type = "item", name = "menu.yabai.doctor", icon = "󰒓", label = "Run Diagnostics", action = ctx.call_script(ctx.scripts.yabai_control, "doctor") },
  }

  local window_action_items = {
    { type = "item", name = "menu.skhd.float", icon = "󰒄", label = "Toggle Float", action = ctx.call_script(ctx.scripts.yabai_control, "window-toggle-float"), shortcut = "⌃⌥F" },
    { type = "item", name = "menu.skhd.sticky", icon = "󰐊", label = "Toggle Sticky", action = ctx.call_script(ctx.scripts.yabai_control, "window-toggle-sticky") },
    { type = "item", name = "menu.skhd.fullscreen", icon = "󰊓", label = "Toggle Fullscreen", action = ctx.call_script(ctx.scripts.yabai_control, "window-toggle-fullscreen"), shortcut = "⌃⌥↩" },
    { type = "item", name = "menu.skhd.center", icon = "󰆾", label = "Center Window", action = ctx.call_script(ctx.scripts.yabai_control, "window-center") },
    { type = "item", name = "menu.skhd.display.next", icon = "󰍹", label = "Send to Next Display", action = ctx.call_script(ctx.scripts.yabai_control, "window-display-next"), shortcut = "⌃⌥→" },
    { type = "item", name = "menu.skhd.display.prev", icon = "󰍷", label = "Send to Prev Display", action = ctx.call_script(ctx.scripts.yabai_control, "window-display-prev"), shortcut = "⌃⌥←" },
    { type = "item", name = "menu.skhd.restart", icon = "󰚌", label = "Restart skhd", action = ctx.call_script(ctx.scripts.skhd_control, "restart") },
    { type = "item", name = "menu.skhd.status", icon = "󰣇", label = "skhd Status", action = ctx.call_script(ctx.scripts.skhd_control, "status") },
  }

  local application_control_items = {
    { type = "item", name = "menu.app.show", icon = "", label = "Bring to Front", action = ctx.call_script(ctx.scripts.front_app_action, "show"), shortcut = "⌘⇥" },
    { type = "item", name = "menu.app.hide", icon = "", label = "Hide App", action = ctx.call_script(ctx.scripts.front_app_action, "hide"), shortcut = "⌘H" },
    { type = "item", name = "menu.app.quit", icon = "", label = "Quit App", action = ctx.call_script(ctx.scripts.front_app_action, "quit"), shortcut = "⌘Q" },
    { type = "item", name = "menu.app.forcequit", icon = "", label = "Force Quit", action = ctx.call_script(ctx.scripts.front_app_action, "force-quit") },
  }

  local space_management_items = {
    { type = "header", name = "menu.spaces.header.displays", label = "Displays" },
    { type = "item", name = "menu.spaces.display.next", icon = "", label = "Send to Next Display", action = ctx.call_script(ctx.scripts.yabai_control, "window-display-next"), shortcut = "⌃⌥→" },
    { type = "item", name = "menu.spaces.display.prev", icon = "", label = "Send to Prev Display", action = ctx.call_script(ctx.scripts.yabai_control, "window-display-prev"), shortcut = "⌃⌥←" },
    { type = "separator", name = "menu.spaces.sep1" },
    { type = "header", name = "menu.spaces.header.assign", label = "Spaces" },
    { type = "item", name = "menu.spaces.space.next", icon = "", label = "Send to Next Space", action = ctx.call_script(ctx.scripts.yabai_control, "window-space-next"), shortcut = "⌃⌥⌘→" },
    { type = "item", name = "menu.spaces.space.prev", icon = "", label = "Send to Prev Space", action = ctx.call_script(ctx.scripts.yabai_control, "window-space-prev"), shortcut = "⌃⌥⌘←" },
    { type = "item", name = "menu.spaces.space.1", icon = "1", label = "Send to Space 1", action = ctx.call_script(ctx.scripts.yabai_control, "window-space", "1"), shortcut = "⌃⌥⌘1" },
    { type = "item", name = "menu.spaces.space.2", icon = "2", label = "Send to Space 2", action = ctx.call_script(ctx.scripts.yabai_control, "window-space", "2"), shortcut = "⌃⌥⌘2" },
    { type = "item", name = "menu.spaces.space.3", icon = "3", label = "Send to Space 3", action = ctx.call_script(ctx.scripts.yabai_control, "window-space", "3"), shortcut = "⌃⌥⌘3" },
    { type = "item", name = "menu.spaces.space.4", icon = "4", label = "Send to Space 4", action = ctx.call_script(ctx.scripts.yabai_control, "window-space", "4"), shortcut = "⌃⌥⌘4" },
    { type = "item", name = "menu.spaces.space.5", icon = "5", label = "Send to Space 5", action = ctx.call_script(ctx.scripts.yabai_control, "window-space", "5"), shortcut = "⌃⌥⌘5" },
  }

  local space_layout_items = {
    { type = "header", name = "menu.yabai.layout.header", label = "Current Space Layout" },
    { type = "item", name = "menu.yabai.layout.bsp", icon = "", label = "Enable BSP Tiling", action = ctx.call_script(ctx.scripts.space_mode, "current", "bsp") },
    { type = "item", name = "menu.yabai.layout.stack", icon = "", label = "Enable Stack Tiling", action = ctx.call_script(ctx.scripts.space_mode, "current", "stack") },
    { type = "item", name = "menu.yabai.layout.float", icon = "", label = "Disable Tiling", action = ctx.call_script(ctx.scripts.space_mode, "current", "float") },
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

  local launch_agent_items = {
    { type = "item", name = "menu.agents.open_panel", icon = "󰘦", label = "Launch Agents Tab", action = ctx.call_script(ctx.scripts.open_control_panel) },
    { type = "separator", name = "menu.agents.sep0" },
    { type = "item", name = "menu.agents.sketchybar.restart", icon = "󰑓", label = "Restart SketchyBar", action = agent_action(ctx.scripts.launch_agent_helper, "restart", "homebrew.mxcl.sketchybar") or agent_action(ctx.scripts.rebuild_sketchybar, "--reload-only") },
    { type = "item", name = "menu.agents.sketchybar.stop", icon = "󰅘", label = "Stop SketchyBar", action = agent_action(ctx.scripts.launch_agent_helper, "stop", "homebrew.mxcl.sketchybar") },
    { type = "item", name = "menu.agents.sketchybar.start", icon = "󰅂", label = "Start SketchyBar", action = agent_action(ctx.scripts.launch_agent_helper, "start", "homebrew.mxcl.sketchybar") },
    { type = "separator", name = "menu.agents.sep1" },
    { type = "item", name = "menu.agents.yabai.restart", icon = "󱂬", label = "Restart Yabai", action = agent_action(ctx.scripts.launch_agent_helper, "restart", "org.nbirrell.yabai") },
    { type = "item", name = "menu.agents.skhd.restart", icon = "󰚌", label = "Restart skhd", action = agent_action(ctx.scripts.launch_agent_helper, "restart", "org.nbirrell.skhd") },
  }

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
    { type = "submenu", name = "menu.control_center.app", icon = "󰣇", label = "Application Controls", items = application_control_items },
    { type = "submenu", name = "menu.windows.section", icon = "󰍿", label = "Window Actions", items = window_action_items },
    { type = "submenu", name = "menu.control_center.spaces", icon = "󰊠", label = "Spaces Management", items = space_management_items },
    { type = "submenu", name = "menu.control_center.layouts", icon = "󰆾", label = "Space Layout", items = space_layout_items },
    { type = "submenu", name = "menu.yabai.section", icon = "󱂬", label = "Yabai Controls", items = yabai_control_items },
    { type = "submenu", name = "menu.sketchybar.styles", icon = "󰔇", label = "SketchyBar Styles", items = style_items },
    { type = "submenu", name = "menu.sketchybar.tools", icon = "󰒓", label = "SketchyBar Tools", items = sketchybar_tool_items },
    { type = "submenu", name = "menu.rom.section", icon = "󰊕", label = "ROM Hacking", items = rom_hacking_items(ctx) },
    { type = "submenu", name = "menu.emacs.section", icon = "", label = "Emacs Workspace", items = emacs_items(ctx) },
    { type = "submenu", name = "menu.halext.section", icon = "󱓷", label = "halext-org", items = halext_items(ctx) },
    { type = "submenu", name = "menu.apps.section", icon = "󰖟", label = "Apps & Tools", items = app_tool_items },
    { type = "submenu", name = "menu.dev.section", icon = "󰙨", label = "Dev Utilities", items = dev_tool_items },
    { type = "submenu", name = "menu.help.section", icon = "󰋖", label = "Help & Tips", items = help_items(ctx) },
    { type = "submenu", name = "menu.agents.section", icon = "󰳟", label = "Launch Agents", items = launch_agent_items },
    { type = "submenu", name = "menu.debug.section", icon = "󰃤", label = "Debug & Tools", items = debug_tool_items },
  }

  render_menu_items("control_center", control_center_items)
end

return menu
