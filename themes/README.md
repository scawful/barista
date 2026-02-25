# Barista themes

Color themes for the bar and popups. Each theme is a Lua module returning a table of colors.

## Contract

- **Required:** `bar` (with `bar.bg`), `WHITE`, `DARK_WHITE`, `BG_PRI_COLR`, `BG_SEC_COLR`
- **Optional (widget tint):** `clock`, `volume`, `battery` — semi-transparent backgrounds for those bar widgets. Omitted keys fall back to `BG_SEC_COLR`.

Popup and menu code use accent names (e.g. `LAVENDER`, `SAPPHIRE`, `SKY`, `YELLOW`). Themes can define a subset; the bar uses safe fallbacks to `WHITE` when a key is missing.

Full details: [docs/features/THEMES.md](../docs/features/THEMES.md).

## Validate a theme

From the repo root:

```bash
lua scripts/validate_theme.lua           # all themes in themes/
lua scripts/validate_theme.lua mocha   # single theme
```

Set `BARISTA_CONFIG_DIR` if your config lives elsewhere.

## Override locally

Optional file `themes/theme.local.lua` is merged over the active theme (see [theme.lua](../theme.lua)).
