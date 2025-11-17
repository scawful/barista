-- Icon Library Module
-- Comprehensive Nerd Font icon library with categories

local icons = {}

-- Icon categories for easy browsing
icons.categories = {
  system = {
    apple = "",
    apple_alt = "",
    settings = "",
    gear = "",
    power = "",
    sleep = "󰒲",
    lock = "󰷛",
    logout = "󰍃",
    restart = "󰜉",
    shutdown = "󰐥",
    info = "󰋗",
    bell = "",
    notification = "󰂚",
    calendar = "",
    clock = "",
    battery = "",
    battery_charging = "",
    volume = "",
    volume_mute = "󰝟",
    wifi = "󰖩",
    wifi_off = "󰖪",
    bluetooth = "󰂯",
    brightness = "󰃞",
  },

  development = {
    code = "",
    terminal = "",
    vim = "",
    emacs = "",
    vscode = "󰨞",
    git = "",
    github = "",
    gitlab = "",
    branch = "",
    commit = "",
    pull_request = "",
    bug = "",
    debug = "",
    build = "",
    test = "󰙨",
    package = "",
    docker = "",
    kubernetes = "󱃾",
    database = "",
    api = "󰘯",
    json = "",
    xml = "󰗀",
    markdown = "",
  },

  files = {
    folder = "",
    folder_open = "",
    file = "",
    file_code = "",
    file_text = "󰈙",
    file_image = "",
    file_pdf = "",
    file_zip = "",
    file_audio = "",
    file_video = "",
    symlink = "",
    trash = "",
    download = "",
    upload = "",
    cloud = "󰅧",
    sync = "󰁪",
  },

  apps = {
    finder = "󰀶",
    safari = "󰀹",
    chrome = "",
    firefox = "",
    mail = "󰇮",
    messages = "󰍦",
    facetime = "",
    photos = "",
    music = "",
    tv = "󰠎",
    notes = "󰎚",
    reminders = "󰄲",
    maps = "󰆋",
    calculator = "",
    app_store = "󰓇",
    activity_monitor = "󰨇",
    system_settings = "",
    terminal_app = "",
  },

  navigation = {
    home = "",
    search = "",
    filter = "󰈶",
    sort = "󰒺",
    menu = "",
    hamburger = "󰍜",
    dots_vertical = "󰇙",
    dots_horizontal = "󰇘",
    arrow_up = "",
    arrow_down = "",
    arrow_left = "",
    arrow_right = "",
    chevron_up = "",
    chevron_down = "",
    chevron_left = "",
    chevron_right = "",
    double_arrow_right = "󰅂",
    expand = "󰁌",
    collapse = "󰁍",
    fullscreen = "󰊓",
    minimize = "󰖰",
    close = "",
    check = "",
    plus = "",
    minus = "",
  },

  status = {
    success = "",
    error = "",
    warning = "",
    info_circle = "",
    question = "",
    hourglass = "",
    loading = "󰔟",
    sync_circle = "󰑓",
    refresh = "󰑐",
    redo = "󰑎",
    undo = "󰕌",
    save = "󰆓",
    bookmark = "",
    star = "",
    star_outline = "󰋙",
    heart = "",
    heart_outline = "󰋕",
    flag = "",
    pin = "",
    tag = "",
  },

  window_management = {
    window = "󰖯",
    windows = "󰍿",
    tile = "󰆾",
    stack = "󰓩",
    float = "󰒄",
    fullscreen = "󰊓",
    split_horizontal = "󰤼",
    split_vertical = "󰤻",
    focus = "󰋗",
    sticky = "󰐊",
    topmost = "󰁜",
    display = "󰍹",
    monitor = "󰍺",
    workspace = "󱂬",
    desktop = "󰧨",
  },

  gaming = {
    triforce = "󰊠",
    quest = "",
    gamepad = "󰍳",
    controller = "󰖺",
    dice = "󰐱",
    sword = "󰚥",
    shield = "󰡁",
    heart_container = "",
    rupee = "",
    key = "󰌆",
    treasure = "",
    map = "󰆋",
    compass = "󰘑",
    potion = "󰍛",
  },

  rom_hacking = {
    rom = "󰯙",
    hex = "󰘨",
    binary = "󰡯",
    assembly = "",
    disassembly = "󰘓",
    memory = "",
    register = "󰫫",
    chip = "",
    cartridge = "󰯙",
    emulator = "󰺷",
    debugger = "",
    breakpoint = "",
    watch = "󰔶",
    trace = "󰄉",
  },

  text_editing = {
    bold = "󰖭",
    italic = "󰖬",
    underline = "󰘴",
    strikethrough = "󰟃",
    align_left = "󰘚",
    align_center = "󰘞",
    align_right = "󰘟",
    align_justify = "󰘙",
    list_bullet = "󰃉",
    list_numbered = "󰃅",
    indent = "󰉶",
    outdent = "󰉵",
    quote = "󰝗",
    link = "",
    unlink = "󰌷",
    heading = "󰉫",
    paragraph = "󰴜",
  },

  org_mode = {
    org = "󰩹",
    todo = "",
    done = "",
    checkbox = "",
    checkbox_checked = "",
    deadline = "󰃰",
    scheduled = "",
    tag = "",
    property = "󰓹",
    drawer = "󰉖",
    table = "󰓫",
    src_block = "",
    quote_block = "󰝗",
    link = "",
    heading_1 = "󰉫",
    heading_2 = "󰉬",
    heading_3 = "󰉭",
  },

  emacs = {
    emacs = "",
    buffer = "󰈙",
    window = "󰖯",
    frame = "󰍿",
    mode = "󰘧",
    command = "󰘳",
    function_icon = "󰡱",
    variable = "󰫧",
    macro = "󰆒",
    keymap = "󰌌",
    hook = "󰛢",
    elisp = "",
    eval = "󰐊",
    compile = "",
  },

  misc = {
    robot = "󰚩",
    sparkle = "󰙴",
    flame = "",
    lightning = "󰚌",
    magic = "󱁉",
    pencil = "",
    brush = "󰏘",
    palette = "󰏘",
    image = "",
    camera = "",
    microphone = "",
    speaker = "",
    movie = "",
    music_note = "",
    book = "",
    newspaper = "󰎕",
    globe = "",
    location = "",
    weather = "",
    sun = "",
    moon = "",
    cloud_icon = "󰅧",
    rain = "",
    snow = "",
  },
}

-- Flattened icon list for searching
function icons.get_all()
  local all = {}
  for category, category_icons in pairs(icons.categories) do
    for name, glyph in pairs(category_icons) do
      table.insert(all, {
        name = name,
        glyph = glyph,
        category = category,
      })
    end
  end
  return all
end

-- Search icons by name
function icons.search(query)
  if not query or query == "" then
    return icons.get_all()
  end

  local results = {}
  local lower_query = query:lower()

  for category, category_icons in pairs(icons.categories) do
    for name, glyph in pairs(category_icons) do
      if name:lower():find(lower_query, 1, true) or category:lower():find(lower_query, 1, true) then
        table.insert(results, {
          name = name,
          glyph = glyph,
          category = category,
        })
      end
    end
  end

  return results
end

-- Get icon by category and name
function icons.get(category, name)
  if icons.categories[category] then
    return icons.categories[category][name]
  end
  return nil
end

-- Get icon by name (searches all categories)
function icons.find(name)
  for category, category_icons in pairs(icons.categories) do
    if category_icons[name] then
      return category_icons[name]
    end
  end
  return nil
end

-- Get all icons from a category
function icons.get_category(category)
  return icons.categories[category] or {}
end

-- List all category names
function icons.list_categories()
  local categories = {}
  for category, _ in pairs(icons.categories) do
    table.insert(categories, category)
  end
  table.sort(categories)
  return categories
end

-- Check if an icon exists
function icons.exists(category, name)
  return icons.get(category, name) ~= nil
end

-- Get a random icon from a category
function icons.random(category)
  local category_icons = icons.get_category(category)
  local icon_list = {}
  for _, glyph in pairs(category_icons) do
    table.insert(icon_list, glyph)
  end
  if #icon_list > 0 then
    math.randomseed(os.time())
    return icon_list[math.random(#icon_list)]
  end
  return nil
end

-- Export for GUI/scripts
function icons.export_json()
  local json = require("json")
  local all_icons = icons.get_all()
  return json.encode(all_icons)
end

-- Common icon sets for quick access
icons.common = {
  -- Menu icons
  menu_apple = icons.categories.system.apple,
  menu_settings = icons.categories.system.settings,
  menu_power = icons.categories.system.power,

  -- Status icons
  status_ok = icons.categories.status.success,
  status_error = icons.categories.status.error,
  status_warning = icons.categories.status.warning,

  -- App icons
  app_terminal = icons.categories.apps.terminal_app,
  app_finder = icons.categories.apps.finder,
  app_vscode = icons.categories.development.vscode,

  -- Window management
  wm_tile = icons.categories.window_management.tile,
  wm_stack = icons.categories.window_management.stack,
  wm_float = icons.categories.window_management.float,
}

return icons
