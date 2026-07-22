local music = require("music")

local function command_ok(result)
  return result == true or result == 0
end

local function make_fixture_root()
  local tmpdir = (os.getenv("TMPDIR") or "/tmp"):gsub("/$", "")
  local template = string.format("%s/barista_music_integration.XXXXXX", tmpdir)
  local handle = io.popen("mktemp -d " .. string.format("%q", template))
  assert_true(handle ~= nil, "run mktemp")
  local root = handle:read("*l")
  local ok = handle:close()
  assert_true(command_ok(ok) and root and root ~= "", "fixture root should be created")
  return root
end

local function mkdir(path)
  assert_true(command_ok(os.execute(string.format("mkdir -p %q", path))), "mkdir " .. path)
end

local function build_ctx(root, overrides)
  overrides = overrides or {}
  local ctx = {
    CONFIG_DIR = "/tmp/config",
    state = {
      appearance = {
        menu_item_height = 23,
      },
      menus = {
        music = {
          title = "Studio",
          item_name = "music_studio",
          show_label = false,
          app_paths = {
            logic_pro = root .. "/Logic Pro.app",
            roland_cloud_manager = root .. "/Roland Cloud Manager.app",
            sp404_mkii = root .. "/SP-404MKII.app",
          },
          items = {
            {
              id = "crate",
              label = "Sample Crate",
              path = root .. "/Crate",
            },
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
        icon = "Symbols Nerd Font",
        style_map = { Semibold = "Semibold", Bold = "Bold" },
        sizes = { small = 12, icon = 16 },
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
      SAPPHIRE = "0xff74c7ec",
      DARK_WHITE = "0xffbac2de",
      BG_SEC_COLR = "0xff1e1e2e",
      bar = { bg = "0xff11111b" },
    },
    font_string = function(family, style, size)
      return string.format("%s:%s:%s", family, style, tostring(size))
    end,
    icon_for = function(_, fallback)
      return fallback
    end,
    paths = {
      ghostty_app = root .. "/Ghostty.app",
    },
  }

  for key, value in pairs(overrides) do
    ctx[key] = value
  end

  return ctx
end

run_test("music integration: model discovers studio app launchers", function()
  local root = make_fixture_root()
  mkdir(root .. "/Logic Pro.app")
  mkdir(root .. "/Roland Cloud Manager.app")
  mkdir(root .. "/SP-404MKII.app")
  mkdir(root .. "/Crate")

  local model = music.build_menu_model(build_ctx(root))
  assert_equal(model.title, "Studio", "menu title should follow music menu config")

  local apps = nil
  local workflow = nil
  for _, section in ipairs(model.sections) do
    if section.id == "apps" then apps = section end
    if section.id == "workflow" then workflow = section end
  end
  assert_true(apps ~= nil, "apps section should exist")
  assert_true(workflow ~= nil, "workflow section should exist")

  local app_ids = {}
  for _, entry in ipairs(apps.entries) do
    app_ids[entry.id] = entry
  end
  assert_true(app_ids.logic_pro ~= nil, "Logic Pro launcher should exist")
  assert_true(app_ids.roland_cloud_manager ~= nil, "Roland Cloud Manager launcher should exist")
  assert_true(app_ids.sp404_mkii ~= nil, "SP-404MKII launcher should exist")
  assert_true(app_ids.logic_pro.action:find("Logic Pro%.app", 1, false) ~= nil, "Logic Pro row should open the app bundle")

  local workflow_ids = {}
  for _, entry in ipairs(workflow.entries) do
    workflow_ids[entry.id] = entry
  end
  assert_true(workflow_ids.crate ~= nil, "custom workflow item should be included")
end)

run_test("music integration: widget and popup mirror Triforce-style behavior", function()
  local root = make_fixture_root()
  mkdir(root .. "/Logic Pro.app")
  mkdir(root .. "/Roland Cloud Manager.app")
  mkdir(root .. "/SP-404MKII.app")
  mkdir(root .. "/Crate")
  mkdir(root .. "/Ghostty.app")

  local ctx = build_ctx(root)
  local widget = music.create_widget({ ctx = ctx })
  assert_equal(widget.name, "music_studio", "widget should use the configured stable item name")
  assert_equal(widget.icon.string, "󰝚", "widget should default to a music glyph")
  assert_true(widget.script:match("/tmp/config/plugins/music_studio%.sh") ~= nil, "widget should route anchor behavior through music_studio.sh")
  assert_true(widget.click_script:match("popup%.drawing=toggle") ~= nil, "clicks should use a direct popup toggle")
  assert_true(widget.click_script:match("BARISTA_MUSIC_ACTION=click") == nil, "clicks should not route through the status/hover controller")
  assert_equal(widget.updates, false, "music menu should not wake on forced routine updates")

  local popup_items, popup_metadata = music.create_popup_items(ctx)
  local by_name = {}
  for _, item in ipairs(popup_items) do
    by_name[item.name] = item
  end

  assert_true(by_name["music.studio.header"] ~= nil, "popup header should exist")
  assert_true(by_name["music.studio.apps.header"] ~= nil, "apps section header should exist")
  assert_true(by_name["music.studio.apps.logic_pro"] ~= nil, "Logic Pro row should exist")
  assert_true(by_name["music.studio.apps.roland_cloud_manager"] ~= nil, "Roland Cloud Manager row should exist")
  assert_true(by_name["music.studio.apps.sp404_mkii"] ~= nil, "SP-404MKII row should exist")
  assert_true(by_name["music.studio.workflow.crate"] ~= nil, "custom workflow row should exist")
  assert_equal(by_name["music.studio.apps.logic_pro"].position, "popup.music_studio",
    "primary app rows should remain immediately available")
  assert_equal(by_name["music.studio.apps.roland_cloud_manager"].position, "popup.music.studio.more_apps",
    "secondary app rows should move under More Apps")
  assert_true(by_name["music.studio.apps.logic_pro"].hover == true, "popup actions should opt into hover treatment")
  assert_true(by_name["music.studio.apps.logic_pro"].click_script:find("popup.drawing=off", 1, true) ~= nil, "launcher rows should close the popup after firing")
  assert_true(by_name["music.studio.apps.roland_cloud_manager"].click_script:find(
    "--set music.studio.more_apps popup.drawing=off --set music_studio popup.drawing=off",
    1,
    true
  ) ~= nil, "nested app launchers should close both popup levels")
  assert_true(#popup_metadata.submenu_parents >= 1, "secondary apps should register a nested popup")
end)

run_test("music integration: progressive disclosure preserves every launcher", function()
  local root = make_fixture_root()
  local ctx = build_ctx(root, { SKETCHYBAR_BIN = "/custom/sketchybar" })
  local function entry(id, primary)
    return {
      id = id,
      label = id,
      icon = "󰐕",
      icon_color = "0xffffffff",
      action = "open-" .. id,
      primary = primary == true,
    }
  end
  local model = {
    title = "Studio",
    ui = { item_name = "music_studio", icon = "󰝚" },
    sections = {
      {
        id = "apps",
        label = "Apps",
        color = "0xff74c7ec",
        entries = {
          entry("yams", true), entry("logic_pro", true), entry("roland_cloud_manager"),
          entry("sp404_mkii"), entry("ableton_live"), entry("garageband"),
          entry("serato_dj_pro"), entry("mpc_beats"), entry("audio_midi_setup"),
        },
      },
      {
        id = "workflow",
        label = "Workflow",
        color = "0xffa6e3a1",
        entries = {
          entry("studio_start"), entry("studio_devices"), entry("songforge_tui"),
          entry("music_guides"), entry("muzak_bounces"),
        },
      },
      {
        id = "kits",
        label = "Kits + Folders",
        color = "0xffcba6f7",
        entries = {
          entry("samples"), entry("opxy_wavetables"), entry("sp404_wavetables"), entry("song_pdfs"),
        },
      },
    },
  }

  local items, metadata = music.create_popup_items(setmetatable({ music_menu_model = model }, { __index = ctx }))
  local by_name = {}
  local root_rows = 0
  local more_apps_rows = 0
  local kits_rows = 0
  local action_rows = 0
  for _, item in ipairs(items) do
    by_name[item.name] = item
    if item.position == "popup.music_studio" then root_rows = root_rows + 1 end
    if item.position == "popup.music.studio.more_apps" then more_apps_rows = more_apps_rows + 1 end
    if item.position == "popup.music.studio.kits" then kits_rows = kits_rows + 1 end
    if type(item.click_script) == "string" and item.click_script:find("open%-", 1, false) then
      action_rows = action_rows + 1
    end
  end

  assert_equal(root_rows, 13, "Music should render only primary actions and nested entry points initially")
  assert_equal(more_apps_rows, 8, "More Apps should contain one header and seven launchers")
  assert_equal(kits_rows, 5, "Kits should contain one header and four launchers")
  assert_equal(action_rows, 18, "progressive disclosure should preserve all launcher actions")
  assert_equal(table.concat(metadata.submenu_parents, "|"), "music.studio.more_apps|music.studio.kits",
    "Music should register both click-open nested popups")
  assert_equal(by_name["music.studio.more_apps"].position, "popup.music_studio",
    "More Apps entry point should remain on the root popup")
  assert_equal(by_name["music.studio.kits"].position, "popup.music_studio",
    "Kits entry point should remain on the root popup")
  assert_equal(by_name["music.studio.more_apps"].click_script,
    "/custom/sketchybar -m --set music.studio.kits popup.drawing=off --set music.studio.more_apps popup.drawing=toggle",
    "More Apps should close its sibling and toggle directly")
  assert_equal(by_name["music.studio.kits"].click_script,
    "/custom/sketchybar -m --set music.studio.more_apps popup.drawing=off --set music.studio.kits popup.drawing=toggle",
    "Kits should close its sibling and toggle directly")
  assert_true(by_name["music.studio.apps.roland_cloud_manager"].click_script:find(
    "open%-roland_cloud_manager; /custom/sketchybar %-m %-%-set music%.studio%.more_apps popup%.drawing=off %-%-set music_studio popup%.drawing=off"
  ) ~= nil, "nested launcher should retain its action and close both popup levels")

  local sparse_model = {
    title = "Studio",
    ui = { item_name = "music_studio", icon = "󰝚" },
    sections = {
      { id = "apps", label = "Apps", color = "0xff74c7ec", entries = { entry("logic_pro", true) } },
    },
  }
  local sparse_items, sparse_metadata = music.create_popup_items(
    setmetatable({ music_menu_model = sparse_model }, { __index = ctx })
  )
  local sparse_by_name = {}
  for _, item in ipairs(sparse_items) do sparse_by_name[item.name] = item end
  assert_equal(#sparse_metadata.submenu_parents, 0, "empty secondary groups should not register nested popups")
  assert_nil(sparse_by_name["music.studio.more_apps"], "empty More Apps should stay hidden")
  assert_nil(sparse_by_name["music.studio.kits"], "empty Kits should stay hidden")

  local one_child_model = {
    title = "Studio",
    ui = { item_name = "music_studio", icon = "󰝚" },
    sections = {
      {
        id = "apps",
        label = "Apps",
        color = "0xff74c7ec",
        entries = { entry("logic_pro", true), entry("garageband") },
      },
    },
  }
  local one_child_items = music.create_popup_items(
    setmetatable({ music_menu_model = one_child_model }, { __index = ctx })
  )
  local one_child_by_name = {}
  for _, item in ipairs(one_child_items) do one_child_by_name[item.name] = item end
  assert_equal(one_child_by_name["music.studio.more_apps"].click_script,
    "/custom/sketchybar -m --set music.studio.more_apps popup.drawing=toggle",
    "a lone Music child should not target a missing sibling")

  local kits_only_items = music.create_popup_items(setmetatable({
    music_menu_model = {
      title = "Studio",
      ui = { item_name = "music_studio", icon = "󰝚" },
      sections = {
        {
          id = "kits",
          label = "Kits + Folders",
          color = "0xffcba6f7",
          entries = { entry("samples") },
        },
      },
    },
  }, { __index = ctx }))
  local kits_only_by_name = {}
  for _, item in ipairs(kits_only_items) do kits_only_by_name[item.name] = item end
  assert_equal(kits_only_by_name["music.studio.kits"].click_script,
    "/custom/sketchybar -m --set music.studio.kits popup.drawing=toggle",
    "a lone Kits child should not target a missing More Apps sibling")
end)

run_test("music integration: exposes configured popup parent name", function()
  local root = make_fixture_root()
  local ctx = build_ctx(root)
  ctx.state.menus.music.item_name = "studio_menu"

  assert_equal(music.get_item_name(ctx), "studio_menu", "popup manager should be able to register the configured item name")

  local model = music.build_menu_model(ctx)
  local popup_items = music.create_popup_items(setmetatable({ music_menu_model = model }, { __index = ctx }))
  assert_equal(popup_items[1].position, "popup.studio_menu", "popup rows should attach to the configured item name")
end)
