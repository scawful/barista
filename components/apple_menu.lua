local M = {}

local function menu_label(label, shortcut)
  if shortcut and shortcut ~= "" then
    return string.format("%-17s %s", label, shortcut)
  end
  return label
end

local function merge_env(parent_name, custom_env)
  local env = {}
  if parent_name and parent_name ~= "" then
    env.SUBMENU_PARENT = parent_name
  end
  if custom_env then
    for key, value in pairs(custom_env) do
      env[key] = value
    end
  end
  if next(env) == nil then
    return nil
  end
  return env
end

local function build_click_script(ctx, entry)
  if entry.click_script then
    return entry.click_script
  end
  if not entry.action or entry.action == "" then
    return ""
  end
  if ctx.menu_action_script and ctx.button then
    return string.format("%s %q %q %q", ctx.menu_action_script, entry.action, entry.name or "", ctx.button)
  end
  return string.format("%s; sketchybar -m --set %s popup.drawing=off", entry.action, ctx.button)
end

local function add_header(ctx, popup_position, entry)
  ctx.sbar.add("item", entry.name, {
    position = popup_position,
    icon = "",
    label = entry.label,
    ["label.font"] = ctx.font_string(ctx.settings.font.text, ctx.settings.font.style_map["Bold"], ctx.settings.font.sizes.small),
    ["label.color"] = ctx.theme.DARK_WHITE,
    ["icon.drawing"] = false,
    background = { drawing = false },
  })
end

local function add_separator(ctx, popup_position, entry)
  ctx.sbar.add("item", entry.name, {
    position = popup_position,
    icon = "",
    label = entry.label or "───────────────",
    ["label.font"] = ctx.font_string(ctx.settings.font.text, ctx.settings.font.style_map["Regular"], ctx.settings.font.sizes.small),
    ["label.color"] = ctx.theme.DARK_WHITE,
    ["icon.drawing"] = false,
    background = { drawing = false },
  })
end

local function add_entry(ctx, popup_position, entry, parent_name)
  local label = menu_label(entry.label, entry.shortcut)
  local env = merge_env(parent_name, entry.env)

  ctx.sbar.add("item", entry.name, {
    position = popup_position,
    icon = entry.icon or "",
    label = label,
    click_script = build_click_script(ctx, entry),
    script = ctx.hover_script,
    env = env,
  })
  ctx.attach_hover(entry.name)
end

local add_menu_item

local function add_submenu(ctx, popup_position, entry)
  local parent = entry.name
  local arrow = entry.arrow_icon or "󰅂"
  local submenu_env = entry.env or {}
  submenu_env.SUBMENU_ROOT = ctx.button

  ctx.sbar.add("item", parent, {
    position = popup_position,
    icon = entry.icon or "",
    label = string.format("%s  %s", entry.label, arrow),
    click_script = entry.click_script or [[sketchybar -m --set $NAME popup.drawing=toggle]],
    ["icon.padding_left"] = 4,
    ["icon.padding_right"] = 6,
    ["label.padding_left"] = 6,
    ["label.padding_right"] = 8,
    background = {
      drawing = false,
      corner_radius = 4,
      height = 20,
    },
    popup = {
      align = "right",
      background = {
        border_width = 2,
        corner_radius = 4,
        border_color = ctx.theme.WHITE,
        color = ctx.theme.bar.bg,
      }
    },
    env = submenu_env,
  })
  ctx.attach_hover(parent, ctx.submenu_hover_script)
  ctx.subscribe_mouse_exit(parent)

  local child_popup = string.format("popup.%s", parent)
  for _, child in ipairs(entry.items or {}) do
    add_menu_item(ctx, child_popup, child, parent)
  end
end

add_menu_item = function(ctx, popup_position, entry, parent_name)
  if entry.type == "header" then
    add_header(ctx, popup_position, entry)
  elseif entry.type == "separator" then
    add_separator(ctx, popup_position, entry)
  elseif entry.type == "submenu" then
    add_submenu(ctx, popup_position, entry)
  else
    add_entry(ctx, popup_position, entry, parent_name)
  end
end

local function default_menu(ctx)
  local call_script = ctx.call_script
  local scripts_dir = ctx.scripts_dir
  local config_dir = ctx.config_dir
  local YABAI_CONTROL_SCRIPT = ctx.yabai_control_script
  local SKHD_CONTROL_SCRIPT = ctx.skhd_control_script

  local sketchybar_tool_items = {
    { type = "item", name = "menu.sketchybar.reload", icon = "󰑐", label = "Reload Bar", action = call_script(config_dir .. "/plugins/reload_bar.sh") },
    { type = "item", name = "menu.sketchybar.logs", icon = "󰍛", label = "Follow Logs (Terminal)", action = string.format("open -a Terminal %q", config_dir .. "/logs") },
    { type = "item", name = "menu.sketchybar.config", icon = "󰒓", label = "Open Config Folder", action = string.format("open %q", config_dir) },
    { type = "item", name = "menu.sketchybar.accessibility", icon = "󰈈", label = "Repair Accessibility", action = call_script(scripts_dir .. "/yabai_accessibility_fix.sh") },
  }

  local yabai_control_items = {
    { type = "item", name = "menu.yabai.toggle", icon = "󱂬", label = "Toggle Layout", action = call_script(YABAI_CONTROL_SCRIPT, "toggle-layout"), shortcut = "⌃⌥L" },
    { type = "item", name = "menu.yabai.balance", icon = "󰓅", label = "Balance Windows", action = call_script(YABAI_CONTROL_SCRIPT, "balance") },
    { type = "item", name = "menu.yabai.restart", icon = "󰐥", label = "Restart Yabai", action = call_script(YABAI_CONTROL_SCRIPT, "restart") },
    { type = "item", name = "menu.yabai.doctor", icon = "󰒓", label = "Run Diagnostics", action = call_script(YABAI_CONTROL_SCRIPT, "doctor") },
  }

  local window_action_items = {
    { type = "item", name = "menu.windows.float", icon = "󰒄", label = "Toggle Float", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-float"), shortcut = "⌃⌥F" },
    { type = "item", name = "menu.windows.sticky", icon = "󰐊", label = "Toggle Sticky", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-sticky") },
    { type = "item", name = "menu.windows.fullscreen", icon = "󰊓", label = "Toggle Fullscreen", action = call_script(YABAI_CONTROL_SCRIPT, "window-toggle-fullscreen"), shortcut = "⌃⌥↩" },
    { type = "item", name = "menu.windows.center", icon = "󰆾", label = "Center Window", action = call_script(YABAI_CONTROL_SCRIPT, "window-center") },
    { type = "item", name = "menu.windows.display.next", icon = "󰍹", label = "Send to Next Display", action = call_script(YABAI_CONTROL_SCRIPT, "window-display-next"), shortcut = "⌃⌥→" },
    { type = "item", name = "menu.windows.display.prev", icon = "󰍷", label = "Send to Prev Display", action = call_script(YABAI_CONTROL_SCRIPT, "window-display-prev"), shortcut = "⌃⌥←" },
    { type = "item", name = "menu.windows.space.next", icon = "󰆼", label = "Send to Next Space", action = call_script(YABAI_CONTROL_SCRIPT, "window-space-next"), shortcut = "⌃⌥⌘→" },
    { type = "item", name = "menu.windows.space.prev", icon = "󰆽", label = "Send to Prev Space", action = call_script(YABAI_CONTROL_SCRIPT, "window-space-prev"), shortcut = "⌃⌥⌘←" },
  }

  local app_tool_items = {
    { type = "item", name = "menu.apps.terminal", icon = "", label = "Terminal", action = "open -a Terminal", shortcut = "⌃⌥T" },
    { type = "item", name = "menu.apps.finder", icon = "", label = "Finder", action = "open -a Finder" },
    { type = "item", name = "menu.apps.vscode", icon = "󰨞", label = "VS Code", action = "open -a 'Visual Studio Code'" },
    { type = "item", name = "menu.apps.activity", icon = "󰨇", label = "Activity Monitor", action = "open -a 'Activity Monitor'" },
    { type = "item", name = "menu.apps.reload", icon = "󰑐", label = "Reload SketchyBar", action = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload" },
  }

  local help_items = {
    { type = "item", name = "menu.help.handoff", icon = "󰣖", label = "Open HANDOFF Notes", action = string.format("open %q", config_dir .. "/HANDOFF.md") },
    { type = "item", name = "menu.help.docs", icon = "󰋖", label = "Docs Folder", action = string.format("open %q", config_dir .. "/docs") },
  }

  return {
    { type = "header", name = "menu.system.header", label = "System" },
    { type = "item", name = "menu.system.about", icon = "󰋗", label = "About This Mac", action = "open -a 'System Information'" },
    { type = "item", name = "menu.system.settings", icon = "", label = "System Settings…", action = "open -a 'System Settings'", shortcut = "⌘," },
    { type = "item", name = "menu.system.forcequit", icon = "󰜏", label = "Force Quit…", action = [[osascript -e 'tell application "System Events" to key code 53 using {command down, option down}']], shortcut = "⌘⌥⎋" },
    { type = "separator", name = "menu.system.sep1" },
    { type = "item", name = "menu.system.sleep", icon = "󰒲", label = "Sleep Display", action = "pmset displaysleepnow" },
    { type = "item", name = "menu.system.lock", icon = "󰷛", label = "Lock Screen", action = [[osascript -e 'tell application "System Events" to keystroke "q" using {control down, command down}']], shortcut = "⌃⌘Q" },
    { type = "separator", name = "menu.system.sep2" },
    { type = "submenu", name = "menu.sketchybar.tools", icon = "󰒓", label = "SketchyBar Tools", items = sketchybar_tool_items },
    { type = "submenu", name = "menu.yabai.section", icon = "󱂬", label = "Yabai Controls", items = yabai_control_items },
    { type = "submenu", name = "menu.windows.section", icon = "󰍿", label = "Window Actions", items = window_action_items },
    { type = "submenu", name = "menu.apps.section", icon = "󰖟", label = "Apps & Tools", items = app_tool_items },
    { type = "submenu", name = "menu.help.section", icon = "󰋖", label = "Help & Tips", items = help_items },
  }
end

function M.setup(opts)
  local ctx = {
    sbar = opts.sbar,
    theme = opts.theme,
    settings = opts.settings,
    font_string = opts.font_string,
    attach_hover = opts.attach_hover,
    subscribe_mouse_exit = opts.subscribe_mouse_exit,
    icon_for = opts.icon_for or _G.icon_for,
    hover_script = opts.hover_script,
    submenu_hover_script = opts.submenu_hover_script or opts.hover_script,
    menu_action_script = opts.menu_action_script,
    popup_anchor_script = opts.popup_anchor_script,
    call_script = opts.call_script,
    scripts_dir = opts.scripts_dir,
    config_dir = opts.config_dir,
    yabai_control_script = opts.yabai_control_script,
    skhd_control_script = opts.skhd_control_script,
    button = (opts.button_name or "zelda"),
  }
  ctx.popup = "popup." .. ctx.button

  local items = (opts.menu and opts.menu.items) or default_menu(ctx)
  local anchor_icon = ctx.icon_for("apple", "")

  ctx.sbar.add("item", opts.apple_item or "apple_menu", {
    position = "left",
    icon = anchor_icon,
    label = { drawing = false },
    click_script = opts.apple_click_script or string.format("%s/gui/bin/config_menu >/tmp/sketchybar_config_menu.log 2>&1 &", ctx.config_dir),
  })

  ctx.sbar.add("item", ctx.button, {
    position = "left",
    icon = ctx.icon_for("quest", "󰊠"),
    ["icon.font"] = ctx.font_string("SF Pro", "Black", 16.0),
    label = { drawing = false },
    script = ctx.popup_anchor_script,
    click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
    popup = {
      background = {
        border_width = 2,
        corner_radius = 3,
        border_color = ctx.theme.WHITE,
        color = ctx.theme.bar.bg,
      }
    }
  })
  ctx.subscribe_mouse_exit(ctx.button)

  for _, entry in ipairs(items) do
    add_menu_item(ctx, ctx.popup, entry, ctx.button)
  end
end

return M

