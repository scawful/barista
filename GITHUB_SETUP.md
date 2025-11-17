# GitHub Setup Guide for barista ☕

Quick reference for uploading barista to GitHub.

## 1. Create GitHub Repository

```bash
# Create the repo
gh repo create barista --public --description "☕ Brewing the perfect macOS status bar experience"

# Or via web:
# https://github.com/new
# Repository name: barista
# Description: ☕ Brewing the perfect macOS status bar experience
# Public
# Don't initialize with README (we already have one)
```

## 2. Add Remote and Push

```bash
# Add remote
git remote add origin https://github.com/scawful/barista.git

# Push all commits
git push -u origin master

# Push tags (if any)
git push --tags
```

## 3. Create First Release

```bash
# Tag the release
git tag -a v1.0.0 -m "Initial public release - barista ☕"

# Push the tag
git push origin v1.0.0

# Create GitHub release with notes
gh release create v1.0.0 \
  --title "v1.0.0 - Initial Release ☕" \
  --notes "$(cat <<'NOTES'
# barista v1.0.0 - Initial Release

> Brewing the perfect macOS status bar experience ☕

## Features

### 🎨 Native Control Panel
- 6 specialized tabs for complete customization
- Live preview of all changes
- Native macOS Cocoa UI
- Persistent app (Shift+Click Apple menu to open)

### ⚡ Performance
- 10-50x faster than shell scripts (C/C++ helpers)
- Batched IPC commands
- Smart caching for integrations

### 🔧 Portable Profiles
- **minimal** - Clean template for new users
- **personal** - Full-featured with custom integrations
- **work** - Professional setup
- Easy custom profile creation

### 🔌 Integrations
- Yaze (ROM Hacking)
- Emacs (org-mode)
- halext-org ready (task management, calendar, LLM)

### 📱 70+ Menu Actions
- System controls, window management
- Yabai integration
- App launchers, dev utilities

## Quick Start

\`\`\`bash
# One-command install
curl -fsSL https://raw.githubusercontent.com/scawful/barista/master/install.sh | bash

# Or clone
git clone https://github.com/scawful/barista ~/.config/sketchybar
cd ~/.config/sketchybar
./install.sh
\`\`\`

## Documentation

- [README.md](README.md) - Complete overview
- [Control Panel Guide](docs/CONTROL_PANEL_V2.md)
- [Architecture Details](docs/IMPROVEMENTS.md)
- [Contributing](CONTRIBUTING.md)

## What's Next

- [ ] Screenshot gallery
- [ ] Video demos
- [ ] More profiles
- [ ] Homebrew tap for halext-org

Enjoy your new status bar! ☕
NOTES
)"
```

## 4. Set Repository Details

On GitHub web interface:
1. **Topics**: Add relevant tags
   - `sketchybar`
   - `macos`
   - `status-bar`
   - `yabai`
   - `lua`
   - `objective-c`
   - `productivity`
   - `dotfiles`

2. **About**: Fill in sidebar
   - ☕ Brewing the perfect macOS status bar experience
   - Website: (leave blank or add docs site later)
   - Topics: (add from list above)

3. **Social Preview**:
   - Upload a screenshot once you have one

## 5. Enable Features

In repository settings:
- ✅ Issues
- ✅ Discussions
- ✅ Wikis (optional)
- ✅ Projects (optional)

## 6. Share Installation Link

The installation link for Chris and others:

```bash
git clone https://github.com/scawful/barista ~/.config/sketchybar
cd ~/.config/sketchybar
./install.sh
```

Or one-liner:
```bash
curl -fsSL https://raw.githubusercontent.com/scawful/barista/master/install.sh | bash
```

## 7. Post-Upload Checklist

After pushing to GitHub:

- [ ] Verify README displays correctly
- [ ] Test installation script from raw URL
- [ ] Create first issue/discussion
- [ ] Add screenshot to README
- [ ] Share with Chris
- [ ] Tweet/blog about it (optional)
- [ ] Add to awesome lists (optional)

## Repository Structure

```
barista/
├── main.lua              # Entry point
├── theme.lua             # Theming
├── modules/              # Lua modules
│   ├── state.lua
│   ├── profile.lua
│   ├── widgets.lua
│   ├── menu.lua
│   └── integrations/
├── profiles/             # User profiles
│   ├── minimal.lua
│   ├── personal.lua
│   └── work.lua
├── plugins/              # Shell scripts
├── helpers/              # C/C++ performance
├── gui/                  # Objective-C control panel
├── docs/                 # Documentation
├── install.sh            # Installer
├── README.md
├── LICENSE
└── CONTRIBUTING.md
```

## Future: Homebrew Tap

When halext-org is ready:

```bash
# Create tap repository
gh repo create homebrew-halext --public

# Users will install with:
brew tap scawful/halext
brew install barista
```

See `docs/HOMEBREW_TAP.md` for complete strategy.

## Maintenance

### Updating Version

```bash
# Make changes
git add .
git commit -m "feat: awesome new feature"

# Tag new version
git tag -a v1.1.0 -m "Version 1.1.0"
git push origin master
git push origin v1.1.0

# Create release
gh release create v1.1.0 --generate-notes
```

### Managing Issues

- Use labels: `bug`, `enhancement`, `documentation`, `good first issue`
- Create issue templates in `.github/ISSUE_TEMPLATE/`
- Set up project board for tracking

---

**Ready to upload!** ☕

Run the commands in order and your barista will be brewing on GitHub!
