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
  local config_dir = ctx.paths and ctx.paths.config_dir or nil

  local function is_executable(path)
    if not path or path == "" then
      return false
    end
    local handle = io.popen(string.format("test -x %q && printf 1 || printf 0", path))
    if not handle then
      return false
    end
    local result = handle:read("*a")
    handle:close()
    return result and result:match("1") ~= nil
  end

  local function resolve_menu_action_command()
    local candidates = {
      ctx.scripts and ctx.scripts.menu_action or nil,
      config_dir and (config_dir .. "/bin/menu_action") or nil,
      config_dir and (config_dir .. "/helpers/menu_action") or nil,
      config_dir and (config_dir .. "/plugins/menu_action.sh") or nil,
    }
    for _, candidate in ipairs(candidates) do
      if candidate and candidate ~= "" and is_executable(candidate) then
        return candidate
      end
    end
    for _, candidate in ipairs(candidates) do
      if candidate and candidate ~= "" then
        local file = io.open(candidate, "r")
        if file then
          file:close()
          return string.format("bash %q", candidate)
        end
      end
    end
    return nil
  end

  local menu_action_cmd = resolve_menu_action_command()

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
    local action = entry.action
    if type(action) == "function" then
      action = entry.shell_action
    end
    if not action or action == "" then
      return ""
    end
    if menu_action_cmd then
      local target_popup = popup_name
      return string.format(
        "MENU_ACTION_CMD=%q %s %q %q",
        action,
        menu_action_cmd,
        entry.name or "",
        target_popup or ""
      )
    else
      return string.format("%s; sketchybar -m --set %s popup.drawing=off", action, popup_name or popup)
    end
  end

  local function add_menu_entry(popup, entry, parent_popup)
    local padding = menu_entry_padding()
    local label = menu_label(entry.label, entry.shortcut)
    local click = wrap_action(entry, parent_popup or popup)
    
    local item_config = {
      position = "popup." .. popup,
      icon = entry.icon or "",
      label = label,
      click_script = click,
      script = string.format("env SUBMENU_PARENT=%q %s", popup, ctx.HOVER_SCRIPT or ""),
      ["icon.padding_left"] = padding.icon_left,
      ["icon.padding_right"] = padding.icon_right,
      ["label.padding_left"] = padding.label_left,
      ["label.padding_right"] = padding.label_right,
      background = {
        drawing = false,
        corner_radius = 4,
        height = math.max(widget_height - 10, 16)
      }
    }

    -- Allow overriding colors
    if entry.label_color then
      item_config["label.color"] = entry.label_color
    elseif entry.color then
      item_config["label.color"] = entry.color
    end
    if entry.icon_color then
      item_config["icon.color"] = entry.icon_color
    end

    sbar.add("item", entry.name, item_config)
    attach_hover(entry.name)
  end

  local function add_popup_action(popup, entry, renderer)
    local padding = menu_entry_padding()
    local popup_name = entry.popup or entry.name
    local items = entry.items or {}
    
    -- Create popup container item (separate item, not nested)
    local popup_item_name = "popup." .. popup_name
    sbar.add("item", popup_item_name, {
      position = "left",
      icon = "",
      label = "",
      drawing = false,
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
    
    -- Render items into the popup
    if items and #items > 0 then
      renderer(popup_item_name, items, popup_item_name)
    end
    
    -- Create clickable menu item that opens the popup
    local click_action = string.format(
      "sketchybar -m --set %s popup.drawing=toggle",
      popup_item_name
    )
    
    sbar.add("item", entry.name, {
      position = "popup." .. popup,
      icon = entry.icon or "",
      label = entry.label or "",
      click_script = click_action,
      script = ctx.HOVER_SCRIPT,
      ["icon.padding_left"] = padding.icon_left,
      ["icon.padding_right"] = padding.icon_right,
      ["label.padding_left"] = padding.label_left,
      ["label.padding_right"] = padding.label_right,
      background = {
        drawing = false,
        corner_radius = 4,
        height = math.max(widget_height - 10, 16)
      }
    })
    attach_hover(entry.name)
  end

  local add_submenu

  local function render_menu_items(popup, entries, parent_popup)
    for _, entry in ipairs(entries or {}) do
      if entry.type == "header" then
        add_menu_header(popup, entry)
      elseif entry.type == "separator" then
        add_menu_separator(popup, entry)
      elseif entry.popup then
        -- New popup-based action (replaces submenu)
        add_popup_action(popup, entry, render_menu_items)
      elseif entry.type == "submenu" then
        -- Legacy submenu support (for backwards compatibility)
        add_submenu(popup, entry, render_menu_items)
      else
        add_menu_entry(popup, entry, parent_popup)
      end
    end
  end
  
  -- Keep old add_submenu for backwards compatibility
  add_submenu = function(popup, entry, renderer)
    local padding = menu_entry_padding()
    local parent = entry.name
    local arrow = entry.arrow_icon or "󰅂"
    sbar.add("item", parent, {
      position = "popup." .. popup,
      icon = entry.icon or "",
      label = string.format("%s  %s", entry.label, arrow),
      script = ctx.SUBMENU_HOVER_SCRIPT,
      click_script = "sketchybar -m --set $NAME popup.drawing=toggle",
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

  return {
    render = render_menu_items,
    appearance_action = appearance_action,
  }
end

return menu_renderer
