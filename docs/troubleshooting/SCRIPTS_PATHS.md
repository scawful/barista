# Scripts Path Troubleshooting

## Symptoms

- skhd shortcuts do nothing
- Yabai actions in the bar do nothing
- Errors about missing `yabai_control.sh` or `toggle_shortcuts.sh`

## How Barista resolves scripts

1. `BARISTA_SCRIPTS_DIR` (environment variable)
2. `paths.scripts_dir` or `paths.scripts` in `state.json`
3. `~/.config/sketchybar/scripts` (preferred default)
4. `~/.config/scripts` (legacy fallback)

## Fix steps

1. Check resolved scripts path:
   - `~/.config/sketchybar/scripts/yabai_control.sh doctor`
   - `~/.config/sketchybar/bin/barista-health-check.sh`
2. If `~/.skhdrc` references `~/.config/scripts` and it is missing, either:
   - Update `~/.skhdrc` to use `~/.config/sketchybar/scripts`, or
   - Create a symlink:
     ```bash
     ln -sfn ~/.config/sketchybar/scripts ~/.config/scripts
     ```
3. If you want a custom scripts directory, set:
   - Control Panel → Advanced → Scripts Directory, or
   - `BARISTA_SCRIPTS_DIR`, or
   - `paths.scripts_dir` in `state.json`
4. Reload the bar: `sketchybar --reload`
5. If Control Panel actions still fail, verify helper scripts exist and are executable:
   - `set_appearance.sh`, `widget_toggle.sh`, `set_widget_color.sh`
   - `set_space_icon.sh`, `set_menu_icon.sh`, `set_clock_font.sh`
   - `toggle_system_info_item.sh`, `set_app_icon.sh`
   - `toggle_yabai_shortcuts.sh`, `runtime_update.sh`
   - Fix with `chmod +x <script>` or reinstall scripts.
6. If skhd shortcuts still do nothing, run the doctor with auto-fix:
   - `~/.config/sketchybar/scripts/yabai_control.sh doctor --fix`

## Notes

- Space switching requires the Yabai scripting addition for full functionality.
- `space-prev/next` fall back to AppleScript when the scripting addition is missing.
- Use Control Panel → Debug to run Yabai Doctor or restart shortcuts.
- skhd requires `.load "/Users/<user>/.config/skhd/barista_shortcuts.conf"` with double quotes.
- skhd parse errors are logged in `/tmp/skhd_<user>.err.log`.
