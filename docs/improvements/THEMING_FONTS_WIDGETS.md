# Theming, Fonts & Widgets — Improvement Ideas

Review of the Barista repo with concrete ways to improve theming, fonts, and widgets. Use this as a backlog; implement in small, reversible steps.

---

## Completed (so far)

- **Theme contract** documented in [THEMES.md](../features/THEMES.md); required and optional keys listed.
- **All themes** now define `clock`, `volume`, `battery`; **halext** updated with required `DARK_WHITE`, `BG_PRI_COLR`, `BG_SEC_COLR`.
- **Theme validation script** `scripts/validate_theme.lua`: run `lua scripts/validate_theme.lua [theme_name]` to check required/optional keys. Use from repo root or set `BARISTA_CONFIG_DIR`.
- **Safe accent fallbacks**: `items_right.lua`, `items_left.lua`, `apple_menu_enhanced.lua`, `control_center.lua`, and `components/clock.lua` use a `tc(key, fallback)` (or inline `theme.X or theme.WHITE`) so themes that omit LAVENDER, SAPPHIRE, SKY, etc. don’t error.
- **Fonts subsection** in [CUSTOMIZATION.md](../guides/CUSTOMIZATION.md): icon font, text/numbers, and link to ICON_REFERENCE.md.
- **themes/README.md** added as a short pointer to the theme contract and validation.

---

## 1. Theming

### 1.1 Theme contract consistency

**Issue:** Themes define different keys. `default.lua` has `clock`, `volume`, `battery`; `mocha.lua` has `clock`, `volume` but no `battery`; `caramel.lua` and `white_coffee.lua` have `clock`, `volume` only. Code falls back to `theme.BG_SEC_COLR` when e.g. `theme.battery` is missing (`modules/widgets.lua`, `bar_config.lua`), but that can make battery look identical to other widgets.

**Improvements:**

- **Document the theme contract** in `docs/features/THEMES.md` (and/or in a `themes/README.md`):
  - Required: `bar.bg`, `WHITE`, `DARK_WHITE`, `BG_PRI_COLR`, `BG_SEC_COLR`
  - Optional but recommended for per-widget tint: `clock`, `volume`, `battery`, `system_info` (and any future right-side widgets)
- **Add missing keys to existing themes** so every theme defines the same optional widget colors (e.g. add `battery` to mocha, caramel, white_coffee using a theme-appropriate shade).
- **Optional:** Add a small Lua or script that validates a theme file has required keys and warns on missing optional ones (e.g. in `scripts/check_scripts.sh` or a dedicated `scripts/validate_theme.lua`).

### 1.2 Theme-driven popup and hover colors

**Issue:** Popup border/background and hover colors come from `state.appearance` (e.g. `popup_border_color`, `hover_color`) with theme used only as default in `bar_config.lua`. Themes don’t define hover/popup palettes, so switching theme doesn’t always feel cohesive.

**Improvements:**

- **Extend theme contract** with optional keys, e.g. `popup_border`, `popup_bg`, `hover_highlight`, `hover_border` (or reuse existing names). In `bar_config.compute()`, prefer `theme.popup_border` (if present) over a generic `theme.WHITE` when no state override is set.
- **Profile + theme:** Girlfriend profile already overrides many appearance keys. Document that profiles can override theme (and that `state.json` overrides both). Optionally, in the theme doc, list which appearance keys are “theme-like” vs “layout-like”.

### 1.3 Theme preview in Control Panel

**Issue:** Themes tab shows “Selected: &lt;name&gt; theme” and applies the theme but doesn’t show actual theme colors. `BaristaStyle` has `themeBarHex` but the preview box doesn’t reflect the palette.

**Improvements:**

- **Preview strip:** In `ThemesTabViewController`, when a theme is selected, parse the theme’s Lua (or a small JSON export) and show a row of color swatches (e.g. `bar.bg`, `WHITE`, `clock`, `volume`, `battery`) in the preview box so users see the palette before applying.
- **Apply feedback:** After “Apply Theme”, optionally set `appearance.bar_color` from `theme.bar.bg` only if the user hasn’t customised it (e.g. track “user set bar_color” in state or a separate key) so theme switch doesn’t overwrite manual bar color.

---

## 2. Fonts

### 2.1 Single source of truth for font sizes

**Issue:** Font sizes are computed in both `bar_config.lua` (icon/label/number/small) and inside `modules/widgets.lua` (e.g. `create_clock`, `create_battery`) with duplicated scale/bar_height logic. Changes in one place can get out of sync.

**Improvements:**

- **Use bar_config only:** Have widget factory receive `settings.font.sizes` and `font_string` from the shared bar config context (already passed in `items_right.lua` / `items_left.lua`) and never recompute font sizes inside `widgets.lua`. Remove duplicate scaling from `widgets.create_factory` so all numeric sizes come from `bar_config.compute()`.
- **Optional:** Add a `font_size_preset` in state (e.g. `compact` / `default` / `large`) that maps to a multiplier or fixed sizes in `bar_config`, so profiles (e.g. girlfriend) can say “large” without touching pixel values.

### 2.2 Font family and style flexibility

**Issue:** `bar_config.lua` uses a fixed `style_map` (Regular, Medium, Semibold, Bold, Heavy). Some fonts use different style names (e.g. “SemiBold” vs “Semibold”, or variable font axes). No per-widget font family override.

**Improvements:**

- **State or theme style_map override:** Allow `state.appearance.font_style_map` (or theme) to override or extend `style_map` so users can align names to their font (e.g. map “Semibold” → “SemiBold”). `bar_config` would merge this with the default map.
- **Per-widget font (optional):** For items that should differ (e.g. clock vs system info), support optional `appearance.font_clock`, `appearance.font_numbers` etc. in state, falling back to the global `font_numbers` / `font_text`. Use sparingly to avoid a large matrix of options.

### 2.3 Icon font fallback and icon_manager

**Issue:** `icon_manager.lua` has a clear priority list (Hack Nerd Font → SF Pro → SF Symbols → Menlo). The default bar font is “Hack Nerd Font” from state. If that font isn’t installed, icons can show as missing or wrong.

**Improvements:**

- **Font detection:** In installer or doctor script, check that at least one of `icon_manager.fonts` is available and report which font will be used for icons; suggest installing “Hack Nerd Font” (or another Nerd Font) if none are present.
- **Doc:** In README or CUSTOMIZATION.md, state that “icon” font in appearance is the primary icon font and that icon_manager falls back by availability; link to `docs/features/ICON_REFERENCE.md`.
- **Optional:** Allow `state.appearance.font_icon` to be a list (e.g. `["Hack Nerd Font", "SF Symbols"]`) parsed by bar_config so the first available is used; keeps a single source of truth while allowing fallback order per machine.

---

## 3. Widgets

### 3.1 Widget factory vs bar_config defaults

**Issue:** Right-side widgets are created via `widget_factory` in `items_right.lua` using context from `bar_config` (font_string, theme, settings), but `modules/widgets.lua`’s `create_clock`, `create_battery`, `create_volume`, `create_system_info` re-read `state_data.appearance` and recompute sizes/colors. So there are two paths: (1) bar_config defaults + item opts in items_right, and (2) widget factory’s own defaults. The factory’s `create_clock` / `create_battery` don’t receive theme widget colors from the theme passed in context; they use `theme.clock`, `theme.battery` from the factory’s closure. That’s consistent only if the factory is built with the same theme. In practice it is, but the duplication (bar_config vs factory) still makes changes harder.

**Improvements:**

- **Single defaults source:** Have widget factory only add items; all default properties (background color, corner radius, font, padding) should come from the shared context (bar_config + theme). So: `widget_factory.create_clock(config)` should only merge `config` onto `ctx.defaults` (or a widget-specific default block from bar_config) and not recompute bar_height, widget_height, or font sizes. That implies bar_config (or a small helper) exposes e.g. “clock_defaults” and “volume_defaults” built from theme + state.
- **Widget colors from theme + state:** Ensure every widget that supports a tint (clock, volume, battery, system_info) gets its color from `widget_color(name, theme[name] or theme.BG_SEC_COLR)` with `theme[name]` part of the theme contract (see 1.1).

### 3.2 Per-widget visibility and presets

**Issue:** Widget on/off is in `state.widgets` (e.g. `system_info`, `clock`, `volume`, `battery`, `network`). There’s no “widget preset” (e.g. “minimal right side: clock only”) beyond listing each widget. Profile can set `profile.widgets` but that’s a fixed list per profile.

**Improvements:**

- **Presets in state or profile:** Add optional `appearance.widget_preset` (e.g. `minimal` | `default` | `full`) that maps to a predefined `widgets` map, so one switch can enable “clock + battery” only without editing multiple keys. Could live in state or in profile; applying a preset would overwrite `state.widgets` for that preset’s keys.
- **GUI/TUI:** Expose preset in Control Panel and TUI (e.g. dropdown “Right side: Minimal / Default / Full”) that writes the corresponding `widgets` and optionally `appearance.theme` or font preset.

### 3.3 System info and calendar popup item styling

**Issue:** Calendar and system info popup items in `items_right.lua` use a mix of `theme.LAVENDER`, `theme.DARK_WHITE`, `theme.WHITE`, `theme.YELLOW`, `theme.SKY` etc. Themes like mocha or white_coffee don’t define all Catppuccin names (LAVENDER, SAPPHIRE, etc.); they define their own palette (e.g. MOCHA, LATTE). So code that references `theme.LAVENDER` can get nil and break or fall back incorrectly.

**Improvements:**

- **Theme contract for popups:** Document “accent” colors that popups use: e.g. header, secondary text, highlight. In theme files, either define the same semantic keys (e.g. `ACCENT_HEADER`, `ACCENT_HIGHLIGHT`) or map them: `LAVENDER = WHIPPED_CREAM` in mocha. Then in items_right (and any popup item list), use only keys that are part of the contract or that have a safe fallback (`theme.SAPPHIRE or theme.WHITE`).
- **Semantic names:** Prefer a small set of semantic keys (e.g. `popup_header_color`, `popup_label_color`, `popup_highlight_color`) in the theme contract and use those in calendar/system_info popup items so every theme only needs to define a few colors for popups.

---

## 4. Quick wins (minimal code)

- ~~Add `battery` to themes that are missing it~~ ✓ Done.
- In THEMES.md, add a “Theme contract” subsection listing required and optional keys and point theme authors to it.
- In `bar_config.lua`, when building defaults, use `theme.battery or theme.BG_SEC_COLR` (and similar) so a single fallback is explicit.
- In Appearance tab (or README), add one sentence that “Icon font” is used for all bar icons and that Nerd Fonts are recommended; link to install script or doctor.
- Run a quick audit: grep for `theme\.(LAVENDER|SAPPHIRE|SKY|YELLOW|PINK|…)` and ensure every theme used in the repo defines those or provide fallbacks in code to `theme.WHITE` / `theme.DARK_WHITE`.

---

## 5. Summary table

| Area        | Change                                                                 | Impact                          |
|------------|-------------------------------------------------------------------------|----------------------------------|
| Theme      | Document theme contract; add missing widget keys to all themes         | Consistency, fewer nil lookups   |
| Theme      | Optional theme keys for popup/hover                                    | Cohesive look when switching     |
| Theme      | Theme preview swatches in GUI                                          | Better UX when choosing theme    |
| Fonts      | Single source for font sizes (bar_config only)                          | Easier tuning, no drift          |
| Fonts      | Optional style_map / font_icon list in state                           | More font choices, fallbacks     |
| Fonts      | Doctor/installer check for icon font availability                      | Clear setup guidance             |
| Widgets    | Widget factory uses only context defaults, no recompute                | One place for dimensions/colors  |
| Widgets    | Widget presets (minimal/default/full) in state or profile              | Faster “right side” configuration|
| Widgets    | Popup colors use semantic theme keys + fallbacks                        | All themes work in popups        |

Implement in small steps: e.g. first theme contract + add missing keys, then font size consolidation, then optional theme preview in GUI.
