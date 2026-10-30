# barista-agent

The Barista dock: a SwiftPM executable that replaces the macOS Dock with an
auto-hiding dock themed like the bar. User-facing behavior and the
`dock.json` format are in
[`docs/architecture/NATIVE_LAYERS.md`](../../docs/architecture/NATIVE_LAYERS.md);
this file covers the code.

Requires macOS 14 (`NSView.displayLink`) and Swift 5.10 or later.

## Build, run, test

| Task | Command |
| --- | --- |
| Unit tests | `swift test --package-path native/BaristaAgent --scratch-path ~/.cache/barista-agent-tests` |
| Release build into `~/.cache/barista-agent` | `scripts/barista_agent.sh build` |
| Rebuild and restart the LaunchAgent | `scripts/barista_agent.sh restart` |
| Switch docks | `scripts/barista_agent.sh dock {barista\|native\|toggle\|status}` |
| Everything, including these tests | `scripts/check_scripts.sh` |

Pass `--scratch-path` (or use the script) so no `.build/` lands in the repo.
The agent runs as `dev.barista.agent` and logs to
`~/Library/Logs/sketchybar-barista/barista-agent.log`.

## Files

| File | Role |
| --- | --- |
| `main.swift` | App delegate, menu bar item, dock switch. |
| `DockController.swift` | The panel: reveal at the screen edge, hide after the pointer leaves, pointer conversion, popover routing, drag commits. Also the shared overlay panel, `MenuChoice`, and `launch` helpers. |
| `DockScene.swift` | All dock geometry and motion, advanced once per display frame. Also `RectSpring` and `FrameClock`. |
| `DockLayout.swift` | Pure layout math: slot frames, magnification, pointer mapping. |
| `DockView.swift` | SwiftUI renderer for the scene's frame, plus gestures, drops, and context menus (`AppMenu` holds the window controls). |
| `TileViews.swift` | `TileIcon`, `TileBadge`, `ActionStatus`, `GroupGlyph`. |
| `TileImage.swift` | What a tile draws: custom `icon` specs, the single-bitmap rasterizing behind the icon cache, and the folder or document mark on borrowed app icons. |
| `Popover.swift` | Folder (browsable), shelf, group (subgroups open in place; search and hidden members), and controls callouts above a tile. |
| `SystemControls.swift` | The controls tile's state and switches: Wi-Fi, Bluetooth via `blueutil`, appearance, Night Shift, keep awake, Low Power, battery, brightness, output volume and device, and System Settings panes. |
| `ControlsPopover.swift` | The controls callout: switch tiles, level sliders, the output menu, and pane links. |
| `DockStore.swift` | Tiles from `dock.json` and running apps, open groups, icon cache, and every edit action. |
| `DockConfig.swift` | `dock.json` model and its pure edit operations. |
| `DockTheme.swift` | Theme and window defaults from Barista's `state.json`, vibrancy background. |
| `Agents.swift` | Agent sessions from `agent_sessions.py`, which ones wait on you, and which finished since you looked. |
| `AttentionCard.swift` | The card above the dock for a session that waits on you, with Open and Later. |
| `Actions.swift` | `ActionRunner`: action runs (tiles, `menu` entries, info rows) as process groups, with logs, results, `lock`s, and group-wide Stop; terminal actions; badge, group info (`InfoRow`), and `menu_command` polling. |
| `Shelf.swift` | The shelf's file references and snippets. |
| `Yabai.swift` | Window and space queries, `yabai_control.sh` actions bound to a window, and the rule that floats viewer windows. |
| `Markdown.swift` | Markdown to blocks (headings, lists, code, quotes, tables, images); inline syntax is left to `AttributedString`. |
| `Viewer.swift` | The viewer windows for Markdown, images, and movies, their keys and sizing, and `FileWatcher`, which reloads a file when it is saved. |
| `MediaViewer.swift` | The picture and movie window: zoom, sharp pixels, rotate, crop, trim, the info panel, and the bar that shows on hover; `MediaEdit` saves edits as copies. |
| `FileBrowserModel.swift` | Barista Files' pure model: tab history, in-window tabs, listing, sorting, filtering, and `FileOperations` (Finder's names for new folders, copies, and kept-both clashes; rename; repo root). |
| `FileBrowser.swift` | The Barista Files window: folder title, bottom path bar, tabs, sidebar, table, preview, in-place rename, Finder's shortcuts and the Go and View menus, `OverlayScrollers`, and `BrowserWindow`, which drives the Quick Look panel, hover scroll bars, and row drag-select. |
| `FileIcons.swift` | `FileIcons`: Finder icons drawn into small bitmaps off the main thread, or Quick Look thumbnails for images and videos, cached by path, size, and modification date (bounded by bytes); `FileIcon` shows one when it's ready. |
| `DSStore.swift` | A read-only reader for Finder's `.DS_Store` (the buddy-allocated B-tree of per-file records); Barista never writes one. |
| `FolderViews.swift` | `FolderView` (layout, sort, icon size), what Finder recorded for a folder, Barista's own per-folder choices in its defaults, and the order they apply in. |
| `OpenWith.swift` | `OpenRules` (Barista's app per extension, under a folder or everywhere, in `files.json`), `DefaultApps` (the system default and Change All), and the Open With menus. |
| `Places.swift` | `FinderFavorites` (Finder's sidebar list, decoded from its shared file list, with template symbols), `PlacesMonitor`, and `DisplayNames`, a cache of Finder's folder names. |
| `Git.swift` | Barista Files' git: porcelain v2 status and worktree parsing, `Git.inspect` (no optional locks), and `Tool` for running Homebrew and cargo tools from launchd. |
| `FileViews.swift` | Barista Files' icon and column views. The column view draws the shown folder as its live column, with the folders above it and a selected folder's contents as read-only columns around it. |
| `Search.swift` | Barista Files' search scopes: `FileSearch` (the fd and rg commands and their output) and `ToolRun`, which streams a tool's lines and stops it at a limit or on cancel. |
| `Jump.swift` | ⌘K: candidate ranking, `JumpIndex` (places, zoxide, repos under `~/src`), and the sheet. |
| `Preview.swift` | Barista Files' preview pane: `Preview.load` (Markdown, org, text, JSON, ROM, image), `Org` to Markdown, and `SNESHeader`. |
| `Syntax.swift` | Regex coloring for code previews: 65816/asar, and comment, string, keyword, and number rules for other languages. |
| `GetInfo.swift` | ⌘I: `FileInfo`, `FolderSize` (cancellable), and the sheet. |
| `ContextPanel.swift` | `AFSContext` (finding and reading a `.context`'s entry points) and the panel shown when nothing is selected. |
| `Storage.swift` | `Volume` (capacity and free space as Finder counts it; network and FUSE mounts, and whether they respond), `VolumeMonitor` (one load at a time, again on mount and unmount), eject or unmount, and `SizeRun`, which stops Calculate All Sizes' folder walks. |
| `Workspace.swift` | Workspace folders: `TaskFile` reads and rewrites org and Markdown task lines, `PageSummary` titles notes and ideas, and `Editor` opens a file at a line in Cursor or Emacs. |
| `WorkspaceBoard.swift` | The board shown in place of the listing in a workspace: task columns by state, notes, ideas, and capture. |
| `AgentWindows.swift` | Focus for the agent's titled windows, the regular activation policy (⌘Tab) while one is open, and the hidden Edit menu that makes ⌘C work in them. |

## Viewer and Barista Files

The dock's panels never take focus, but these windows do: opening one
activates the agent, and closing the last one returns focus to the app you
were in. Both disable macOS window tabbing, so yabai sees exactly one window
per viewer or browser. Viewer windows are titled `<file> - Barista Viewer`
and `Yabai.ensureViewerRule` floats that title on the below sub-layer, so
focused tiled windows stack over it; browser
windows match no rule and tile. Tabs in Barista Files are drawn inside the
window, which is the point: native tabs are separate windows to yabai.

Pictures and movies AVFoundation can play open in a window that is only the
picture, like PictureView: it keeps the picture's shape as it resizes, and
the window buttons and a bar of controls fade in while the pointer is over
it. Small PNG, GIF, and BMP files open in sharp-pixel mode at the biggest
whole multiple that fits, so emulator captures and sprites don't blur.
Zooming by scroll, pinch, keys, or double-click sizes the window to the
picture around the pointer, up to the screen, so no black shows; dragging an
edge moves it over a still picture, stopping at the picture's edges (⌥ scales
the view with the window instead). The part showing is only a view until
Crop to View (⇧C) or the C handles and Return make it an edit. Scroll bars
float and fade. Movies wait to be played and loop. Keys: ←/→ step through the
folder's pictures and movies (zoomed in they pan, and ⌘←/⌘→ step), Space plays, 0 fits, 1–9 zoom to that
multiple, +/− step the zoom, P toggles sharp pixels, I shows info, R and ⇧R
rotate, C crops, ⇧C crops to the view, T trims a movie, ⌘S saves the edits,
⌘C copies, ⌘⌫ moves the file to the Trash and steps to the next one (⌘Z puts
it back). Edits never touch the original: Save Copy writes
`name (edited).ext` beside it and shows that. A trim alone copies the movie's
samples; a crop re-encodes. Right-click has all of it, plus Show in Files.

Several pictures or movies tile in one window: `barista-agent view A B …`,
opening a multi-selection in Barista Files, Add Pictures or Movies…, or a
drop. Tab cycles the active tile, Delete removes it, `[` and `]` move it, L
cycles the layout (grid, row, column, main with a strip, or rows justified
by shape), F switches between whole pictures and filling the tiles. Each tile
decodes at its share of the screen and more only when zoomed; hidden and
minimized windows let movie decoders go, and memory pressure sheds pixels.

`dock.json` settings: `viewer_scroll_zoom` (`off`, `fine`, `normal`,
`fast`) and `viewer_loops_movies`; the bar's More menu writes both.
Right-click → Window (and the Window button in Barista Files) runs yabai on
that window: Float, Level, Size, Next Display. `window_sizes` maps an app
to `small`, `medium`, or `large` for its new floating windows, as yabai
`grid=` rules labeled `barista-size-*`; Barista Files windows with a size
float at it.

From a shell, `barista-agent {view|browse|open} PATH` posts a distributed
notification to the running agent (`scripts/barista_agent.sh view PATH` does
the same); `barista-agent group TITLE` opens a dock group's callout.

## How a frame is made

```text
DockStore (tiles, settings) ──syncScene──▶ DockScene.update(Input)
pointer / drag / show / hide ────────────▶ DockScene ──requestFrame──▶ FrameClock
FrameClock (CADisplayLink) ──step(now)──▶ DockScene.frame (@Published) ──▶ DockView
```

`DockScene` owns every moving value, and `DockView` renders them with
animations disabled. Do not add `withAnimation` or `.animation` to the dock
view. An unanimated pointer update cancels a running SwiftUI spring, and the
AppKit blur behind the bar does not follow SwiftUI animations, so mixing the
two is what made the dock stutter.

Each `step`:

1. Lays out the tiles in display order. `Input.sections` splits each list
   around open groups, whose members get a section of their own. A dragged
   tile appears at the index it would drop to; an open group counts as one
   slot in its list.
2. Eases the magnification strength `amount` toward 1 while the pointer is
   over the bar, or toward 0 when it is not (τ 0.05 s in, 0.09 s out). The
   magnified frames come from `DockLayout.frames(baseX:amount:)`.
3. Applies FLIP when the order changes or a dragged tile is released. Each
   tile keeps the rect it was drawn at and springs to its new one. The
   spring is a critically damped `RectSpring` with response 0.3 s, solved
   exactly so frame rate does not matter.
4. Computes the reveal rise for each element. It is an analytic spring
   (response 0.42 s, damping 0.7), staggered 16 ms per slot outward from the
   middle. Hiding is an ease-in drop over 0.14 s. With Reduce Motion
   enabled, both become 0.15 s fades.
5. Hops tiles in `Input.attention` (finished agent sessions) once per reveal,
   0.45 s after it starts, as an offset on the drawn rect only, so FLIP never
   sees it.
6. Publishes the frame if it changed, and tells the clock whether more frames
   are needed. The clock pauses when nothing moves, so an idle dock costs
   nothing.

## Coordinates

- **Canvas:** top-left origin, the size of `DockScene.canvas`. It is wide
  enough for the widest magnified bar plus `DockLayout.margin` for the
  shadow. All scene and layout rects use it.
- **Panel:** the canvas, pinned to the panel's bottom center. While a tile is
  dragged, the panel grows upward by `dragLift` (160 pt) so the tile can leave
  the bar. The canvas does not move inside it, so nothing on screen jumps.
  `DockController.pointerChanged` converts panel points to canvas points.
- **Screen:** drags track `NSEvent.mouseLocation`, because the gesture's own
  coordinates shift when the panel grows. Popover anchors are converted from
  canvas to screen in `DockController.activate`.

## Icons

`DockStore.image(for:)` runs for every tile on every frame. Each icon is
rasterized once into a single bitmap at the largest size it is ever drawn
(icon size × magnification × 2 px), so magnification only scales a texture.
Workspace icons carry many representations and would otherwise be redrawn at
each new size. The cache key covers the tile, its icon spec, its path, the
pixel size, and the Trash's full or empty state, so it never needs flushing.

`DockView` redraws every frame while the dock moves, but each tile is an
Equatable `DockTileView` holding only what it draws (the cached bitmap, its
size, badge, and state). A frame that only moves a tile skips its body, and
callout anchors are read from the scene on click rather than baked into the
tile. `DockStore.tilesByID` is built when `refresh` changes the tiles, not
per frame.

## Popovers

`PopoverController` sizes the callout once with a centered arrow, clamps it
to the screen, and renders it again with the arrow over the tile. It appears
through a Core Animation spring and fade on the host layer, which runs on the
render server and stays smooth while SwiftUI lays out the cells. SwiftUI
hover does not work in windows of an app that is never active, so cells
hit-test `PopoverPointer` instead. It reaches them as a plain environment
value, and each `PointerHover` keeps its own hovered state, so a mouse move
redraws only the cells it enters or leaves. Observing the pointer redrew
every cell on every move.

## Testing live

Unit tests cover config edits, layout math, and scene motion (reveal,
magnification easing, drag reorder and remove, FLIP continuity, hide). For a
live check, restart the agent and use the dock by hand. Synthesized pointer
tests (CGEvent probes or computer use) take over the real mouse, so run them
only after asking whoever is at the machine. Keep probe scripts in `/tmp`,
not in the repo.
