# Contributing to SketchyBar Configuration

Thank you for your interest in contributing! This document provides guidelines and instructions for contributing to this project.

## Code of Conduct

- Be respectful and constructive
- Help others learn and grow
- Focus on what is best for the community
- Show empathy towards other community members

## How to Contribute

### Reporting Bugs

Before creating bug reports, please check existing issues. When creating a bug report, include:

- **Clear title and description**
- **Steps to reproduce**
- **Expected vs actual behavior**
- **Screenshots** (if applicable)
- **Environment details**:
  - macOS version
  - SketchyBar version
  - Configuration profile
  - Relevant logs

### Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues. When creating an enhancement suggestion, include:

- **Clear use case**
- **Expected behavior**
- **Why this enhancement would be useful**
- **Examples** from other projects (if applicable)

### Pull Requests

1. **Fork the repo** and create your branch from `master`
2. **Make your changes**:
   - Follow existing code style
   - Add tests if applicable
   - Update documentation
3. **Test thoroughly**:
   - Test with different profiles
   - Check for memory leaks in C code
   - Verify no performance regressions
4. **Commit your changes**:
   - Use clear, descriptive commit messages
   - Reference issues in commits
5. **Submit pull request**

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/sketchybar-config
cd sketchybar-config

# Install dependencies
brew install sketchybar lua jq

# Build
make -C helpers clean && make -C helpers
make -C gui clean && make -C gui all

# Test
sketchybar --reload
```

## Project Structure

```
├── main.lua              # Entry point
├── theme.lua             # Theme definitions
├── modules/              # Lua modules
│   ├── state.lua         # State management
│   ├── profile.lua       # Profile system
│   ├── widgets.lua       # Widget factory
│   ├── menu.lua          # Menu rendering
│   └── integrations/     # Integration modules
├── profiles/             # User profiles
├── plugins/              # Shell script plugins
├── helpers/              # C/C++ performance helpers
├── gui/                  # Objective-C control panel
└── docs/                 # Documentation
```

## Coding Standards

### Lua

```lua
-- Use 2-space indentation
-- snake_case for functions and variables
-- Module pattern

local my_module = {}

function my_module.do_something(param)
  -- Implementation
end

return my_module
```

### C/C++

```c
// K&R brace style
// snake_case for functions
// 2-space indentation

static void my_function(const char *param) {
  // Implementation
}
```

### Objective-C

```objc
// Apple conventions
// camelCase for methods
// Properties with @property

@interface MyClass : NSObject
@property (strong) NSString *myProperty;
- (void)myMethod;
@end
```

## Testing

### Manual Testing

1. **Test all profiles**:
   ```bash
   # Edit state.json
   { "profile": "minimal" }
   { "profile": "personal" }
   { "profile": "work" }
   sketchybar --reload
   ```

2. **Test control panel**:
   - Shift-click Apple menu
   - Navigate all 6 tabs
   - Make changes and verify they persist

3. **Test menu actions**:
   - Hover over menu items
   - Click actions
   - Verify submenus open/close properly

### Performance Testing

```bash
# Measure hover latency
time ~/.config/sketchybar/helpers/popup_hover menu.item on

# Check memory usage
ps aux | grep sketchybar

# Profile with Instruments (macOS)
# Use Time Profiler template
```

## Documentation

### Update Documentation When:

- Adding new features
- Changing existing behavior
- Adding new modules or integrations
- Updating installation steps

### Documentation Files:

- `README.md` - Overview and quick start
- `docs/CONTROL_PANEL_V2.md` - Control panel guide
- `docs/IMPROVEMENTS.md` - Architecture details
- Inline code comments for complex logic

## Commit Message Guidelines

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

- **feat**: New feature
- **fix**: Bug fix
- **docs**: Documentation only
- **style**: Code style (formatting, no logic change)
- **refactor**: Code refactoring
- **perf**: Performance improvement
- **test**: Adding tests
- **chore**: Maintenance tasks

### Examples

```
feat(menu): Add halext-org integration menu

Add submenu for halext-org with tasks, calendar, and LLM suggestions.
Includes configuration UI in control panel Integrations tab.

Closes #123
```

```
fix(helpers): Increase submenu hover delay to 0.25s

The previous 0.15s delay was too short, causing inconsistent behavior
when quickly moving between submenus. Increased to 0.25s for better UX.

Fixes #456
```

## Adding Integrations

To add a new integration:

1. **Create integration module**:
   ```bash
   cp modules/integrations/halext.lua modules/integrations/myint.lua
   ```

2. **Update module**:
   ```lua
   -- modules/integrations/myint.lua
   local myint = {}

   function myint.get_data(config)
     -- Fetch data
   end

   function myint.format_for_menu(data)
     -- Format for display
   end

   return myint
   ```

3. **Add to profiles**:
   ```lua
   -- profiles/personal.lua
   profile.integrations = {
     myint = true,
   }
   ```

4. **Add menu items**:
   ```lua
   -- modules/menu.lua
   local function myint_items(ctx)
     return {
       { type = "item", name = "menu.myint.action", icon = "", label = "Action" }
     }
   end
   ```

5. **Update state defaults**:
   ```lua
   -- modules/state.lua
   integrations = {
     myint = {
       enabled = false,
       config_key = "value",
     }
   }
   ```

6. **Add to control panel** (optional):
   ```objc
   // gui/config_menu_v2.m
   // Add section to IntegrationsTabViewController
   ```

7. **Document**:
   - Add to README.md
   - Create docs/INTEGRATION_MYINT.md

## Release Process

1. Update version in relevant files
2. Update CHANGELOG.md
3. Create git tag: `git tag -a v1.0.0 -m "Version 1.0.0"`
4. Push tag: `git push origin v1.0.0`
5. Create GitHub release with notes

## Questions?

- Open a [discussion](https://github.com/scawful/sketchybar-config/discussions)
- Comment on relevant issue
- Reach out to maintainers

Thank you for contributing! 🎉
