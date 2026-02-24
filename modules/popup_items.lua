-- Helper to add multiple popup items with shared defaults and hover.
-- Used by items_left (front_app, volume, battery) and items_right.

local function add_popup_items(sbar, parent_name, items, opts)
  opts = opts or {}
  local hover_script = opts.hover_script or ""
  local attach_hover_fn = opts.attach_hover or function() end
  local defaults = {
    position = "popup." .. parent_name,
    script = hover_script,
    ["icon.padding_left"] = opts.icon_padding_left or 6,
    ["icon.padding_right"] = opts.icon_padding_right or 6,
    ["label.padding_left"] = opts.label_padding_left or 8,
    ["label.padding_right"] = opts.label_padding_right or 8,
    background = { drawing = false },
  }
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
    sbar.add("item", id, merged)
    attach_hover_fn(id)
  end
end

-- Add a single popup item (merge props onto defaults).
local function add_popup_item(sbar, id, props, opts)
  local parent = (opts and opts.parent_name) or "popup"
  add_popup_items(sbar, parent, { { name = id, props = props } }, opts)
end

-- Return a function add(id, props) for a given parent and opts (hover_script, attach_hover).
function make_add(sbar, parent_name, opts)
  opts = opts or {}
  opts.parent_name = parent_name
  return function(id, props)
    add_popup_item(sbar, id, props, opts)
  end
end

return {
  add_popup_items = add_popup_items,
  add_popup_item = add_popup_item,
  make_add = make_add,
}
