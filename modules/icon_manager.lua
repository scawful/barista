-- Centralized Icon Manager
-- Multi-font support with automatic fallback
-- Font-agnostic icon loading system

local icon_manager = {}

-- Supported icon font families and their priorities
icon_manager.fonts = {
  {name = "Hack Nerd Font", priority = 1, style = "Bold"},
  {name = "SF Pro", priority = 2, style = "Regular"},
  {name = "SF Symbols", priority = 3, style = "Regular"},
  {name = "Menlo", priority = 4, style = "Regular"},
}

-- Icon library with font-specific glyphs
-- Format: {icon_name = {glyph = "char", font = "font_name", codepoint = 0x...}}
icon_manager.library = {
  -- System icons
  apple = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Apple logo (Nerd Font)"},
      {char = "", font = "SF Symbols", desc = "Apple logo (SF Symbols)"},
    }
  },

  settings = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Settings"},
      {char = "⚙", font = "SF Pro", desc = "Gear"},
    }
  },

  power = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Power"},
      {char = "⏻", font = "SF Pro", desc = "Power symbol"},
    }
  },

  sleep = {
    glyphs = {
      {char = "󰒲", font = "Hack Nerd Font", desc = "Sleep moon"},
      {char = "☾", font = "SF Pro", desc = "Moon"},
    }
  },

  lock = {
    glyphs = {
      {char = "󰷛", font = "Hack Nerd Font", desc = "Lock"},
      {char = "", font = "SF Symbols", desc = "Lock"},
    }
  },

  calendar = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Calendar"},
      {char = "", font = "SF Symbols", desc = "Calendar"},
    }
  },

  clock = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Clock"},
      {char = "", font = "SF Symbols", desc = "Clock"},
    }
  },

  battery = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Battery"},
      {char = "", font = "SF Symbols", desc = "Battery"},
    }
  },

  volume = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Volume"},
      {char = "", font = "SF Symbols", desc = "Volume"},
    }
  },

  wifi = {
    glyphs = {
      {char = "󰖩", font = "Hack Nerd Font", desc = "WiFi"},
      {char = "", font = "SF Symbols", desc = "WiFi"},
    }
  },

  -- Window management
  window = {
    glyphs = {
      {char = "󰖯", font = "Hack Nerd Font", desc = "Window"},
      {char = "◻", font = "SF Pro", desc = "Window square"},
    }
  },

  tile = {
    glyphs = {
      {char = "󰆾", font = "Hack Nerd Font", desc = "Tile"},
      {char = "▦", font = "SF Pro", desc = "Tile grid"},
    }
  },

  stack = {
    glyphs = {
      {char = "󰓩", font = "Hack Nerd Font", desc = "Stack"},
      {char = "▥", font = "SF Pro", desc = "Stack"},
    }
  },

  float = {
    glyphs = {
      {char = "󰒄", font = "Hack Nerd Font", desc = "Float"},
      {char = "◫", font = "SF Pro", desc = "Float"},
    }
  },

  fullscreen = {
    glyphs = {
      {char = "󰊓", font = "Hack Nerd Font", desc = "Fullscreen"},
      {char = "⛶", font = "SF Pro", desc = "Fullscreen"},
    }
  },

  -- Development
  code = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Code"},
      {char = "<>", font = "SF Mono", desc = "Code brackets"},
    }
  },

  terminal = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Terminal"},
      {char = "$", font = "SF Mono", desc = "Terminal prompt"},
    }
  },

  emacs = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Emacs"},
      {char = "E", font = "SF Mono", desc = "Emacs letter"},
    }
  },

  git = {
    glyphs = {
      {char = "", font = "Hack Nerd Font", desc = "Git"},
      {char = "", font = "SF Symbols", desc = "Git branch"},
    }
  },

  -- Gaming / ROM
  gamepad = {
    glyphs = {
      {char = "󰍳", font = "Hack Nerd Font", desc = "Gamepad"},
      {char = "🎮", font = "SF Pro", desc = "Game controller emoji"},
    }
  },

  rom = {
    glyphs = {
      {char = "󰯙", font = "Hack Nerd Font", desc = "ROM cartridge"},
      {char = "▪", font = "SF Pro", desc = "Chip"},
    }
  },
}

-- Get icon with font fallback
-- Returns: {char = "icon", font = "Font Name", style = "Bold"}
function icon_manager.get(name, preferred_font)
  local icon_entry = icon_manager.library[name]

  if not icon_entry or not icon_entry.glyphs then
    return {char = "?", font = "SF Pro", style = "Regular"}
  end

  -- If preferred font specified, try to find it
  if preferred_font then
    for _, glyph in ipairs(icon_entry.glyphs) do
      if glyph.font == preferred_font then
        -- Find font style
        local style = "Regular"
        for _, font_info in ipairs(icon_manager.fonts) do
          if font_info.name == glyph.font then
            style = font_info.style
            break
          end
        end
        return {char = glyph.char, font = glyph.font, style = style}
      end
    end
  end

  -- Use first available glyph (highest priority)
  local glyph = icon_entry.glyphs[1]
  local style = "Regular"
  for _, font_info in ipairs(icon_manager.fonts) do
    if font_info.name == glyph.font then
      style = font_info.style
      break
    end
  end

  return {char = glyph.char, font = glyph.font, style = style}
end

-- Get just the character (for backwards compatibility)
function icon_manager.get_char(name, fallback)
  local icon = icon_manager.get(name)
  return icon.char or fallback or ""
end

-- Get font string for SketchyBar
function icon_manager.get_font_string(name, size, preferred_font)
  local icon = icon_manager.get(name, preferred_font)
  size = size or 16
  return string.format("%s:%s:%0.1f", icon.font, icon.style, size)
end

-- Create SketchyBar icon configuration
function icon_manager.create_config(name, size, preferred_font, color)
  local icon = icon_manager.get(name, preferred_font)
  size = size or 16
  color = color or "0xFFFFFFFF"

  return {
    value = icon.char,
    font = string.format("%s:%s:%0.1f", icon.font, icon.style, size),
    color = color,
  }
end

-- List all available icons
function icon_manager.list_icons()
  local icons = {}
  for name, _ in pairs(icon_manager.library) do
    table.insert(icons, name)
  end
  table.sort(icons)
  return icons
end

-- Get icon info (for debugging/inspection)
function icon_manager.get_info(name)
  local icon_entry = icon_manager.library[name]
  if not icon_entry then
    return nil
  end

  local info = {
    name = name,
    glyphs = {}
  }

  for _, glyph in ipairs(icon_entry.glyphs) do
    table.insert(info.glyphs, {
      char = glyph.char,
      font = glyph.font,
      desc = glyph.desc
    })
  end

  return info
end

-- Register a new icon
function icon_manager.register(name, glyphs)
  icon_manager.library[name] = {glyphs = glyphs}
end

-- Bulk import from existing icons module
function icon_manager.import_from_module(icons_module)
  if not icons_module or not icons_module.categories then
    return
  end

  for category, category_icons in pairs(icons_module.categories) do
    for name, char in pairs(category_icons) do
      if not icon_manager.library[name] then
        -- Create entry with Hack Nerd Font as default
        icon_manager.register(name, {
          {char = char, font = "Hack Nerd Font", desc = string.format("%s (%s)", name, category)}
        })
      end
    end
  end
end

return icon_manager
