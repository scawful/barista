local whichkey = {}

local sbar = require("sketchybar")
local json = require("json")
local menu_renderer = require("menu_renderer")

local HOME = os.getenv("HOME") or ""

local function load_json(path)
  if not path then return nil end
  local file = io.open(path, "r")
  if not file then return nil end
  local contents = file:read("*a")
  file:close()
  if not contents then return nil end
  local ok, data = pcall(json.decode, contents)
  if not ok or type(data) ~= "table" then
    return nil
  end
  return data
end

local function trim(str)
  if not str then return "" end
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function expand_path(path)
  if not path or path == "" then return nil end
  if path:sub(1, 2) == "~/" then
    return HOME .. path:sub(2)
  elseif path:sub(1, 1) == "/" then
    return path
  else
    return HOME .. "/" .. path
  end
end

local function shell_read(cmd)
  local handle = io.popen(cmd)
  if not handle then return "" end
  local result = handle:read("*a") or ""
  handle:close()
  return result
end

local function repo_status(repo)
  local path = expand_path(repo.path)
  if not path then return nil end
  local branch_output = shell_read(string.format("cd %q && git rev-parse --abbrev-ref HEAD 2>/dev/null", path))
  local dirty_output = shell_read(string.format("cd %q && git status --short 2>/dev/null", path))
  local branch = trim(branch_output)
  if branch == "" then branch = "—" end
  local dirty = trim(dirty_output) ~= ""
  return { branch = branch, dirty = dirty, path = path }
end

function whichkey.setup(ctx)
  local data = load_json(ctx.paths.workflow_data)
  if not data then
    return
  end

  local base_item = "whichkey_hud"
  sbar.add("item", base_item, {
    position = "center",
    icon = "󰘥",
    label = "?",
    click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
    script = [[if [ "$SENDER" = "whichkey_toggle" ]; then sketchybar -m --set $NAME popup.drawing=toggle; fi]],
    popup = {
      align = "center",
      background = {
        border_width = 2,
        corner_radius = 6,
        border_color = ctx.theme.WHITE,
        color = ctx.theme.bar.bg,
        padding_left = 16,
        padding_right = 16,
        padding_top = 12,
        padding_bottom = 16,
      }
    }
  })
  ctx.subscribe_popup_autoclose(base_item)
  sbar.exec("sketchybar --subscribe whichkey_hud whichkey_toggle")

  local renderer = menu_renderer.create(ctx)
  local render_menu_items = renderer.render
  local items = {}

  local keymap = data.keymap or {}
  if #keymap > 0 then
    table.insert(items, { type = "header", label = "Shortcuts" })
    for _, section in ipairs(keymap) do
      if section.section then
        table.insert(items, { 
          type = "item", 
          name = "whichkey.section." .. section.section:gsub("%s+", "_"),
          icon = "", 
          label = section.section, 
          action = "", 
          color = ctx.theme.SAPPHIRE 
        })
      end
      if type(section.items) == "table" then
        for i, item in ipairs(section.items) do
          local keys = item.keys or ""
          local description = item.description or ""
          table.insert(items, {
            type = "item",
            name = "whichkey.key." .. i .. "." .. keys:gsub("%s+", "_"),
            icon = "󰘥",
            label = keys,
            shortcut = description,
            action = "",
          })
        end
      end
    end
  end

  local actions = data.actions or {}
  if #actions > 0 then
    table.insert(items, { type = "separator" })
    table.insert(items, { type = "header", label = "Quick Actions" })
    local action_map = {
      reload_bar = "/opt/homebrew/opt/sketchybar/bin/sketchybar --reload",
      open_logs = ctx.open_path("/opt/homebrew/var/log/sketchybar"),
      repair_accessibility = ctx.call_script(ctx.scripts.accessibility),
      focus_emacs = ctx.call_script(ctx.scripts.yabai_control, "space-focus-app", "Emacs"),
      launch_yaze = ctx.open_path(ctx.paths.yaze .. "/build/bin/yaze"),
    }
    for _, action in ipairs(actions) do
      local cmd = action_map[action.id]
      if cmd then
        table.insert(items, { 
          type = "item", 
          name = "whichkey.action." .. action.id,
          icon = "󰐕", 
          label = action.title or action.id, 
          action = cmd 
        })
      end
    end
  end

  local docs = data.docs or {}
  if #docs > 0 then
    table.insert(items, { type = "separator" })
    table.insert(items, { type = "header", label = "Docs" })
    for _, doc in ipairs(docs) do
      local path = expand_path(doc.path)
      if path then
        table.insert(items, { 
          type = "item", 
          name = "whichkey.doc." .. (doc.id or "doc"),
          icon = "󰈙", 
          label = doc.title or path, 
          action = ctx.open_path(path) 
        })
      end
    end
  end

  local repos = data.repos or {}
  if #repos > 0 then
    table.insert(items, { type = "separator" })
    table.insert(items, { type = "header", label = "Repos" })
    for _, repo in ipairs(repos) do
      local status = repo_status(repo)
      if status then
        local suffix = status.dirty and " *" or ""
        table.insert(items, {
          type = "item",
          name = "whichkey.repo." .. (repo.id or "repo"),
          icon = "󰊢",
          label = string.format("%s [%s%s]", repo.name or repo.id or "repo", status.branch, suffix),
          action = ctx.open_path(status.path),
          color = status.dirty and ctx.theme.PEACH or ctx.theme.WHITE,
        })
      end
    end
  end

  table.insert(items, { type = "separator" })
  table.insert(items, { type = "header", label = "Help" })
  local help_action
  if ctx.helpers.help_center then
    help_action = ctx.open_path(ctx.helpers.help_center)
  else
    help_action = [[osascript -e 'display alert "Help Center binary missing" message "Run `cd ~/.config/sketchybar/gui && make help`"']]
  end
  table.insert(items, { type = "item", name = "whichkey.help.center", icon = "󰘥", label = "Help Center", action = help_action })
  table.insert(items, { type = "item", name = "whichkey.help.toggle", icon = "󰌌", label = "Toggle WhichKey", action = "sketchybar --trigger whichkey_toggle" })

  render_menu_items(base_item, items)
end

return whichkey
