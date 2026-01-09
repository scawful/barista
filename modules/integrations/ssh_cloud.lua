-- SSH Cloud Workflow Integration for Barista
-- Provides widgets and menu items for SSH and cloud development

local ssh_cloud = {}

ssh_cloud.enabled = false
ssh_cloud.config = {}

-- Default SSH connections
ssh_cloud.connections = {}

-- Terminal multiplexer support
ssh_cloud.multiplexers = {
  tmux = {
    name = "tmux",
    icon = "󰆍",
    new_session = "tmux new-session -d -s",
    attach = "tmux attach -t",
    list_sessions = "tmux list-sessions",
  },
  screen = {
    name = "screen",
    icon = "󰆍",
    new_session = "screen -dmS",
    attach = "screen -r",
    list_sessions = "screen -ls",
  },
}

function ssh_cloud.init(sbar, config)
  if not config.integrations or not config.integrations.ssh_cloud then
    return
  end
  
  local ssh_config = config.integrations.ssh_cloud
  if not ssh_config.enabled then
    return
  end
  
  ssh_cloud.enabled = true
  ssh_cloud.config = ssh_config
  
  -- Load SSH connections from config
  if ssh_config.connections then
    ssh_cloud.connections = ssh_config.connections
  end
  
  -- Load from SSH config file
  local ssh_config_file = os.getenv("HOME") .. "/.ssh/config"
  if os.execute("test -f " .. ssh_config_file) == 0 then
    ssh_cloud.load_ssh_config(ssh_config_file)
  end
  
  print("SSH Cloud integration enabled")
end

-- Parse SSH config file
function ssh_cloud.load_ssh_config(config_file)
  local file = io.open(config_file, "r")
  if not file then
    return
  end
  
  local current_host = nil
  for line in file:lines() do
    line = line:match("^%s*(.-)%s*$")  -- trim
    if line:match("^Host ") then
      current_host = line:match("^Host%s+(.+)$")
      if current_host and current_host ~= "*" then
        ssh_cloud.connections[current_host] = {
          name = current_host,
          host = current_host,
        }
      end
    elseif current_host and line:match("^HostName ") then
      local hostname = line:match("^HostName%s+(.+)$")
      if ssh_cloud.connections[current_host] then
        ssh_cloud.connections[current_host].hostname = hostname
      end
    elseif current_host and line:match("^User ") then
      local user = line:match("^User%s+(.+)$")
      if ssh_cloud.connections[current_host] then
        ssh_cloud.connections[current_host].user = user
      end
    end
  end
  
  file:close()
end

function ssh_cloud.get_menu_items(ctx)
  if not ssh_cloud.enabled then
    return {}
  end
  
  local items = {}
  
  table.insert(items, {
    type = "header",
    name = "menu.ssh.header",
    label = "SSH & Cloud",
  })
  
  -- SSH Connections
  local connection_count = 0
  for name, conn in pairs(ssh_cloud.connections) do
    connection_count = connection_count + 1
    local host = conn.hostname or conn.host or name
    local user = conn.user or os.getenv("USER")
    local ssh_cmd = string.format("ssh %s@%s", user, host)
    
    -- Check if tmux session exists
    local tmux_session = conn.tmux_session or name
    local has_tmux = os.execute("ssh -o ConnectTimeout=2 " .. user .. "@" .. host .. " 'command -v tmux > /dev/null 2>&1'") == 0
    
    if has_tmux then
      table.insert(items, {
        type = "item",
        name = "menu.ssh." .. name,
        icon = "󰆍",
        label = name .. " (" .. host .. ")",
        action = string.format("osascript -e 'tell application \"Terminal\" to do script \"%s -t %s || %s\"'", 
          ssh_cmd, tmux_session, ssh_cmd),
      })
    else
      table.insert(items, {
        type = "item",
        name = "menu.ssh." .. name,
        icon = "󰆍",
        label = name .. " (" .. host .. ")",
        action = string.format("osascript -e 'tell application \"Terminal\" to do script \"%s\"'", ssh_cmd),
      })
    end
  end
  
  if connection_count == 0 then
    table.insert(items, {
      type = "item",
      name = "menu.ssh.configure",
      icon = "󰈙",
      label = "Configure SSH Connections",
      action = ctx.open_path(os.getenv("HOME") .. "/.ssh/config"),
    })
  end
  
  table.insert(items, { type = "separator", name = "menu.ssh.sep1" })
  
  -- Cloud Services
  if ssh_cloud.config.cloud_services then
    for _, service in ipairs(ssh_cloud.config.cloud_services) do
      table.insert(items, {
        type = "item",
        name = "menu.cloud." .. service.name,
        icon = service.icon or "󰨞",
        label = service.label or service.name,
        action = service.action or "",
      })
    end
  end
  
  -- Remote file operations
  table.insert(items, { type = "separator", name = "menu.ssh.sep2" })
  table.insert(items, {
    type = "item",
    name = "menu.ssh.sync_up",
    icon = "󰈐",
    label = "Sync to Remote",
    action = ctx.call_script(ctx.scripts.ssh_sync or "", "up"),
  })
  table.insert(items, {
    type = "item",
    name = "menu.ssh.sync_down",
    icon = "󰈑",
    label = "Sync from Remote",
    action = ctx.call_script(ctx.scripts.ssh_sync or "", "down"),
  })
  
  return items
end

-- Create SSH connection widget
function ssh_cloud.create_connection_widget(sbar, factory, theme, state_data)
  if not ssh_cloud.enabled then
    return nil
  end
  
  local widget = factory.create("ssh_connections", {
    icon = "󰆍",
    label = "SSH",
    update_freq = 30,
    script = os.getenv("HOME") .. "/.config/sketchybar/plugins/ssh_status.sh",
    click_script = [[sketchybar -m --set $NAME popup.drawing=toggle]],
    popup = {
      background = {
        border_width = 2,
        corner_radius = 4,
        border_color = theme.WHITE,
        color = theme.bar.bg,
      }
    }
  })
  
  return widget
end

return ssh_cloud
