# Google C++ and SSH Cloud Workflows - Quick Summary

## What's New

Barista now includes comprehensive support for Google C++ development and SSH cloud workflows:

✅ **3 New Integration Modules**
- `cpp_dev.lua` - C++ development tools
- `ssh_cloud.lua` - SSH and cloud workflows  
- `google_cpp.lua` - Google-specific C++ tools

✅ **3 New Status Bar Widgets**
- `cpp_build_status` - Monitor CMake/Bazel/Make builds
- `ssh_connections` - Track active SSH connections
- `bazel_status` - Google Bazel build monitoring

✅ **3 New Menu Sections**
- C++ Dev - Build, test, debug tools
- SSH & Cloud - Connection management
- Google C++ - Gerrit, CodeSearch, Bazel

✅ **3 Helper Scripts**
- `cpp_project_switch.sh` - Switch between projects
- `ssh_sync.sh` - Sync files to/from remote
- `ci_status.sh` - Check CI/CD status

## Quick Setup

### 1. Enable in Work Profile

The work profile is already configured! Just ensure your `state.json` has:

```json
{
  "profile": "work",
  "integrations": {
    "cpp_dev": {"enabled": true},
    "ssh_cloud": {"enabled": true},
    "google_cpp": {"enabled": true}
  },
  "widgets": {
    "cpp_build_status": true,
    "ssh_connections": true,
    "bazel_status": true
  }
}
```

### 2. Configure Your Projects

**C++ Projects:**
```json
{
  "integrations": {
    "cpp_dev": {
      "project_path": "/Users/yourname/Code",
      "current_project": "my-project"
    }
  }
}
```

**Google3:**
```json
{
  "integrations": {
    "google_cpp": {
      "project_path": "/Users/yourname/google3",
      "current_target": "//path/to:target"
    }
  }
}
```

**SSH Connections:**
- Automatically loaded from `~/.ssh/config`
- Or configure manually in state.json

### 3. Use the Features

**Build Status:**
- Widget shows current build status
- Click for build details
- Menu: C++ Dev > Build/Test/Clean

**SSH Management:**
- Widget shows active connections
- Menu: SSH & Cloud > [Host Name]
- Auto-detects tmux sessions

**Google Tools:**
- Menu: Google C++ > Gerrit/CodeSearch/Bazel
- Quick access to code review
- Bazel commands in menu

## Menu Structure

```
Apple Menu
├── Emacs Workspace
├── halext-org
├── Google (Workspace)
├── C++ Dev ⭐ NEW
│   ├── Build (CMake/Bazel/Make)
│   ├── Run Tests
│   ├── Clean Build
│   ├── Switch Project
│   ├── Find Symbol
│   ├── Go to Definition
│   └── Start Debugger
├── SSH & Cloud ⭐ NEW
│   ├── [SSH Host 1]
│   ├── [SSH Host 2]
│   ├── GCP Console
│   ├── GCP Cloud Shell
│   ├── Sync to Remote
│   └── Sync from Remote
└── Google C++ ⭐ NEW
    ├── Gerrit (Code Review)
    ├── Critter
    ├── CodeSearch
    ├── G3 Documentation
    ├── Bazel Build
    ├── Bazel Test
    ├── Bazel Query
    └── CI/CD Status
```

## Widgets

### C++ Build Status
- **Icon**: Changes based on status
- **Label**: Shows build system and status
- **Colors**: 
  - Green = Built/Ready
  - Yellow = Building
  - Red = Not Built/Error

### SSH Connections
- **Icon**: SSH symbol
- **Label**: Number of active connections
- **Colors**:
  - Green = Connected
  - Yellow = Active
  - Red = Disconnected

### Bazel Status
- **Icon**: Bazel symbol
- **Label**: Build/test status
- **Colors**:
  - Green = Ready
  - Yellow = Building/Testing
  - Cyan = Bazel Server Running

## Common Workflows

### Starting Work on a C++ Project

1. Switch project: `cpp_project_switch.sh switch my-project`
2. Widget auto-detects build system
3. Use menu: C++ Dev > Build
4. Monitor status in widget

### Connecting to Remote Server

1. SSH connection appears in menu (from ~/.ssh/config)
2. Click to connect (auto-attaches to tmux if available)
3. Widget shows connection status
4. Use sync scripts to keep files in sync

### Google3 Development

1. Set `google_cpp.project_path` to your google3 directory
2. Use Google C++ menu for code review
3. Bazel widget monitors builds
4. Use Bazel commands from menu

## Helper Scripts

### Project Switching
```bash
# List projects
cpp_project_switch.sh list

# Switch project
cpp_project_switch.sh switch my-project
```

### File Sync
```bash
# Upload to remote
ssh_sync.sh up

# Download from remote
ssh_sync.sh down
```

### CI/CD Status
```bash
ci_status.sh show
```

## Configuration Examples

### Multiple C++ Projects
```json
{
  "integrations": {
    "cpp_dev": {
      "project_path": "/Users/name/Code",
      "current_project": "project-a"
    }
  }
}
```

### SSH with Custom Config
```json
{
  "integrations": {
    "ssh_cloud": {
      "connections": {
        "dev-server": {
          "hostname": "dev.example.com",
          "user": "developer",
          "tmux_session": "work"
        }
      }
    }
  }
}
```

### Google3 with CI
```json
{
  "integrations": {
    "google_cpp": {
      "project_path": "/Users/name/google3",
      "current_target": "//path/to:target",
      "ci_url": "https://ci.corp.google.com",
      "ci_project_id": "my-project"
    }
  }
}
```

## Tips & Tricks

1. **Quick Project Switch**: Use menu instead of command line
2. **SSH Auto-tmux**: Configure tmux_session in SSH config for auto-attach
3. **Build Monitoring**: Widget updates every 5 seconds
4. **Bazel Targets**: Use specific targets for faster builds
5. **Sync Exclusions**: Configure rsync to skip build artifacts

## Troubleshooting

**Widgets not showing?**
- Check `widgets` section in state.json
- Verify integration is enabled
- Reload: `sketchybar --reload`

**Build status wrong?**
- Check project path
- Verify build system detection
- Check script permissions

**SSH not connecting?**
- Verify SSH config format
- Check host connectivity
- Verify permissions

## Documentation

- **[Full Documentation](GOOGLE_CPP_WORKFLOWS.md)** - Complete guide
- **[Release Strategy](RELEASE_STRATEGY.md)** - Installation and updates
- **[Installation Guide](INSTALLATION_GUIDE.md)** - Setup instructions

## Next Steps

1. Configure your projects in state.json
2. Set up SSH connections
3. Enable widgets
4. Customize menu items
5. Start using the workflows!

---

**Questions?** Check the full documentation or open an issue on GitHub.

