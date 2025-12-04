# Final Recommendations Before Work MacBook Setup

## Top 5 Critical Checks

### 1. ⚠️ Corporate Policy Compliance
**Most Important:** Verify your company allows:
- Installing software from GitHub
- Using Homebrew (or use git clone method)
- Modifying Accessibility permissions
- Running custom launch agents

**Action:** Check with IT or review company policy before starting.

### 2. ✅ Backup Everything First
```bash
# Quick backup script
mkdir -p ~/barista-backup-$(date +%Y%m%d)
cp -r ~/.config/sketchybar ~/barista-backup-$(date +%Y%m%d)/ 2>/dev/null || true
cp ~/.ssh/config ~/barista-backup-$(date +%Y%m%d)/ 2>/dev/null || true
```

### 3. 🧪 Test Installation Method
**Before full install, test:**
```bash
# Test git clone (if Homebrew not allowed)
git clone --depth 1 https://github.com/scawful/barista /tmp/barista-test
rm -rf /tmp/barista-test && echo "✅ Git access works"

# Test network access
curl -I https://github.com/scawful/barista | head -1
```

### 4. 🔒 Verify Permissions Access
**Can you grant:**
- Accessibility permissions? (Required)
- Screen Recording? (If using Yabai)
- Launch agents? (Optional but recommended)

**Test:** Try granting a permission manually in System Settings first.

### 5. 📦 Check Dependencies
```bash
# Required
which lua jq cmake || echo "⚠️  Need to install dependencies"

# Optional but recommended
which sketchybar yabai skhd || echo "ℹ️  Will be installed"
```

## Recommended Installation Strategy

### Phase 1: Minimal Test (30 minutes)
1. Install with `minimal` profile
2. Test basic functionality
3. Verify no conflicts
4. **Don't customize yet!**

### Phase 2: Add Work Features (Day 2)
1. Switch to `work` profile
2. Enable C++ dev integration
3. Configure one project
4. Test build status widget

### Phase 3: Full Setup (Week 1)
1. Add SSH connections
2. Enable Google C++ tools
3. Customize menu items
4. Fine-tune appearance

## Work-Specific Considerations

### If Behind Corporate Firewall
- ✅ Use git clone method (no Homebrew needed)
- ✅ May need to configure proxy
- ✅ Test GitHub access first
- ✅ Download dependencies manually if needed

### If VPN Required
- ✅ Connect VPN before using Google tools
- ✅ Configure SSH to work through VPN
- ✅ Test internal tools (Gerrit, CodeSearch) after VPN

### If Security Software Present
- ✅ May need to whitelist `~/.config/sketchybar/`
- ✅ Scripts may need approval
- ✅ Check with IT if scripts are blocked

## Quick Start Commands

### Installation (Git Clone - Recommended for Work)
```bash
# Clone repository
git clone https://github.com/scawful/barista ~/.config/sketchybar
cd ~/.config/sketchybar

# Install
./install.sh

# Setup permissions
./helpers/setup_permissions.sh

# Start
sketchybar --reload
```

### Configuration
```bash
# Edit state.json
code ~/.config/sketchybar/state.json
# Or: vim ~/.config/sketchybar/state.json

# Set work profile
# Change "profile": "minimal" to "profile": "work"
```

## What to Test First

### 1. Basic Bar Visibility
- [ ] Bar appears in menu bar
- [ ] Clock widget shows time
- [ ] Battery widget shows (if applicable)

### 2. Control Panel
- [ ] Shift + Click Apple menu icon opens panel
- [ ] Can navigate tabs
- [ ] Settings save correctly

### 3. Menu System
- [ ] Apple menu has new sections
- [ ] Menu items execute correctly
- [ ] No errors in logs

### 4. Widgets
- [ ] C++ build status updates
- [ ] SSH connections show status
- [ ] Bazel status works (if using)

## Common Pitfalls to Avoid

### ❌ Don't Skip Permissions
**Problem:** Widgets won't work without Accessibility permissions
**Solution:** Run `setup_permissions.sh` immediately after install

### ❌ Don't Customize Too Fast
**Problem:** Hard to debug if something breaks
**Solution:** Test minimal setup first, add features gradually

### ❌ Don't Forget Backups
**Problem:** Can't rollback if something goes wrong
**Solution:** Backup before any major changes

### ❌ Don't Ignore Errors
**Problem:** Small errors can cause bigger issues
**Solution:** Check logs, fix issues before proceeding

### ❌ Don't Skip Testing
**Problem:** May not work in your environment
**Solution:** Test each component before relying on it

## Rollback Plan

### If Something Goes Wrong

**Quick Disable:**
```bash
# Stop SketchyBar
brew services stop sketchybar
# Or: launchctl bootout gui/$(id -u)/homebrew.mxcl.sketchybar
```

**Full Removal:**
```bash
# Remove everything
rm -rf ~/.config/sketchybar
rm ~/Library/LaunchAgents/dev.barista.control.plist

# Restore from backup
cp -r ~/barista-backup-*/sketchybar ~/.config/ 2>/dev/null || true
```

## Success Criteria

You'll know it's working when:

1. ✅ Bar appears in menu bar
2. ✅ Widgets update automatically
3. ✅ Control panel opens and works
4. ✅ Menu items execute correctly
5. ✅ No errors in logs
6. ✅ Build status widget shows project status
7. ✅ SSH connections load from config
8. ✅ Google tools accessible from menu

## Getting Help

### Documentation
- **Pre-Setup Checklist**: `docs/PRE_SETUP_CHECKLIST.md`
- **Work Setup Guide**: `docs/WORK_MACBOOK_SETUP.md`
- **Workflows Guide**: `docs/GOOGLE_CPP_WORKFLOWS.md`

### Logs
```bash
# SketchyBar logs
tail -f ~/Library/Logs/sketchybar/sketchybar.log

# Launch agent logs
tail -f /tmp/barista.control.out.log
```

### Common Issues
- Check `docs/PRE_SETUP_CHECKLIST.md` troubleshooting section
- Review logs for error messages
- Verify permissions are granted
- Test with minimal profile first

## Final Checklist

Before you start installation:

- [ ] Reviewed corporate policies
- [ ] Backed up existing configs
- [ ] Tested network access
- [ ] Verified permissions can be granted
- [ ] Checked dependencies
- [ ] Chosen installation method
- [ ] Have rollback plan ready
- [ ] Read pre-setup checklist
- [ ] Have 30-60 minutes for initial setup
- [ ] Ready to test gradually

## My Recommendation

**For work MacBook, I recommend:**

1. **Start with git clone method** (more control, no Homebrew needed)
2. **Use minimal profile first** (test basic functionality)
3. **Add one feature at a time** (easier to debug)
4. **Keep backups** (before any major changes)
5. **Test thoroughly** (before relying on it for work)

**Timeline:**
- Day 1: Install and test basic functionality
- Day 2: Add C++ development features
- Day 3: Configure SSH connections
- Week 1: Customize and fine-tune

**Don't rush!** Take time to test each component. It's better to set it up correctly over a few days than to have issues during important work.

---

**Ready?** Start with `docs/PRE_SETUP_CHECKLIST.md` and work through it methodically!

Good luck! 🚀

