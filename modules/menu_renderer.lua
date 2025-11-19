local menu_renderer = {}

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

function menu_renderer.create(ctx)
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
    
    local item_config = {
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
    }

    -- Allow overriding colors
    if entry.color then
      item_config["label.color"] = entry.color
    end

    sbar.add("item", entry.name, item_config)
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

return menu_renderer

