-- Girlfriend Profile
-- Warm, cozy layout with friendly defaults

local profile = {}

-- Profile metadata
profile.name = "girlfriend"
profile.description = "Warm, cozy bar with friendly widgets"
profile.author = "scawful"

-- Integration toggles (keep it simple)
profile.integrations = {
  control_center = true,
  yaze = false,
  emacs = false,
  halext = false,
  oracle = false,
  journal = false,
  nerv = false,
  halext_org = false,
}

-- Window manager mode (keep yabai/skhd optional)
profile.modes = {
  window_manager = "disabled",
}

-- Custom paths (none by default)
profile.paths = {}

-- Appearance preferences
profile.appearance = {
  theme = "mocha",
  bar_height = 32,
  corner_radius = 12,
  bar_color = "0xE04A3426",
  blur_radius = 26,
  bar_padding_left = 12,
  bar_padding_right = 12,
  bar_border_width = 1,
  bar_border_color = "0x30F5E6D3",
  widget_scale = 1.05,
  widget_corner_radius = 8,
  popup_padding = 10,
  popup_corner_radius = 10,
  popup_border_width = 1,
  popup_border_color = "0x40F5E6D3",
  popup_bg_color = "0xE04A3426",
  popup_item_corner_radius = 6,
  hover_color = "0x50F5E6D3",
  hover_border_color = "0x60F5E6D3",
  hover_border_width = 1,
  hover_animation_curve = "sin",
  hover_animation_duration = 10,
  submenu_hover_color = "0x80CDAF95",
  submenu_idle_color = "0x00000000",
  group_bg_color = "0x403E2723",
  group_border_color = "0x305C4033",
  group_border_width = 1,
  group_corner_radius = 8,
}

-- Widget configuration
profile.widgets = {
  clock = true,
  battery = true,
  network = true,
  system_info = true,
  volume = true,
}

-- Space configuration
profile.spaces = {
  count = 6,
  icons = {
    ["1"] = "",  -- Home
    ["2"] = "󰈙",  -- Notes
    ["3"] = "󰊗",  -- Games
    ["4"] = "󰎈",  -- Music
    ["5"] = "󰆋",  -- Maps
    ["6"] = "󰏘",  -- Creative
  }
}

-- Initialization hook
profile.init = function()
  print("Loaded girlfriend profile: warm + cozy")
end

return profile
