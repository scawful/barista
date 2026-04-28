# Work Machine Gemini Upgrade Guide

Use this path on managed/work Macs where Barista should stay debuggable without
building C/C++ helpers, running yabai, or launching a native Barista settings
app that needs approval.

## Target State

- Control panel uses the Python TUI
- Bar runtime uses the Lua fallback path
- Window-manager/yabai state is disabled
- Basic Work Apps menu rows are configurable through Python/shell scripts
- `state.json` is repaired to match installed fonts on the machine
- `barista-doctor` reports the resolved runtime backend and fonts

## Fresh Setup

```bash
cd ~/src/lab/barista

./scripts/setup_machine.sh \
  --yes \
  --restricted-work \
  --domain yourcompany.com

./scripts/barista-doctor.sh --fix --report
./scripts/barista-debug.sh --lua-only --reload
```

## Update Existing Install

```bash
cd ~/.config/sketchybar
./bin/barista-update --yes --target origin/main --skip-restart

./scripts/setup_machine.sh \
  --yes \
  --restricted-work \
  --domain yourcompany.com

./scripts/barista-doctor.sh --fix --report
./scripts/barista-debug.sh --lua-only --reload --logs
```

## Script-Only Customization

These commands do not require `jq`, Homebrew, yabai, or any compiled Barista
binary. They only require `/usr/bin/python3`.

```bash
# Re-apply the restricted defaults and default web-app rows.
./scripts/configure_restricted_work_barista.sh \
  --domain yourcompany.com \
  --replace

# Refresh only the Work Apps menu rows.
./scripts/configure_work_google_apps.sh \
  --domain yourcompany.com \
  --replace

# Add one custom row to the Apple menu.
python3 ./scripts/restricted_config.py menu-item \
  --label "Runbook" \
  --url "https://example.com/runbook" \
  --section work

# Inspect the current restricted-mode state.
python3 ./scripts/restricted_config.py summary
```

The restricted defaults write:

- `modes.window_manager = "disabled"`
- `modes.runtime_backend = "lua"`
- `modes.widget_daemon = "disabled"`
- `control_panel.preferred = "tui"`
- `toggles.yabai_shortcuts = false`
- `menus.work.apps_file = "data/work_apps.local.json"`

If the TUI dependencies are not installed, `bin/open_control_panel.sh` now stops
at the manual `state.json` / TUI docs fallback while `runtime_backend` is pinned
to `lua`; it does not try to build or launch the native panel.

## Font Repair Only

```bash
./scripts/barista-fonts.sh --report
./scripts/barista-fonts.sh --apply-state --report
```

This preserves valid configured fonts and only repairs missing families.

## Remote Upgrade From Another Mac

```bash
./scripts/update_work_mac.sh \
  --host user@work-mac.local \
  --target origin/main \
  --panel-mode tui \
  --runtime-backend lua \
  --work-domain yourcompany.com
```

## What Gemini Should Do

1. Pull or update the repo to the desired ref.
2. Run `setup_machine.sh --restricted-work --domain <domain> --yes`.
3. Run `barista-doctor.sh --fix --report`.
4. If the bar still looks wrong, run `barista-fonts.sh --apply-state --report`.
5. Reload with `barista-debug.sh --lua-only --reload`.

## Notes

- `modes.runtime_backend = "lua"` is persisted in `state.json`, so the fallback survives reloads and launchd restarts.
- `bin/open_control_panel.sh` automatically prefers the TUI when that runtime backend is pinned to Lua.
- `scripts/restricted_config.py` is intentionally Python-stdlib only. Use it for
  menu and state edits when the managed laptop does not have `jq` or TUI deps.
- If you later want compiled helpers again, run:

```bash
./scripts/barista-debug.sh --auto --reload
```
