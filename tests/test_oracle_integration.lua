local oracle = require("oracle")

local function build_ctx()
  return {
    CONFIG_DIR = "/tmp/config",
    state = {
      appearance = {
        menu_item_height = 23,
      },
      menus = {
        oracle = {
          triforce = {
            title = "Zelda Hacking",
            update_freq = 30,
            show_label = false,
          },
          sections = {
            play = { enabled = true },
          },
        },
      },
    },
    settings = {
      font = {
        text = "Source Code Pro",
        style_map = { Semibold = "Semibold", Bold = "Bold" },
        sizes = { small = 12 },
      },
    },
    theme = {
      WHITE = "0xffffffff",
      GREEN = "0xffa6e3a1",
      TEAL = "0xff94e2d5",
      LAVENDER = "0xffb4befe",
      RED = "0xfff38ba8",
      SKY = "0xff89dceb",
      PEACH = "0xfffab387",
      MAUVE = "0xffcba6f7",
      SAPPHIRE = "0xff74c7ec",
    },
    scripts = {
      runtime_update = "/tmp/runtime_update.sh",
      set_appearance = "/tmp/set_appearance.sh",
      oracle_layout = "/tmp/oracle_layout.sh",
      open_control_panel = "/tmp/open_control_panel.sh",
      open_oracle_agent_manager = "/tmp/open_oracle_agent_manager.sh",
      yabai_control = "/tmp/yabai_control.sh",
    },
    call_script = function(path, ...)
      local parts = { path }
      for _, arg in ipairs({ ... }) do
        table.insert(parts, tostring(arg))
      end
      return table.concat(parts, " ")
    end,
    open_path = function(path)
      return "open " .. path
    end,
    icon_for = function(_, fallback)
      return fallback
    end,
    font_string = function(family, style, size)
      return string.format("%s:%s:%s", family, style, tostring(size))
    end,
    oracle_status_snapshot = {
      finish_line = {
        status_line = "Maku 0 • dirty",
        alerts_level = "warn",
        focus = {
          title = "Play Maku Tree at 0 crystals",
          label = "Maku 0",
          detail = "Verify message and icon state.",
          command = "./scripts/oos-session.sh maku --crystals 0",
        },
        today = {
          {
            title = "Maku 1",
            action = "session-maku-1",
            command = "./scripts/oos-session.sh maku --crystals 1",
          },
        },
        next = {
          {
            title = "Maku 3 / 5 / 7",
            action = "session-maku-3",
            command = "./scripts/oos-session.sh maku --crystals 3",
          },
        },
        blocked = {
          {
            title = "APU deadlock",
            action = "open-handoff",
          },
        },
      },
      commands = {
        quick = "./scripts/oos-quick.sh 168",
        verify = "./scripts/oos-verify.sh 168",
        sessions = {
          maku0 = "./scripts/oos-session.sh maku --crystals 0",
          maku3 = "./scripts/oos-session.sh maku --crystals 3",
          d6 = "./scripts/oos-session.sh d6",
          menu = "./scripts/oos-session.sh menu",
        },
      },
    },
  }
end

run_test("oracle integration: shared model respects section visibility overrides", function()
  local model = oracle.build_menu_model(build_ctx())
  local by_id = {}
  for _, section in ipairs(model.sections) do
    by_id[section.id] = section
  end

  assert_equal(model.title, "Zelda Hacking", "menu title should follow the broader Zelda hub")
  assert_true(by_id.play ~= nil, "play section should exist")
  assert_equal(#model.sections, 1, "triforce should stay a shallow launcher")
end)

run_test("oracle integration: triforce widget uses runtime overrides", function()
  local widget = oracle.create_triforce_widget({ ctx = build_ctx() })
  assert_true(widget ~= nil, "widget should be created")
  assert_equal(widget.icon.string, "󰯙", "widget should use the current triforce glyph")
  assert_equal(widget.label.drawing, false, "widget should default to icon-only")
  assert_equal(widget.update_freq, 30, "widget update frequency override should win")
  assert_true(widget.script:match("/tmp/config/plugins/oracle_triforce%.sh") ~= nil, "widget should route anchor behavior through oracle_triforce.sh")
  assert_true(widget.click_script:match("BARISTA_TRIFORCE_ACTION=click") ~= nil, "clicks should use the unified triforce controller")
end)

run_test("oracle integration: triforce popup stays shallow and exposes launch actions", function()
  local items = oracle.create_triforce_popup_items(build_ctx())
  local by_name = {}
  for _, item in ipairs(items) do
    by_name[item.name] = item
  end

  assert_true(by_name["oracle.triforce.rom"] ~= nil, "rom row should exist")
  assert_equal(by_name["oracle.triforce.rom"].label, "ROM: oos168x.sfc", "rom row should surface the detected ROM version")
  assert_true(by_name["oracle.triforce.play.continue"] ~= nil, "continue row should exist")
  assert_equal(by_name["oracle.triforce.play.continue"].label, "Continue: Maku Tree at 0 crystals", "continue row should use the richer focus title")
  assert_true(by_name["oracle.triforce.play.continue"].hover == true, "popup actions should opt into hover treatment")
  assert_true(by_name["oracle.triforce.play.continue"].click_script:find("popup%.drawing=off", 1, false) ~= nil, "popup actions should close the triforce popup after firing")
  assert_true(by_name["oracle.triforce.play.patch_continue"] ~= nil, "patch + continue row should exist")
  assert_nil(by_name["oracle.triforce.play.verify"], "verify row should not be in the shallow popup")
  assert_true(by_name["oracle.triforce.play.panel"] ~= nil, "oracle hub row should exist")
  assert_equal(by_name["oracle.triforce.play.panel"].label, "Open Oracle Hub", "panel row should use the broader hub label")
  assert_nil(by_name["oracle.triforce.play.header"], "single-section popup should not render an extra section subtitle")
  assert_nil(by_name["oracle.triforce.tools"], "tools submenu should be gone")
  assert_nil(by_name["oracle.triforce.queue"], "queue submenu should be gone")
  assert_nil(by_name["oracle.triforce.sessions"], "sessions submenu should be gone")
end)
