local sbar = require("sketchybar")

local PLUGIN_DIR = "/Users/scawful/.config/sketchybar/plugins"

sbar.begin_config()

colors = {
  bar = {
    bg = 0xD04C3B52
  },
  ROSEWATER = "0xFFf5e0dc",
  FLAMINGO = "0xFFf2cdcd",
  PINK = "0xFFf5c2e7",
  MAUVE = "0xFFcba6f7",
  RED = "0xFFf38ba8",
  MAROON = "0xFFeba0ac",
  PEACH = "0xFFfab387",
  YELLOW = "0xFFf9e2af",
  GREEN = "0xFFa6e3a1",
  TEAL = "0xFF94e2d5",
  SKY = "0xFF89dceb",
  SAPPHIRE = "0xFF74c7ec",
  BLUE = "0xFF89b4fa",
  LAVENDER = "0xFFb4befe",
  WHITE = "0xFFcdd6f4",
  DARK_WHITE = "0xFF9399b2",
  BG_PRI_COLR = "0xEE1e1e2e",
  BG_SEC_COLR = "0xFF313244",
}

local settings = {
  font = {
    icon = "Hack Nerd Font",
    text = "Source Code Pro", -- Used for text
    numbers = "SF Mono", -- Used for numbers
    style_map = {
      Regular = "Regular",
      Bold = "Bold",
      Heavy = "Heavy",
      Semibold = "Semibold"
    }
  },
  paddings = 5
}

-- Bar Config
sbar.bar({
  position = "top",
  height = 25,
  blur_radius = 30,
  color = colors.bar.bg,
  margin = 5,
  padding_left = 5,
  padding_right = 5,
  corner_radius = 7,
  y_offset = 5,
  display = "all",
})

-- Defaults
sbar.default({
  updates = "when_shown",
  padding_left = 5,
  padding_right = 5,
  color = 0xD04C3B52,
  height = 25,
  blur_radius = 30,
  icon = {
    font = {
      family = settings.font.icon,
      style = settings.font.style_map["Bold"],
      size = 16.0
    },
    color = 0xffffffff,
    padding_left = 4,
    padding_right = 4,
  },
  label = {
    font = {
      family = settings.font.text,
      style = settings.font.style_map["Semibold"],
      size = 14.0
    },
    color = 0xffffffff,
    padding_left = 4,
    padding_right = 4,
  },
})

-- Zelda Main Button
sbar.add("item", "zelda", {
  position = "left",
  icon = "󰀵",
  icon_font = "SF Pro:Black:16.0",
  label = { drawing = false },
  click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
  popup = {
    background = {
      border_width = 2,
      corner_radius = 3,
      border_color = 0xffffffff,
      color = colors.bar.bg
    }
  }
})

-- Zelda Popup Apps
local popup_apps = {
  yaze = {
    icon = "󰯙",
    label = "Yaze",
    script = "open -a ~/Code/yaze/build/bin/yaze.app/Contents/MacOS/yaze"
  },
  mesen = {
    icon = "󰺷",
    label = "Mesen",
    script = "open -a mesen"
  },
  ["apple.activity"] = {
    icon = "󰨇",
    label = "Activity",
    script = "open -a 'Activity Monitor'"
  },
  ["apple.preferences"] = {
    icon = "",
    label = "Preferences",
    script = "open -a 'System Preferences'"
  },
  ["sketchybar.reload"] = {
    icon = "󰑐",
    label = "Reload",
    script = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload"
  },
  ["app.terminal"] = {
    icon = "terminal",
    label = "Terminal",
    script = "open -a Terminal"
  },
  ["app.finder"] = {
    icon = "",
    label = "Finder",
    script = "open -a Finder"
  },
  ["app.vscode"] = {
    icon = "󰨞",
    label = "VSCode",
    script = "open -a \"Visual Studio Code\""
  }
}

for name, opts in pairs(popup_apps) do
  sbar.add("item", name, {
    position = "popup.zelda",
    icon = opts.icon,
    label = opts.label,
    click_script = opts.script .. "; sketchybar -m --set zelda popup.drawing=off"
  })
end

-- Spaces
local space_icons = { "", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" }

for i, icon in ipairs(space_icons) do
  local index = tostring(i)  -- Use space index (1-based)
  sbar.add("space", "space." .. index, {
    position = "left",
    space = index,
    icon = icon,
    icon_padding_left = 5,
    icon_padding_right = 5,
    label = { drawing = false },
    background = {
      color = "0x20ffffff",
      corner_radius = 7,
      height = 18
    },
    script = PLUGIN_DIR .. "/space.sh",
    click_script = "yabai -m space --focus " .. index
  })
end

sbar.add("bracket", { "/space\\..*/" }, {
  background = {
    color = "0x40000000",
    corner_radius = 7,
    height = 20
  }
})

-- App Name on Left
sbar.add("item", "front_app", {
  position = "left",
  icon = { drawing = true },
  script = PLUGIN_DIR .. "/front_app.sh",
})
sbar.exec("sketchybar --subscribe front_app front_app_switched")

-- Clock
sbar.add("item", "clock", {
  position = "right",
  icon = "",
  update_freq = 10,
  script = PLUGIN_DIR .. "/clock.sh",
  background = {
    color = "0x80111111",
    corner_radius = 7,
    height = 20
  },
  font = {
    family = settings.font.numbers,
    style = settings.font.style_map["Regular"],
    size = 14.0
  }
})

-- Volume
sbar.add("item", "volume", {
  position = "right",
  script = PLUGIN_DIR .. "/volume.sh",
  background = {
    color = 0x8020B2AA,
    corner_radius = 7,
    height = 20
  },
})
sbar.exec("sketchybar --subscribe volume volume_change")

-- Battery
sbar.add("item", "battery", {
  position = "right",
  update_freq = 120,
  script = PLUGIN_DIR .. "/battery.sh '" .. colors.GREEN .. "' '" .. colors.YELLOW .. "' '" .. colors.RED .. "' '" .. colors.BLUE .. "'",
  background = {
    color = colors.LAVENDER,
    corner_radius = 7,
    height = 20
  },
})
sbar.exec("sketchybar --subscribe battery system_woke power_source_change")

sbar.end_config()

sbar.event_loop()