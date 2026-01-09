# Barista Documentation Index

**Status:** Experimental (hybrid C/Lua)
**Last Updated:** 2026-01-06

## Quick Links

- [README](../README.md) - Project overview
- [BUILD.md](BUILD.md) - Build instructions
- [CHANGELOG.md](CHANGELOG.md) - Version history

---

## Documentation Structure

### guides/
User-facing setup and usage guides.

| Document | Description |
|----------|-------------|
| [INSTALLATION_GUIDE.md](guides/INSTALLATION_GUIDE.md) | Complete installation walkthrough |
| [UPDATE_GUIDE.md](guides/UPDATE_GUIDE.md) | Safe upgrade procedures |
| [QUICK_START.md](guides/QUICK_START.md) | Get running in 5 minutes |
| [QUICK_REBUILD.md](guides/QUICK_REBUILD.md) | Rebuild commands reference |
| [QUICK_REFERENCE.md](guides/QUICK_REFERENCE.md) | Command cheat sheet |
| [PRE_SETUP_CHECKLIST.md](guides/PRE_SETUP_CHECKLIST.md) | Prerequisites checklist |
| [HANDOFF.md](guides/HANDOFF.md) | System overview and handoff notes |
| [CONTRIBUTING.md](guides/CONTRIBUTING.md) | Contribution guidelines |
| [GITHUB_SETUP.md](guides/GITHUB_SETUP.md) | GitHub distribution setup |
| [TUI_CONFIGURATION.md](guides/TUI_CONFIGURATION.md) | TUI setup and config |

### architecture/
System design and technical documentation.

| Document | Description |
|----------|-------------|
| [README.md](architecture/README.md) | Architecture overview |
| [ANALYSIS.md](architecture/ANALYSIS.md) | System analysis and notes |
| [DIAGRAMS.md](architecture/DIAGRAMS.md) | Visual diagrams |
| [CODE_ANALYSIS.md](architecture/CODE_ANALYSIS.md) | Codebase metrics and analysis |
| [CONTROL_PANEL_DESIGN.md](architecture/CONTROL_PANEL_DESIGN.md) | GUI architecture |
| [PORTABILITY_SUMMARY.md](architecture/PORTABILITY_SUMMARY.md) | Cross-platform notes |

### dev/
Implementation notes and engineering details.

| Document | Description |
|----------|-------------|
| [CLAUDE.md](dev/CLAUDE.md) | AI assistant context |
| [CMake_MIGRATION.md](dev/CMake_MIGRATION.md) | CMake migration notes |
| [DEBUGGING_ANALYSIS.md](dev/DEBUGGING_ANALYSIS.md) | Debugging notes |
| [FIXES_SUMMARY.md](dev/FIXES_SUMMARY.md) | Bug fixes summary |
| [IMPLEMENTATION_SUMMARY.md](dev/IMPLEMENTATION_SUMMARY.md) | Implementation notes |
| [IMPROVEMENTS.md](dev/IMPROVEMENTS.md) | Planned improvements |
| [SHARING.md](dev/SHARING.md) | Sharing/export notes |

### features/
Feature documentation and specifications.

| Document | Description |
|----------|-------------|
| [CONTROL_PANEL_V2.md](features/CONTROL_PANEL_V2.md) | Control panel user guide |
| [BARISTA_CONTROL_PANEL.md](features/BARISTA_CONTROL_PANEL.md) | Control panel architecture |
| [CONTROL_PANEL_PARITY.md](features/CONTROL_PANEL_PARITY.md) | Feature parity tracking |
| [BARISTA_LAUNCH_AGENT.md](features/BARISTA_LAUNCH_AGENT.md) | Launch agent documentation |
| [THEMES.md](features/THEMES.md) | Theme system and customization |
| [ICONS_AND_SHORTCUTS.md](features/ICONS_AND_SHORTCUTS.md) | Icon system and keyboard shortcuts |
| [ICON_REFERENCE.md](features/ICON_REFERENCE.md) | Icon library reference |
| [WHICHKEY_PLAN.md](features/WHICHKEY_PLAN.md) | Which-key implementation plan |
| [MENU_REDESIGN_PROPOSAL.md](features/MENU_REDESIGN_PROPOSAL.md) | Menu system redesign |
| [APPLE_MENU_TOOLS.md](features/APPLE_MENU_TOOLS.md) | Apple menu tools configuration |

### troubleshooting/
Issue resolution and fixes.

| Document | Description |
|----------|-------------|
| [ICON_FIXES_SUMMARY.md](troubleshooting/ICON_FIXES_SUMMARY.md) | Icon display fixes |
| [ICON_SYSTEM_DOCS.md](troubleshooting/ICON_SYSTEM_DOCS.md) | Icon system documentation |
| [QUICK_ICON_FIX.md](troubleshooting/QUICK_ICON_FIX.md) | Quick icon repairs |
| [FINAL_ICON_STATUS.md](troubleshooting/FINAL_ICON_STATUS.md) | Current icon status |
| [WIDGET_FIXES.md](troubleshooting/WIDGET_FIXES.md) | Widget troubleshooting |
| [YABAI_SCRIPTING_ADDITION.md](troubleshooting/YABAI_SCRIPTING_ADDITION.md) | Yabai scripting setup |
| [DISPLAYLINK_SPACES_FLAKE.md](troubleshooting/DISPLAYLINK_SPACES_FLAKE.md) | DisplayLink spaces flake notes |
| [SCRIPTS_PATHS.md](troubleshooting/SCRIPTS_PATHS.md) | Script path reference |

### release/
Release and distribution documentation.

| Document | Description |
|----------|-------------|
| [RELEASE_STRATEGY.md](release/RELEASE_STRATEGY.md) | Release planning |
| [RELEASE_SUMMARY.md](release/RELEASE_SUMMARY.md) | Release notes |
| [HOMEBREW_TAP.md](release/HOMEBREW_TAP.md) | Homebrew formula |
| [LICENSE_ANALYSIS.md](release/LICENSE_ANALYSIS.md) | Licensing details |

---

## Deployment

Use `./scripts/deploy.sh` in the repo to sync changes to `~/.config/sketchybar`:

```bash
./scripts/deploy.sh              # Full deploy with restart
./scripts/deploy.sh --dry-run    # Preview changes
./scripts/deploy.sh --no-restart # Deploy without restart
```

---

**Maintainer:** scawful
