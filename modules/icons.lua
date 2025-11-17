-- Icon Library Module
-- Comprehensive Nerd Font icon library with categories

local icons = {}

-- Icon categories for easy browsing
icons.categories = {
  apps = {
    activity_monitor = "󰨇",
    app_store = "󰓇",
    calculator = "",
    chrome = "",
    facetime = "",
    finder = "󰀶",
    firefox = "",
    mail = "󰇮",
    maps = "󰆋",
    messages = "󰍦",
    music = "",
    notes = "󰎚",
    photos = "",
    reminders = "󰄲",
    safari = "󰀹",
    system_settings = "",
    terminal_app = "",
    tv = "󰠎",
  },

  development = {
    api = "󰘯",
    branch = "",
    bug = "",
    build = "",
    code = "",
    commit = "",
    database = "",
    debug = "",
    docker = "",
    emacs = "",
    git = "",
    github = "",
    gitlab = "",
    json = "",
    kubernetes = "󱃾",
    markdown = "",
    package = "",
    pull_request = "",
    terminal = "",
    test = "󰙨",
    vim = "",
    vscode = "󰨞",
    xml = "󰗀",
  },

  emacs = {
    buffer = "󰈙",
    command = "󰘳",
    compile = "",
    elisp = "",
    emacs = "",
    eval = "󰐊",
    frame = "󰍿",
    function_icon = "󰡱",
    hook = "󰛢",
    keymap = "󰌌",
    macro = "󰆒",
    mode = "󰘧",
    variable = "󰫧",
    window = "󰖯",
  },

  files = {
    cloud = "󰅧",
    download = "",
    file = "",
    file_audio = "",
    file_code = "",
    file_image = "",
    file_pdf = "",
    file_text = "󰈙",
    file_video = "",
    file_zip = "",
    folder = "",
    folder_open = "",
    symlink = "",
    sync = "󰁪",
    trash = "",
    upload = "",
  },

  gaming = {
    compass = "󰘑",
    controller = "󰖺",
    dice = "󰐱",
    gamepad = "󰍳",
    heart_container = "",
    key = "󰌆",
    map = "󰆋",
    potion = "󰍛",
    quest = "",
    rupee = "",
    shield = "󰡁",
    sword = "󰚥",
    treasure = "",
    triforce = "󰊠",
  },

  misc = {
    book = "",
    brush = "󰏘",
    camera = "",
    cloud_icon = "󰅧",
    flame = "",
    globe = "",
    image = "",
    lightning = "󰚌",
    location = "",
    magic = "󱁉",
    microphone = "",
    moon = "",
    movie = "",
    music_note = "",
    newspaper = "󰎕",
    palette = "󰏘",
    pencil = "",
    rain = "",
    robot = "󰚩",
    snow = "",
    sparkle = "󰙴",
    speaker = "",
    sun = "",
    weather = "",
  },

  navigation = {
    arrow_down = "",
    arrow_left = "",
    arrow_right = "",
    arrow_up = "",
    check = "",
    chevron_down = "",
    chevron_left = "",
    chevron_right = "",
    chevron_up = "",
    close = "",
    collapse = "󰁍",
    dots_horizontal = "󰇘",
    dots_vertical = "󰇙",
    double_arrow_right = "󰅂",
    expand = "󰁌",
    filter = "󰈶",
    fullscreen = "󰊓",
    hamburger = "󰍜",
    home = "",
    menu = "",
    minimize = "󰖰",
    minus = "",
    plus = "",
    search = "",
    sort = "󰒺",
  },

  org_mode = {
    checkbox = "",
    checkbox_checked = "",
    deadline = "󰃰",
    done = "",
    drawer = "󰉖",
    heading_1 = "󰉫",
    heading_2 = "󰉬",
    heading_3 = "󰉭",
    link = "",
    org = "󰩹",
    property = "󰓹",
    quote_block = "󰝗",
    scheduled = "",
    src_block = "",
    table = "󰓫",
    tag = "",
    todo = "",
  },

  rom_hacking = {
    assembly = "",
    binary = "󰡯",
    breakpoint = "",
    cartridge = "󰯙",
    chip = "",
    debugger = "",
    disassembly = "󰘓",
    emulator = "󰺷",
    hex = "󰘨",
    memory = "",
    register = "󰫫",
    rom = "󰯙",
    trace = "󰄉",
    watch = "󰔶",
  },

  status = {
    bookmark = "",
    error = "",
    flag = "",
    heart = "",
    heart_outline = "󰋕",
    hourglass = "",
    info_circle = "",
    loading = "󰔟",
    pin = "",
    question = "",
    redo = "󰑎",
    refresh = "󰑐",
    save = "󰆓",
    star = "",
    star_outline = "󰋙",
    success = "",
    sync_circle = "󰑓",
    tag = "",
    undo = "󰕌",
    warning = "",
  },

  system = {
    apple = "",
    apple_alt = "",
    battery = "",
    battery_charging = "",
    bell = "",
    bluetooth = "󰂯",
    brightness = "󰃞",
    calendar = "",
    clock = "",
    gear = "",
    info = "󰋗",
    lock = "󰷛",
    logout = "󰍃",
    notification = "󰂚",
    power = "",
    restart = "󰜉",
    settings = "",
    shutdown = "󰐥",
    sleep = "󰒲",
    volume = "",
    volume_mute = "󰝟",
    wifi = "󰖩",
    wifi_off = "󰖪",
  },

  text_editing = {
    align_center = "󰘞",
    align_justify = "󰘙",
    align_left = "󰘚",
    align_right = "󰘟",
    bold = "󰖭",
    heading = "󰉫",
    indent = "󰉶",
    italic = "󰖬",
    link = "",
    list_bullet = "󰃉",
    list_numbered = "󰃅",
    outdent = "󰉵",
    paragraph = "󰴜",
    quote = "󰝗",
    strikethrough = "󰟃",
    underline = "󰘴",
    unlink = "󰌷",
  },

  window_management = {
    desktop = "󰧨",
    display = "󰍹",
    float = "󰒄",
    focus = "󰋗",
    fullscreen = "󰊓",
    monitor = "󰍺",
    split_horizontal = "󰤼",
    split_vertical = "󰤻",
    stack = "󰓩",
    sticky = "󰐊",
    tile = "󰆾",
    topmost = "󰁜",
    window = "󰖯",
    windows = "󰍿",
    workspace = "󱂬",
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
