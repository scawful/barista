# Barista Themes

Barista comes with a collection of carefully crafted color themes inspired by coffee culture and beyond.

## Available Themes

### Coffee Themes ☕

#### Default (Catppuccin Mocha)
The default theme featuring the beloved Catppuccin Mocha color palette.
- **Vibe**: Dark, purple-tinted, modern
- **Best for**: General use, coding at night
- **File**: `themes/default.lua`

#### Caramel
Warm golden browns and amber tones.
- **Vibe**: Cozy, warm, inviting
- **Colors**: Rich caramel, butterscotch, honey, cream
- **Best for**: Daytime productivity, warm lighting environments
- **File**: `themes/caramel.lua`

#### White Coffee (Flat White)
Creamy whites and light browns reminiscent of a flat white or latte.
- **Vibe**: Clean, minimal, sophisticated
- **Colors**: Milk, foam, cream, cappuccino
- **Best for**: Bright environments, minimal aesthetic lovers
- **File**: `themes/white_coffee.lua`

#### Chocolate
Rich dark browns and warm chocolatey tones.
- **Vibe**: Decadent, rich, cozy
- **Colors**: Dark chocolate, bittersweet, milk chocolate, cocoa
- **Best for**: Evening work, dark mode enthusiasts
- **File**: `themes/chocolate.lua`

#### Mocha
Medium browns with chocolate and coffee accents.
- **Vibe**: Balanced, warm, classic
- **Colors**: Espresso, mocha, latte, whipped cream
- **Best for**: All-day use, coffee shop vibes
- **File**: `themes/mocha.lua`

### Specialty Themes 🍓

#### Strawberry Matcha
Fresh pinks and vibrant greens.
- **Vibe**: Fresh, vibrant, playful
- **Colors**: Strawberry, rose, matcha, jade, sage
- **Best for**: Creative work, standing out
- **File**: `themes/strawberry_matcha.lua`

## How to Switch Themes

### Method 1: Edit theme.lua (Permanent)

Edit `theme.lua` in your barista config directory:

\`\`\`lua
-- Change "default" to your chosen theme name
local current_theme = "mocha"  -- or "caramel", "white_coffee", "chocolate", "strawberry_matcha"
local theme = require("themes." .. current_theme)

return theme
\`\`\`

Then reload SketchyBar:
\`\`\`bash
sketchybar --reload
\`\`\`

### Method 2: Via Control Panel (Coming Soon)

The control panel will include a theme selector in a future update.

### Method 3: Profile-Based Themes

You can set different themes for different profiles. Edit your profile file (e.g., `profiles/personal.lua`):

\`\`\`lua
return {
  name = "personal",
  description = "Personal development setup",

  -- Set theme for this profile
  theme = "caramel",  -- This profile uses caramel theme

  appearance = {
    -- other appearance settings...
  },

  -- rest of profile...
}
\`\`\`

## Creating Custom Themes

Want to create your own theme? It's easy!

1. Create a new file in `themes/` directory:
   \`\`\`bash
   touch ~/.config/sketchybar/themes/my_theme.lua
   \`\`\`

2. Use this template:

\`\`\`lua
-- My Custom Theme
-- Description of your theme

return {
  bar = {
    bg = 0xF0RRGGBB  -- Bar background color (with alpha)
  },
  clock = 0x80RRGGBB,   -- Clock widget background
  volume = 0x80RRGGBB,  -- Volume widget background

  -- Define your color palette
  COLOR_NAME = "0xFFRRGGBB",
  ANOTHER_COLOR = "0xFFRRGGBB",

  -- Standard colors (required)
  WHITE = "0xFFRRGGBB",        -- Main text color
  DARK_WHITE = "0xFFRRGGBB",   -- Secondary text color
  BG_PRI_COLR = "0xEERRGGBB",  -- Primary background
  BG_SEC_COLR = "0xFFRRGGBB",  -- Secondary background
}
\`\`\`

3. Activate your theme by editing `theme.lua`:
   \`\`\`lua
   local current_theme = "my_theme"
   \`\`\`

### Color Format

Colors use hexadecimal format with alpha channel:
- Format: `0xAARRGGBB`
- `AA` = Alpha (transparency): `00` (transparent) to `FF` (opaque)
- `RR` = Red: `00` to `FF`
- `GG` = Green: `00` to `FF`
- `BB` = Blue: `00` to `FF`

Examples:
- `0xFF000000` = Solid black
- `0xFFFFFFFF` = Solid white
- `0x80FF0000` = Semi-transparent red (50% opacity)
- `0xF0123456` = Custom color with 94% opacity

### Theme Palette Guidelines

For best results, your theme should include:

1. **Bar colors** (`bar.bg`): Background for the main bar
2. **Widget colors** (`clock`, `volume`, etc.): Individual widget backgrounds
3. **Text colors** (`WHITE`, `DARK_WHITE`): For readability
4. **Background colors** (`BG_PRI_COLR`, `BG_SEC_COLR`): For popups and menus
5. **Accent colors**: Theme-specific colors for variety

## Theme Showcase

Want to share your theme? Open a pull request or discussion on GitHub!

### Community Themes

(Space for community-contributed themes)

## Tips for Theme Creation

1. **Contrast**: Ensure text is readable against backgrounds
2. **Consistency**: Stick to a cohesive color palette (5-12 colors)
3. **Alpha channel**: Use transparency (`0x80` - `0xF0`) for modern glass effects
4. **Test**: Try your theme in different lighting conditions
5. **Inspiration**: Use tools like [coolors.co](https://coolors.co) or [color.adobe.com](https://color.adobe.com)

## Preview Your Theme

After changing themes, preview by:
1. Open the control panel (if available)
2. Check the apple menu (click the Apple icon)
3. Hover over widgets to see backgrounds
4. Open app menus to check popup colors

## Troubleshooting

**Theme not applying?**
- Make sure you reload SketchyBar: `sketchybar --reload`
- Check for syntax errors in your theme file: `lua -c ~/.config/sketchybar/themes/my_theme.lua`
- Verify the theme name matches the filename

**Colors look wrong?**
- Verify hex color format (`0xAARRGGBB`)
- Check alpha channel (first two digits after `0x`)
- Ensure `WHITE` and text colors have good contrast

**Want to reset to default?**
- Edit `theme.lua` and set: `local current_theme = "default"`
- Reload SketchyBar

## Future Enhancements

Planned features:
- [ ] Theme switcher in control panel
- [ ] Per-widget theme customization
- [ ] Dynamic theme switching based on time of day
- [ ] Theme preview before applying
- [ ] Import themes from URL
- [ ] Theme collections
