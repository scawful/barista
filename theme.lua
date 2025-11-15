local current_theme = "halext"

local function load_theme(theme)
  local theme = require("themes." .. theme_name)
  sbar.bar({ color = theme.bg })
  sbar.default({
      label = { color = theme.fg },
      icon = { color = theme.accent },
  })
  -- Update existing items dynamically
  sbar.set("/.*/", {
             background = { color = theme.bg },
             label = { color = theme.fg },
             icon = { color = theme.accent },
  })
end

-- Apply initial theme
load_theme(current_theme)

-- Expose function to change theme externally
return { load_theme = load_theme }