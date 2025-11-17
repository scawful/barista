-- Personal Profile (scawful)
-- ROM hacking, personal Emacs workflows, development tools

local profile = {}

-- Profile metadata
profile.name = "personal"
profile.description = "Personal development setup with ROM hacking and Emacs"
profile.author = "scawful"

-- Integration toggles
profile.integrations = {
  yaze = true,        -- ROM hacking with Yaze
  emacs = true,       -- Personal Emacs org-mode workflows
  halext = false,     -- halext-org (when ready)
}

-- Custom paths
profile.paths = {
  rom_doc = os.getenv("HOME") .. "/Code/docs/workflow/rom-hacking.org",
  yaze = os.getenv("HOME") .. "/Code/yaze",
  workflow_data = os.getenv("HOME") .. "/.config/sketchybar/data/workflow_shortcuts.json",
}

-- Custom menu sections (add to Apple menu)
profile.menu_sections = {
  { type = "submenu", name = "menu.rom.section", icon = "󰊕", label = "ROM Hacking", order = 50 },
  { type = "submenu", name = "menu.emacs.section", icon = "", label = "Emacs Workspace", order = 60 },
}

-- Appearance preferences
profile.appearance = {
  bar_height = 38,
  corner_radius = 0,
  bar_color = "0xd03b2b4a",
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
  count = 10,
  default_mode = "bsp",  -- bsp, stack, float
  icons = {
    ["1"] = "",  -- Code
    ["2"] = "",  -- Browser
    ["3"] = "󰊕",  -- ROM Hacking
    ["4"] = "",  -- Emacs
  }
}

-- Custom scripts (optional)
profile.scripts = function(base_scripts)
  -- Extend base scripts with profile-specific ones
  return base_scripts
end

-- Initialization hook (called once on profile load)
profile.init = function(sbar, config, modules)
  print("Loaded personal profile: ROM hacking + Emacs")
end

return profile
