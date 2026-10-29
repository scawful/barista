# Native Layers

Status: Draft (Barista dock running)
Last updated: 2026-10-27

Barista absorbs the native macOS host role that Cortex held. Cortex is trimmed
to a standalone Oracle app; this document replaces the "Cortex owns" section of
`~/src/lab/cortex/docs/PRODUCT_BOUNDARY.md` for everything that is not Oracle.

## Layers

| Layer | Lives in | Owns |
|-------|----------|------|
| Render engine | `~/src/lab/sketchybar` ([`scawful/SketchyBar`](https://github.com/scawful/SketchyBar), branch `barista-perf`) | top bar and popup windows, drawing, click routing, display hold, latency trace |
| Layout and widgets | this repo (Lua, shell, C helpers) | items, popups, menus, spaces, theme, yabai/skhd glue |
| Native agent | `native/BaristaAgent` (`barista-agent`, Swift) | native panels (dock), EventKit, notifications, secrets, API clients, shared data cache |
| Backend | `halext-org` on the backend host | admin API, sync for agent, web, and the Cafe iOS app |
| Oracle | `~/src/lab/cortex` (trimmed) | Zelda-first AI sessions only |

## Rules

1. The fork stays a renderer. New data sources go into `barista-agent`, which
   pushes values with `sketchybar --set`/`--trigger`; the fork never calls
   network or EventKit APIs.
2. Lua owns layout. The agent does not create SketchyBar items; it fills items
   that Lua declared.
3. Native windows that SketchyBar cannot draw well (the dock, rich panels) belong to the agent, not to the `gui/` control panel, which stays a
   settings window.
4. One process holds a secret or API session. Shell plugins ask the agent
   (CLI or cached file) instead of reading keychain items themselves.
5. Reminders and calendar data flow through halext-org when they must reach
   iOS; EventKit is the local source on the Mac.

## barista-agent today: the Barista dock

- `scripts/barista_agent.sh dock {barista|native|toggle|status}` switches
  between the Barista dock and the native Dock; Control Center → Bar Settings →
  `Dock: Barista` / `Dock: macOS` runs `toggle`, and the dock's own right-click
  menu has `Use macOS Dock`.
- `barista` saves the native `autohide`/`autohide-delay` values once to
  `~/.local/state/barista/native-dock.env`, sets `autohide-delay` to 1000 so
  the native Dock never reveals, and loads the KeepAlive LaunchAgent
  `dev.barista.agent`. `native` restores the saved values, restarts the Dock,
  and unloads the agent last (it may be running from the agent's menu).
- `build` compiles with `swift build -c release` into `~/.cache/barista-agent`
  (override with `BARISTA_AGENT_BUILD_DIR`); `restart` rebuilds and restarts
  the running agent.
- The dock is one non-activating panel at Dock window level, hidden until the
  pointer pushes against a screen's bottom edge (a global mouse-moved monitor), then
  shown on that screen until the pointer leaves for `hide_delay`. A callout
  that shrinks out from under a still pointer (opening a filter match or a
  subfolder) is not leaving; the timer starts once the pointer moves. Icons spring
  up from the screen edge, middle first; hiding drops them together. Reduce
  Motion falls back to a fade.
- Pins live in `~/.config/barista/dock.json` (override with
  `BARISTA_DOCK_CONFIG`), copied once from the native Dock's `persistent-apps`
  and `persistent-others`. After that the native Dock is never written; delete
  the file to copy it again. Sections: `pinned`, then running apps that are not
  pinned, then `others`, minimized windows, and `system` (the shelf and the
  controls) beside the Trash. A config without `system` moves its top-level
  shelf and controls tiles there when it is read. Running apps update from NSWorkspace
  notifications, with no polling; the file and Barista's `state.json` are
  re-read on reveal only when their modification time changed.
- Editing: drag an icon sideways to reorder it, onto the middle of a closed
  group to add it to that group (the group lights up; its edges still
  reorder), or above the dock to remove it; drop apps from Finder onto the bar to pin them, folders, files, and web
  links to add them to `others`. Right-click offers Add to Group (an existing
  group or New Group…) and, under Options, Keep in Dock / Remove from Dock. If
  `dock.json` fails to parse, the menu says so and edits are refused rather
  than overwriting it.
- Drops onto icons: apps open the files, folders ask at the pointer whether
  to copy or move them, the Trash recycles them, action tiles
  receive their paths as arguments, groups take dropped apps, and the shelf
  keeps files and text.
- Groups show their first four members in a tinted tile and open a callout grid
  with each app's running dot; clicking an app opens it, and right-click has
  the app menu below plus Move to Subgroup (an existing subgroup or New
  Subgroup…), Hide in Group, and Remove from Group (Move to the parent group
  inside a subgroup). The group's own menu has Rename…, Ungroup, and Remove
  from Dock.
- Subgroups: a group inside a group is one cell, marked with a chevron, that
  opens in place with a back button and the parents as breadcrumbs; it runs,
  badges, and polls like a top-level group. Titles are unique across the
  dock, so a subgroup shows without the words it shares with its parent
  ("Oracle Tools" in "Oracle of Secrets" reads "Tools"); Rename… edits the
  full title. An open group draws only its own members inline, subgroups as
  one tile; drag them sideways to reorder the group, or up to remove them.
  In a callout, drag a member onto another to take its place, or onto a
  subgroup to move it in.
- `barista_agent.sh group TITLE` (or `barista-agent group TITLE`) brings up
  the dock with that group's callout open over its tile, or its parent's for
  a subgroup, for hotkeys and bar menus. It stays until the pointer moves
  away from it. A member with `"hidden": true` stays
  out of the grid, the inline tiles, and the group icon until the callout's
  Hidden toggle shows it (dimmed). A group holding more than 8 members,
  counting its subgroups' members, gets a search field: typing lists matching
  members at any depth (with their subgroup path), `menu` and `menu_command`
  entries, and status rows, over the grid so the callout keeps its size;
  Return opens or runs the first. The Status and Agents lists fold from their
  headers, remembered per group.
- Open groups (contexts): while one of a group's apps is frontmost, the group
  is drawn open, its members inline between dividers, so the rest of that
  context is one click away. A group with `spaces` also opens on those yabai
  spaces. The members keep their menus but are reordered inside the group,
  not on the bar. `expand_active_group: false` turns the app trigger off for
  every group; `"expand": false` on a group keeps just that one closed.
- Agent sessions: each refresh of the bar's `agents` widget (every 30 s)
  writes the live sessions to `cache/agent_sessions.json` next to
  `state.json` (override with `BARISTA_AGENT_BADGES_FILE`); files older than
  10 minutes are ignored. The dock checks it every 5 s and lists each session
  under the group's apps in its callout (the title counts them and how many
  need you), followed by plan usage where known (Codex's `88% wk`); clicking
  a session brings its window or chat forward. Running sessions badge
  nothing. A session that waits on you badges its tile red with a count
  (summed over a group), lists first with "Needs you" and its question, and
  stays listed for up to a day: Claude's session status `waiting` (with
  `waitingFor`, such as a permission dialog), a Codex
  `request_user_input_async` call with no later user message, or a Cursor
  chat whose transcript ends in CreatePlan. A pending Cursor AskQuestion is
  not detected: Cursor saves transcripts and chat state (`state.vscdb`) only
  now and then, and runs no hooks for AskQuestion. The bar's `agents`
  label shows the same count and is blank otherwise. While the dock is out
  and no callout is open, a card above it points at the first such
  session's tile (or its closed group) with the question, how many more
  wait, and Open and Later; either one sets that question aside until the
  session asks something else, though its badge stays. A session that stops
  working without asking (Claude reports busy/idle; Codex and Cursor count
  as working while their transcript was written in the last 90 s) gets a
  green dot. Either kind makes the tile hop once each time the dock appears;
  the dot clears when you switch to that app or open the session, and
  sessions of the frontmost app do not get one.
- Action tiles show a spinning ring while their command runs, then a check
  for two minutes or a cross until you look. Clicking a failed action opens
  its output; the next click runs it again. Each run's output goes to
  `~/Library/Logs/sketchybar-barista/dock-actions/<title>-<hash>.log` (the
  hash keeps same-titled actions in different groups apart), and the menu
  has Stop and Show Last Output. Each run is its own process group: Stop
  sends SIGTERM to the group, the ring turns amber while anything in it is
  still exiting, and after 5 s the rest gets SIGKILL; apps the command
  launched through `open` or a new session keep running. Actions with the
  same `lock` name never overlap: while one runs, the dock beeps instead of
  starting another. `notify: true` also posts a notification
  when the command finishes. `terminal: true` runs the command in a new
  Ghostty window (Terminal without Ghostty) that stays open as a login shell,
  for interactive tools; those actions have no status ring.
- Badge commands: any tile's `badge_command` runs with `zsh -lc` when the
  dock appears (at most every 20 s, 5 s timeout); the first line of output
  is the badge, and empty output or `0` shows none.
- Right-click entries: any tile's `menu` lists extra actions (`title`,
  `command`, optional `notify`/`terminal`) at the top of its right-click
  menu, in the dock and in group callouts; an entry of kind `group` with
  `items` is a submenu. A running entry offers Stop and a failed one shows
  its output; an entry with `disabled: "<reason>"` is greyed out with the
  reason. `menu_command` prints `{"menu": [...]}` on the badge schedule,
  for entries that depend on live state; they follow the `menu` entries.
  Entries' runs show on their tile's status ring, and a closed
  group's ring shows its members' runs (running over failed over passed).
- Group info: a group's `info_command` runs on the same schedule and prints
  `{"rows": [{"title", "detail", "tone", "action", "run", "open"}]}`; the
  rows appear in the group's callout between its apps and its agent
  sessions. `tone` is `ok`, `warn`, `error`, or `none` (the dot color). A
  click uses the first of: `action` runs the member tile with that title,
  `run` runs a command in the background (progress replaces the row's
  detail), `open` opens a path or URL and closes the callout. Every finished
  action reruns the info commands, and the callout sizes itself again when
  its number of rows changes.
- `scripts/dock_oracle.py` runs the Oracle group. It reads an explicit
  binding, `~/.config/barista/oracle.json` (`repo`, `version`, `project`,
  `project_launcher`, `evidence`, `test_instance`; override with
  `BARISTA_ORACLE_BINDING`), and never guesses a ROM from file times.
  `info` prints the rows:
  - Editing: the bound yaze project, when it was saved, and whether its ROM
    is the build's base. Click opens the project.
  - Built: read from `Roms/oos<v>x.build.json` through Oracle's own receipt
    verifier. It says passed (with runtime untested or smoke passed),
    changed since the build (source, base ROM, or output), failed at a
    stage, building, or no receipt. Click builds.
  - Tested: the last dock test report's selected, passed, failed, and
    skipped counts, and whether it tested an older build.
  - The Mesen play window, the dock's test instance, dead sockets (click
    prunes), git, the finish-line focus, the top quest, and alerts.

  `build [--validate]` holds `Roms/.oos-build.lock` while it builds and
  reports the build result before, and apart from, the Mesen offer. Oracle's
  `build_rom.sh` takes the same lock itself (exit 75 when busy), so the dock
  passes its locked descriptor to the build (`pass_fds` plus
  `OOS_BUILD_LOCK_FD`); the build accepts it only if it is that lock file
  and holds the lock. Older Oracle checkouts ignore the variable.
  `play dev|beta [--now]` opens the current development build or the last
  staged beta. `test transitions` runs the 5 `transition`-tagged tests
  against the verified output ROM on the bound test instance and writes a
  report. If that instance is already running a different ROM, the run
  stops there; the dock never closes an instance it can't prove it owns.
  `sessions-menu` lists debug presets, marking those without a
  trusted seed as unavailable. `edit` opens the project launcher detached.
- Folders open the same callout with Quick Look thumbnails, ordered by
  `sort`: `added` (default, newest first), `modified`, or `name` (folders
  first). Folders inside a group open there too, with a back button to the
  group. A filter field narrows the whole folder (Return opens the first
  match), Hidden shows dot files, and the first 60 cells grow by 60 with
  Show More. Clicking a subfolder opens it inside the callout, with a back
  button and clickable parent folders in the subtitle; files open on click
  and can be dragged out. Right-click a file for Open, Quick Look, Open in
  Cursor or Emacs (when installed), Terminal Here, Show in Finder, Copy Path,
  Copy Relative Path (from the dock folder), Add to Shelf, and Move to
  Trash. Downloads and other protected folders need a one-time
  Files and Folders permission for `barista-agent`, which macOS may ask for
  again after a rebuild because the binary is ad-hoc signed.
- The shelf (`{ "kind": "shelf" }` in `system`, or Add Shelf to Dock on the
  dock's menu) is a scratch space: drop files to keep a
  reference (nothing moves), or text to save it as a snippet. Its callout
  lists them newest first for opening or dragging out, with Clear Shelf and
  per-item Remove from Shelf. Items go after `shelf_days` (default 3), and
  missing files drop off. State lives in `~/.local/state/barista/shelf.json`
  (override with `BARISTA_SHELF_FILE`), snippets in `shelf/snippets/` next
  to it.
- The controls tile (`{ "kind": "controls" }` in `system`, or Add Controls to Dock on
  the dock's menu) opens Control Center's everyday switches: Wi-Fi, Dark
  Mode, Night Shift, Keep Awake (holds the display on until switched off or
  the agent quits), and Low Power (asks for an administrator password);
  brightness of the built-in display, output volume with mute, and the
  output device; then links to twelve System Settings panes. It polls every
  two seconds while open, so volume keys and switches flipped elsewhere
  show. Bluetooth switches only with `blueutil` installed (the agent has no
  Info.plist to ask for Bluetooth access) and otherwise opens its pane.
  macOS has no API to switch a Focus, so the Focus switch runs the Shortcut
  named by `focus_shortcut`, or opens Focus settings when that is empty.
  Dark Mode goes through System Events, which macOS asks to allow once.
  Brightness and Night Shift use private frameworks and drop out of the
  callout when those don't answer.
- Right-click on an app follows the macOS Dock's order: its windows (one
  yabai query per reveal), then Barista's own entries — the tile's `menu`
  actions, Add to Group, Window (Float, Sticky, Zoom to Fill, Center, Utility
  Size, Tile Here, Next Display, Minimize, Close, applied to the focused or
  first window), Move to Space (every window of the app), Gather Windows
  Here, New Windows (Barista's float/tile app default, or Follow yabai
  Rules, and Size When Floating: small, medium, or large, kept in
  `window_sizes` and applied as a yabai `grid=` rule), and Window Level (Normal, Raised, Always on Top, or Follow yabai
  Rules; see `window_levels` in `docs/STATE_SCHEMA.md`). The window items run `scripts/yabai_control.sh` bound to the
  window, like the bar's window menu. Then Options (Keep in Dock / Remove
  from Dock / Remove from Group, Show in Finder, Dock Settings…, Use macOS
  Dock), and last Open, Show or Hide, and Quit, which turns into Force Quit
  while Option is held. Other tiles' menus end with Dock Settings… and Use
  macOS Dock. The Trash menu has Empty Trash…, which confirms first and then
  asks Finder.
- Callouts have right-click menus too. A group's header offers Open All
  Apps, Hide All Apps, Rename…, Ungroup, and Remove from Dock; its info rows
  offer Run or Open, Stop, Show Last Output, Show in Finder, and copying; its
  agent sessions offer Go to Session, opening the app, Copy Question, Hide
  from Attention Card, and Mark as Seen. A folder's header offers Open in
  Finder, the editors, Terminal Here, and Copy Path; the shelf's offers Copy
  All Paths, Show All in Finder, and Clear Shelf. The attention card offers
  Go to Session, Open App, Later, and copying.
- Running apps follow launch, quit, hide, and each app's activation policy,
  so a menu bar app (LM Studio, Docker) leaves the dock when its last window
  closes, as it does in the macOS Dock.

### Viewer and Barista Files

- Markdown and image files open in a small viewer window instead of their
  default app: from a folder callout or the shelf, a `file` tile, or an info
  row's `open` path. Open with Default App stays on the right-click menu.
  Markdown renders headings, lists and task boxes, code, quotes, tables, and
  images next to the file; relative `.md` links open in the same window.
  Pictures and movies open in a window that is only the picture: zooming
  (scroll, pinch, keys, double-click) sizes the window to the picture, and
  resizing moves the window's edges over it, up to its edges.
  `viewer_scroll_zoom` (`off`, `fine`, `normal`, `fast`) sets how fast
  scrolling zooms; `viewer_loops_movies` loops movies once played. Several
  files tile in one window, laid out from its right-click menu. Both kinds
  reload when the file is saved. ⌘E opens the file in its editor, Escape or
  ⌘W closes.
- Barista Files is a Finder replacement that tiles: one window with its tabs
  inside it, back/forward history per tab, the folder's name in the toolbar
  (click it for the folders above), Finder's path bar along the bottom
  (folders a narrow window can't fit wait behind …; the icon slider and
  free space give way first), a
  Window button (yabai: Float, Level, Size, Next Display, and New Windows
  Open tiled or floating at a size; a window under 760 points wide keeps
  only the toolbar buttons with no shortcut of their own), a sidebar (⌥⌘S) of
  Finder's own Favorites in Finder's order (read from Finder's sidebar list,
  so adding a favorite in Finder adds it here) and the dock's other folders,
  a sortable list, a preview pane (⇧⌘P), Quick Look (Space or ⌘Y; arrows
  follow the list), drag in and out, and Finder's shortcuts (⌘T, ⌘W, ⌘N, ⌘[
  and ⌘], ⌘↑, ⌘↓, ⇧⌘., ⌘F, ⌃Tab, ⌘1–9, ⌘⌫, ⇧⌘⌫ Empty Trash, ⇧⌘N New Folder,
  ⌃⌘N New Folder with Selection, ⌘D Duplicate, ⌥⌘C Copy as Pathname, ⌘E
  Eject, ⌘C then ⌘V to copy or ⌥⌘V to move here). Finder's Go menu works
  too: ⇧⌘H Home, ⇧⌘D Desktop, ⇧⌘O Documents, ⌥⌘L Downloads, ⇧⌘A
  Applications, ⇧⌘U Utilities, ⇧⌘L Library, ⇧⌘I iCloud Drive, ⇧⌘C
  Computer (`/Volumes`). Go and View menus in the menu bar list them. Typing
  a name selects the first row it starts.
- Loading: listings skip the per-file type description (Kind comes from
  the extension, once per extension), icons are drawn off the main thread
  and cached, and the last 48 folders' listings are remembered, so back,
  up, tabs, and revisits show their rows at once while the folder is read
  again. A folder that takes over 0.1 s the first time shows Loading…
  instead of the last folder's rows. git status is skipped on network
  mounts. Each row's place in name order is worked out once, off the main
  thread, so re-sorting on a filter keystroke or a measured folder size
  compares numbers, not names (2,800 rows: about 15 ms to 1 ms).
- Views are remembered per folder. Picking a layout in a folder makes it
  always open that way, as Finder's "Always open in"; other folders keep
  the window's layout, and columns stay columns while browsing. Sort and
  icon size (32 to 512 points, by the status-bar slider, ⌘- and ⌘=, or a
  pinch) are the folder's own. The sidebar, list, and preview share one
  surface, with no row stripes; scroll bars float and show while the
  pointer moves over what scrolls. Dragging across empty space in the icon
  view selects what the rectangle touches (⇧ or ⌘ adds), scrolling a row
  at a time while held past the top or bottom; in the list a drag up or
  down selects rows and a drag sideways carries files out. An empty folder
  or search says so. Sidebar sections fold from their headers, and stay
  folded; favorites that share a name (`/Applications` and
  `~/Applications`) show their paths.
  Barista's choices live in its defaults; where it has none, it reads what
  Finder recorded in `.DS_Store` (the parent's record under the folder's
  name, or the folder's own `.`), off the main thread, and never writes
  one. View → Use as Defaults sets the view for everything else and for
  new windows. The window's frame, the sidebar and preview widths (drag
  the lines between panes), and the list's columns (right-click a header
  to show Date Created or Date Added; drag to reorder or resize) are kept
  too.
- Open With lists Barista's own choice first, then the default. Always
  Open With is Finder's Change All (the system default for the type, after
  a confirmation). In Barista, Open .ext With sets Barista's app for the
  extension in the shown folder or everywhere, kept in
  `~/.config/barista/files.json`; opening a file uses the deepest folder's
  rule, then the viewer for Markdown and images, then the default. Get Info
  shows what opens the file and changes it the same ways.
  Return renames in place, as in Finder: the name up to its extension is
  selected, so typing keeps `.asm`; ⌘O, ⌘↓, or a double-click opens. The
  folder shows as a list, icons, or columns (⌥⌘1–3, since ⌘1–9 pick tabs;
  the toolbar picker; or View on the empty-space menu, beside Sort By). In columns the shown folder is
  the live column, so search, file operations, and git work as in the list;
  the folders above it (from Home, or the root outside it) are columns to
  its left, a selected folder's contents a column to its right, → enters
  and ← goes up. Icons take ⌘- and ⇧-clicks and all four arrows. The list
  takes keyboard focus when a window opens and again when a rename ends, so
  arrows work without a click. ⌘A selects everything shown. The right-click menu
  has Rename, Open With, Open in Cursor or Emacs, Terminal Here, and Copy Relative
  Path (relative to the enclosing git repo or worktree). Right-click on empty
  space for the folder's own menu. Name clashes keep both (`name 2`), copies
  are `name copy`, and a failed operation shows an alert. The Finder tile
  opens it (⌥-click opens Finder; `files_browser: "finder"` turns this off),
  as do Browse in Barista Files on any folder callout or file, a folder
  tile's Open, and a folder parked on the shelf. While a
  Files or viewer window is open the agent is a regular app, so ⌘Tab
  reaches it; it goes back to an accessory when the last one closes.
- Inside a git repo, each changed file in the list carries a letter (M, A,
  D, R, ? untracked, U conflicted) and folders that hold changes a dot. The
  sidebar's Repository section shows the branch, change count, and
  ahead/behind, and lists the repo's worktrees by branch; clicking one goes
  to the same folder in that worktree, or its top when the folder isn't
  there. Right-click the repo or a worktree to open it in Cursor or Emacs,
  a terminal or lazygit at its top, or copy its branch or path. git runs
  after the listing is shown and without optional locks, so browsing never
  takes `index.lock` from an agent committing in the repo. A burst of
  writes in the shown folder (a build, an agent) reloads it at most five
  times a second.
- Search (⌘F) filters the shown folder as you type. With a query, a scope
  bar offers This Folder, Subfolders (names holding every word, via `fd`),
  and Contents (the query as one phrase, via `rg`; ⇧⌘F starts here).
  Subfolder and content results show their path under the folder, contents
  show the first matching line, and the preview pane opens a text result at
  that line. Both skip `.git`, and skip what `.gitignore` ignores unless
  hidden files are shown (⇧⌘.); results stop at 1000. Escape clears the
  search; ⌘R (or Show in Enclosing Folder) shows a result in its folder.
- The sidebar's Locations section lists every mounted drive: the startup
  disk, external drives, and network and FUSE mounts (sshfs and the like,
  which report no size; one whose server went away says Not responding).
  Local volumes get a usage bar (orange past 75 % used, red past 90 %) and
  free space as Finder counts it, purgeable space included; the list
  reloads on mount and unmount and at most every 10 seconds otherwise.
  Every drive but the startup disk has an eject button (⌘E ejects the
  selected drive or the one shown); network mounts unmount through
  `diskutil` when Disk Arbitration can't eject them, and a window showing
  the drive goes Home. Right-click a volume for Show Largest
  Folders (in Home, for the startup volume), Get Info, or Eject. Calculate
  Sizes in the status bar (or Calculate All Sizes on the empty-space menu)
  walks each shown folder in the background, one at a time, and keeps
  going as you sort: folders get a size, Size sorting ranks them, the
  Size column draws a bar against the largest, and the status bar adds
  the folder's total. Leaving the folder stops the walk; the setting stays
  on for the next one. The status bar also shows the volume's free space.
- ⌘I (or Get Info on either right-click menu) shows kind, size (a folder's
  is measured in the background and stops when the sheet closes), where,
  created and modified dates, permissions, a symlink's target, and the last
  commit that touched the item. Several selected items show their count and
  total size; nothing selected shows the folder itself.
- ⌘K (or ⇧⌘G) jumps to a folder: type parts of its name or path (`oos
  core`); Return goes, ⌘Return opens a tab, a path starting with `/` or `~`
  goes straight there. Candidates are the places, zoxide's folders by
  frecency, and every repo under `~/src` (found with `fd`), read again after
  five minutes. Folders you browse are added to zoxide, as `cd` does.
- The preview pane renders Markdown and org (headings, lists, src blocks,
  tables, links), shows code and other text unwrapped in a monospaced view
  (first 256 KB) with light coloring (65816/asar: labels, mnemonics,
  directives, `!defines`, `%macros`, numbers; C-family, `#`-comment, Lua,
  and Lisp files: comments, strings, keywords, numbers; by name, shell
  startup files, `yabairc`, `skhdrc`, and build files), indents minified
  JSON, and reads a SNES ROM's internal
  header: title, LoROM/HiROM/ExHiROM, ROM and SRAM size, region, version,
  and the stored checksum against the computed one (skipped when the size
  has no standard mirroring). Images and anything else fall back to details.
- yaze and Mesen2 OOS declare no document types, so Open With never lists
  them: a ROM's right-click menu and its preview have Open in yaze
  (`--rom_file`) and Play in Mesen2 OOS, each in a new instance.
- With nothing selected inside a folder that has an AFS `.context` (the
  nearest one above it with entries, Home's excepted), the preview pane
  shows that context: the scratchpad's `state.md`, unfinished items by
  priority with a done count, the newest hivemind messages, scratchpad
  notes, and handoffs. It reads those entry points only, never the whole
  tree; items and messages open in a tab with the file selected. Each
  message lists its recipients with their ack state. Right-click an item to
  mark it pending, in progress, done, or failed (the task file is rewritten
  as `TaskQueue` would, with a new `updated_at`), or a message to mark it
  done for a recipient through `afs messages ack --done`. That entry needs
  the `afs` CLI, found through `AFS_ROOT`, `PATH`, or the usual checkouts.
- A folder with `tasks.org` or `tasks.md` at its top is a workspace, and
  shows as a board instead of a listing (⌥⌘4, or the first view segment;
  any other view leaves it, and each workspace you enter starts on it).
  Make Workspace Here, on the empty-space menu, adds `tasks.org` and
  `notes` and `ideas` folders. Tasks come from the org and Markdown files
  at the top: org headings with a TODO keyword (`* NEXT [#A] title :tag:`,
  with `DEADLINE:` or `SCHEDULED:` as the due date) and checkboxes in
  either format (`- [ ] [WAITING] title #tag due:2026-11-01`), skipping
  code blocks. They sit in halext-org's four columns, To Do, Doing,
  Blocked, and Done (NEXT is to do; ACTIVE, DOING, and `[-]` doing;
  WAITING, BLOCKED, and HOLD blocked; CANCELLED done; the newest 50 done
  show). Dragging a card to another column or Move to … on its menu
  rewrites its line in place: a keyword that already means the new state
  stays, otherwise TODO, ACTIVE, WAITING, or DONE is written; a ticked box
  keeps its tag. The line is found again by its text if lines above it
  moved, and the change is refused if it was edited. Click a card to
  preview its file, double-click to edit it at that line (Cursor's `-g`,
  else `emacsclient +line`). Notes list `notes/` newest first with their
  title and first line; ideas show `ideas/` as cards, images as
  thumbnails. The field above the board appends a task to the tasks file,
  or starts a note or idea in the tasks file's format and opens it for
  writing.
- yabai: viewer windows float on the raised layer through the rule
  `barista-agent-viewer` (title `… - Barista Viewer`), which the agent adds
  when it opens one. Browser windows match no rule and tile. macOS window
  tabbing is off in the agent, so neither ever becomes several windows.
- From a shell or skhd: `scripts/barista_agent.sh view|browse|open PATH`, or
  `group TITLE` for a dock group's callout.
  `browse` on a file (or an app) shows it selected in its folder, like
  `open -R`.

### `dock.json`

```json
{
  "settings": {
    "icon_size": 44,
    "magnification": 1.6,
    "spacing": 4,
    "reveal_push": 10,
    "reveal_delay": 0.5,
    "hide_delay": 0.3,
    "show_running": true,
    "show_trash": true,
    "expand_active_group": true,
    "shelf_days": 3,
    "theme": "barista",
    "files_browser": "barista",
    "focus_shortcut": "",
    "viewer_scroll_zoom": "normal",
    "viewer_loops_movies": true,
    "window_sizes": { "Ghostty": "medium" }
  },
  "pinned": [
    { "kind": "app", "path": "/Applications/Ghostty.app", "bundle_id": "com.mitchellh.ghostty" },
    { "kind": "group", "title": "AI Agents", "items": [
      { "kind": "app", "path": "/Applications/Cursor.app", "bundle_id": "com.todesktop.230313mzl4w4u92" },
      { "kind": "app", "path": "/Applications/Claude.app", "bundle_id": "com.anthropic.claudefordesktop" }
    ] },
    { "kind": "group", "title": "Oracle", "spaces": ["4"],
      "info_command": "~/.config/sketchybar/scripts/dock_oracle.py info", "items": [
      { "kind": "app", "path": "/Applications/Mesen2 OOS.app", "bundle_id": "ca.mesen.oos",
        "menu_command": "~/.config/sketchybar/scripts/dock_oracle.py sessions-menu",
        "menu": [
          { "kind": "action", "title": "Play Current Development Build",
            "command": "~/.config/sketchybar/scripts/dock_oracle.py play dev" }
        ] },
      { "kind": "action", "title": "Build ROM", "icon": "sf:hammer.fill", "notify": true,
        "lock": "oracle-roms", "command": "~/.config/sketchybar/scripts/dock_oracle.py build",
        "badge_command": "git -C ~/src/hobby/oracle-of-secrets status --porcelain | wc -l",
        "menu": [
          { "kind": "action", "title": "Transition Tests", "lock": "oracle-roms", "notify": true,
            "command": "~/.config/sketchybar/scripts/dock_oracle.py test transitions" }
        ] },
      { "kind": "group", "title": "Oracle Folders", "items": [
        { "kind": "folder", "title": "Oracle Source", "path": "~/src/hobby/oracle-of-secrets", "sort": "name" },
        { "kind": "folder", "title": "Build Output", "path": "~/src/hobby/oracle-of-secrets/Roms", "hidden": true }
      ] }
    ] },
    { "kind": "url", "title": "Oracle docs", "url": "https://example.com" }
  ],
  "others": [
    { "kind": "folder", "path": "~/src", "sort": "name" },
    { "kind": "folder", "path": "~/Downloads" }
  ],
  "system": [
    { "kind": "shelf" },
    { "kind": "controls" }
  ]
}
```

- Every setting is optional. `magnification` is the peak scale under the
  pointer (1 turns it off). Icons shrink when the dock would be wider than the
  screen.
- Reveal: with the pointer pinned at the bottom edge, keep pushing down
  `reveal_push` points (default 10), or rest there `reveal_delay` seconds
  (default 0.5). Setting either to 0 reveals the dock as soon as the pointer
  touches the edge.
- `theme: "barista"` tints the dock with the bar's `bar_color`,
  `popup_border_color`, `hover_color`, `menu_label_color`, and
  `submenu_hover_color` (the active-app dot and action tiles); `system` uses
  plain vibrancy and the system accent color.
- Item kinds: `app`, `folder` (optional `sort`), `file`, `action` (runs
  `command` with `zsh -lc`; optional `notify`, `terminal`, and `lock`), `url`,
  `group` (a titled list of `items`, which may hold groups; titles are unique
  across every group and subgroup; optional `spaces`, yabai space indexes or labels as strings,
  `expand: false`, and `info_command`), `shelf`, and `controls` (one of each
  per dock). Any item
  takes `badge_command`, `menu`, and `menu_command`; a group member takes `hidden`. `icon` takes `sf:<SF Symbol name>` or a path to an
  image or app; actions default to `sf:terminal`, URLs to `sf:globe`, the
  shelf to a tray, the controls to switches, and groups to a grid of their apps. A folder or file
  whose `icon` is an app gets a small folder or document mark so it does not
  pass for the app (packages with no icon of their own, such as
  `.yazeproj`, otherwise show a blank document). In a group's callout,
  members with their own art stay in the icon grid while plain folders (no
  `icon`, not a package) list below it as rows with their path; clicking one
  browses it in place, and Back returns to the group.
- Requires macOS 14. Unit tests: `swift test --package-path native/BaristaAgent`
  (run by `scripts/check_scripts.sh` on macOS). Code layout, the per-frame
  motion model, and coordinate spaces are in
  [`native/BaristaAgent/README.md`](../../native/BaristaAgent/README.md).

## Next slices

- EventKit reminders and calendar into the agent cache, surfaced by the
  existing calendar/task popups.
- halext-org API client in the agent (admin status, reminders sync).
- Move remaining Cortex modules (Secrets, Services, Processes, widgets) into
  the agent or retire them; keep Oracle standalone.
