# DisplayLink Spaces/Widgets Flake

## Summary
On multi-monitor setups that include a DisplayLink monitor, the SketchyBar layout intermittently collapses after initially rendering correctly. The bar briefly shows spaces/widgets on the focused display, then later only the Apple icon (menu) remains visible on some displays. Switching focus/desktop can temporarily restore items.

This doc captures the symptoms, suspected causes, and recent mitigations so future agents can reproduce and debug without re-learning the history.

## Symptoms
- On a DisplayLink monitor, SketchyBar shows only the Apple icon (menu) after a short delay.
- Initially, spaces/widgets can render correctly, then disappear or move to another display.
- Spaces sometimes appear only on the MacBook Pro display, while other monitors show only the Apple icon.
- Switching desktops/monitors can repopulate spaces/widgets temporarily.
- Behavior is inconsistent across displays (e.g., one external monitor shows widgets but no spaces).

## Environment Notes
- Multiple displays (at least 4 total) including a DisplayLink monitor.
- SketchyBar runs via `brew services`.
- Yabai is present and used for spaces mapping.
- `main.lua` sets `associated_display` for items based on display lists.

## Hypotheses
1. **Display association mismatch or late overrides**
   - Items render on the focused display, then a later refresh overrides associations using stale data.
   - SketchyBar display list vs. Yabai display list can be slightly out of sync during DisplayLink wake or hot-plug.

2. **Yabai space data incomplete during DisplayLink wake**
   - `yabai -m query --spaces` returns an incomplete list temporarily.
   - Spaces are created with incomplete display associations then later reattached, causing visibility gaps.

3. **Event timing and refresh race**
   - Rapid display/space events cause refreshes that race and momentarily collapse to Apple-only.
   - `space_change` triggers were previously not refreshing the space list, requiring manual focus changes.

## Recent Mitigations (commits)
- `caf1c45` Speed up space loading and reduce layout churn
- `176547a` Anchor spaces after front_app once ready
- `d4f9aaf` Stabilize display targeting and space rendering
  - `main.lua`: `associated_display` now uses SketchyBar display list first, then Yabai, then `active`.
  - `plugins/simple_spaces.sh`: if Yabai data misses displays, temporarily attach spaces to `active` display and retry.
- `1f250c9` Refresh spaces on focus changes
  - `space_change` now triggers a refresh to avoid needing manual desktop switches.

## Relevant Files
- `main.lua`
  - `get_associated_displays()`
  - `watch_spaces()` (Yabai signal handlers)
  - initial `refresh_spaces()` and delayed refresh
- `plugins/simple_spaces.sh`
  - builds all `space.*` items and their display associations
  - retry and fallback logic when Yabai space data is incomplete
- `plugins/refresh_spaces.sh`
  - cache/lock logic controlling when space rebuilds happen
- `plugins/space.sh`
  - per-space item update; active space layout enforcement

## Known Behaviors
- Spaces often show immediately after reload, then disappear on DisplayLink monitors.
- Switching to another display or space can repopulate items.

## Diagnostics
Run these when the issue happens:

```
# Check the bar’s item order and whether items exist
sketchybar --query bar | head -n 80

# Check which displays SketchyBar sees
sketchybar --query displays | jq -r '.[] | "id=\(."arrangement-id") frame=\(.frame.x),\(.frame.y)"'

# Check Yabai display focus and ordering
yabai -m query --displays | jq -r '.[] | "idx=\(.index) frame=\(.frame.x),\(.frame.y) has_focus=\(."has-focus")"'

# Inspect item association masks
sketchybar --query apple_menu | rg -n "associated_display_mask|associated_space_mask|ignore_association"
sketchybar --query clock | rg -n "associated_display_mask|associated_space_mask|ignore_association"
```

If only Apple is visible on the active display, compare the `associated_display_mask` of a right-side widget (e.g., `clock`) against the active display ID. If the mask excludes the focused display, the item will not render there.

## Suggested Next Debug Steps
1. **Log actual display IDs used during refresh**
   - Add debug prints in `main.lua` after `get_associated_displays()` and in `plugins/simple_spaces.sh` when `fallback_active` triggers.

2. **Force per-display association after focus changes**
   - On `front_app_switched` or `space_change`, explicitly set `associated_display=active` for left/right anchors (e.g., `front_app`, `space_mode`, `clock`) and reapply when Yabai reports full space list.

3. **Capture timing of refresh events**
   - Temporarily log when `refresh_spaces.sh` runs and what `yabai -m query --spaces` returns.

4. **Consider disabling association caching for DisplayLink**
   - If the display list is unstable on wake, consider using `associated_display=active` for widgets and only use per-display association for spaces.

## Notes
- This issue is intermittent and timing-sensitive. Repro is strongest after display sleep/wake or monitor re-plug.
- If debugging live, trigger a refresh with `sketchybar --reload` and then quickly switch monitors to catch the transition.
