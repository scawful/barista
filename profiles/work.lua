-- Work Profile (Generic)
-- Emacs and work-oriented spaces; machine-specific tools stay opt-in

local profile = {}

-- Profile metadata
profile.name = "work"
profile.description = "Portable Work setup with Emacs and no personal surfaces"
profile.author = "scawful"

-- Integration toggles
profile.integrations = {
  control_center = true, -- Primary window-manager status + controls
  yaze = false,       -- No ROM hacking at work
  oracle = false,     -- Keep the personal Triforce menu opt-in
  music = false,      -- Keep Music Studio launchers machine-local
  emacs = true,       -- Keep Emacs for org-mode
  halext = false,     -- Keep unfinished halext integration opt-in
  journal = false,    -- Hide personal journal at work
  nerv = false,       -- Hide NERV at work
}

-- Window manager mode (expects yabai/skhd on work machines)
profile.modes = {
  window_manager = "required",
}

profile.paths = {}
profile.menu_sections = {}

-- Appearance preferences
profile.appearance = {
  bar_height = 32,
  corner_radius = 6,
  bar_color = "0xC021162F",
  blur_radius = 30,
  widget_scale = 1.0,
}

-- Widget configuration
profile.widgets = {
  lmstudio = false,
  clock = true,
  battery = true,
  network = true,
  system_info = true,
  volume = true,
}

-- Space configuration
profile.spaces = {
  count = 6,
  default_mode = "bsp",
  icons = {
    ["1"] = "",  -- Code
    ["2"] = "",  -- Browser
    ["3"] = "",  -- Mail
    ["4"] = "",  -- Emacs
    ["5"] = "",  -- Meetings
  }
}

return profile
