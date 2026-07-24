-- submenu_registry.lua - Write submenu/popup names to TMPDIR for C helpers
-- This replaces hardcoded lists in submenu_hover.c and popup_manager.c

local M = {}

local MAX_TOPOLOGY_NAMES = 128
local MAX_TOPOLOGY_RELATIONS = 512
local MAX_TOPOLOGY_NAME_LENGTH = 127
local topology_token_sequence = 0

local function unique_token()
  topology_token_sequence = topology_token_sequence + 1
  local tmpname_ok, seed = pcall(os.tmpname)
  if tmpname_ok and type(seed) == "string" then
    pcall(os.remove, seed)
  else
    seed = table.concat({
      tostring(os.time()),
      tostring(math.floor(os.clock() * 1000000)),
      tostring({}),
    }, "-")
  end
  local basename = seed:match("([^/]+)$") or seed
  basename = basename:gsub("[^%w_.-]", "")
  if basename == "" then basename = tostring(os.time()) end
  local suffix = "-" .. tostring(topology_token_sequence)
  local maximum_basename_length = MAX_TOPOLOGY_NAME_LENGTH
    - #"barista-" - #suffix
  basename = basename:sub(1, maximum_basename_length)
  return "barista-" .. basename .. suffix
end

local function temporary_path(path)
  return string.format("%s.tmp.%s", path, unique_token())
end

local function publish_lines(path, lines)
  local temporary_path = temporary_path(path)
  local fh = io.open(temporary_path, "w")
  if not fh then
    print("submenu_registry: cannot write " .. temporary_path)
    return false
  end
  for _, line in ipairs(lines) do
    local wrote = fh:write(line .. "\n")
    if not wrote then
      fh:close()
      os.remove(temporary_path)
      print("submenu_registry: cannot write " .. temporary_path)
      return false
    end
  end
  if not fh:close() then
    os.remove(temporary_path)
    print("submenu_registry: cannot close " .. temporary_path)
    return false
  end
  local renamed, rename_error = os.rename(temporary_path, path)
  if not renamed then
    os.remove(temporary_path)
    print("submenu_registry: cannot publish " .. path .. ": " .. tostring(rename_error))
    return false
  end
  return true
end

local function unique_names(items)
  local names = {}
  local seen = {}
  for _, name in ipairs(items or {}) do
    if type(name) == "string" and name ~= "" and not seen[name] then
      seen[name] = true
      table.insert(names, name)
    end
  end
  return names
end

local function valid_field(value, label, max_length)
  if type(value) ~= "string" or value == "" then
    return false, label .. " must be a non-empty string"
  end
  if value:find("\t", 1, true)
      or value:find("\n", 1, true)
      or value:find("\r", 1, true)
      or value:find("\0", 1, true) then
    return false, label .. " contains a reserved delimiter"
  end
  if max_length and #value > max_length then
    return false, label .. " exceeds " .. tostring(max_length) .. " bytes"
  end
  return true
end

local function topology_names(items, kind)
  local names = {}
  local seen = {}
  if items ~= nil and type(items) ~= "table" then
    return nil, kind .. " names must be a table"
  end
  for _, name in ipairs(items or {}) do
    local valid, validation_error = valid_field(
      name,
      kind .. " name",
      MAX_TOPOLOGY_NAME_LENGTH
    )
    if not valid then return nil, validation_error end
    if not seen[name] then
      if #names >= MAX_TOPOLOGY_NAMES then
        return nil, "too many unique " .. kind .. " names"
      end
      seen[name] = true
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

--- Write a list of item names to a file, one per line.
local function write_list(path, items)
  return publish_lines(path, unique_names(items))
end

local function topology_lines(popups, submenus, submenu_ancestors, generation_token)
  local lines = { "version\t1" }
  if generation_token ~= nil then
    local valid, validation_error = valid_field(generation_token, "generation token")
    if not valid then return nil, validation_error end
    table.insert(lines, "generation\t" .. generation_token)
  end

  local roots, roots_error = topology_names(popups, "root")
  if not roots then return nil, roots_error end
  local children, children_error = topology_names(submenus, "child")
  if not children then return nil, children_error end

  for _, name in ipairs(roots) do
    table.insert(lines, "root\t" .. name)
  end
  for _, name in ipairs(children) do
    table.insert(lines, "child\t" .. name)
  end

  local relations = {}
  local seen = {}
  if submenu_ancestors ~= nil and type(submenu_ancestors) ~= "table" then
    return nil, "submenu ancestors must be a table"
  end
  for target, ancestors in pairs(submenu_ancestors or {}) do
    local valid_target, target_error = valid_field(
      target,
      "ancestor target",
      MAX_TOPOLOGY_NAME_LENGTH
    )
    if not valid_target then return nil, target_error end
    if type(ancestors) ~= "table" then
      return nil, "ancestors for " .. target .. " must be a table"
    end

    seen[target] = seen[target] or {}
    for _, ancestor in ipairs(ancestors) do
      local valid_ancestor, ancestor_error = valid_field(
        ancestor,
        "ancestor name",
        MAX_TOPOLOGY_NAME_LENGTH
      )
      if not valid_ancestor then return nil, ancestor_error end
      if ancestor == target then
        return nil, "ancestor target cannot reference itself"
      end
      if not seen[target][ancestor] then
        if #relations >= MAX_TOPOLOGY_RELATIONS then
          return nil, "too many unique ancestor relations"
        end
        seen[target][ancestor] = true
        table.insert(relations, { target = target, ancestor = ancestor })
      end
    end
  end
  table.sort(relations, function(left, right)
    if left.target == right.target then
      return left.ancestor < right.ancestor
    end
    return left.target < right.target
  end)
  for _, relation in ipairs(relations) do
    table.insert(lines, "ancestor\t" .. relation.target .. "\t" .. relation.ancestor)
  end
  return lines
end

local function invalidate_topology(path)
  local removed, remove_error = os.remove(path)
  local stale = not removed and io.open(path, "r") or nil
  if stale then
    stale:close()
    print(
      "submenu_registry: cannot invalidate stale topology "
        .. path .. ": " .. tostring(remove_error)
    )
  end
end

local function publish_topology(path, lines)
  local published = lines and publish_lines(path, lines) or false
  if not published then invalidate_topology(path) end
  return published
end

--- Register submenu section names so C helpers can discover them.
--- Call this after menus are rendered.
function M.write_submenu_list(submenu_names, directory)
  local tmpdir = directory or os.getenv("TMPDIR") or "/tmp"
  return write_list(tmpdir .. "/sketchybar_submenu_list", submenu_names)
end

--- Register popup parent names for the popup_manager.
function M.write_popup_list(popup_names, directory)
  local tmpdir = directory or os.getenv("TMPDIR") or "/tmp"
  return write_list(tmpdir .. "/sketchybar_popup_list", popup_names)
end

--- Publish the click-time root/child topology as one atomic generation.
function M.write_popup_topology(
    popups,
    submenus,
    submenu_ancestors,
    directory,
    generation_token
)
  local tmpdir = directory or os.getenv("TMPDIR") or "/tmp"
  local path = tmpdir .. "/sketchybar_popup_topology"
  local lines, validation_error = topology_lines(
    popups,
    submenus,
    submenu_ancestors,
    generation_token
  )
  if not lines then
    print("submenu_registry: invalid popup topology: " .. tostring(validation_error))
    invalidate_topology(path)
    return false
  end
  return publish_topology(path, lines)
end

--- Return an opaque token for one click-topology publication generation.
function M.new_topology_token()
  return unique_token()
end

--- Convenience: write both lists at once.
function M.register(popups, submenus, directory, submenu_ancestors, generation_token)
  local topology
  local topology_path
  if popups or submenus or submenu_ancestors then
    local validation_error
    topology, validation_error = topology_lines(
      popups or {},
      submenus or {},
      submenu_ancestors or {},
      generation_token
    )
    topology_path = (directory or os.getenv("TMPDIR") or "/tmp")
      .. "/sketchybar_popup_topology"
    if not topology then
      print("submenu_registry: invalid popup topology: " .. tostring(validation_error))
      invalidate_topology(topology_path)
      return false
    end
  end

  local ok = true
  if popups then ok = M.write_popup_list(popups, directory) and ok end
  if submenus then ok = M.write_submenu_list(submenus, directory) and ok end
  if topology then
    ok = publish_topology(topology_path, topology) and ok
  end
  return ok
end

return M
