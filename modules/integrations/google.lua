-- Google-specific integrations for Barista
-- Provides Google Workspace shortcuts and custom program integration

local google = {}

google.enabled = false
google.config = {}

-- Default Google Workspace URLs
google.urls = {
  gmail = "https://mail.google.com",
  calendar = "https://calendar.google.com",
  drive = "https://drive.google.com",
  docs = "https://docs.google.com",
  sheets = "https://sheets.google.com",
  slides = "https://slides.google.com",
  meet = "https://meet.google.com",
}

-- Custom programs configuration
google.custom_programs = {
  -- Example:
  -- {
  --   name = "custom_tool",
  --   path = os.getenv("HOME") .. "/google/tools/custom_tool",
  --   icon = "󰨞",
  --   label = "Custom Tool",
  -- },
}

function google.init(sbar, config)
  if not config.integrations or not config.integrations.google then
    return
  end
  
  local google_config = config.integrations.google
  if not google_config.enabled then
    return
  end
  
  google.enabled = true
  google.config = google_config
  
  -- Merge custom URLs if provided
  if google_config.urls then
    for k, v in pairs(google_config.urls) do
      google.urls[k] = v
    end
  end
  
  -- Merge custom programs if provided
  if google_config.custom_programs then
    for _, program in ipairs(google_config.custom_programs) do
      table.insert(google.custom_programs, program)
    end
  end
  
  print("Google integration enabled")
end

function google.get_menu_items()
  if not google.enabled then
    return {}
  end
  
  local items = {}
  
  -- Add Google Workspace items
  for name, url in pairs(google.urls) do
    local icon = "󰨞"  -- Default icon
    local label = name:gsub("^%l", string.upper)  -- Capitalize first letter
    
    -- Custom icons for common services
    local icon_map = {
      gmail = "󰬦",
      calendar = "󰃭",
      drive = "󰨞",
      docs = "󰈬",
      sheets = "󰈙",
      slides = "󰈨",
      meet = "󰕧",
    }
    
    if icon_map[name] then
      icon = icon_map[name]
    end
    
    table.insert(items, {
      type = "item",
      name = "menu.google." .. name,
      icon = icon,
      label = label,
      action = string.format("open -a 'Google Chrome' '%s'", url),
    })
  end
  
  -- Add custom programs
  for _, program in ipairs(google.custom_programs) do
    -- Check if program exists
    local program_path = program.path
    if program_path and os.execute("test -f " .. program_path) == 0 then
      table.insert(items, {
        type = "item",
        name = "menu.google." .. program.name,
        icon = program.icon or "󰨞",
        label = program.label or program.name,
        action = program_path,
      })
    end
  end
  
  return items
end

function google.setup_menu_items(menu_items)
  if not google.enabled then
    return menu_items
  end
  
  local google_items = google.get_menu_items()
  
  -- Add Google items to menu
  for _, item in ipairs(google_items) do
    table.insert(menu_items, item)
  end
  
  return menu_items
end

return google

