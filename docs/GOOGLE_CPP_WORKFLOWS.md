# Google C++ and SSH Cloud Workflows

## Overview

Barista now includes comprehensive support for Google C++ development workflows and SSH cloud operations. This includes widgets, menu integrations, and helper scripts optimized for Google's development environment.

## Features

### C++ Development Integration

- **Build Status Widget**: Real-time monitoring of CMake, Bazel, or Make builds
- **Project Switcher**: Quick switching between C++ projects
- **Build System Detection**: Automatic detection of CMake, Bazel, or Make
- **Code Navigation**: Quick access to find symbol, go to definition
- **Debugger Integration**: Start debugger from menu

### SSH Cloud Workflows

- **SSH Connection Widget**: Monitor active SSH connections
- **Connection Manager**: Quick access to configured SSH hosts
- **Terminal Multiplexer Support**: tmux and screen integration
- **File Sync**: Sync files to/from remote servers
- **Cloud Service Integration**: GCP console and cloud shell access

### Google C++ Specific

- **Bazel Integration**: Google's build system support
- **Code Review Tools**: Gerrit and Critter integration
- **Code Search**: CodeSearch and G3 documentation
- **CI/CD Status**: Check build and test status

## Configuration

### Enable Integrations

Edit `~/.config/sketchybar/state.json`:

```json
{
  "profile": "work",
  "integrations": {
    "cpp_dev": {
      "enabled": true,
      "project_path": "/Users/yourname/Code",
      "current_project": "my-project",
      "build_system": "auto"
    },
    "ssh_cloud": {
      "enabled": true,
      "gcp_enabled": true,
      "sync_host": "remote-server",
      "sync_remote_path": "/remote/path",
      "sync_local_path": "/local/path",
      "connections": {
        "server1": {
          "hostname": "server1.example.com",
          "user": "username",
          "tmux_session": "main"
        }
      }
    },
    "google_cpp": {
      "enabled": true,
      "project_path": "/Users/yourname/google3",
      "current_target": "//...",
      "ci_url": "https://ci.example.com",
      "ci_project_id": "my-project"
    }
  },
  "widgets": {
    "cpp_build_status": true,
    "ssh_connections": true,
    "bazel_status": true
  }
}
```

## Widgets

### C++ Build Status Widget

Monitors build status for your current C++ project.

**Features:**
- Shows build system (CMake, Bazel, Make)
- Displays build status (Building, Built, Not Built)
- Color-coded status indicators
- Click to see build details

**Configuration:**
- Set `integrations.cpp_dev.current_project` in state.json
- Widget automatically detects build system

### SSH Connections Widget

Monitors active SSH connections.

**Features:**
- Shows number of active connections
- Lists connected hosts
- Color-coded status (green = connected, yellow = active, red = disconnected)
- Click to manage connections

### Bazel Status Widget

Monitors Bazel build status for Google3 projects.

**Features:**
- Shows Bazel server status
- Displays build/test progress
- Color-coded indicators
- Click for Bazel commands

## Menu Items

### C++ Development Menu

Access via: Apple Menu > C++ Dev

**Items:**
- **Build**: Build current project
- **Run Tests**: Execute test suite
- **Clean Build**: Clean build artifacts
- **Switch Project**: Change active project
- **Find Symbol**: Code navigation
- **Go to Definition**: Jump to definition
- **Start Debugger**: Launch debugger
- **Bazel Query** (if using Bazel): Query build graph
- **Bazel Info** (if using Bazel): Show build info

### SSH & Cloud Menu

Access via: Apple Menu > SSH & Cloud

**Items:**
- **SSH Connections**: List of configured hosts
- **GCP Console**: Open Google Cloud Platform console
- **GCP Cloud Shell**: Open cloud shell
- **Sync to Remote**: Upload files to remote
- **Sync from Remote**: Download files from remote

### Google C++ Menu

Access via: Apple Menu > Google C++

**Items:**
- **Gerrit**: Code review system
- **Critter**: Code review tool
- **CodeSearch**: Search codebase
- **G3 Documentation**: Internal documentation
- **Bazel Build**: Build with Bazel
- **Bazel Test**: Run tests
- **Bazel Query**: Query build graph
- **CI/CD Status**: Check build status

## Helper Scripts

### cpp_project_switch.sh

Switch between C++ projects.

```bash
# List available projects
~/.config/sketchybar/helpers/cpp_project_switch.sh list

# Switch to a project
~/.config/sketchybar/helpers/cpp_project_switch.sh switch my-project
```

### ssh_sync.sh

Sync files to/from remote servers.

```bash
# Sync local files to remote
~/.config/sketchybar/helpers/ssh_sync.sh up

# Sync remote files to local
~/.config/sketchybar/helpers/ssh_sync.sh down
```

**Configuration:**
Set in state.json:
- `integrations.ssh_cloud.sync_host`
- `integrations.ssh_cloud.sync_remote_path`
- `integrations.ssh_cloud.sync_local_path`

### ci_status.sh

Check CI/CD status.

```bash
~/.config/sketchybar/helpers/ci_status.sh show
```

## Workflow Examples

### Starting a New C++ Project

1. Create project directory: `mkdir ~/Code/my-project`
2. Initialize build system (CMake, Bazel, or Make)
3. Switch to project: `cpp_project_switch.sh switch my-project`
4. Widget will automatically detect build system
5. Use menu to build/test

### Working with Remote Servers

1. Configure SSH in `~/.ssh/config`
2. Barista automatically loads SSH hosts
3. Use SSH & Cloud menu to connect
4. Widget shows connection status
5. Use sync scripts to keep files in sync

### Google3 Development

1. Set `integrations.google_cpp.project_path` to your google3 directory
2. Set `integrations.google_cpp.current_target` to your Bazel target
3. Use Google C++ menu for code review and search
4. Bazel widget monitors build status
5. Use CI/CD status to check builds

## Customization

### Adding Custom Build Systems

Edit `modules/integrations/cpp_dev.lua`:

```lua
cpp_dev.build_systems.custom = {
  name = "Custom Build",
  icon = "󰨞",
  build_cmd = "custom-build",
  test_cmd = "custom-test",
  clean_cmd = "custom-clean",
}
```

### Adding Custom SSH Connections

Edit state.json:

```json
{
  "integrations": {
    "ssh_cloud": {
      "connections": {
        "my-server": {
          "hostname": "server.example.com",
          "user": "username",
          "tmux_session": "main"
        }
      }
    }
  }
}
```

### Custom Cloud Services

Edit state.json:

```json
{
  "integrations": {
    "ssh_cloud": {
      "cloud_services": [
        {
          "name": "custom-service",
          "label": "Custom Service",
          "icon": "󰨞",
          "action": "open -a 'Google Chrome' 'https://service.example.com'"
        }
      ]
    }
  }
}
```

## Troubleshooting

### Build Status Widget Not Updating

1. Check project path in state.json
2. Verify build system is detected
3. Check widget script permissions: `chmod +x plugins/cpp_build_status.sh`

### SSH Connections Not Showing

1. Verify SSH config file exists: `~/.ssh/config`
2. Check SSH config format
3. Ensure connections are properly formatted

### Bazel Widget Not Working

1. Verify google3 path in state.json
2. Check Bazel is installed: `which bazel`
3. Verify project path exists

## Best Practices

1. **Project Organization**: Keep projects in a consistent directory structure
2. **SSH Config**: Use SSH config file for connection management
3. **Build Targets**: Use specific Bazel targets instead of `//...` for faster builds
4. **Sync Exclusions**: Configure rsync exclusions to avoid syncing build artifacts
5. **Widget Updates**: Adjust update frequencies based on your needs

## Integration with Other Tools

### Emacs

The C++ development integration works well with Emacs:
- Use Emacs for code editing
- Use Barista widgets for build status
- Use menu items for quick actions

### VS Code / Cursor

Similar integration:
- Use editor for code
- Use Barista for build monitoring
- Use menu for project switching

### Terminal Multiplexers

SSH integration supports tmux and screen:
- Automatic tmux session detection
- Quick attach to existing sessions
- Create new sessions if needed

## Future Enhancements

Planned features:
- Build notification system
- Test result display
- Code coverage integration
- Remote build support
- Multi-project monitoring
- CI/CD webhook integration

