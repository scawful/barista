# barista

Local SketchyBar configuration plus helper tooling for a macOS menu bar setup. Experimental and workspace-specific.

## Status

- Experimental (hybrid C/Lua helpers + Lua config)
- Not packaged for public distribution; use locally

## What Lives Here

- **Lua config:** `main.lua`, `modules/`, `profiles/`, `themes/`
- **Helpers:** `scripts/` (deploy, rebuild, toggles)
- **Optional C helpers:** build via CMake (`CMakeLists.txt`)
- **TUI:** `tui/` configuration and helpers

## Quick Start (Local)

```bash
# Sync repo to ~/.config/sketchybar
./scripts/deploy.sh

# Rebuild optional helpers
./scripts/rebuild.sh
```

For a fresh install on a new machine, see `docs/guides/INSTALLATION_GUIDE.md`.
`./scripts/install.sh` is available but still references the GitHub repo; use it only if that flow is intentional.

## Build (Optional Helpers)

```bash
cmake -B build -S .
cmake --build build
```

## Docs

- `docs/INDEX.md` - Documentation map
- `docs/BUILD.md` - Build details
- `docs/guides/QUICK_START.md` - Quick start walkthrough
- `docs/guides/UPDATE_GUIDE.md` - Update procedures

## License

MIT (see `LICENSE`)
