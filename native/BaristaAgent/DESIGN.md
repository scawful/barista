# Barista Files and Viewer design system

The sizes, styles, and row patterns that Barista Files, the gallery, and
the sidebar share, and how to add to them without breaking what's there.
The code is in `Sources/BaristaAgent`; [README.md](README.md) maps the files.
The dock has its own theme (`DockTheme.swift`) and isn't covered here.

## Rules

1. Each number has one home: a button style, a layout struct, or a
   `static let`. A view that needs the number reads it from there rather than
   typing it again.
2. A target is bigger than its symbol. Buttons fill their frame with
   `.contentShape(Rectangle())`, so the click lands anywhere in the lit area.
3. Spacing grows with what it holds, between a floor and a ceiling
   (`IconLayout`), instead of one fixed value that is too tight at one end
   and too loose at the other.
4. Everything explains itself: a `.help` tooltip that names the shortcut, a
   caption line for state, and a context menu for the rest.
5. A choice the user makes is kept (`UserDefaults`, `@AppStorage`, or the
   collections file) and read back leniently: an unknown or missing value
   falls back to the default instead of failing.

## Window chrome

| Part | Value | Where |
| --- | --- | --- |
| Title bar | 40 pt: an empty `NSToolbar` with `.unifiedCompact` | `BrowserController` (`window.toolbarStyle`) |
| Toolbar insets | 82 pt leading (clear of the window buttons), 10 pt trailing | `toolbar` in `FileBrowser.swift` |
| Toolbar spacing | 10 pt between groups, 2 pt inside a group | `toolbar` |
| Picker and search field | `.controlSize(.large)`; search 180 pt wide, 110 pt compact | `toolbar` |
| Compact width | under 820 pt, buttons that have their own key hide | `toolbar` (`compact`) |
| Status bar, scope bar | 26 pt; `.caption` and `.callout` | `statusBar`, `scopeBar` |

`ChromeButtonStyle` (bottom of `FileBrowser.swift`) draws every toolbar and
status bar button:

| Style | Frame | Symbol | Use |
| --- | --- | --- | --- |
| `ChromeButtonStyle()` | 30 × 28 pt | 15 pt regular | Toolbar buttons. Apply once to the toolbar `HStack`. |
| `ChromeButtonStyle.small` | 22 × 22 pt | 10 pt bold | Status bar steps, such as the icon size − and +. |

Both fill a 6 pt rounded rectangle with `Color.primary` at 0.08 while the
pointer is over an enabled button and 0.16 while it's pressed. Symbols are
`.secondary`, or `.tertiary` when disabled.

The gallery's bar is drawn over the pictures, so it uses its own white
styling (`GalleryBar` in `Gallery.swift`): 38 pt high, 78 pt leading inset,
24 × 24 pt buttons from its `icon(_:_:on:action:)` helper, a 5 pt rounded
fill at white 0.25 for the chosen layout, and a black gradient behind it
that also drags the window (`WindowDragArea`).

## Sidebar

Sections, top to bottom, in `sidebar` (`FileBrowser.swift`):

| Section | Rows | Shows when |
| --- | --- | --- |
| Favorites | `placeRow` | always |
| Dock | `placeRow` | the dock pins folders that Favorites doesn't list |
| Locations | `volumeRow`, then `remoteRow` | a volume is mounted or a known remote is offline |
| Collections | `collectionRow` | always (Favorites is listed before it's made) |
| Repository | `repoRow`, worktree rows | the shown folder is in a git repo |

Repository is last on purpose: entering or leaving a repo never moves the
rows above it.

Each section header is `sectionHeader(_:symbol:divided:)`: a `Divider` and a
`Label`. Pass `divided: false` only for the first section. Each section is
`Section(isExpanded: expanded("Name"))`; `expanded` keeps the closed ones in
`@AppStorage("BaristaFilesCollapsedSections")`, one name per line, so a
section's name is also its key. Renaming a section reopens it once.

### Row anatomy

Every row type follows the same five parts. Copy an existing row rather
than starting from a blank `Label`.

1. **Title.** `Label(name, systemImage:)` with `.lineLimit(1)`; semibold
   when it's the shown folder.
2. **Mark.** `.listRowBackground(currentMark(url))` for a folder, or
   `rowMark(bool)` for anything else (the Collections row uses it while a
   drag is over it). The mark is a 5 pt rounded rectangle, accent color at
   0.22, inset 8 pt.
3. **Inline action** (optional). A `.borderless` button at the trailing
   edge with a `.caption2` symbol, `.secondary`, and a `.help`. While the
   action runs, it's replaced by `ProgressView().controlSize(.mini)`.
4. **Detail** (optional). A second line in `.caption`, `.secondary`,
   `.lineLimit(1)`; orange for a problem, such as a volume that doesn't
   respond. The title and detail sit in a `VStack(alignment: .leading,
   spacing: 3)`.
5. **Behavior.** `.help`, `.contentShape(Rectangle())`, `.onTapGesture`,
   and a `.contextMenu` that ends with `Divider()` and `fontSizeMenu`.

Row types today:

| Row | Inline action | Detail | Tap |
| --- | --- | --- | --- |
| `placeRow` | none | none | opens the folder |
| `volumeRow` | Reconnect (dead remote), Eject | free space bar and text, or "Not responding" | opens, or reconnects a dead remote |
| `remoteRow` | Connect (`link`) | the `user@host:path` source | connects; the row is at 0.7 opacity until then |
| `collectionRow` | none (a count on the trailing edge) | none | opens the collection's gallery; takes dropped pictures and movies |
| `repoRow` | none | branch · changes · ↑ahead ↓behind | opens the repo root |

### Sidebar preferences

`SidebarPreferences.shared` (`SidebarPreferences.swift`) holds:

- `fontSize`: 9 to 24 pt, 12 by default, saved as
  `BaristaFilesSidebarFontSize`. Below 12 the rows are `.small`, above 14
  `.large` (`sidebarRowSize`).
- `customIcons`: SF Symbol names keyed by full path, `~` path, or folder
  name, saved as `BaristaFilesSidebarCustomIcons`. `symbol(for:)` checks
  them before Finder's default.

`fontSizeMenu` and `iconCustomizationMenu(for:current:)` are the menus
that change them.

## Icon grid

`IconLayout` (`FileViews.swift`) turns the window width and icon size into
cells. Every spacing value scales with the icon, rounded, between a floor
and a ceiling:

| Value | Formula | Range |
| --- | --- | --- |
| `margin` (edges, above the first row) | fixed | 8 pt |
| `spacing` (between cells) | icon × 0.06 | 4–16 pt |
| `inset` (around the icon in its cell) | icon × 0.05 | 3–12 pt |
| `gap` (icon to name) | icon × 0.03 | 2–8 pt |
| `fontSize` | steps at 80, 160, 320 pt icons | 10, 11, 12, 13 pt |
| narrowest cell | max(72, icon + 2 × inset + 8) | — |

The columns that fit share the width; the leftover is split evenly as
`left`, so the block is centered. The selection background surrounds the
icon only, with a corner radius of `inset + 3`. Icon sizes step through
`FolderView.iconSizes` (32 to 512 pt).

## Gallery

`Gallery.swift` holds the types; a gallery window is a `ViewerModel` in
gallery mode with a `GalleryModel`.

| Type | Cases | Notes |
| --- | --- | --- |
| `ViewMode` | `gallery`, `tiles`, `one` | ⌘1, ⌘2, ⌘3 (`key`) |
| `GalleryLayout` | `grid`, `justified`, `columns`, `featured` | each has a `title` and `symbol`; L steps to the next |
| `FeatureShare` | `half`, `twoThirds` | how wide a featured picture is |

`GalleryGrid` places the thumbnails. It's pure, so clicks, arrow keys,
drops, and drawing all use the same frames:

- `gap` is 4 pt.
- `sizes` is `[80, 110, 150, 200, 260, 340, 440]`: a grid cell's side, a
  justified row's height, or a column's width. − and + step through it;
  `defaultSize` is index 3 (200 pt).
- `frames(aspects:width:layout:target:featured:share:)` clamps each aspect
  ratio to 0.2–5 and dispatches to one private function per layout.

`GalleryView` insets the grid by 44 pt top (under the bar), 6 pt leading
and trailing, and 12 pt bottom. `GalleryCell` draws the selection as a
3 pt accent border, focus as a 1.5 pt white (0.6) border inside it, a
removed item at 0.45 opacity, and a yellow star on a featured one.
Thumbnails come from `GalleryThumbnails` in 256, 512, 1024, and 2048 pixel
buckets.

A folder's gallery keeps its layout, size, and share in `UserDefaults`
(`Gallery.layout`, `Gallery.size`, `Gallery.share`). A collection keeps
its own in its entry in the collections file.

## Collections

`CollectionStore.shared` (`Collections.swift`) reads and writes
`data/barista_collections.local.json` under the Barista config folder.

- An entry needs only `name` and `items` (`~` paths). `mode`, `layout`,
  `tileLayout`, `size`, `featured`, and `share` are optional, and a value
  that doesn't decode falls back to its default.
- The first rewrite each day copies the file to `<file>.YYYY-MM-DD.bak`;
  the newest three copies stay.
- There's no file watcher. `refresh()` reloads when the file's
  modification date changed, so **call `refresh()` before any write that
  starts from the sidebar or a menu**, or a hand edit is lost.
- `Favorites` (`CollectionStore.favorites`) is listed first and made the
  first time something is added to it.

`CollectionPlace` (`Places.swift`) is a sidebar row's data: name, count,
whether it's made, and its symbol (`star` for Favorites, `photo.stack`
otherwise). `CollectionPlace.media(_:)` keeps only the dropped files the
viewer can show.

## Remotes

`RemoteMount` (`Storage.swift`) is a remote that the `mounts` tool knows.
Barista only reads the tool's output and runs it; it never edits the
tool's config.

- The tool is `BARISTA_MOUNTS_TOOL` if that's an executable, else `mounts`
  on a tool path (`Tool.find`), else `~/src/tools/mounts/mounts`.
- `mounts status` must print one line per remote,
  `name state volname source`, with `state` one of `mounted`,
  `not-mounted`, or `stale`, and a final `Mount points: <folder>` line.
  Without that line, the output is ignored.
- `mounts <name>` mounts one remote. Barista waits up to 40 seconds and
  shows the last output line if it fails; `status` gets 20 seconds.
- `VolumeMonitor` asks for the status at most every 300 seconds. A
  remote is offline when no mounted volume has its folder, so after a
  connect the volume reload alone moves it from `remoteRow` to `volumeRow`.

## Extending

Each recipe names the files to change and the tests that cover them. Run
the tests with:

```sh
swift test --package-path native/BaristaAgent --scratch-path ~/.cache/barista-agent-tests
```

Then `scripts/barista_agent.sh restart` to see the change in the running
agent.

### Add a toolbar button

1. Add a `Button` with an `Image(systemName:)` label to the right group in
   `toolbar` (`FileBrowser.swift`). It inherits `ChromeButtonStyle`.
2. Give it `.help("Name (shortcut)")` and `.disabled(...)` when it can't act.
3. If it has its own key, wrap it in `if !compact` so a narrow window drops
   it first.
4. Add the key to the Go or View menu (`installMenus` in
   `BrowserController`), not only the button, so it works when the toolbar
   hides it.

### Add a sidebar section

1. Add a `Section(isExpanded: expanded("Name"))` in `sidebar`, at the place
   it belongs in the order. Keep Repository last.
2. Use `sectionHeader("Name", symbol: "...")` as its header.
3. Hide the section when it would be empty, unless an empty state is useful
   (Collections shows Favorites before it's made).
4. Put the rows' data in a small pure type, as `CollectionPlace` is, and test
   that type rather than the view.

### Add a sidebar row type

1. Copy the closest row in `FileBrowser.swift` and keep the five parts in
   [Row anatomy](#row-anatomy).
2. Put an inline action's long-running work off the main thread, and show
   `ProgressView().controlSize(.mini)` in its place while it runs.
3. End the context menu with `Divider()` and `fontSizeMenu`.
4. Test the data the row shows (for example `CollectionPlaceTests`,
   `StorageTests`).

### Add a gallery layout

1. Add a case to `GalleryLayout` with a `title` and a `symbol`. The bar's
   buttons and the L key read `allCases`, so they pick it up.
2. Add its branch to `GalleryGrid.frames` and a private static function
   that returns `(frames, height)` in top-left coordinates, using `gap`.
3. Interpret `target` (one of `sizes`) the way the size steps should feel
   for that layout, and say how in a comment.
4. Add tests to `GalleryTests`: frames don't overlap, they fit `width`, and
   `height` covers the last frame.
5. Add new cases at the end and don't rename old ones: saved settings store
   the raw value, and an unknown value falls back to `justified`.

### Add a remote

1. Add the remote to the `mounts` tool, so `mounts status` lists it and
   `mounts <name>` mounts it. Barista needs no change.
2. Check the output with `~/src/tools/mounts/mounts status`.
3. Wait up to 5 minutes, or run `scripts/barista_agent.sh restart`; the
   row shows under Locations while the remote is offline.

### Add a customization preference

1. Add a `@Published` property to `SidebarPreferences`, saved in
   `UserDefaults` in its `didSet`, read with a range check in `init`.
2. Add the menu that changes it next to `fontSizeMenu`, and put it in the
   context menus of the rows it affects.
3. For a per-folder or per-collection choice, store it with the folder
   (`FolderViews.swift`) or in `MediaCollection` with a default in its
   decoder, not in `SidebarPreferences`.
4. Test the stored value and its fallback (`SettingsViewTests`,
   `FolderViewTests`).

### Change a size or spacing value

1. Change it in its one home: `ChromeButtonStyle`, `IconLayout`,
   `GalleryGrid`, or the view's `static let`.
2. Update this file's tables.
3. `FolderViewTests` checks the icon grid's cells and columns, and
   `GalleryTests` checks gallery frames; update their expected values.
