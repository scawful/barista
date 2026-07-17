local oracle = require("oracle")

local function command_ok(result)
  return result == true or result == 0
end

local function make_fixture_root()
  local tmpdir = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")
  local template = string.format("%s/barista_oracle_integration.XXXXXX", tmpdir)
  local handle = io.popen("mktemp -d " .. string.format("%q", template))
  assert_true(handle ~= nil, "run mktemp")
  local root = handle:read("*l")
  local ok = handle:close()
  assert_true(command_ok(ok) and root and root ~= "", "fixture root should be created")
  return root
end

local function build_ctx(overrides)
  overrides = overrides or {}
  local ctx = {
    CONFIG_DIR = "/tmp/config",
    state = {
      appearance = {
        menu_item_height = 23,
      },
      menus = {
        oracle = {
          triforce = {
            title = "Zelda Hacking",
            show_label = false,
          },
          sections = {
            play = { enabled = true },
          },
        },
      },
    },
    appearance = {
      menu_item_height = 23,
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
      YELLOW = "0xfff9e2af",
      SKY = "0xff89dceb",
      PEACH = "0xfffab387",
      MAUVE = "0xffcba6f7",
      MAGENTA = "0xffcba6f7",
      SAPPHIRE = "0xff74c7ec",
      DARK_WHITE = "0xffbac2de",
      BG_SEC_COLR = "0xff1e1e2e",
      bar = { bg = "0xff11111b" },
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
          command = "./Scripts/Build/oos-session.sh maku --crystals 0",
        },
        today = {
          {
            title = "Maku 1",
            action = "session-maku-1",
            command = "./Scripts/Build/oos-session.sh maku --crystals 1",
          },
        },
        next = {
          {
            title = "Maku 3 / 5 / 7",
            action = "session-maku-3",
            command = "./Scripts/Build/oos-session.sh maku --crystals 3",
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
        quick = "./Scripts/Build/oos-quick.sh 168",
        verify = "./Scripts/Build/oos-verify.sh 168",
        sessions = {
          maku0 = "./Scripts/Build/oos-session.sh maku --crystals 0",
          maku3 = "./Scripts/Build/oos-session.sh maku --crystals 3",
          d6 = "./Scripts/Build/oos-session.sh d6",
          menu = "./Scripts/Build/oos-session.sh menu",
        },
      },
    },
  }

  for key, value in pairs(overrides) do
    ctx[key] = value
  end

  if type(overrides.state) == "table" then
    ctx.state = overrides.state
  end
  if overrides.appearance == nil then
    ctx.appearance = ctx.state and ctx.state.appearance or ctx.appearance
  end

  return ctx
end

run_test("oracle integration: shared model respects section visibility overrides", function()
  local model = oracle.build_menu_model(build_ctx())
  local by_id = {}
  for _, section in ipairs(model.sections) do
    by_id[section.id] = section
  end

  assert_equal(model.title, "Zelda Hacking", "menu title should follow the broader Zelda hub")
  assert_true(by_id.play ~= nil, "play section should exist")
  assert_true(by_id.apps ~= nil, "apps section should exist")
  assert_equal(#model.sections, 2, "triforce should stay shallow but include session and launcher sections")
end)

run_test("oracle integration: triforce widget uses runtime overrides", function()
  local widget = oracle.create_triforce_widget({ ctx = build_ctx() })
  assert_true(widget ~= nil, "widget should be created")
  assert_equal(widget.icon.string, "󰯙", "widget should use the current triforce glyph")
  assert_equal(widget.label.drawing, false, "widget should default to icon-only")
  assert_nil(widget.update_freq, "triforce should not install a polling timer")
  assert_true(widget.script:match("/tmp/config/plugins/oracle_triforce%.sh") ~= nil, "widget should route anchor behavior through oracle_triforce.sh")
  assert_true(widget.click_script:match("popup%.drawing=toggle") ~= nil, "clicks should use a direct popup toggle")
  local toggle_at = widget.click_script:find("popup.drawing=toggle", 1, true)
  local refresh_at = widget.click_script:find("SENDER=popup_refresh", 1, true)
  assert_true(toggle_at ~= nil and refresh_at ~= nil and toggle_at < refresh_at, "clicks should toggle before starting async status refresh")
  assert_true(widget.click_script:find(">/dev/null 2>&1 &", 1, true) ~= nil, "status refresh should run in the background")
  assert_true(widget.click_script:match("BARISTA_TRIFORCE_ACTION=click") == nil, "clicks should not route toggle ownership through the controller")
end)

run_test("oracle integration: dynamic rows exist before the first status refresh", function()
  local items = oracle.create_triforce_popup_items(build_ctx({
    oracle_status_snapshot = {},
  }))
  local by_name = {}
  for _, item in ipairs(items) do
    by_name[item.name] = item
  end

  local focus = by_name["oracle.triforce.focus"]
  local continue = by_name["oracle.triforce.play.continue"]
  assert_true(focus ~= nil, "focus row should have a stable refresh target")
  assert_equal(focus.drawing, false, "unknown focus should start hidden")
  assert_equal(continue.label, "Continue Session", "unknown focus should use the stable fallback label")
  assert_true(continue.click_script:find("./Scripts/Build/oos-triforce.sh continue-play", 1, true) ~= nil, "continue action should resolve the current focus at click time")
end)

run_test("oracle integration: configured anchor label is passed to refresh", function()
  local ctx = build_ctx()
  ctx.state.menus.oracle.triforce.label = "Zelda $(echo unsafe)"
  ctx.state.menus.oracle.triforce.show_label = true
  local widget = oracle.create_triforce_widget({ ctx = ctx })

  assert_equal(widget.label.string, "Zelda $(echo unsafe)", "configured label should render before refresh")
  assert_equal(widget.label.drawing, true, "configured label should honor show_label")
  assert_true(widget.click_script:find("BARISTA_TRIFORCE_LABEL_OVERRIDE='Zelda $(echo unsafe)'", 1, true) ~= nil, "async refresh should preserve and quote the configured label")
end)

run_test("oracle integration: triforce popup uses apple-style sections and Oracle launchers", function()
  local root = make_fixture_root()
  local ghostty_app = root .. "/Ghostty.app"
  local yaze_app = root .. "/yaze.app"
  local z3ed = root .. "/z3ed"
  local mesen_run = root .. "/mesen-run"
  assert_true(command_ok(os.execute(string.format("mkdir -p %q", ghostty_app))), "ghostty fixture should be created")
  assert_true(command_ok(os.execute(string.format("mkdir -p %q", yaze_app))), "yaze fixture should be created")
  local z3ed_file = io.open(z3ed, "w")
  assert_true(z3ed_file ~= nil, "z3ed fixture should be writable")
  z3ed_file:write("#!/bin/sh\nexit 0\n")
  z3ed_file:close()
  assert_true(command_ok(os.execute(string.format("chmod +x %q", z3ed))), "z3ed fixture should be executable")
  local mesen_file = io.open(mesen_run, "w")
  assert_true(mesen_file ~= nil, "mesen fixture should be writable")
  mesen_file:write("#!/bin/sh\nexit 0\n")
  mesen_file:close()
  assert_true(command_ok(os.execute(string.format("chmod +x %q", mesen_run))), "mesen fixture should be executable")

  local items = oracle.create_triforce_popup_items(build_ctx({
    paths = {
      ghostty_app = ghostty_app,
      yaze_app = yaze_app,
      z3ed = z3ed,
      mesen_run = mesen_run,
    },
  }))
  local by_name = {}
  for _, item in ipairs(items) do
    by_name[item.name] = item
  end

  assert_true(by_name["oracle.triforce.rom"] ~= nil, "rom row should exist")
  assert_equal(by_name["oracle.triforce.rom"].label, "ROM: oos168x.sfc", "rom row should surface the detected ROM version")
  assert_true(by_name["oracle.triforce.focus"] ~= nil, "focus status row should exist")
  assert_equal(by_name["oracle.triforce.focus"].label, "Focus: Maku Tree at 0 crystals", "focus row should surface the current play focus without adding docs/tests")
  assert_true(by_name["oracle.triforce.play.header"] ~= nil, "session section header should exist")
  assert_equal(by_name["oracle.triforce.play.header"].label, "Oracle Session", "session section header should use the configured section label")
  assert_true(by_name["oracle.triforce.apps.header"] ~= nil, "apps section header should exist")
  assert_equal(by_name["oracle.triforce.apps.header"].label, "Apps", "apps section header should use the apple-style section label")
  assert_true(by_name["oracle.triforce.meta.sep"] ~= nil, "metadata separator should exist")
  assert_true(by_name["oracle.triforce.sep.apps"] ~= nil, "section separator should exist")
  assert_true(by_name["oracle.triforce.play.header"].background.drawing == true, "section headers should draw a background like the apple menu")
  assert_equal(by_name["oracle.triforce.play.header"].background.height, 25, "section header height should follow menu_style")
  assert_equal(by_name["oracle.triforce.play.continue"].background.height, 23, "action rows should use menu item height")
  assert_true(by_name["oracle.triforce.play.continue"] ~= nil, "continue row should exist")
  assert_equal(by_name["oracle.triforce.play.continue"].label, "Continue: Maku Tree at 0 crystals", "continue row should use the richer focus title")
  assert_true(by_name["oracle.triforce.play.continue"].click_script:find("./Scripts/Build/oos-triforce.sh continue-play", 1, true) ~= nil, "continue row should not retain a stale reload-time focus command")
  assert_true(by_name["oracle.triforce.play.continue"].hover == true, "popup actions should opt into hover treatment")
  assert_true(by_name["oracle.triforce.play.continue"].click_script:find("popup%.drawing=off", 1, false) ~= nil, "popup actions should close the triforce popup after firing")
  assert_true(by_name["oracle.triforce.play.patch_continue"] ~= nil, "patch + continue row should exist")
  assert_nil(by_name["oracle.triforce.play.verify"], "verify row should not be in the shallow popup")
  assert_true(by_name["oracle.triforce.apps.oracle_hub"] ~= nil, "oracle hub row should exist in the apps section")
  assert_equal(by_name["oracle.triforce.apps.oracle_hub"].label, "Oracle Hub", "oracle hub row should use the app label")
  assert_equal(by_name["oracle.triforce.apps.oracle_hub"].icon.color, "0xffcba6f7", "oracle hub row should keep the apple-menu icon color")
  assert_true(by_name["oracle.triforce.apps.yaze"] ~= nil, "yaze row should exist in the apps section")
  assert_equal(by_name["oracle.triforce.apps.yaze"].label, "Yaze", "yaze row should use the app label")
  assert_equal(by_name["oracle.triforce.apps.yaze"].icon.color, "0xfff9e2af", "yaze row should keep the apple-menu icon color")
  assert_true(by_name["oracle.triforce.apps.z3ed"] ~= nil, "z3ed row should exist in the apps section")
  assert_equal(by_name["oracle.triforce.apps.z3ed"].label, "z3ed", "z3ed row should use the CLI label")
  assert_equal(by_name["oracle.triforce.apps.z3ed"].icon.color, "0xff89dceb", "z3ed row should use the Ghostty/CLI accent color")
  assert_true(by_name["oracle.triforce.apps.z3ed"].click_script:find("Ghostty%.app", 1, false) ~= nil, "z3ed row should launch via Ghostty")
  assert_true(by_name["oracle.triforce.apps.z3ed"].click_script:find("z3ed", 1, true) ~= nil, "z3ed row should invoke z3ed")
  assert_true(by_name["oracle.triforce.apps.z3ed"].click_script:find("mkdir", 1, true) ~= nil, "z3ed row should debounce Ghostty launch")
  assert_true(by_name["oracle.triforce.apps.z3ed"].click_script:find("bash %-lc '", 1, false) ~= nil, "z3ed row should pass a literal bash payload")
  assert_true(by_name["oracle.triforce.apps.z3ed"].click_script:find("%$lock_dir", 1, false) ~= nil, "z3ed row should preserve lock_dir for bash")
  assert_true(by_name["oracle.triforce.apps.mesen_oos"] ~= nil, "mesen row should exist in the apps section")
  assert_equal(by_name["oracle.triforce.apps.mesen_oos"].label, "Mesen2 OoS", "mesen row should use the app label")
  assert_equal(by_name["oracle.triforce.apps.mesen_oos"].icon.color, "0xfff38ba8", "mesen row should keep the apple-menu icon color")
  assert_true(by_name["oracle.triforce.apps.yaze"].hover == true, "launcher rows should use apple-style hover behavior")
  assert_nil(by_name["oracle.triforce.tools"], "tools submenu should be gone")
  assert_nil(by_name["oracle.triforce.queue"], "queue submenu should be gone")
  assert_nil(by_name["oracle.triforce.sessions"], "sessions submenu should be gone")
end)
