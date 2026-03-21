# Work Machine Gemini Upgrade Guide

Use this path on managed/work Macs where Barista should stay debuggable without building C/C++ helpers or `barista_config`.

## Target State

- Control panel uses the Python TUI
- Bar runtime uses the Lua fallback path
- `state.json` is repaired to match installed fonts on the machine
- `barista-doctor` reports the resolved runtime backend and fonts

## Fresh Setup

```bash
cd ~/src/lab/barista

./scripts/setup_machine.sh \
  --yes \
  --panel-mode tui \
  --runtime-backend lua

./scripts/barista-doctor.sh --fix --report
./scripts/barista-debug.sh --lua-only --reload
```

## Update Existing Install

```bash
cd ~/.config/sketchybar
./bin/barista-update --yes --target origin/main --skip-restart

./scripts/setup_machine.sh \
  --yes \
  --panel-mode tui \
  --runtime-backend lua

./scripts/barista-doctor.sh --fix --report
./scripts/barista-debug.sh --lua-only --reload --logs
```

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
2. Run `setup_machine.sh --panel-mode tui --runtime-backend lua --yes`.
3. Run `barista-doctor.sh --fix --report`.
4. If the bar still looks wrong, run `barista-fonts.sh --apply-state --report`.
5. Reload with `barista-debug.sh --lua-only --reload`.

## Notes

- `modes.runtime_backend = "lua"` is persisted in `state.json`, so the fallback survives reloads and launchd restarts.
- `bin/open_control_panel.sh` automatically prefers the TUI when that runtime backend is pinned to Lua.
- If you later want compiled helpers again, run:

```bash
./scripts/barista-debug.sh --auto --reload
```
