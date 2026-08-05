local apple_menu = require("apple_menu_enhanced")

run_test("apple_menu_enhanced: apple menu stays hover-highlight + click-open", function()
  local added = {}
  local subscribed = {}

  local meta = apple_menu.setup({
    sbar = {
      add = function(kind, name, props)
        table.insert(added, { kind = kind, name = name, props = props })
      end,
    },
    theme = {
      WHITE = "0xffffffff",
      DARK_WHITE = "0xffcccccc",
      BG_SEC_COLR = "0xff111111",
      bar = { bg = "0xff000000" },
    },
    widget_height = 22,
    associated_displays = "all",
    popup_anchor_script = "/tmp/popup_anchor",
    popup_toggle_action = function()
      return "toggle:apple_menu"
    end,
    subscribe_popup_autoclose = function(name)
      table.insert(subscribed, name)
    end,
    call_script = function(path, ...)
      local parts = { path }
      for _, arg in ipairs({ ... }) do
        table.insert(parts, tostring(arg))
      end
      return table.concat(parts, " ")
    end,
    apple_menu_prepared = {
      config_dir = "/tmp/config",
      style = {
        popup_border_width = 2,
        popup_corner_radius = 4,
        popup_border_color = "0xffffffff",
        popup_bg_color = "0xff111111",
        popup_padding = 8,
      },
      font_small = "Inter:Regular:12.0",
      font_bold = "Inter:Bold:12.0",
      popup_item_height = 20,
      popup_header_height = 22,
      popup_item_corner_radius = 4,
      popup_padding = {
        icon_left = 4,
        icon_right = 6,
        label_left = 6,
        label_right = 6,
      },
      hover_script_cmd = nil,
      rendered = {},
      sections = {},
    },
    icon_for = function(_, fallback)
      return fallback or ""
    end,
  })

  local apple_menu_item = nil
  for _, entry in ipairs(added) do
    if entry.name == "apple_menu" then
      apple_menu_item = entry
      break
    end
  end

  assert_true(apple_menu_item ~= nil, "apple_menu should be added")
  assert_equal(apple_menu_item.props.click_script, "toggle:apple_menu", "apple_menu should still toggle on click")
  assert_true(apple_menu_item.props.script:find("/tmp/popup_anchor", 1, true) ~= nil, "apple_menu should use the popup anchor without hover-open env")
  assert_true(not apple_menu_item.props.script:find("POPUP_OPEN_ON_ENTER", 1, true), "apple_menu script should not enable hover-open")
  assert_equal(apple_menu_item.props.background.color, "0x18313a46", "apple_menu should use the shared idle chip background")
  assert_equal(apple_menu_item.props.background.drawing, true, "apple_menu should draw the shared anchor chip")
  assert_equal(subscribed[1], "apple_menu", "apple_menu should still subscribe to popup autoclose")
  assert_type(meta, "table", "setup should return metadata")
end)

run_test("apple_menu_enhanced: actionable popup rows get hover scripts by default", function()
  local added = {}

  apple_menu.setup({
    sbar = {
      add = function(kind, name, props)
        table.insert(added, { kind = kind, name = name, props = props })
      end,
    },
    theme = {
      WHITE = "0xffffffff",
      DARK_WHITE = "0xffcccccc",
      BG_SEC_COLR = "0xff111111",
      bar = { bg = "0xff000000" },
    },
    widget_height = 22,
    associated_displays = "all",
    popup_anchor_script = "/tmp/popup_anchor",
    popup_toggle_action = function()
      return "toggle:apple_menu"
    end,
    subscribe_popup_autoclose = function() end,
    attach_hover = function() end,
    apple_menu_prepared = {
      config_dir = "/tmp/config",
      style = {
        popup_border_width = 2,
        popup_corner_radius = 4,
        popup_border_color = "0xffffffff",
        popup_bg_color = "0xff111111",
        popup_padding = 8,
      },
      font_small = "Inter:Regular:12.0",
      font_bold = "Inter:Bold:12.0",
      popup_item_height = 20,
      popup_header_height = 22,
      popup_item_corner_radius = 4,
      popup_padding = {
        icon_left = 4,
        icon_right = 6,
        label_left = 6,
        label_right = 6,
      },
      hover_script_cmd = "/tmp/popup_hover",
      rendered = {
        {
          name = "apple_menu.apps.afs_browser",
          label = "AFS Browser",
          icon = "󰈙",
          section = "apps",
          action = "open /tmp/afs",
        },
      },
      sections = { apps = { id = "apps", label = "Apps" } },
    },
    icon_for = function(_, fallback)
      return fallback or ""
    end,
  })

  local afs_item = nil
  for _, entry in ipairs(added) do
    if entry.name == "apple_menu.apps.afs_browser" then
      afs_item = entry
      break
    end
  end

  assert_true(afs_item ~= nil, "AFS Browser row should be added")
  assert_equal(afs_item.props.script, "/tmp/popup_hover", "actionable popup rows should attach hover highlight by default")
end)

run_test("apple_menu_enhanced: missing rows keep explicit recovery actions", function()
  local added = {}

  apple_menu.setup({
    sbar = {
      add = function(kind, name, props)
        table.insert(added, { kind = kind, name = name, props = props })
      end,
    },
    theme = {
      WHITE = "0xffffffff",
      DARK_WHITE = "0xffcccccc",
      BG_SEC_COLR = "0xff111111",
      bar = { bg = "0xff000000" },
    },
    widget_height = 22,
    associated_displays = "all",
    popup_anchor_script = "/tmp/popup_anchor",
    popup_toggle_action = function()
      return "toggle:apple_menu"
    end,
    subscribe_popup_autoclose = function() end,
    attach_hover = function() end,
    apple_menu_prepared = {
      config_dir = "/tmp/config",
      style = {
        popup_border_width = 2,
        popup_corner_radius = 4,
        popup_border_color = "0xffffffff",
        popup_bg_color = "0xff111111",
        popup_padding = 8,
      },
      font_small = "Inter:Regular:12.0",
      font_bold = "Inter:Bold:12.0",
      popup_item_height = 20,
      popup_header_height = 22,
      popup_item_corner_radius = 4,
      popup_padding = {
        icon_left = 4,
        icon_right = 6,
        label_left = 6,
        label_right = 6,
      },
      hover_script_cmd = nil,
      rendered = {
        {
          name = "apple_menu.apps.build_afs_browser",
          label = "Build AFS Browser",
          icon = "󰈙",
          section = "apps",
          action = "osascript -e 'display notification \"Need rebuild\" with title \"Barista\"'; open /tmp/afs",
          missing = true,
        },
      },
      sections = { apps = { id = "apps", label = "Apps" } },
    },
    icon_for = function(_, fallback)
      return fallback or ""
    end,
  })

  local afs_item = nil
  for _, entry in ipairs(added) do
    if entry.name == "apple_menu.apps.build_afs_browser" then
      afs_item = entry
      break
    end
  end

  assert_true(afs_item ~= nil, "Build AFS Browser row should be added")
  assert_true((afs_item.props.click_script or ""):find("Need rebuild", 1, true) ~= nil, "missing rows with explicit actions should keep their recovery action")
end)

run_test("apple_menu_enhanced: AI Apps renders as one child whose actions close both levels", function()
  local added = {}
  local meta = apple_menu.setup({
    sbar = {
      add = function(kind, name, props)
        table.insert(added, { kind = kind, name = name, props = props })
      end,
    },
    theme = {
      WHITE = "0xffffffff",
      DARK_WHITE = "0xffcccccc",
      BG_SEC_COLR = "0xff111111",
      bar = { bg = "0xff000000" },
    },
    widget_height = 22,
    associated_displays = "all",
    SKETCHYBAR_BIN = "/custom/sketchybar",
    popup_anchor_script = "/tmp/popup_anchor",
    popup_toggle_action = function(item, opts)
      return string.format("%s:%s", tostring(opts and opts.origin), tostring(item))
    end,
    subscribe_popup_autoclose = function() end,
    attach_hover = function() end,
    apple_menu_prepared = {
      config_dir = "/tmp/config",
      menu_action = "/tmp/menu_action",
      style = {
        popup_border_width = 2,
        popup_corner_radius = 4,
        popup_border_color = "0xffffffff",
        popup_bg_color = "0xff111111",
        popup_padding = 8,
      },
      font_small = "Inter:Regular:12.0",
      font_bold = "Inter:Bold:12.0",
      popup_item_height = 20,
      popup_header_height = 22,
      popup_item_corner_radius = 4,
      popup_padding = {
        icon_left = 4,
        icon_right = 6,
        label_left = 6,
        label_right = 6,
      },
      hover_script_cmd = "/tmp/popup_hover",
      rendered = {
        {
          id = "ai_apps",
          name = "menu.tools.ai_apps",
          label = "AI Apps",
          icon = "󰚩",
          section = "apps",
          submenu = true,
          items = {
            { id = "lm_studio", name = "menu.tools.lm_studio", label = "LM Studio", action = "open-lm" },
            { id = "chatgpt", name = "menu.tools.chatgpt", label = "ChatGPT", action = "open \"/Applications/ChatGPT.app\"" },
            { id = "claude", name = "menu.tools.claude", label = "Claude", action = "open-claude" },
            { id = "cursor", name = "menu.tools.cursor", label = "Cursor", action = "open-cursor" },
          },
        },
      },
      sections = { apps = { id = "apps", label = "Apps" } },
    },
    icon_for = function(_, fallback)
      return fallback or ""
    end,
  })

  local by_name = {}
  for _, entry in ipairs(added) do
    by_name[entry.name] = entry.props
  end

  assert_equal(by_name["menu.tools.ai_apps"].position, "popup.apple_menu",
    "AI Apps entry point should remain on the Apple root")
  assert_equal(by_name["menu.tools.ai_apps"].popup.align, "right",
    "AI Apps should open as a right-aligned child")
  assert_equal(by_name["menu.tools.ai_apps"].click_script, "submenu:menu.tools.ai_apps",
    "AI Apps should use the managed submenu switch")
  for _, id in ipairs({ "lm_studio", "chatgpt", "claude", "cursor" }) do
    assert_equal(by_name["menu.tools." .. id].position, "popup.menu.tools.ai_apps",
      id .. " should materialize beneath AI Apps")
  end
  assert_true(by_name["menu.tools.chatgpt"].click_script:find(
    "/custom/sketchybar -m --set menu.tools.ai_apps popup.drawing=off --set apple_menu popup.drawing=off",
    1,
    true
  ) ~= nil, "AI child actions should close the child and Apple root in one batch")
  assert_true(by_name["menu.tools.chatgpt"].click_script:find(
    "MENU_ACTION_CMD='open \"/Applications/ChatGPT.app\"' /tmp/menu_action menu.tools.chatgpt ''",
    1,
    true
  ) ~= nil, "menu actions should use query-safe POSIX quoting before the batched close")
  assert_true(not by_name["menu.tools.chatgpt"].click_script:find('\\"', 1, true),
    "menu action scripts should not store backslash-escaped quotes")
  assert_equal(by_name["menu.tools.chatgpt"].script, "/tmp/popup_hover",
    "AI child actions should retain hover treatment")
  assert_equal(table.concat(meta.submenu_parents or {}, "|"), "menu.tools.ai_apps",
    "AI Apps should register exactly one child popup")
  assert_equal(table.concat(meta.popup_parents or {}, "|"), "apple_menu",
    "AI Apps should never register as another root popup")
end)

run_test("apple_menu_enhanced: nested submenu metadata preserves every ancestor", function()
  local added = {}
  local meta = apple_menu.setup({
    sbar = {
      add = function(kind, name, props)
        table.insert(added, { kind = kind, name = name, props = props })
      end,
    },
    theme = {
      WHITE = "0xffffffff",
      DARK_WHITE = "0xffcccccc",
      BG_SEC_COLR = "0xff111111",
      bar = { bg = "0xff000000" },
    },
    widget_height = 22,
    associated_displays = "all",
    SKETCHYBAR_BIN = "/custom/sketchybar",
    popup_anchor_script = "/tmp/popup_anchor",
    popup_toggle_action = function(item, opts)
      return string.format("%s:%s", tostring(opts and opts.origin), tostring(item))
    end,
    subscribe_popup_autoclose = function() end,
    attach_hover = function() end,
    apple_menu_prepared = {
      config_dir = "/tmp/config",
      menu_action = "/tmp/menu_action",
      style = {
        popup_border_width = 2,
        popup_corner_radius = 4,
        popup_border_color = "0xffffffff",
        popup_bg_color = "0xff111111",
        popup_padding = 8,
      },
      font_small = "Inter:Regular:12.0",
      font_bold = "Inter:Bold:12.0",
      popup_item_height = 20,
      popup_header_height = 22,
      popup_item_corner_radius = 4,
      popup_padding = {
        icon_left = 4,
        icon_right = 6,
        label_left = 6,
        label_right = 6,
      },
      rendered = {
        {
          name = "menu.level1",
          label = "Level 1",
          section = "tools",
          submenu = true,
          items = {
            {
              name = "menu.level2",
              label = "Level 2",
              submenu = true,
              items = {
                {
                  name = "menu.level3",
                  label = "Level 3",
                  submenu = true,
                  items = {
                    { name = "menu.leaf", label = "Leaf", action = "echo leaf" },
                  },
                },
              },
            },
          },
        },
      },
      sections = { tools = { id = "tools", label = "Tools" } },
    },
    icon_for = function(_, fallback)
      return fallback or ""
    end,
  })

  assert_equal(
    table.concat(meta.submenu_ancestors["menu.level3"] or {}, "|"),
    "menu.level1|menu.level2",
    "deep submenu should preserve its complete ancestor chain"
  )
  local roots = {}
  for _, name in ipairs(meta.popup_parents or {}) do
    roots[name] = true
  end
  assert_true(roots.apple_menu == true, "Apple anchor should remain a root popup")
  assert_true(not roots["menu.level1"] and not roots["menu.level2"] and not roots["menu.level3"],
    "nested Apple fly-outs should be children only, not duplicate roots")

  local leaf = nil
  for _, entry in ipairs(added) do
    if entry.name == "menu.leaf" then
      leaf = entry.props
      break
    end
  end
  assert_true(leaf ~= nil, "deep nested leaf should render")
  assert_true(leaf.click_script:find(
    "/custom/sketchybar -m --set menu.level3 popup.drawing=off --set menu.level2 popup.drawing=off --set menu.level1 popup.drawing=off --set apple_menu popup.drawing=off",
    1,
    true
  ) ~= nil, "deep actions should close every containing Apple popup")
end)
