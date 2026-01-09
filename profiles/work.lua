-- Work Profile (Generic)
-- Emacs for org-mode, halext-org, and C++/SSH workflows

local profile = {}

-- Profile metadata
profile.name = "work"
profile.description = "Work setup with Emacs and productivity integrations"
profile.author = "scawful"

-- Integration toggles
profile.integrations = {
  yaze = false,       -- No ROM hacking at work
  emacs = true,       -- Keep Emacs for org-mode
  halext = true,      -- Use halext-org for task management
  cpp_dev = true,     -- C++ development tools
  ssh_cloud = true,   -- SSH and cloud workflows
}

-- Custom paths
profile.paths = {
  work_docs = os.getenv("HOME") .. "/work/docs",
  code = os.getenv("BARISTA_CODE_DIR") or (os.getenv("HOME") .. "/src"),  -- General code directory
  -- Add work-specific program paths here
  -- Example: custom_tool = os.getenv("HOME") .. "/work/tools/custom_tool",
}

-- Custom menu sections (add to Apple menu)
profile.menu_sections = {
  { type = "submenu", name = "menu.emacs.section", icon = "", label = "Emacs Workspace", order = 60 },
  { type = "submenu", name = "menu.halext.section", icon = "󱓷", label = "halext-org", order = 70 },
  { type = "submenu", name = "menu.cpp.section", icon = "󰨞", label = "C++ Dev", order = 90 },
  { type = "submenu", name = "menu.ssh.section", icon = "󰆍", label = "SSH & Cloud", order = 100 },
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
  cpp_build_status = true,  -- C++ build status widget
  ssh_connections = true,   -- SSH connection status widget
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
  print("Loaded work profile: Emacs + C++ + SSH")
end

return profile
