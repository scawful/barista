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
  pinned, then `others` and the Trash. Running apps update from NSWorkspace
  notifications, with no polling; the file and Barista's `state.json` are
  re-read on reveal only when their modification time changed.
- Editing: drag an icon sideways to reorder it, or above the dock to remove
  it; drop apps from Finder onto the bar to pin them, folders, files, and web
  links to add them to `others`. Right-click offers Add to Group (an existing
  group or New Group…) and, under Options, Keep in Dock / Remove from Dock. If
  `dock.json` fails to parse, the menu says so and edits are refused rather
  than overwriting it.
- Drops onto icons: apps open the files, folders ask at the pointer whether
  to copy or move them, the Trash recycles them, action tiles
  receive their paths as arguments, groups take dropped apps, and the shelf
  keeps files and text.
- Groups show their first four apps in a tinted tile and open a callout grid
  with each app's running dot; clicking an app opens it, and right-click has
  the app menu below plus Remove from Group. The group's own menu has
  Rename…, Ungroup, and Remove from Dock.
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
  `~/Library/Logs/sketchybar-barista/dock-actions/<title>.log`, and the menu
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
- The shelf (`{ "kind": "shelf" }`) is a scratch space: drop files to keep a
  reference (nothing moves), or text to save it as a snippet. Its callout
  lists them newest first for opening or dragging out, with Clear Shelf and
  per-item Remove from Shelf. Items go after `shelf_days` (default 3), and
  missing files drop off. State lives in `~/.local/state/barista/shelf.json`
  (override with `BARISTA_SHELF_FILE`), snippets in `shelf/snippets/` next
  to it.
- Right-click on an app follows the macOS Dock's order: its windows (one
  yabai query per reveal), then Barista's own entries — the tile's `menu`
  actions, Add to Group, Window (Float, Sticky, Zoom to Fill, Center, Utility
  Size, Tile Here, Next Display, Minimize, Close, applied to the focused or
  first window), Move to Space (every window of the app), Gather Windows
  Here, New Windows (Barista's float/tile app default, or Follow yabai
  Rules), and Window Level (Normal, Raised, Always on Top, or Follow yabai
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
  Images fit the window, pinch to zoom, and step through the folder's other
  images with ←/→ (0 fits, 1 is actual size, double-click toggles). Both
  reload when the file is saved. ⌘E opens the file in its editor, Escape or
  ⌘W closes.
- Barista Files is a Finder replacement that tiles: one window with its tabs
  inside it, back/forward history per tab, a path bar, a sidebar of standard
  places and the dock's folders, a sortable list, a preview pane (⇧⌘P),
  Quick Look (Space; arrows follow the list), drag in and out, and Finder's
  shortcuts (⌘T, ⌘W, ⌘N, ⌘[ and ⌘], ⌘↑, ⌘↓, ⇧⌘., ⌘F, ⌃Tab, ⌘1–9, ⌘⌫, ⇧⌘N
  New Folder, ⌘D Duplicate, ⌘C then ⌘V to copy or ⌥⌘V to move here).
  Return opens the selection; Rename (in place) is on the right-click menu,
  with Open With, Open in Cursor or Emacs, Terminal Here, and Copy Relative
  Path (relative to the enclosing git repo or worktree). Right-click on empty
  space for the folder's own menu. Name clashes keep both (`name 2`), copies
  are `name copy`, and a failed operation shows an alert. The Finder tile
  opens it (⌥-click opens Finder; `files_browser: "finder"` turns this off),
  as does Browse in Barista Files on any folder callout or file. While a
  Files or viewer window is open the agent is a regular app, so ⌘Tab
  reaches it; it goes back to an accessory when the last one closes.
- Inside a git repo, each changed file in the list carries a letter (M, A,
  D, R, ? untracked, U conflicted) and folders that hold changes a dot. The
  sidebar's Repository section shows the branch, change count, and
  ahead/behind, and lists the repo's worktrees by branch; clicking one goes
  to the same folder in that worktree, or its top when the folder isn't
  there. git runs after the listing is shown and without optional locks, so
  browsing never takes `index.lock` from an agent committing in the repo.
- ⌘K (or ⇧⌘G) jumps to a folder: type parts of its name or path (`oos
  core`); Return goes, ⌘Return opens a tab, a path starting with `/` or `~`
  goes straight there. Candidates are the places, zoxide's folders by
  frecency, and every repo under `~/src` (found with `fd`), read again after
  five minutes. Folders you browse are added to zoxide, as `cd` does.
- The preview pane renders Markdown and org (headings, lists, src blocks,
  tables, links), shows code and other text unwrapped in a monospaced view
  (first 256 KB), indents minified JSON, and reads a SNES ROM's internal
  header: title, LoROM/HiROM/ExHiROM, ROM and SRAM size, region, version,
  and the stored checksum against the computed one (skipped when the size
  has no standard mirroring). Images and anything else fall back to details.
- With nothing selected inside a folder that has an AFS `.context` (the
  nearest one above it with entries, Home's excepted), the preview pane
  shows that context: the scratchpad's `state.md`, unfinished items by
  priority with a done count, the newest hivemind messages, scratchpad
  notes, and handoffs. It reads those entry points only, never the whole
  tree; items and messages open in a tab with the file selected.
- yabai: viewer windows float on the raised layer through the rule
  `barista-agent-viewer` (title `… - Barista Viewer`), which the agent adds
  when it opens one. Browser windows match no rule and tile. macOS window
  tabbing is off in the agent, so neither ever becomes several windows.
- From a shell or skhd: `scripts/barista_agent.sh view|browse|open PATH`.

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
    "files_browser": "barista"
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
      { "kind": "folder", "title": "Oracle Source", "path": "~/src/hobby/oracle-of-secrets", "sort": "name" }
    ] },
    { "kind": "url", "title": "Oracle docs", "url": "https://example.com" }
  ],
  "others": [
    { "kind": "folder", "path": "~/src", "sort": "name" },
    { "kind": "folder", "path": "~/Downloads" },
    { "kind": "shelf" }
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
  `group` (a titled list of `items`; titles are unique, groups do not nest;
  optional `spaces`, yabai space indexes or labels as strings,
  `expand: false`, and `info_command`), and `shelf` (one per dock). Any item
  takes `badge_command`, `menu`, and `menu_command`. `icon` takes `sf:<SF Symbol name>` or a path to an
  image or app; actions default to `sf:terminal`, URLs to `sf:globe`, the
  shelf to a tray, and groups to a grid of their apps. A folder or file
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

- Barista Files: Get Info, column and icon views, syntax colors for code
  previews, and acting on AFS items (status, ack) from the context panel.
- EventKit reminders and calendar into the agent cache, surfaced by the
  existing calendar/task popups.
- halext-org API client in the agent (admin status, reminders sync).
- Move remaining Cortex modules (Secrets, Services, Processes, widgets) into
  the agent or retire them; keep Oracle standalone.
