# Common Pitfalls and Solutions

This document tracks recurring technical issues discovered during development and maintenance of Barista and SketchyBar.

## 1. SketchyBar Initialization Race Conditions

### Issue
When using `sbar.exec` or `os.execute` to run `sketchybar --subscribe` commands during the initial configuration block, the items may not yet exist in the SketchyBar registry, leading to `[!] Subscribe: Item not found` errors.

### Guidance
- **Always use `sbar.add` or `sbar.default` within the `sbar.begin_config()` / `sbar.end_config()` block** for item creation.
- **Delay subscription commands**: If using `shell_exec` (outside the Lua API) to subscribe to events, add a small delay (e.g., `sleep 0.1`) or, preferably, move these calls to *after* the configuration block has finished.
- **Prefer Lua API**: Use the native Lua `subscribe` methods when available instead of calling the binary directly.

## 2. AWK Reserved Word Collisions

### Issue
Using the variable name `load` in `awk` scripts (e.g., `awk -v load="$VAL"`) can cause fatal errors on systems using `gawk` (GNU Awk), as `load` is a built-in function.
- **Error**: `awk: fatal: cannot use gawk builtin 'load' as variable name`

### Guidance
- **Avoid common keywords**: Do not use `load`, `print`, `split`, `index`, or `close` as variable names in `awk -v`.
- **Naming convention**: Use short, unambiguous names like `l` or `val`, or prefix them like `cpu_load`.

## 3. Invalid Property Errors

### Issue
SketchyBar is strict about properties passed to items. Using properties like `padding_top`, `padding_bottom`, or custom keys like `show_cpu` inside a `sbar.add` or `sbar.set` call will trigger internal errors and may prevent the bar from rendering.

### Guidance
- **Verify properties**: Check the SketchyBar documentation for valid properties for each item type.
- **Lua-side filtering**: If passing a configuration table to a factory function, ensure that non-SketchyBar keys are removed or handled before the final `sbar.add` call.

## 4. Caching and Overrides

### Issue
Using Lua's `require` to load user overrides (`barista_config.lua`) means the file is cached in `package.loaded`. Subsequent reloads of SketchyBar (which often just re-runs the Lua script) might not pick up changes to the config file.

### Guidance
- **Use `loadfile`**: For programmatic overrides intended to be edited by users, use `loadfile(path)` followed by `pcall`. This ensures the file is read fresh from disk on every execution.

## 5. Process Management

### Issue
Sometimes SketchyBar fails to appear even if `brew services` says it is running. This is often due to a "zombie" or dangling `sketchybar` process holding a lock or a display connection.

### Guidance
- **Force Kill**: Use `pkill -9 sketchybar` before restarting to ensure a clean slate.
- **Verify with Query**: Always run `sketchybar --query bar` to check if the bar has successfully rendered and is visible.
