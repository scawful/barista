# Interface Extensions

Interface extensions are script-backed menu rows that can appear in the Apple
menu, the disabled front-app/yabai replacement area, the disabled Control
Center replacement area, or the LM Studio popup.

They are intended for machine-local tools. The committed default
`data/project_shortcuts.json` stays empty so personal apps do not appear on a
work or restricted Mac unless that machine opts into a local extension file.

## Surfaces

- `apple_menu`: rows in the Apple-menu `Extensions` section
- `front_app`: rows under the front-app popup `Desk` section when yabai controls are unavailable
- `control_center`: rows under the Control Center `Desk` section when yabai is disabled or unavailable
- `lmstudio`: model preset rows in the LM Studio popup
- `all`: all extension-aware surfaces

When yabai is disabled, Barista always provides a few safe Desk rows:
Mission Control, Barista Settings, and this guide. Local extension rows are
added below those rows.

## Local Install

```bash
cd ~/.config/sketchybar

# Personal Mac only. The output file is gitignored.
cp data/interface_extensions.personal.example.json data/interface_extensions.local.json

# Make sure this machine has the personal pack enabled.
python3 ./scripts/machine_profile.py apply --variant personal --report
```

For a work or restricted machine, leave `data/interface_extensions.local.json`
absent unless you have a work-safe extension pack to add.

## State Keys

```json
{
  "menus": {
    "extensions": {
      "enabled": true,
      "file": "data/interface_extensions.local.json",
      "files": [],
      "packs": [],
      "items": []
    }
  },
  "machine": {
    "menu_packs": ["core", "work", "restricted_safe"]
  }
}
```

`machine.menu_packs` comes from `scripts/machine_profile.py`. An extension with
`"pack": "personal"` only loads when `personal` is in `machine.menu_packs` or
`menus.extensions.packs`.

## Entry Schema

```json
{
  "id": "runbook",
  "pack": "work",
  "label": "Runbook",
  "icon": "󰘥",
  "icon_color": "0xff89dceb",
  "label_color": "0xffcdd6f4",
  "url": "https://example.com/runbook",
  "surfaces": ["apple_menu", "control_center"],
  "section": "work",
  "order": 100,
  "enabled": true
}
```

Action fields are checked in this order:

- `command` or `action`: shell command used as-is after path template expansion
- `url`: opens with `open`
- `path`: opens with `open`; relative paths resolve against the code directory
- `script` plus optional `args`: runs `bash <script> <args...>`

Templates available in string fields:

- `%CONFIG%` or `${CONFIG_DIR}`
- `%CODE%` or `${CODE_DIR}`
- `%HOME%` or `${HOME}`

Scripts receive:

- `BARISTA_EXTENSION_ID`
- `BARISTA_EXTENSION_PACK`

## Agent Upgrade Checklist

1. Keep personal app links out of committed defaults. Use
   `data/interface_extensions.local.json` for machine-local rows.
2. Add broadly useful examples to `data/interface_extensions.example.json`.
3. Add private/personal examples to `data/interface_extensions.personal.example.json`
   with `"pack": "personal"`.
4. Use `scripts/open_local_workflow.sh` for repo/app launchers when possible.
5. Run `lua tests/run_tests.lua tests/test_interface_extensions.lua tests/test_items.lua`
   after Lua surface changes.
6. Run `bash -n` on any changed shell scripts.

## LM Studio

The right-side LM Studio widget is opt-in by profile. Personal machines enable
it; minimal, cozy, work, and restricted variants disable it by default. The base
popup only exposes status/open/unload behavior. Model presets belong in
interface extensions on the `lmstudio` surface.
