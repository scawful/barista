-- submenu_registry.lua - Write submenu/popup names to TMPDIR for C helpers
-- This replaces hardcoded lists in submenu_hover.c and popup_manager.c

local M = {}

--- Write a list of item names to a file, one per line.
local function write_list(path, items)
  local seen = {}
  local fh = io.open(path, "w")
  if not fh then
    print("submenu_registry: cannot write " .. path)
    return
  end
  for _, name in ipairs(items) do
    if type(name) == "string" and name ~= "" and not seen[name] then
      seen[name] = true
      fh:write(name .. "\n")
    end
  end
  fh:close()
end

--- Register submenu section names so C helpers can discover them.
--- Call this after menus are rendered.
function M.write_submenu_list(submenu_names)
  local tmpdir = os.getenv("TMPDIR") or "/tmp"
  write_list(tmpdir .. "/sketchybar_submenu_list", submenu_names)
end

--- Register popup parent names for the popup_manager.
function M.write_popup_list(popup_names)
  local tmpdir = os.getenv("TMPDIR") or "/tmp"
  write_list(tmpdir .. "/sketchybar_popup_list", popup_names)
end

--- Convenience: write both lists at once.
function M.register(popups, submenus)
  if popups then M.write_popup_list(popups) end
  if submenus then M.write_submenu_list(submenus) end
end

return M
