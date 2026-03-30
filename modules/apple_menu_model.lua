local apple_menu_model = {}

local function normalize_bool(value)
  if type(value) == "boolean" then
    return value
  end
  if type(value) == "number" then
    return value ~= 0
  end
  if type(value) == "string" then
    local lowered = value:lower()
    if lowered == "true" or lowered == "yes" or lowered == "1" then
      return true
    end
    if lowered == "false" or lowered == "no" or lowered == "0" then
      return false
    end
  end
  return nil
end

local function normalize_order(value)
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" then
    return tonumber(value)
  end
  return nil
end

local function normalize_section_id(value)
  local section_id = tostring(value or ""):lower()
  if section_id == "" or section_id == "projects" then
    return "apps"
  end
  return section_id
end

local function shell_quote(value)
  return string.format("%q", tostring(value or ""))
end

local function sanitize_id(value, fallback)
  local raw = tostring(value or fallback or "item")
  raw = raw:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if raw == "" then
    return tostring(fallback or "item")
  end
  return raw
end

local function clone_sections(sections)
  local cloned = {}
  for key, value in pairs(sections or {}) do
    if type(value) == "table" then
      local section = {}
      for section_key, section_value in pairs(value) do
        section[section_key] = section_value
      end
      cloned[key] = section
    end
  end
  return cloned
end

local function merge_section_overrides(sections, overrides)
  for section_id, override in pairs(overrides or {}) do
    if type(override) == "table" then
      local normalized_section_id = normalize_section_id(section_id)
      local section = sections[normalized_section_id] or {
        id = normalized_section_id,
        label = normalized_section_id,
        order = 99,
      }
      if override.label and override.label ~= "" then
        section.label = override.label
      end
      if override.icon and override.icon ~= "" then
        section.icon = override.icon
      end
      if override.color and override.color ~= "" then
        section.color = override.color
      end
      local order = normalize_order(override.order)
      if order ~= nil then
        section.order = order
      end
      sections[normalized_section_id] = section
    end
  end
  return sections
end

local function action_from_entry(entry)
  local action = entry.command or entry.action or ""
  if action == "" and type(entry.url) == "string" and entry.url ~= "" then
    action = string.format("open %s", shell_quote(entry.url))
  end
  return action
end

local function normalize_custom_popup_items(prefix, items)
  local normalized = {}
  for index, item in ipairs(items or {}) do
    if type(item) == "table" then
      local item_type = item.type
      if item.separator == true then
        item_type = "separator"
      end

      local item_id = sanitize_id(item.id or item.name or item.label or item.title, index)
      local item_name = string.format("%s.%s", prefix, item_id)

      if item_type == "separator" then
        table.insert(normalized, {
          type = "separator",
          name = item_name,
        })
      elseif item_type == "header" then
        table.insert(normalized, {
          type = "header",
          id = item_id,
          name = item_name,
          label = item.label or item.title or "",
        })
      else
        local submenu_items = normalize_custom_popup_items(item_name, item.items)
        local action = action_from_entry(item)
        local submenu = submenu_items ~= nil and #submenu_items > 0

        if submenu or action ~= "" then
          table.insert(normalized, {
            name = item_name,
            label = item.label or item.title or ("Item " .. index),
            icon = item.icon or "",
            icon_color = item.icon_color or item.color,
            label_color = item.label_color,
            action = action,
            shortcut = item.shortcut,
            shortcut_action = item.shortcut_action,
            submenu = submenu,
            items = submenu_items,
            arrow_icon = item.arrow_icon,
          })
        end
      end
    end
  end

  if #normalized == 0 then
    return nil
  end
  return normalized
end

local function collect_base_items(rendered, base_items, menu_config, show_missing)
  for index, item in ipairs(base_items or {}) do
    local override = menu_config.items[item.id] or {}
    local enabled_override = normalize_bool(override.enabled)
    local should_show = false
    local missing = false

    if enabled_override == false then
      should_show = false
    elseif item.blocked then
      should_show = true
    elseif enabled_override == true then
      should_show = true
      missing = not item.available
    else
      if item.default_enabled == false then
        should_show = false
      elseif item.available then
        should_show = true
      elseif show_missing then
        should_show = true
        missing = true
      end
    end

    if should_show then
      local order = normalize_order(override.order) or item.order or (1000 + index)
      table.insert(rendered, {
        id = item.id,
        name = "menu.tools." .. item.id,
        label = override.label or item.label,
        icon = override.icon or item.icon,
        icon_color = override.icon_color or override.color or item.icon_color,
        label_color = override.label_color or item.label_color,
        action = item.action or "",
        blocked = item.blocked == true,
        submenu = item.submenu == true,
        items = item.items,
        arrow_icon = item.arrow_icon,
        shortcut = override.shortcut or item.shortcut,
        shortcut_action = override.shortcut_action or item.shortcut_action,
        missing = missing,
        order = order,
        default_index = index,
        section = normalize_section_id(override.section or item.section or "controls"),
      })
    end
  end
end

local function collect_custom_items(rendered, menu_config)
  for index, custom in ipairs(menu_config.custom or {}) do
    if type(custom) == "table" then
      local enabled_override = normalize_bool(custom.enabled)
      if enabled_override ~= false then
        local label = custom.label or custom.title or ("Custom " .. index)
        local action = action_from_entry(custom)
        local custom_id = sanitize_id(custom.id or custom.name or custom.label, index)
        local custom_name = "menu.tools.custom." .. custom_id
        local submenu_items = normalize_custom_popup_items(custom_name, custom.items)
        local submenu = submenu_items ~= nil and #submenu_items > 0

        if label ~= "" and (action ~= "" or submenu) then
          table.insert(rendered, {
            id = "custom_" .. custom_id,
            name = custom_name,
            label = label,
            icon = custom.icon or "",
            icon_color = custom.icon_color or custom.color,
            label_color = custom.label_color,
            action = action,
            shortcut = custom.shortcut,
            shortcut_action = custom.shortcut_action,
            submenu = submenu,
            items = submenu_items,
            arrow_icon = custom.arrow_icon,
            missing = false,
            order = normalize_order(custom.order) or (2000 + index),
            default_index = 1000 + index,
            section = normalize_section_id(custom.section or "custom"),
          })
        end
      end
    end
  end
end

local function collect_project_shortcuts(rendered, project_shortcuts, show_missing)
  if not (project_shortcuts and project_shortcuts.enabled) then
    return
  end

  for index, project in ipairs(project_shortcuts.items or {}) do
    if project.available or show_missing then
      table.insert(rendered, {
        id = project.id,
        name = "menu.tools.project." .. project.id,
        label = project.label,
        icon = project.icon,
        icon_color = project.icon_color,
        label_color = project.label_color,
        action = project.action,
        shortcut = project.shortcut,
        missing = not project.available,
        order = project.order or (1300 + index),
        default_index = 1100 + index,
        section = normalize_section_id(project.section or "apps"),
      })
    end
  end
end

local function collect_work_items(rendered, menu_config, theme)
  for index, app in ipairs(menu_config.work_google_apps or {}) do
    if type(app) == "table" then
      local enabled = normalize_bool(app.enabled)
      if enabled ~= false then
        local label = app.label or app.title or app.name or ("Work App " .. index)
        local action = action_from_entry(app)
        if label ~= "" and action ~= "" then
          table.insert(rendered, {
            id = app.id or ("work_google_" .. index),
            name = "menu.tools.work." .. index,
            label = label,
            icon = app.icon or "󰊯",
            icon_color = app.icon_color or app.color or theme.BLUE,
            label_color = app.label_color,
            action = action,
            shortcut = app.shortcut,
            missing = false,
            order = normalize_order(app.order) or (1500 + index),
            default_index = 1200 + index,
            section = normalize_section_id(app.section or "work"),
          })
        end
      end
    end
  end
end

local function sort_rendered_items(rendered, sections)
  table.sort(rendered, function(a, b)
    local section_a = sections[a.section] and sections[a.section].order or 99
    local section_b = sections[b.section] and sections[b.section].order or 99
    if section_a ~= section_b then
      return section_a < section_b
    end
    if a.order == b.order then
      return a.default_index < b.default_index
    end
    return a.order < b.order
  end)
end

function apple_menu_model.build(opts)
  opts = opts or {}
  local sections = merge_section_overrides(
    clone_sections(opts.sections or {}),
    opts.menu_config and opts.menu_config.sections or {}
  )
  local rendered = {}

  collect_base_items(rendered, opts.base_items or {}, opts.menu_config or {}, opts.show_missing == true)
  collect_custom_items(rendered, opts.menu_config or {})
  collect_project_shortcuts(rendered, opts.project_shortcuts or {}, opts.show_missing == true)
  collect_work_items(rendered, opts.menu_config or {}, opts.theme or {})
  sort_rendered_items(rendered, sections)

  return {
    rendered = rendered,
    sections = sections,
  }
end

return apple_menu_model
