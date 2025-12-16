# Barista Documentation Index

**Version:** 2.0 (Hybrid C/Lua Architecture)  
**Last Updated:** December 2025

## Quick Links

- [README](../README.md) - Getting started guide
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
| [WORK_MACBOOK_SETUP.md](guides/WORK_MACBOOK_SETUP.md) | Work machine configuration |
| [HANDOFF.md](guides/HANDOFF.md) | System overview and handoff notes |
| [CONTRIBUTING.md](guides/CONTRIBUTING.md) | Contribution guidelines |
| [GITHUB_SETUP.md](guides/GITHUB_SETUP.md) | GitHub distribution setup |

### architecture/
System design and technical documentation.

| Document | Description |
|----------|-------------|
| [ARCHITECTURE_ANALYSIS.md](architecture/ARCHITECTURE_ANALYSIS.md) | Comprehensive event flow and system analysis |
| [ARCHITECTURE_DIAGRAMS.md](architecture/ARCHITECTURE_DIAGRAMS.md) | Visual system diagrams |
| [ARCHITECTURE_README.md](architecture/ARCHITECTURE_README.md) | Architecture overview |
| [ARCHITECTURE_SUMMARY.txt](architecture/ARCHITECTURE_SUMMARY.txt) | Quick architecture summary |
| [CODE_ANALYSIS.md](architecture/CODE_ANALYSIS.md) | Codebase metrics and analysis |
| [CONTROL_PANEL_DESIGN.md](architecture/CONTROL_PANEL_DESIGN.md) | GUI architecture |
| [PORTABILITY_SUMMARY.md](architecture/PORTABILITY_SUMMARY.md) | Cross-platform notes |
| [REFACTOR_SUMMARY.md](architecture/REFACTOR_SUMMARY.md) | C/Lua refactor overview |
| [REFACTORING_SUMMARY.md](architecture/REFACTORING_SUMMARY.md) | Refactoring details |

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

### release/
Release and distribution documentation.

| Document | Description |
|----------|-------------|
| [RELEASE_STRATEGY.md](release/RELEASE_STRATEGY.md) | Release planning |
| [RELEASE_SUMMARY.md](release/RELEASE_SUMMARY.md) | Release notes |
| [HOMEBREW_TAP.md](release/HOMEBREW_TAP.md) | Homebrew formula |
| [LICENSE_ANALYSIS.md](release/LICENSE_ANALYSIS.md) | Licensing details |

### internal/
Development notes and internal documentation.

| Document | Description |
|----------|-------------|
| [IMPROVEMENTS.md](internal/IMPROVEMENTS.md) | Planned improvements |
| [FIXES_SUMMARY.md](internal/FIXES_SUMMARY.md) | Bug fixes summary |
| [DEBUGGING_ANALYSIS.md](internal/DEBUGGING_ANALYSIS.md) | Debugging notes |
| [SYNC_AUDIT.md](internal/SYNC_AUDIT.md) | Repository sync audit |
| [MENU_MIGRATION_PLAN.md](internal/MENU_MIGRATION_PLAN.md) | Menu migration notes |
| [HANDOFF_POPUP_FIXES.md](internal/HANDOFF_POPUP_FIXES.md) | Popup fix notes |
| [FINAL_RECOMMENDATIONS.md](internal/FINAL_RECOMMENDATIONS.md) | Implementation recommendations |
| [SYSTEM_FIXES.md](internal/SYSTEM_FIXES.md) | System-level fixes |
| [SHARING.md](internal/SHARING.md) | Sharing/export notes |
| [CMake_MIGRATION.md](internal/CMake_MIGRATION.md) | CMake migration notes |
| [GOOGLE_CPP_WORKFLOWS.md](internal/GOOGLE_CPP_WORKFLOWS.md) | Google C++ integration |
| [GOOGLE_WORKFLOWS_SUMMARY.md](internal/GOOGLE_WORKFLOWS_SUMMARY.md) | Workflow summary |

### meta/
Project meta-documentation.

| Document | Description |
|----------|-------------|
| [CLAUDE.md](meta/CLAUDE.md) | AI assistant context |
| [IMPLEMENTATION_SUMMARY.md](meta/IMPLEMENTATION_SUMMARY.md) | Implementation notes |
| [MIGRATION_NOTES.md](meta/MIGRATION_NOTES.md) | Migration documentation |
| [INTEGRATION_STATUS.md](meta/INTEGRATION_STATUS.md) | Integration tracking |

---

## Additional Resources

### Components (Experimental)
See [components/README.md](../components/README.md) for experimental modular widget architecture from the fusion branch.

### Deployment
Use `./deploy.sh` in the repo root to sync changes to `~/.config/sketchybar`:
```bash
./deploy.sh           # Full deploy with restart
./deploy.sh --dry-run # Preview changes
./deploy.sh --no-restart # Deploy without restart
```

---

**Maintainer:** scawful
