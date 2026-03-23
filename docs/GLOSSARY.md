# Barista Glossary

Use these terms consistently in docs, code reviews, and the config panel.

## Menu Popup

The large popup opened by clicking a bar item such as `apple_menu`, `control_center`, `clock`, or `system_info`.

## Popup Section

A grouped block of rows inside a menu popup.

Examples:
- `Apps`
- `Core Tools`
- `Controls`

Popup sections are the primary Apple-menu structure now.

## Legacy Fly-out Submenu

A nested hover-open popup attached to a row inside another popup.

These are still supported for older integrations, but they are no longer the main Apple-menu pattern.

## App Shortcut

A menu row in the Apple-menu `Apps` section, typically loaded from `data/project_shortcuts.json`.

Most app shortcuts launch a local app or tool directly. Legacy path-based entries can still open a Terminal tab, Finder, or VS Code when the JSON entry only provides a repo/workspace path.

## Space Chip

One `space.N` item in the spaces widget row.

Each space chip can have its own icon, layout mode, popup menu, and reorder behavior.
