-- Profile Management Module
-- Handles loading user profiles and merging with base configuration

local profile = {}

local HOME = os.getenv("HOME")
local CONFIG_DIR = HOME .. "/.config/sketchybar"

-- Load profile by name
function profile.load(profile_name)
  profile_name = profile_name or "minimal"

  local profile_path = CONFIG_DIR .. "/profiles/" .. profile_name .. ".lua"

  -- Check if profile exists
  local file = io.open(profile_path, "r")
  if not file then
    print("Warning: Profile '" .. profile_name .. "' not found, using minimal profile")
    profile_name = "minimal"
    profile_path = CONFIG_DIR .. "/profiles/minimal.lua"
    file = io.open(profile_path, "r")
    if not file then
      print("Error: Minimal profile not found!")
      return nil
    end
  end
  file:close()

  -- Load profile module
  local ok, loaded_profile = pcall(require, "profiles." .. profile_name)
  if not ok then
    print("Error loading profile '" .. profile_name .. "': " .. tostring(loaded_profile))
    return nil
  end

  return loaded_profile
end

-- Get profile name from state or environment
function profile.get_selected_profile(state)
  -- Priority: state.json > environment variable > default
  if state and state.profile then
    return state.profile
  end

  local env_profile = os.getenv("SKETCHYBAR_PROFILE")
  if env_profile and env_profile ~= "" then
    return env_profile
  end

  return "minimal"  -- Default
end

-- Merge profile configuration with base config
function profile.merge_config(base_config, user_profile)
  if not user_profile then
    return base_config
  end

  -- Merge appearance (only for non-nil values to preserve state.json)
  if user_profile.appearance then
    base_config.appearance = base_config.appearance or {}
    for k, v in pairs(user_profile.appearance) do
      -- Only merge if value is not nil (allows profiles to preserve existing settings)
      if v ~= nil then
        base_config.appearance[k] = v
      end
    end
  end

  -- Merge widgets
  if user_profile.widgets then
    base_config.widgets = base_config.widgets or {}
    for k, v in pairs(user_profile.widgets) do
      base_config.widgets[k] = v
    end
  end

  -- Merge integrations
  if user_profile.integrations then
    base_config.integrations = base_config.integrations or {}
    for k, v in pairs(user_profile.integrations) do
      if base_config.integrations[k] == nil then
        base_config.integrations[k] = {}
      end
      if type(base_config.integrations[k]) == "table" then
        base_config.integrations[k].enabled = v
      end
    end
  end

  -- Merge space icons
  if user_profile.spaces and user_profile.spaces.icons then
    base_config.space_icons = base_config.space_icons or {}
    for k, v in pairs(user_profile.spaces.icons) do
      base_config.space_icons[k] = v
    end
  end

  -- Merge space modes (ONLY if explicitly set in profile)
  -- DO NOT automatically apply default_mode to all spaces
  -- This prevents forcing window management on users
  if user_profile.spaces and user_profile.spaces.default_mode then
    -- Only apply if user explicitly wants it
    -- Most users should NOT set default_mode in their profile
    print("Warning: Profile sets default_mode to " .. user_profile.spaces.default_mode)
    print("This will force window management on all spaces!")
  end
  -- Space modes should be set via control panel, not profile

  return base_config
end

-- Get integration flags from profile
function profile.get_integration_flags(user_profile)
  if not user_profile or not user_profile.integrations then
    return {}
  end

  return user_profile.integrations
end

-- Get custom menu sections from profile
function profile.get_menu_sections(user_profile)
  if not user_profile or not user_profile.menu_sections then
    return {}
  end

  -- Sort by order if specified
  local sections = {}
  for _, section in ipairs(user_profile.menu_sections) do
    table.insert(sections, section)
  end

  table.sort(sections, function(a, b)
    return (a.order or 100) < (b.order or 100)
  end)

  return sections
end

-- Get custom paths from profile
function profile.get_paths(user_profile)
  if not user_profile or not user_profile.paths then
    return {}
  end

  return user_profile.paths
end

-- List available profiles
function profile.list_available()
  local profiles = {}
  local profiles_dir = CONFIG_DIR .. "/profiles"

  local handle = io.popen("ls " .. profiles_dir .. "/*.lua 2>/dev/null")
  if not handle then
    return profiles
  end

  for line in handle:lines() do
    local name = line:match("([^/]+)%.lua$")
    if name then
      table.insert(profiles, name)
    end
  end

  handle:close()
  return profiles
end

-- Create new profile from template
function profile.create_from_template(new_name, template_name)
  template_name = template_name or "minimal"

  local template_path = CONFIG_DIR .. "/profiles/" .. template_name .. ".lua"
  local new_path = CONFIG_DIR .. "/profiles/" .. new_name .. ".lua"

  -- Check if profile already exists
  local file = io.open(new_path, "r")
  if file then
    file:close()
    return false, "Profile already exists"
  end

  -- Copy template
  local cmd = string.format("cp '%s' '%s'", template_path, new_path)
  local success = os.execute(cmd)

  if success then
    return true, "Profile created: " .. new_path
  else
    return false, "Failed to create profile"
  end
end

return profile
