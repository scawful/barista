-- components/front_app.lua

local M = {}

function M.setup(config, menu_context)
  local sbar = config.sbar
  local theme = config.theme
  local PLUGIN_DIR = config.paths.plugins
  local subscribe_popup_autoclose = menu_context.subscribe_popup_autoclose
  local attach_hover = menu_context.attach_hover
  local menu_module = config.menu_module

  sbar.add("item", "front_app", {
    position = "left",
    icon = { drawing = true },
    label = { drawing = true },
    script = PLUGIN_DIR .. "/front_app.sh",
    click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
    background = {
      color = "0x00000000",
      corner_radius = config.appearance.widget_corner_radius,
      height = config.appearance.widget_height,
    },
    popup = {
      background = {
        border_width = 2,
        corner_radius = 4,
        border_color = theme.WHITE,
        color = theme.bar.bg
      }
    }
  })
  sbar.exec("sketchybar --subscribe front_app front_app_switched")
  sbar.exec("sketchybar --trigger front_app_switched") -- Trigger initial update
  subscribe_popup_autoclose("front_app")
  attach_hover("front_app")

  -- Render front app menu
  menu_module.render_front_app(menu_context)
end

return M
