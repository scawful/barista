-- Minimal Profile (Template)
-- Clean, minimal setup with no specific integrations
-- Perfect starting point for new users or as a base template

local profile = {}

-- Profile metadata
profile.name = "minimal"
profile.description = "Minimal, clean setup - great starting point"
profile.author = "template"

-- Integration toggles (all disabled by default)
profile.integrations = {
  yaze = false,
  emacs = false,
  halext = false,
}

-- Custom paths (none for minimal)
profile.paths = {}

-- Custom menu sections (only essential items)
profile.menu_sections = {
  -- No custom sections - just the base system menu
}

-- Appearance preferences (sensible defaults)
profile.appearance = {
  bar_height = 32,
  corner_radius = 9,
  bar_color = "0xC021162F",  -- Dark translucent
  blur_radius = 30,
  widget_scale = 1.0,
}

-- Widget configuration (all enabled)
profile.widgets = {
  clock = true,
  battery = true,
  network = true,
  system_info = true,
  volume = true,
  yabai_status = true,
}

-- Space configuration (simple 5 spaces)
profile.spaces = {
  count = 5,
  default_mode = "bsp",
  icons = {
    ["1"] = "①",
    ["2"] = "②",
    ["3"] = "③",
    ["4"] = "④",
    ["5"] = "⑤",
  }
}

-- Custom scripts
profile.scripts = function(base_scripts)
  return base_scripts
end

-- Initialization hook
profile.init = function(sbar, config, modules)
  print("Loaded minimal profile")
end

return profile
