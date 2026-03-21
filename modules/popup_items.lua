-- Helper to create popup items with shared defaults and hover.
-- Used by items_left (front_app, volume, battery) and items_right.
-- Returns layout entries (declarative) — no sbar.add calls.

local function build_popup_items(parent_name, items, opts)
  opts = opts or {}
  local hover_script = opts.hover_script or ""
  local defaults = {
    position = "popup." .. parent_name,
    script = hover_script,
    ["icon.padding_left"] = opts.icon_padding_left or 6,
    ["icon.padding_right"] = opts.icon_padding_right or 6,
    ["label.padding_left"] = opts.label_padding_left or 8,
    ["label.padding_right"] = opts.label_padding_right or 8,
    background = { drawing = false },
  }
  local definitions = {}
  for _, item in ipairs(items) do
    local id = item.name
    local props = item.props or item
    local merged = {}
    for k, v in pairs(defaults) do
      merged[k] = v
    end
    for k, v in pairs(props) do
      if k ~= "name" then
        merged[k] = v
      end
    end
    table.insert(definitions, { type = "item", name = id, props = merged, attach_hover = true })
  end
  return definitions
end

-- Return a function add(id, props) that produces a single layout entry.
local function make_add(parent_name, opts)
  opts = opts or {}
  return function(id, props)
    local items = build_popup_items(parent_name, { { name = id, props = props } }, opts)
    return items[1]
  end
end

return {
  build_popup_items = build_popup_items,
  make_add = make_add,
}
