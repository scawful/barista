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
  google = true,      -- Google Workspace integrations
  cpp_dev = true,     -- C++ development tools
  ssh_cloud = true,   -- SSH and cloud workflows
  google_cpp = true,  -- Google C++ specific tools (Bazel, Gerrit, etc.)
}

-- Custom paths
profile.paths = {
  work_docs = os.getenv("HOME") .. "/work/docs",
  google_tools = os.getenv("HOME") .. "/google/tools",
  google3 = os.getenv("HOME") .. "/google3",  -- Google3 monorepo
  code = os.getenv("HOME") .. "/Code",        -- General code directory
  -- Add custom Google program paths here
  -- Example: custom_tool = os.getenv("HOME") .. "/google/tools/custom_tool",
}

-- Custom menu sections (add to Apple menu)
profile.menu_sections = {
  { type = "submenu", name = "menu.emacs.section", icon = "", label = "Emacs Workspace", order = 60 },
  { type = "submenu", name = "menu.halext.section", icon = "󱓷", label = "halext-org", order = 70 },
  { type = "submenu", name = "menu.google.section", icon = "󰡷", label = "Google", order = 80 },
  { type = "submenu", name = "menu.cpp.section", icon = "󰨞", label = "C++ Dev", order = 90 },
  { type = "submenu", name = "menu.ssh.section", icon = "󰆍", label = "SSH & Cloud", order = 100 },
  { type = "submenu", name = "menu.google_cpp.section", icon = "󰆍", label = "Google C++", order = 110 },
}

-- Custom menu items for Google tools
profile.custom_menu_items = {
  {
    type = "item",
    name = "menu.google.gmail",
    icon = "󰬦",
    label = "Gmail",
    action = "open -a 'Google Chrome' 'https://mail.google.com'",
    section = "menu.google.section",
  },
  {
    type = "item",
    name = "menu.google.calendar",
    icon = "󰃭",
    label = "Calendar",
    action = "open -a 'Google Chrome' 'https://calendar.google.com'",
    section = "menu.google.section",
  },
  {
    type = "item",
    name = "menu.google.drive",
    icon = "󰨞",
    label = "Drive",
    action = "open -a 'Google Chrome' 'https://drive.google.com'",
    section = "menu.google.section",
  },
  {
    type = "item",
    name = "menu.google.docs",
    icon = "󰈬",
    label = "Docs",
    action = "open -a 'Google Chrome' 'https://docs.google.com'",
    section = "menu.google.section",
  },
  -- Add custom Google programs here
  -- Example:
  -- {
  --   type = "item",
  --   name = "menu.google.custom_tool",
  --   icon = "󰨞",
  --   label = "Custom Tool",
  --   action = profile.paths.custom_tool,
  --   section = "menu.google.section",
  -- },
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
  ssh_connections = true,    -- SSH connection status widget
  bazel_status = true,      -- Bazel build status (Google C++)
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
