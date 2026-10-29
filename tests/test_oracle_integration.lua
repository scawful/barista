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
  local root = make_fixture_root()
  local mesen_run = root .. "/mesen-run"
  local mesen_file = io.open(mesen_run, "w")
  assert_true(mesen_file ~= nil, "mesen fixture should be writable")
  mesen_file:write("#!/bin/sh\nexit 0\n")
  mesen_file:close()
  assert_true(command_ok(os.execute(string.format("chmod +x %q", mesen_run))), "mesen fixture should be executable")

  local model = oracle.build_menu_model(build_ctx({ paths = { mesen_run = mesen_run } }))
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

local function dev_row_label(root)
  local saved_repo = oracle.config.repo_path
  oracle.config.repo_path = root
  local ok, result = pcall(function()
    local items = oracle.create_triforce_popup_items(build_ctx({
      oracle_status_snapshot = {},
    }))
    local by_name = {}
    for _, item in ipairs(items) do
      by_name[item.name] = item
    end
    assert_nil(by_name["oracle.triforce.play.launch_stable"], "the stale stable row should be gone")
    assert_nil(by_name["oracle.triforce.focus"], "focus row should be gone")
    assert_nil(by_name["oracle.triforce.rom"], "ROM row should be gone")
    local dev = by_name["oracle.triforce.play.launch_test"]
    assert_true(dev ~= nil, "dev row should exist before any status refresh")
    return dev.label
  end)
  oracle.config.repo_path = saved_repo
  assert_true(ok, tostring(result))
  return result
end

run_test("oracle integration: dev row names the newest Roms/TestBuilds build", function()
  local root = make_fixture_root()
  local fixtures = {
    { "old-fix-2026-09-01", "oos168x.sfc", "202609010000" },
    { "kydreeok-pr209-2026-10-19", "oos168x.sfc", "202610190000" },
    { "notes-only", "random.sfc", "202610200000" }, -- not oos*x.sfc: the launcher skips it
  }
  for _, fixture in ipairs(fixtures) do
    local dir = root .. "/Roms/TestBuilds/" .. fixture[1]
    assert_true(command_ok(os.execute(string.format("mkdir -p %q", dir))), "TestBuilds fixture should be created")
    assert_true(command_ok(os.execute(string.format("touch -t %s %q", fixture[3], dir .. "/" .. fixture[2]))), "ROM fixture should be created")
  end
  assert_equal(dev_row_label(root), "Dev kydreeok-pr209", "dev row should name the newest oos*x.sfc folder without its date")
end)

run_test("oracle integration: dev row falls back without test builds", function()
  local root = make_fixture_root()
  assert_true(command_ok(os.execute(string.format("mkdir -p %q", root .. "/Roms"))), "Roms fixture should be created")
  assert_equal(dev_row_label(root), "Dev build", "dev row should keep a generic label")
end)

run_test("oracle integration: Ganondorf row uses its configured private launcher", function()
  local root = make_fixture_root()
  local launcher = root .. "/Play Ganondorf's $(literal).command"
  local file = assert(io.open(launcher, "w"))
  file:write("#!/bin/sh\nexit 0\n")
  file:close()
  local quoted_launcher = "'" .. launcher:gsub("'", "'\"'\"'") .. "'"
  assert_true(command_ok(os.execute("chmod +x " .. quoted_launcher)), "packet launcher should be executable")
  local saved = oracle.config.ganondorf_launcher
  oracle.config.ganondorf_launcher = launcher
  local ok, result = pcall(function()
    local items = oracle.create_triforce_popup_items(build_ctx())
    local row
    for _, item in ipairs(items) do
      if item.name == "oracle.triforce.play.launch_ganondorf" then row = item end
    end
    assert_true(row ~= nil, "configured executable packet should add the Ganondorf row")
    assert_equal(row.label, "Ganondorf test", "row should name the fight")
    assert_true(row.click_script:find("launch_ganondorf", 1, true) ~= nil, "row should use the private packet action")
    assert_true(row.click_script:find("BARISTA_GANONDORF_LAUNCHER", 1, true) ~= nil, "row should forward its launcher path")
    assert_true(row.click_script:find("/tmp/oos-launch-ganondorf.log", 1, true) ~= nil, "launch should have a dedicated log")
    assert_true(row.click_script:find("popup.drawing=off", 1, true) ~= nil, "launch should close the popup")
    assert_true(row.click_script:find("oos_play.py", 1, true) == nil, "private packet should stay separate from the Play window")
  end)
  oracle.config.ganondorf_launcher = saved
  assert_true(ok, tostring(result))
end)

run_test("oracle integration: missing Ganondorf packet omits the optional row", function()
  local saved = oracle.config.ganondorf_launcher
  oracle.config.ganondorf_launcher = "/missing/Play Ganondorf.command"
  local ok, result = pcall(function()
    for _, item in ipairs(oracle.create_triforce_popup_items(build_ctx())) do
      assert_true(item.name ~= "oracle.triforce.play.launch_ganondorf", "missing packet should not create a dead menu action")
    end
  end)
  oracle.config.ganondorf_launcher = saved
  assert_true(ok, tostring(result))
end)

run_test("oracle integration: play window rows run oos_play.py", function()
  local items = oracle.create_triforce_popup_items(build_ctx({
    oracle_status_snapshot = {},
  }))
  local by_name = {}
  for _, item in ipairs(items) do
    by_name[item.name] = item
  end

  local status = by_name["oracle.triforce.play.play_status"]
  local latest = by_name["oracle.triforce.play.play_latest"]
  local now = by_name["oracle.triforce.play.play_now"]
  assert_true(status ~= nil and latest ~= nil and now ~= nil, "play window rows should exist")
  assert_equal(status.label, "—", "status row starts with a placeholder until refresh")
  assert_equal(latest.label, "Play", "play row label stays short")
  assert_equal(now.label, "Load now", "load row label stays short")
  local latest_click = latest.click_script or ""
  local now_click = now.click_script or ""
  assert_true(latest_click:find("oos_play.py", 1, true) ~= nil, "Play latest should run oos_play.py")
  assert_true(latest_click:find("--now", 1, true) == nil, "Play latest should offer, not force-load")
  assert_true(now_click:find("oos_play.py --now", 1, true) ~= nil, "Load latest now should pass --now")
  assert_true(latest_click:find("/tmp/oos-play.log", 1, true) ~= nil, "play rows should log to /tmp/oos-play.log")
  assert_true(by_name["oracle.triforce.play.launch_test"] ~= nil, "the dev row should stay next to the play rows")
end)

run_test("oracle integration: mesen row falls back to mesen-run without the app", function()
  local root = make_fixture_root()
  local mesen_run = root .. "/mesen-run"
  local mesen_file = io.open(mesen_run, "w")
  assert_true(mesen_file ~= nil, "mesen fixture should be writable")
  mesen_file:write("#!/bin/sh\nexit 0\n")
  mesen_file:close()
  assert_true(command_ok(os.execute(string.format("chmod +x %q", mesen_run))), "mesen fixture should be executable")

  local model = oracle.build_menu_model(build_ctx({
    paths = { mesen_run = mesen_run, mesen_app = root .. "/missing/Mesen2 OOS.app" },
  }))
  assert_equal(model.state.mesen_action, string.format("%q", mesen_run), "mesen row should run mesen-run when the app is missing")
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

run_test("oracle integration: guarded project launcher does not need a global Yaze app", function()
  local root = make_fixture_root()
  local launcher = root .. "/Open Oracle.command"
  local file = assert(io.open(launcher, "w"))
  file:write("#!/bin/sh\nexit 0\n")
  file:close()
  assert_true(command_ok(os.execute(string.format("chmod +x %q", launcher))), "launcher fixture executable")
  local locator = require("tool_locator")
  local resolve = locator.resolve_yaze_app
  locator.resolve_yaze_app = function() return nil, false end
  local ok, items = pcall(oracle.create_triforce_popup_items, build_ctx({
    paths = { oracle_project_launcher = launcher },
  }))
  locator.resolve_yaze_app = resolve
  assert_true(ok, "project model should build without global Yaze")
  local project
  for _, item in ipairs(items) do
    if item.name == "oracle.triforce.apps.lyra_project" then project = item end
  end
  assert_true(project ~= nil, "guarded project row should exist")
  assert_equal(project.label, "Edit Oracle Project", "unified project label")
  assert_true(project.click_script:find("('" .. launcher .. "' >/tmp/oos-open-oracle.log 2>&1 &)", 1, true) ~= nil, "quoted launcher should run asynchronously")
  assert_nil(project.click_script:find("open -n", 1, true), "no global app invocation")
  assert_nil(project.click_script:find("--rom_file=", 1, true), "launcher owns project selection")
  assert_nil(project.click_script:find("--editor=", 1, true), "launcher owns startup editor")
  assert_true(project.click_script:find("popup.drawing=off", 1, true) ~= nil, "popup should close after dispatch")
end)

run_test("oracle integration: configured bad project launcher never falls back", function()
  local root = make_fixture_root()
  local global_app = root .. "/yaze.app"
  assert_true(command_ok(os.execute(string.format("mkdir -p %q", global_app))), "global app fixture")
  local project = root .. "/working.yaze"
  local descriptor = assert(io.open(project, "w"))
  descriptor:write("[project]\n")
  descriptor:close()
  local plain = root .. "/not-executable.command"
  local file = assert(io.open(plain, "w"))
  file:write("not executable\n")
  file:close()
  for _, launcher in ipairs({ root .. "/missing.command", plain, false, true }) do
    local items = oracle.create_triforce_popup_items(build_ctx({
      paths = { oracle_project_launcher = launcher, lyra_project = project, yaze_app = global_app },
    }))
    for _, item in ipairs(items) do
      assert_true(item.name ~= "oracle.triforce.apps.lyra_project", "bad configured launcher must not select the legacy project")
    end
  end
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

  local mesen_app = root .. "/Mesen2 OOS.app"
  assert_true(command_ok(os.execute(string.format("mkdir -p %q", mesen_app))), "mesen app fixture should be created")
  local lyra_project = root .. "/Oracle-of-Secrets-Working.yaze"
  local lyra_file = io.open(lyra_project, "w")
  assert_true(lyra_file ~= nil, "lyra project fixture should be writable")
  lyra_file:write("[project]\n")
  lyra_file:close()

  local items = oracle.create_triforce_popup_items(build_ctx({
    paths = {
      ghostty_app = ghostty_app,
      yaze_app = yaze_app,
      lyra_project = lyra_project,
      oracle_project_launcher = "",
      z3ed = z3ed,
      mesen_run = mesen_run,
      mesen_app = mesen_app,
    },
  }))
  local by_name = {}
  for _, item in ipairs(items) do
    by_name[item.name] = item
  end

  assert_nil(by_name["oracle.triforce.rom"], "ROM row should be gone")
  assert_nil(by_name["oracle.triforce.focus"], "focus row should be gone")
  assert_true(by_name["oracle.triforce.play.header"] ~= nil, "play section header should exist")
  assert_equal(by_name["oracle.triforce.play.header"].label, "Play", "play section header should use the default section label")
  assert_true(by_name["oracle.triforce.apps.header"] ~= nil, "apps section header should exist")
  assert_equal(by_name["oracle.triforce.apps.header"].label, "Apps", "apps section header should use the apple-style section label")
  assert_true(by_name["oracle.triforce.meta.sep"] ~= nil, "metadata separator should exist")
  assert_true(by_name["oracle.triforce.sep.apps"] ~= nil, "section separator should exist")
  assert_true(by_name["oracle.triforce.play.header"].background.drawing == true, "section headers should draw a line like the apple menu")
  assert_equal(by_name["oracle.triforce.play.header"].background.height, 1, "section header line should be a hairline")
  local test = by_name["oracle.triforce.play.launch_test"]
  assert_nil(by_name["oracle.triforce.play.launch_stable"], "stale stable launch row should be gone")
  assert_true(test ~= nil, "dev launch row should exist")
  assert_equal(test.background.height, 23, "action rows should use menu item height")
  assert_true(test.label:find("^Dev ") ~= nil, "dev launch row should be marked Dev")
  assert_true(test.click_script:find("./Scripts/Build/oos-triforce.sh launch test", 1, true) ~= nil, "dev row should launch the newest test build")
  assert_true(test.click_script:find(">/tmp/oos-launch-test.log 2>&1 &", 1, true) ~= nil, "dev launch should run in the background with a log")
  assert_true(test.hover == true, "popup actions should opt into hover treatment")
  assert_true(test.click_script:find("popup%.drawing=off", 1, false) ~= nil, "popup actions should close the triforce popup after firing")
  assert_nil(by_name["oracle.triforce.play.continue"], "continue row should be gone")
  assert_nil(by_name["oracle.triforce.play.patch_continue"], "patch + launch row should be gone")
  assert_nil(by_name["oracle.triforce.play.verify"], "verify row should not be in the shallow popup")
  assert_nil(by_name["oracle.triforce.apps.oracle_hub"], "Oracle Hub launcher should be gone")
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
  assert_true(by_name["oracle.triforce.apps.mesen_oos"].click_script:find("open \"" .. mesen_app .. "\"", 1, true) ~= nil, "mesen row should open the app bundle the launcher uses")
  assert_true(by_name["oracle.triforce.apps.yaze"].hover == true, "launcher rows should use apple-style hover behavior")
  local lyra = by_name["oracle.triforce.apps.lyra_project"]
  assert_true(lyra ~= nil, "Edit Lyra Sea row should exist in the apps section")
  assert_equal(lyra.label, "Edit Lyra Sea", "lyra row should use its label")
  assert_true(lyra.click_script:find("open -n -a \"" .. yaze_app .. "\"", 1, true) ~= nil, "lyra row should open the resolved yaze app")
  assert_true(lyra.click_script:find("--rom_file=\"" .. lyra_project .. "\"", 1, true) ~= nil, "lyra row should pass the working project")
  assert_true(lyra.click_script:find("--editor=Overworld --map=160", 1, true) ~= nil, "lyra row should open the first Lyra Sea map")
  assert_nil(by_name["oracle.triforce.tools"], "tools submenu should be gone")
  assert_nil(by_name["oracle.triforce.queue"], "queue submenu should be gone")
  assert_nil(by_name["oracle.triforce.sessions"], "sessions submenu should be gone")
end)
