local sbar = require("sketchybar")

sbar.begin_config()

-- Test: Create a simple space
sbar.add("space", "space.1", {
  position = "left",
  space = "1",
  icon = "1",
  icon_padding_left = 5,
  icon_padding_right = 5,
  label = { drawing = false },
  background = {
    color = "0x20ffffff",
    corner_radius = 7,
    height = 18
  },
  script = "/Users/scawful/.config/sketchybar/plugins/space.sh",
  click_script = "yabai -m space --focus 1"
})

sbar.end_config()
sbar.event_loop()
