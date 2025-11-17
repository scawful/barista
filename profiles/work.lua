-- Work Profile (Google)
-- Google-specific integrations, Emacs for org-mode, no ROM hacking

local profile = {}

-- Profile metadata
profile.name = "work"
profile.description = "Work setup for Google with Emacs integration"
profile.author = "scawful"

-- Integration toggles
profile.integrations = {
  yaze = false,       -- No ROM hacking at work
  emacs = true,       -- Keep Emacs for org-mode
  halext = true,      -- Use halext-org for task management
  google = true,      -- Future: Google-specific integrations
}

-- Custom paths
profile.paths = {
  -- Work-specific paths would go here
  work_docs = os.getenv("HOME") .. "/work/docs",
}

-- Custom menu sections (add to Apple menu)
profile.menu_sections = {
  { type = "submenu", name = "menu.emacs.section", icon = "", label = "Emacs Workspace", order = 60 },
  { type = "submenu", name = "menu.halext.section", icon = "󱓷", label = "halext-org", order = 70 },
  -- Future: Google-specific menu items
}

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
  clock = true,
  battery = true,
  network = true,
  system_info = true,
  volume = true,
  yabai_status = true,
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

-- Custom scripts
profile.scripts = function(base_scripts)
  return base_scripts
end

-- Initialization hook
profile.init = function(sbar, config, modules)
  print("Loaded work profile: Google + Emacs")
end

return profile
