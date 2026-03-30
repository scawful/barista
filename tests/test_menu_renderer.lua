local menu_renderer = require("menu_renderer")

local function find_entry(entries, name)
  for _, entry in ipairs(entries) do
    if entry.name == name then
      return entry
    end
  end
  return nil
end

run_test("menu_renderer: uses direct toggle for nested submenu parents", function()
  local added = {}
  local renderer = menu_renderer.create({
    sbar = {
      add = function(kind, name, props)
        table.insert(added, { kind = kind, name = name, props = props })
      end,
    },
    settings = {
      font = {
        text = "Source Code Pro",
        style_map = { Regular = "Regular", Semibold = "Semibold", Bold = "Bold" },
        sizes = { small = 12 },
      },
    },
    theme = {
      WHITE = "0xffffffff",
      DARK_WHITE = "0xffcccccc",
      bar = { bg = "0xff111111" },
    },
    appearance = {},
    attach_hover = function() end,
    shell_exec = function() end,
    HOVER_SCRIPT = "hover.sh",
    SUBMENU_HOVER_SCRIPT = "submenu_hover.sh",
    popup_toggle_action = function(item_name, opts)
      if opts and opts.direct then
        return "direct:" .. (item_name or "$NAME")
      end
      return "default:" .. (item_name or "$NAME")
    end,
  })

  renderer.render("apple_menu", {
    {
      type = "submenu",
      name = "menu.oracle",
      icon = "O",
      label = "Oracle",
      items = {
        {
          type = "item",
          name = "oracle.workbench",
          label = "Open Workbench",
          action = "echo oracle",
        },
      },
    },
  })

  local parent = find_entry(added, "menu.oracle")
  assert_true(parent ~= nil, "submenu parent should be rendered")
  assert_equal(parent.props.click_script, "direct:menu.oracle", "submenu parent should use direct toggle")

  local metadata = renderer.get_metadata()
  assert_true(#metadata.submenu_parents == 1, "submenu parent metadata should be tracked")
  assert_equal(metadata.submenu_parents[1], "menu.oracle", "submenu parent metadata value")
end)
