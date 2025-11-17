-- C Bridge Module - Integration with enhanced C components
-- Provides Lua interface to the new high-performance C APIs

local c_bridge = {}

local HOME = os.getenv("HOME")
local BIN_DIR = HOME .. "/.config/sketchybar/bin"

-- Helper function to execute C programs and get output
local function exec_c(program, ...)
    local args = {...}
    local cmd = BIN_DIR .. "/" .. program
    for _, arg in ipairs(args) do
        cmd = cmd .. " " .. string.format("%q", tostring(arg))
    end

    local handle = io.popen(cmd)
    if not handle then
        return nil, "Failed to execute: " .. program
    end

    local result = handle:read("*a")
    handle:close()

    return result
end

-- Helper function to execute C programs without waiting for output
local function exec_c_async(program, ...)
    local args = {...}
    local cmd = BIN_DIR .. "/" .. program
    for _, arg in ipairs(args) do
        cmd = cmd .. " " .. string.format("%q", tostring(arg))
    end
    cmd = cmd .. " &"

    os.execute(cmd)
end

-- Icon Manager API
c_bridge.icons = {}

function c_bridge.icons.get(name, fallback)
    local result = exec_c("icon_manager", "get", name, fallback or "")
    if result then
        return result:gsub("%s+$", "")  -- Trim whitespace
    end
    return fallback or ""
end

function c_bridge.icons.set(item, icon_name, fallback)
    exec_c_async("icon_manager", "set", item, icon_name, fallback or "")
end

function c_bridge.icons.search(query)
    local result = exec_c("icon_manager", "search", query or "")
    if result then
        -- Parse JSON result
        local ok, icons = pcall(function()
            return require("json").decode(result)
        end)
        if ok then
            return icons
        end
    end
    return {}
end

function c_bridge.icons.list_category(category)
    local result = exec_c("icon_manager", "list", category)
    if result then
        local ok, icons = pcall(function()
            return require("json").decode(result)
        end)
        if ok then
            return icons
        end
    end
    return {}
end

function c_bridge.icons.categories()
    local result = exec_c("icon_manager", "categories")
    if result then
        local ok, cats = pcall(function()
            return require("json").decode(result)
        end)
        if ok then
            return cats
        end
    end
    return {}
end

-- State Manager API
c_bridge.state = {}

function c_bridge.state.init()
    exec_c("state_manager", "init")
end

function c_bridge.state.save()
    exec_c("state_manager", "save")
end

function c_bridge.state.widget(name, action)
    if action then
        exec_c_async("state_manager", "widget", name, action)
    else
        local result = exec_c("state_manager", "widget", name)
        if result then
            return result:find("on") ~= nil
        end
    end
    return false
end

function c_bridge.state.toggle_widget(name)
    exec_c_async("state_manager", "widget", name, "toggle")
end

function c_bridge.state.appearance(key, value)
    if value then
        exec_c_async("state_manager", "appearance", key, value)
    else
        -- For getting, we'd need to parse the state file
        -- This is a limitation - we should enhance state_manager to support getters
        return nil
    end
end

function c_bridge.state.space_icon(space_num, icon)
    exec_c_async("state_manager", "space-icon", space_num, icon)
end

function c_bridge.state.space_mode(space_num, mode)
    exec_c_async("state_manager", "space-mode", space_num, mode)
end

function c_bridge.state.stats()
    local result = exec_c("state_manager", "stats")
    if result then
        local stats = {}
        for line in result:gmatch("[^\n]+") do
            local key, value = line:match("(%w+): (%d+)")
            if key and value then
                stats[key:lower()] = tonumber(value)
            end
        end
        return stats
    end
    return {}
end

-- Widget Manager API
c_bridge.widgets = {}

function c_bridge.widgets.update(widget_name)
    exec_c_async("widget_manager", "update", widget_name)
end

function c_bridge.widgets.batch_update(...)
    local widgets = {...}
    if #widgets > 0 then
        exec_c_async("widget_manager", "batch", table.unpack(widgets))
    end
end

function c_bridge.widgets.start_daemon()
    exec_c_async("widget_manager", "daemon")
end

function c_bridge.widgets.stop_daemon()
    os.execute("pkill -f 'widget_manager daemon'")
end

function c_bridge.widgets.stats()
    local result = exec_c("widget_manager", "stats")
    if result then
        local stats = {}
        for line in result:gmatch("[^\n]+") do
            local key, value = line:match("([%w ]+): ([%d.]+)")
            if key and value then
                stats[key:lower():gsub(" ", "_")] = value
            end
        end
        return stats
    end
    return {}
end

-- Menu Renderer API
c_bridge.menus = {}

function c_bridge.menus.render(menu_file, popup_name)
    exec_c_async("menu_renderer", "render", menu_file, popup_name)
end

function c_bridge.menus.batch_render(...)
    local menus = {...}
    if #menus > 0 then
        exec_c_async("menu_renderer", "batch", table.unpack(menus))
    end
end

function c_bridge.menus.cache(menu_file)
    exec_c("menu_renderer", "cache", menu_file)
end

function c_bridge.menus.clear(popup_name)
    exec_c_async("menu_renderer", "clear", popup_name)
end

-- Enhanced widget creation using C components
function c_bridge.create_widget(sbar, config)
    local name = config.name
    local widget_type = config.type or "custom"

    -- Get icon from icon manager
    local icon = config.icon
    if config.icon_name then
        icon = c_bridge.icons.get(config.icon_name, icon)
    end

    -- Create base widget
    local widget_config = {
        position = config.position or "right",
        icon = icon or "",
        label = config.label or "",
        ["icon.font"] = config.icon_font or "Symbols Nerd Font:Regular:14.0",
        ["label.font"] = config.label_font or "SF Pro:Semibold:12.0",
        update_freq = config.update_freq or 1,
    }

    -- Add widget-specific configurations
    if widget_type == "clock" then
        widget_config.script = BIN_DIR .. "/widget_manager update clock"
    elseif widget_type == "battery" then
        widget_config.script = BIN_DIR .. "/widget_manager update battery"
    elseif widget_type == "system_info" then
        widget_config.script = BIN_DIR .. "/widget_manager update system_info"
    end

    -- Apply state-based settings
    local enabled = c_bridge.state.widget(name)
    widget_config.drawing = enabled and "on" or "off"

    -- Create the widget
    sbar.add("item", name, widget_config)

    -- Subscribe to events if needed
    if config.events then
        for _, event in ipairs(config.events) do
            sbar.subscribe(name, event)
        end
    end

    return name
end

-- Initialize C components
function c_bridge.init()
    -- Initialize state manager
    c_bridge.state.init()

    -- Pre-cache common icons
    local common_icons = {"apple", "clock", "battery", "wifi", "cpu", "memory"}
    for _, icon in ipairs(common_icons) do
        c_bridge.icons.get(icon, "")
    end

    -- Cache menus
    local menu_files = {"menu_apple", "menu_help", "menu_settings"}
    for _, menu in ipairs(menu_files) do
        c_bridge.menus.cache(menu)
    end

    return true
end

-- Check if C components are available
function c_bridge.check_components()
    local components = {
        icon_manager = "Icon management",
        state_manager = "State management",
        widget_manager = "Widget updates",
        menu_renderer = "Menu rendering"
    }

    local available = {}
    local missing = {}

    for component, description in pairs(components) do
        local path = BIN_DIR .. "/" .. component
        local file = io.open(path, "r")
        if file then
            file:close()
            table.insert(available, description)
        else
            table.insert(missing, component)
        end
    end

    return {
        available = available,
        missing = missing,
        all_present = #missing == 0
    }
end

return c_bridge