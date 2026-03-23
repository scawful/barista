local menu_renderer = {}
local menu_style = require("menu_style")

local unpack = table.unpack or _G.unpack

local function menu_label(label, shortcut)
  if shortcut and shortcut ~= "" then
    return string.format("%-16s %s", label, shortcut)
  end
  return label
end

function menu_renderer.create(ctx)
  local sbar = ctx.sbar
  local settings = ctx.settings
  local theme = ctx.theme
  local widget_height = ctx.widget_height
  local attach_hover = ctx.attach_hover
  local shell_exec = ctx.shell_exec
  local sketchybar_bin = ctx.sketchybar_bin or "sketchybar"
  local post_config_delay = ctx.post_config_delay or 1.0
  local config_dir = ctx.paths and ctx.paths.config_dir or nil
  local associated_displays = ctx.associated_displays or "all"
  local style = menu_style.compute(ctx)
  local popup_padding = style.popup_padding
  local popup_item_height = style.item_height
  local popup_header_height = style.header_height
  local popup_item_corner_radius = style.item_corner_radius
  local popup_border_width = style.popup_border_width
  local popup_corner_radius = style.popup_corner_radius
  local popup_border_color = style.popup_border_color
  local popup_bg_color = style.popup_bg_color
  local menu_label_color = style.label_color
  local menu_font_small = style.font_small
  local menu_font_header = style.font_header
  local submenu_hover_script = ctx.SUBMENU_HOVER_SCRIPT or ""
  if submenu_hover_script ~= "" and ctx.env_prefix and style.submenu_hover_env then
    submenu_hover_script = ctx.env_prefix(style.submenu_hover_env) .. submenu_hover_script
  end
  local metadata = { popup_parents = {}, submenu_parents = {} }

  local function remember(target, name)
    if type(name) ~= "string" or name == "" then return end
    target[name] = true
  end

  local function list_from_set(set)
    local items = {}
    for name, enabled in pairs(set or {}) do
      if enabled then
        table.insert(items, name)
      end
    end
    table.sort(items)
    return items
  end

  local function menu_entry_padding()
    local icon_left = style.padding.icon_left
    local icon_right = style.padding.icon_right
    local label_left = style.padding.label_left
    local label_right = style.padding.label_right
    return {
      icon_left = icon_left,
      icon_right = icon_right,
      label_left = label_left,
      label_right = label_right,
    }
  end

  local function popup_background()
    return style.popup_background()
  end

  local function popup_toggle(item_name)
    if type(ctx.popup_toggle_action) == "function" then
      return ctx.popup_toggle_action(item_name)
    end
    if item_name and item_name ~= "" then
      return string.format("sketchybar -m --set %s popup.drawing=toggle", item_name)
    end
    return "sketchybar -m --set $NAME popup.drawing=toggle"
  end

  -- PERF: Lua-native file check + cached executable test
  local function is_executable(path)
    if not path or path == "" then
      return false
    end
    local f = io.open(path, "r")
    if not f then
      return false
    end
    f:close()
    local ok = os.execute(string.format("test -x %q", path))
    return ok == true or ok == 0
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
      ["label.font"] = menu_font_header,
      ["label.color"] = theme.DARK_WHITE,
      ["icon.drawing"] = false,
      background = {
        drawing = false,
        corner_radius = popup_item_corner_radius,
        height = popup_header_height,
      },
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
      ["label.font"] = menu_font_small,
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
      ["label.font"] = menu_font_small,
      ["label.color"] = entry.label_color or entry.color or menu_label_color,
      ["icon.padding_left"] = padding.icon_left,
      ["icon.padding_right"] = padding.icon_right,
      ["label.padding_left"] = padding.label_left,
      ["label.padding_right"] = padding.label_right,
      background = {
        drawing = false,
        corner_radius = popup_item_corner_radius,
        height = popup_item_height
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
    remember(metadata.popup_parents, popup_item_name)
    sbar.add("item", popup_item_name, {
      position = "left",
      icon = "",
      label = "",
      drawing = false,
      associated_display = associated_displays,
      associated_space = "all",
      popup = {
        align = "right",
        background = popup_background()
      }
    })
    
    -- Render items into the popup
    if items and #items > 0 then
      renderer(popup_item_name, items, popup_item_name)
    end
    
    -- Create clickable menu item that opens the popup
    local click_action = popup_toggle(popup_item_name)
    
    sbar.add("item", entry.name, {
      position = "popup." .. popup,
      icon = entry.icon or "",
      label = entry.label or "",
      click_script = click_action,
      script = ctx.HOVER_SCRIPT,
      ["label.font"] = menu_font_small,
      ["label.color"] = menu_label_color,
      ["icon.padding_left"] = padding.icon_left,
      ["icon.padding_right"] = padding.icon_right,
      ["label.padding_left"] = padding.label_left,
      ["label.padding_right"] = padding.label_right,
      background = {
        drawing = false,
        corner_radius = popup_item_corner_radius,
        height = popup_item_height
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
      script = submenu_hover_script,
      click_script = popup_toggle(),
      ["icon.padding_left"] = padding.icon_left,
      ["icon.padding_right"] = padding.icon_right,
      ["label.padding_left"] = padding.label_left,
      ["label.padding_right"] = padding.label_right,
      background = {
        drawing = false,
        corner_radius = popup_item_corner_radius,
        height = popup_item_height
      },
      popup = {
        align = "right",
        background = popup_background()
      }
    })
    remember(metadata.submenu_parents, parent)
    shell_exec(string.format("sleep %.1f; %s --subscribe %s mouse.entered mouse.exited mouse.exited.global", post_config_delay, sketchybar_bin, parent))
    renderer(parent, entry.items or {})
  end

  return {
    render = render_menu_items,
    appearance_action = appearance_action,
    get_metadata = function()
      return {
        popup_parents = list_from_set(metadata.popup_parents),
        submenu_parents = list_from_set(metadata.submenu_parents),
      }
    end,
  }
end

return menu_renderer
