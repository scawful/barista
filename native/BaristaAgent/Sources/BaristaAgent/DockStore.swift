import AppKit
import Combine
import SwiftUI

struct DockTile: Identifiable, Equatable {
  enum Section { case pinned, running, others, trash }

  let id: String
  let item: DockItem
  /// The app, file, or folder on disk, or the link for URL tiles.
  let url: URL?
  let section: Section
  let pid: pid_t?
  let isActive: Bool
  let isHidden: Bool
  /// A group's members; empty for every other kind.
  var children: [DockTile] = []
  /// A subgroup's title without the words it shares with its parent's.
  var shortName: String?
  /// Finder's name for `url`, looked up once when the tile is made: views
  /// read `name` every frame, and Launch Services takes milliseconds per app.
  var fileName: String?
  /// The group holding this tile, for members drawn in an open group.
  var parentGroup: String?

  var isRunning: Bool { pid != nil || children.contains(where: \.isRunning) }

  /// Group titles are unique across the dock, so a subgroup is often named
  /// after its parent ("Oracle Tools" in "Oracle of Secrets"); it shows as "Tools".
  static func shortTitle(_ title: String, under parent: String) -> String? {
    let words = title.split(separator: " ")
    let shared = zip(words, parent.split(separator: " ")).prefix { $0.lowercased() == $1.lowercased() }.count
    guard shared > 0, shared < words.count else { return nil }
    return words.dropFirst(shared).joined(separator: " ")
  }

  /// Members of this group and of its subgroups, depth first.
  var descendants: [DockTile] { children.flatMap { [$0] + $0.descendants } }

  /// Members drawn in the group's grid and inline; hidden ones wait for Show Hidden or a search.
  var visibleChildren: [DockTile] { children.filter { $0.item.hidden != true } }

  /// This tile is the app, or a group holding it at any depth.
  func contains(app bundleID: String) -> Bool {
    item.bundleID == bundleID || children.contains { $0.contains(app: bundleID) }
  }

  var name: String {
    if let shortName { return shortName }
    if let title = item.title, !title.isEmpty { return title }
    if item.kind == .shelf { return "Shelf" }
    if item.kind == .controls { return "Controls" }
    if let fileName { return fileName }
    if let url, url.isFileURL { return FileManager.default.displayName(atPath: url.path) }
    return item.command ?? item.url ?? ""
  }

  /// The top-level list holding this tile; nil for group members.
  var list: DockConfig.List? {
    guard parentGroup == nil else { return nil }
    switch section {
    case .pinned: return .pinned
    case .others: return .others
    case .running, .trash: return nil
    }
  }

  /// What dragging this tile reorders: its list, or its open group's members.
  var dragScope: DockScene.Scope? {
    parentGroup.map(DockScene.Scope.group) ?? list.map(DockScene.Scope.list)
  }

  var acceptsDrops: Bool {
    section == .trash || [.app, .folder, .action, .group, .shelf].contains(item.kind)
  }

  /// Quitting Finder from a dock leaves no way to get it back from the dock.
  var canQuit: Bool { pid != nil && item.bundleID != "com.apple.finder" }
}

/// Pins live in Barista's own `dock.json`, copied from the native Dock the
/// first time, so editing them never touches the native Dock. Running apps
/// that are not pinned follow the pins in launch order, like the native Dock.
final class DockStore: ObservableObject {
  @Published private(set) var pinned: [DockTile] = []
  @Published private(set) var running: [DockTile] = []
  @Published private(set) var others: [DockTile] = []
  @Published private(set) var trash: DockTile?
  @Published private(set) var settings = DockSettings()
  @Published private(set) var theme = DockTheme.system
  @Published private(set) var configError: String?
  @Published private(set) var trashFull = false
  @Published private(set) var windowsByPID: [pid_t: [YabaiWindow]] = [:]
  @Published private(set) var spaces: [YabaiSpace] = []
  /// Agent sessions, re-read whenever the bar's agents widget rewrites them.
  @Published private(set) var agents = AgentSnapshot()
  @Published private(set) var attention = AgentAttention()
  /// Questions the attention card set aside, by session ID.
  @Published private var setAside: [String: String] = [:]
  /// Groups drawn open because one of their apps is frontmost or their space is.
  @Published private(set) var expanded: Set<String> = []
  /// Barista's float/tile default for new windows, by app name.
  @Published private(set) var windowDefaults: [String: String] = [:]
  /// Barista's stacking level for every window of an app, by app name.
  @Published private(set) var windowLevels: [String: String] = [:]

  let configURL = DockConfigFile.url
  let actions = ActionRunner()
  let shelf = Shelf()
  private var config = DockConfig()
  private var configStamp: Date?
  private var themeStamp: String?
  private var agentStamp: Date?
  private var resolvedURLs: [String: URL] = [:]
  /// Finder names by path; cleared with `resolvedURLs` when the config reloads.
  private var fileNames: [String: String] = [:]
  private var images: [String: TileImage] = [:]
  /// Tiles whose icons `warmImages` has yet to draw, last first.
  private var unwarmed: [DockTile] = []
  private var observers: [NSObjectProtocol] = []
  /// Observations don't retain what they watch, so each keeps its app alive.
  private var policyWatches: [pid_t: (app: NSRunningApplication, watch: NSKeyValueObservation)] = [:]
  private var cancellables: Set<AnyCancellable> = []
  private var agentTimer: Timer?
  private let windowQueue = DispatchQueue(label: "dev.barista.agent.windows", qos: .userInitiated)
  private static let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")

  init() {
    let center = NSWorkspace.shared.notificationCenter
    let names: [Notification.Name] = [
      NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
      NSWorkspace.didHideApplicationNotification,
      NSWorkspace.didUnhideApplicationNotification,
    ]
    observers = names.map { name in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.refresh()
      }
    }
    observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                        object: nil, queue: .main) { [weak self] note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      if let id = app?.bundleIdentifier { self?.attention.clear(app: id) }
      self?.refresh()
    })
    observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                        object: nil, queue: .main) { [weak self] _ in
      self?.refreshSpaces()
    })
    for child in [actions.objectWillChange, shelf.objectWillChange] {
      child.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }
    // A build or a prune changes what the group info rows report.
    actions.onFinish = { [weak self] _ in
      guard let self else { return }
      self.actions.expireInfos()
      self.actions.refreshInfos(self.commands(\.infoCommand))
      self.actions.refreshMenus(self.commands(\.menuCommand))
    }
    // Sessions finish while the dock is hidden; a stat every few seconds is all this costs.
    agentTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
      self?.loadAgents()
    }
    agentTimer?.tolerance = 2
    reload()
    refreshSpaces()
  }

  /// Every section left to right; the Trash closes the last one.
  var sections: [[DockTile]] {
    [pinned, running, others + (trash.map { [$0] } ?? [])]
  }

  /// Every drawable tile by ID, including the members of open groups.
  var tilesByID: [String: DockTile] {
    var tiles: [String: DockTile] = [:]
    for tile in sections.joined() {
      tiles[tile.id] = tiles[tile.id] ?? tile
      if expanded.contains(tile.id) {
        for child in tile.visibleChildren { tiles[child.id] = tiles[child.id] ?? child }
      }
    }
    return tiles
  }

  /// Runs on every reveal; rereads the config and theme only when their files changed.
  func reload() {
    loadConfig()
    loadTheme()
    refreshTrash()
    loadAgents()
    shelf.load(maxAge: settings.shelfDays * 86400)
    refresh()
    actions.refreshBadges(commands(\.badgeCommand))
    actions.refreshInfos(commands(\.infoCommand))
    actions.refreshMenus(commands(\.menuCommand))
    warmImages()
  }

  /// Drawing every workspace icon takes a few hundred milliseconds, which the
  /// first reveal would otherwise spend at once. Icons are drawn here a few
  /// milliseconds at a time, outside menu tracking and drags.
  /// Members go before their groups, whose grids would otherwise draw them in one turn.
  private func warmImages() {
    let idle = unwarmed.isEmpty
    unwarmed = sections.joined().flatMap { $0.descendants.reversed() + [$0] }.reversed()
    if idle { warmNextImages() }
  }

  private func warmNextImages() {
    let start = CFAbsoluteTimeGetCurrent()
    while !unwarmed.isEmpty, CFAbsoluteTimeGetCurrent() - start < 0.008 {
      _ = image(for: unwarmed.removeLast())
    }
    guard !unwarmed.isEmpty else { return }
    RunLoop.main.perform(inModes: [.default]) { [weak self] in self?.warmNextImages() }
  }

  /// A tile's badge: its badge command's output, the shelf's item count, or
  /// how many agent sessions wait on you (summed over a group's apps).
  /// Sessions that are only running badge nothing; the group callout counts them.
  func badgeText(for tile: DockTile) -> String? {
    if let text = actions.badges[tile.id] { return text }
    if tile.item.kind == .shelf { return shelf.entries.isEmpty ? nil : "\(shelf.entries.count)" }
    let count = waiting(on: tile)
    return count > 0 ? "\(count)" : nil
  }

  /// Red when the badge counts sessions waiting on you, as the bar does.
  func badgeColor(for tile: DockTile) -> Color {
    let counted = actions.badges[tile.id] == nil && tile.item.kind != .shelf
    return counted && waiting(on: tile) > 0 ? theme.failure : theme.accent
  }

  /// Agent sessions in this app, or in this group's apps, that wait on you.
  func waiting(on tile: DockTile) -> Int {
    if tile.item.kind == .group { return tile.children.reduce(0) { $0 + waiting(on: $1) } }
    return tile.item.bundleID.flatMap { agents.needs[$0] } ?? 0
  }

  /// An agent session in this app, or in one of this group's apps, finished.
  func hasFinished(_ tile: DockTile) -> Bool {
    if tile.item.kind == .group { return tile.children.contains(where: hasFinished) }
    return tile.item.bundleID.map(attention.apps.contains) ?? false
  }

  /// Sessions waiting on you that the attention card offers, oldest feed
  /// order first; Later or Open sets a question aside until it changes.
  var waitingSessions: [AgentSession] {
    agents.sessions.filter { !$0.needs.isEmpty && setAside[$0.id] != $0.needs }
  }

  func setAside(_ session: AgentSession) {
    setAside[session.id] = session.needs
  }

  /// Clears a finished session's mark without bringing it forward.
  func markSeen(_ session: AgentSession) {
    attention.clear(session: session.id)
  }

  /// Sessions shown in a group's callout: those of its apps, the ones waiting
  /// on you first (the feed already lists them first).
  func sessions(in group: DockTile) -> [AgentSession] {
    let apps = Set(group.descendants.compactMap(\.item.bundleID))
    return agents.sessions.filter { apps.contains($0.app) }
  }

  func info(in group: DockTile) -> [InfoRow] {
    actions.infos[group.id] ?? []
  }

  /// A click on an info row. Returns true when it opened something, so the
  /// callout can close; runs keep it open to show their progress.
  func activate(_ row: InfoRow, in group: DockTile) -> Bool {
    if let title = row.action, !title.isEmpty {
      guard let member = group.descendants.first(where: { $0.name == title }) else {
        NSSound.beep()
        return false
      }
      open(member)
      return member.item.kind != .action
    }
    if let command = row.run, !command.isEmpty {
      start(rowID(row, in: group), item: DockItem(kind: .action, title: row.title, command: command), title: row.title)
      return false
    }
    guard let target = row.open, !target.isEmpty else { return false }
    if target.contains("://"), let url = URL(string: target) {
      NSWorkspace.shared.open(url)
    } else {
      PopoverController.open(URL(fileURLWithPath: (target as NSString).expandingTildeInPath))
    }
    return true
  }

  /// The run a row shows: the member it names, or its own command's.
  func runID(for row: InfoRow, in group: DockTile) -> String? {
    if let title = row.action, let member = group.descendants.first(where: { $0.name == title }) {
      return member.id
    }
    return (row.run ?? "").isEmpty ? nil : rowID(row, in: group)
  }

  func actionState(for row: InfoRow, in group: DockTile) -> ActionRunner.State? {
    runID(for: row, in: group).flatMap { actions.states[$0] }
  }

  /// What a tile's status ring shows: its own run, else its menu entries',
  /// else (for a group) its members'. Running wins over failed over passed.
  func actionState(for tile: DockTile) -> ActionRunner.State? {
    var states = [actions.states[tile.id]]
    states += Self.menuActions(menuEntries(for: tile)).map { actions.states[menuID($0, of: tile)] }
    states += tile.children.map { actionState(for: $0) }
    let known = states.compactMap { $0 }
    if let active = known.first(where: \.isActive) { return active }
    if let failed = known.first(where: { if case .failed = $0 { return true } else { return false } }) {
      return failed
    }
    return known.first
  }

  /// A tile's extra right-click entries: its `menu`, then its `menu_command`'s.
  func menuEntries(for tile: DockTile) -> [DockItem] {
    (tile.item.menu ?? []) + (actions.menus[tile.id] ?? [])
  }

  func menuID(_ entry: DockItem, of tile: DockTile) -> String {
    tile.id + "/" + (entry.title ?? entry.command ?? "")
  }

  /// A right-click entry: runs it, or shows the output of its last failure.
  func runMenuEntry(_ entry: DockItem, of tile: DockTile) {
    start(menuID(entry, of: tile), item: entry, title: entry.title ?? tile.name)
  }

  /// Every action in a menu, through its submenus.
  static func menuActions(_ entries: [DockItem]) -> [DockItem] {
    entries.flatMap { $0.kind == .group ? menuActions($0.items ?? []) : [$0] }
  }

  func focus(_ session: AgentSession) {
    attention.clear(session: session.id)
    guard !session.focus.isEmpty else { return }
    launch("/bin/zsh", ["-lc", session.focus])
  }

  func refresh() {
    let apps = NSWorkspace.shared.runningApplications
    watchPolicies(of: apps)
    var unclaimed: [String: NSRunningApplication] = [:]
    var keysByPath: [String: String] = [:]
    var launchOrder: [String] = []
    let me = ProcessInfo.processInfo.processIdentifier
    // The agent itself turns regular while a Files or viewer window is open.
    for app in apps where app.activationPolicy == .regular && !app.isTerminated && app.processIdentifier != me {
      guard let key = app.bundleIdentifier ?? app.bundleURL?.path, unclaimed[key] == nil else { continue }
      unclaimed[key] = app
      if let path = app.bundleURL?.path { keysByPath[path] = key }
      launchOrder.append(key)
    }
    func claim(_ item: DockItem) -> NSRunningApplication? {
      guard item.kind == .app else { return nil }
      if let id = item.bundleID, let app = unclaimed.removeValue(forKey: id) { return app }
      guard let path = item.expandedPath, let key = keysByPath[path] else { return nil }
      return unclaimed.removeValue(forKey: key)
    }

    func tiles(_ items: [DockItem], section: DockTile.Section, in parent: DockTile? = nil) -> [DockTile] {
      items.map { item in
        var tile = self.tile(for: item, section: section, app: claim(item))
        if item.kind == .group {
          if let parent { tile.shortName = DockTile.shortTitle(tile.name, under: parent.name) }
          let children = tiles(item.items ?? [], section: section, in: tile)
          tile = DockTile(id: tile.id, item: item, url: nil, section: section, pid: nil,
                          isActive: children.contains(where: \.isActive), isHidden: false, children: children,
                          shortName: tile.shortName)
        }
        tile.parentGroup = parent?.id
        return tile
      }
    }
    let pinned = tiles(config.pinned, section: .pinned)
    let others = tiles(config.others, section: .others)
    let running = !settings.showRunning ? [] : launchOrder.compactMap { key -> DockTile? in
      guard let app = unclaimed[key], let url = app.bundleURL else { return nil }
      let item = DockItem(kind: .app, path: DockConfigFile.tilde(url.path), bundleID: app.bundleIdentifier)
      return tile(for: item, section: .running, app: app)
    }
    let trash = !settings.showTrash ? nil : DockTile(
      id: "trash", item: DockItem(kind: .folder, path: "~/.Trash", title: "Trash"),
      url: Self.trashURL, section: .trash, pid: nil, isActive: false, isHidden: false)

    let space = spaces.first(where: \.hasFocus)
    let expanded = Set((pinned + others).filter { group in
      guard group.item.kind == .group, group.item.expand != false, !group.visibleChildren.isEmpty else { return false }
      if settings.expandActiveGroup, group.isActive { return true }
      return space?.matches(group.item.spaces ?? []) ?? false
    }.map(\.id))

    if pinned != self.pinned { self.pinned = pinned }
    if running != self.running { self.running = running }
    if others != self.others { self.others = others }
    if trash != self.trash { self.trash = trash }
    if expanded != self.expanded { self.expanded = expanded }
  }

  /// Closing the last window of a menu bar app (LM Studio, Docker) turns it
  /// into an accessory without quitting, and no workspace notification says so.
  private func watchPolicies(of apps: [NSRunningApplication]) {
    let pids = Set(apps.map(\.processIdentifier))
    for (pid, entry) in policyWatches where !pids.contains(pid) {
      // Before the app goes: a watched object must not outlive its observation.
      entry.watch.invalidate()
      policyWatches[pid] = nil
    }
    for app in apps where policyWatches[app.processIdentifier] == nil && app.bundleURL != nil {
      let watch = app.observe(\.activationPolicy) { [weak self] _, _ in
        DispatchQueue.main.async { self?.refresh() }
      }
      policyWatches[app.processIdentifier] = (app, watch)
    }
  }

  /// One yabai query per reveal; the context menu reads the cached result.
  func refreshWindows() {
    windowQueue.async { [weak self] in
      guard let windows = Yabai.query("windows", as: [YabaiWindow].self) else { return }
      let grouped = Dictionary(grouping: windows.filter { $0.subrole == "AXStandardWindow" }, by: \.pid)
      DispatchQueue.main.async { self?.windowsByPID = grouped }
    }
    refreshSpaces()
  }

  /// Spaces for the Move to Space menu and for groups that open on a space.
  func refreshSpaces() {
    windowQueue.async { [weak self] in
      guard let spaces = Yabai.query("spaces", as: [YabaiSpace].self) else { return }
      DispatchQueue.main.async {
        guard let self, spaces != self.spaces else { return }
        self.spaces = spaces
        self.refresh()
      }
    }
  }

  /// Called for every tile on every frame, so icons are cached as single
  /// bitmaps at the largest size the dock draws them. Workspace icons hold
  /// many representations and would otherwise be redrawn at each new
  /// magnified size.
  func image(for tile: DockTile) -> TileImage {
    let key = imageKey(for: tile)
    if let cached = images[key] { return cached }
    let image: TileImage
    if tile.section == .trash {
      let name = trashFull ? NSImage.trashFullName : NSImage.trashEmptyName
      image = .image(NSImage(named: name) ?? NSWorkspace.shared.icon(forFile: Self.trashURL.path))
    } else if let custom = TileImage.custom(tile.item.icon) {
      image = custom
    } else if tile.item.kind == .group {
      image = .group(tile.visibleChildren.prefix(4).map(self.image(for:)))
    } else {
      image = defaultImage(for: tile)
    }
    var result = image.rasterized(pixels: iconPixels)
    if case .image(let drawn) = result, let symbol = tile.item.borrowedIconBadge {
      result = .badged(drawn, symbol: symbol)
    }
    if images.count > 256 { images.removeAll() }
    images[key] = result
    return result
  }

  /// Groups in the dock and their subgroups, for "Add to Group" menus.
  var groups: [DockTile] {
    (pinned + others).flatMap { [$0] + $0.descendants }.filter { $0.item.kind == .group }
  }

  func group(id: String) -> DockTile? { groups.first { $0.id == id } }

  /// "Oracle › Tools" for a subgroup; a top-level group's own name.
  func path(of group: DockTile) -> String {
    guard let parent = group.parentGroup.flatMap(self.group(id:)) else { return group.name }
    return path(of: parent) + " › " + group.name
  }

  // MARK: Actions

  /// Opens a tile's target. Folder stacks, the shelf, and the controls are
  /// opened by the controller instead. A failed action shows its output; the next click runs it.
  func open(_ tile: DockTile) {
    switch tile.item.kind {
    case .app:
      guard let url = tile.url else { return }
      if tile.item.bundleID == "com.apple.finder", settings.filesBrowser == "barista",
         !NSEvent.modifierFlags.contains(.option) {
        BrowserController.shared.show()
        return
      }
      if let id = tile.item.bundleID { attention.clear(app: id) }
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    case .file:
      if let url = tile.url { PopoverController.open(url) }
    // The Trash stays Finder's: reading it takes Full Disk Access.
    case .folder where tile.section != .trash && settings.filesBrowser == "barista"
      && !NSEvent.modifierFlags.contains(.option):
      if let url = tile.url { BrowserController.shared.open(url) }
    case .folder, .url:
      if let url = tile.url { NSWorkspace.shared.open(url) }
    case .action:
      start(tile.id, item: tile.item, title: tile.name)
    case .group, .shelf, .controls:
      break
    }
  }

  /// A running action beeps, a failed one shows its output, others run.
  private func start(_ id: String, item: DockItem, title: String) {
    switch actions.states[id] {
    case .running?, .stopping?: NSSound.beep()
    case .failed?: actions.showOutput(id)
    default: actions.run(id, item: item, title: title)
    }
  }

  private func rowID(_ row: InfoRow, in group: DockTile) -> String {
    group.id + "/run:" + (row.run ?? "")
  }

  /// Files dropped from Finder: the Trash recycles them, apps open them,
  /// folders copy or move them (you choose), and actions receive their paths
  /// as arguments.
  func drop(_ urls: [URL], on tile: DockTile) {
    guard !urls.isEmpty else { return }
    if tile.section == .trash {
      NSWorkspace.shared.recycle(urls) { [weak self] recycled, error in
        if let error { Self.log("could not move \(urls.map(\.path)) to the Trash: \(error)") }
        guard !recycled.isEmpty else { return }
        DispatchQueue.main.async { self?.trashFull = true }
      }
      return
    }
    switch tile.item.kind {
    case .app:
      if urls.allSatisfy({ $0.pathExtension == "app" }) {
        let list = tile.list ?? .pinned
        let index = tile.list == nil ? nil : config[list].firstIndex { $0.key == tile.id }
        add(urls, to: list, at: index)
      } else if let app = tile.url {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
      }
    case .folder:
      guard let folder = tile.url else { return }
      Self.askTransfer(urls, into: folder)
    case .action:
      actions.run(tile, arguments: urls.map(\.path))
    case .group:
      let apps = urls.filter { $0.pathExtension == "app" }.map(DockItem.init(droppedURL:))
      edit { config in apps.forEach { config.add($0, toGroup: tile.id) } }
    case .shelf:
      shelf.add(urls)
    case .file, .url, .controls:
      break
    }
  }

  /// What a member dragged inside a group callout carries, before its ID.
  static let memberDragPrefix = "barista-dock-member:"

  /// Text dropped on the shelf becomes a snippet; elsewhere it is ignored.
  func drop(text: String, on tile: DockTile) {
    if tile.item.kind == .shelf, !text.hasPrefix(Self.memberDragPrefix) { shelf.add(text: text) }
  }

  func add(_ urls: [URL], to list: DockConfig.List, at index: Int?) {
    edit { $0.insert(urls.map(DockItem.init(droppedURL:)), at: index, in: list) }
  }

  func addToGroup(_ tile: DockTile, group: DockTile) {
    edit { $0.add(tile.item, toGroup: group.id) }
  }

  func newGroup(with tile: DockTile) {
    guard let title = Self.prompt("New Group", message: "Name the group for \(tile.name).", value: "") else { return }
    edit { config in
      if !config.makeGroup(title: title, with: tile.item) { NSSound.beep() }
    }
  }

  func takeOut(_ tile: DockTile, from group: DockTile) {
    edit { $0.takeOut(tile.id, fromGroup: group.id) }
  }

  func setHidden(_ tile: DockTile, _ hidden: Bool) {
    edit { $0.setHidden(tile.id, hidden) }
  }

  func ungroup(_ group: DockTile) {
    edit { $0.ungroup(group.id) }
  }

  func rename(_ group: DockTile) {
    let current = group.item.title ?? group.name
    guard let title = Self.prompt("Rename Group", message: "Group names are unique across the dock.", value: current),
          title != current else { return }
    edit { config in
      if !config.renameGroup(group.id, to: title) { NSSound.beep() }
    }
  }

  var hasControls: Bool { (pinned + others).contains { $0.item.kind == .controls } }

  func addControls() {
    edit { $0.insert([DockItem(kind: .controls)], at: nil, in: .others) }
  }

  func keepInDock(_ tile: DockTile) {
    edit { $0.insert([tile.item], at: nil, in: .pinned) }
  }

  func remove(_ tile: DockTile) {
    edit { $0.remove(key: tile.id) }
  }

  /// `index` counts what the dock draws: for a member, its group's visible members.
  func move(_ tile: DockTile, to index: Int) {
    if let group = tile.parentGroup.flatMap(group(id:)) {
      let rest = group.visibleChildren.map(\.id).filter { $0 != tile.id }
      edit { $0.place(tile.id, before: index < rest.count ? rest[index] : nil, inGroup: group.id) }
      return
    }
    guard let list = tile.list else { return }
    edit { $0.move(key: tile.id, to: index, in: list) }
  }

  /// A member dropped on another in the group's callout: onto a subgroup it
  /// moves in; onto anything else it takes that member's place.
  func drop(member id: String, on target: DockTile, in group: DockTile) {
    guard id != target.id, let member = group.children.first(where: { $0.id == id }) else { return }
    if target.item.kind == .group {
      addToGroup(member, group: target)
      return
    }
    let ids = group.children.map(\.id)
    guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target.id) else { return }
    let before = from < to ? (to + 1 < ids.count ? ids[to + 1] : nil) : target.id
    edit { $0.place(id, before: before, inGroup: group.id) }
  }

  func hide(_ tile: DockTile) { runningApplication(tile)?.hide() }
  func unhide(_ tile: DockTile) { runningApplication(tile)?.unhide() }
  func quit(_ tile: DockTile) { runningApplication(tile)?.terminate() }
  func forceQuit(_ tile: DockTile) { runningApplication(tile)?.forceTerminate() }

  func reveal(_ tile: DockTile) {
    if let url = tile.url, url.isFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
  }

  func focus(_ window: YabaiWindow) {
    if window.isMinimized {
      Yabai.runAsync(["window", "--deminimize", String(window.id)])
    }
    Yabai.runAsync(["window", "--focus", String(window.id)])
  }

  // MARK: Windows

  func windows(of tile: DockTile) -> [YabaiWindow] {
    tile.pid.flatMap { windowsByPID[$0] } ?? []
  }

  /// The window that single-window actions apply to: the focused one, else
  /// the first one on screen.
  func primaryWindow(of tile: DockTile) -> YabaiWindow? {
    let windows = windows(of: tile)
    return windows.first(where: \.hasFocus) ?? windows.first { !$0.isMinimized } ?? windows.first
  }

  var focusedSpace: YabaiSpace? { spaces.first(where: \.hasFocus) }

  /// A `yabai_control.sh` window action (`window-center`, `window-toggle-float`, ...).
  func windowAction(_ action: String, on window: YabaiWindow) {
    Yabai.control([([action], window)]) { [weak self] in self?.refreshWindows() }
  }

  func move(_ tile: DockTile, toSpace index: Int) {
    let steps = windows(of: tile).filter { $0.space != index }.map { (["window-space", String(index)], Optional($0)) }
    guard !steps.isEmpty else { return }
    Yabai.control(steps) { [weak self] in self?.refreshWindows() }
  }

  func gatherWindows(_ tile: DockTile) {
    guard let space = focusedSpace else { return }
    move(tile, toSpace: space.index)
  }

  /// The name yabai and Barista's saved state know the app by.
  private func appName(_ tile: DockTile) -> String? {
    windows(of: tile).first?.app ?? runningApplication(tile)?.localizedName
  }

  /// Barista's app default for new windows: `float`, `tile`, or `unset`.
  func setWindowDefault(_ tile: DockTile, mode: String) {
    guard let app = appName(tile) else { return }
    let arguments = mode == "unset" ? ["app-default", "unset", app] : ["app-default", "set", app, mode]
    Yabai.control([(arguments, nil)]) { [weak self] in
      self?.themeStamp = nil
      self?.loadTheme()
    }
  }

  func windowDefault(_ tile: DockTile) -> String? {
    appName(tile).flatMap { windowDefaults[$0] }
  }

  /// Where every window of the app stacks: `normal`, `raised`, `top`, or
  /// `unset` to hand stacking back to the yabai rules. Open windows move too.
  func setWindowLevel(_ tile: DockTile, level: String) {
    guard let app = appName(tile) else { return }
    let arguments = level == "unset" ? ["app-level", "unset", app] : ["app-level", "set", app, level]
    Yabai.control([(arguments, nil)]) { [weak self] in
      self?.themeStamp = nil
      self?.loadTheme()
    }
  }

  func windowLevel(_ tile: DockTile) -> String? {
    appName(tile).flatMap { windowLevels[$0] }
  }

  func editConfig() {
    launch("/usr/bin/open", ["-t", configURL.path])
  }

  func emptyTrash() {
    let alert = NSAlert()
    alert.messageText = "Empty the Trash?"
    alert.informativeText = "Items in the Trash are deleted immediately. You can't undo this."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Empty Trash")
    alert.addButton(withTitle: "Cancel")
    guard Self.runModal(alert) == .alertFirstButtonReturn else { return }
    launch("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"]) { [weak self] in
      self?.trashFull = false
      self?.refreshTrash()
    }
  }

  // MARK: Private

  /// The agent has to be active to show an alert; hand focus back afterwards.
  private static func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
    let previous = NSWorkspace.shared.frontmostApplication
    NSApp.activate(ignoringOtherApps: true)
    defer { previous?.activate() }
    return alert.runModal()
  }

  private static func prompt(_ title: String, message: String, value: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    field.stringValue = value
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard runModal(alert) == .alertFirstButtonReturn else { return nil }
    let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  private func loadConfig() {
    guard let stamp = DockConfigFile.modificationDate(configURL) else {
      config = DockConfigFile.seedFromNativeDock()
      configError = nil
      applySettings()
      persist()
      return
    }
    guard stamp != configStamp else { return }
    configStamp = stamp
    do {
      config = try DockConfigFile.decode(Data(contentsOf: configURL))
      configError = nil
    } catch {
      configError = "dock.json has an error; dock edits are paused until it is fixed"
      Self.log("\(configURL.path): \(error)")
    }
    applySettings()
  }

  private func applySettings() {
    resolvedURLs = [:]
    fileNames = [:]
    if config.settings != settings { settings = config.settings }
  }

  /// A magnified icon's side in pixels on a 2x display.
  private var iconPixels: Int {
    Int((settings.iconSize * max(1, settings.magnification) * 2).rounded(.up))
  }

  /// Everything that changes a tile's picture.
  private func imageKey(for tile: DockTile) -> String {
    if tile.section == .trash { return "trash|\(trashFull)|\(iconPixels)" }
    if tile.item.kind == .shelf { return "shelf|\(shelf.entries.isEmpty)|\(tile.item.icon ?? "")|\(iconPixels)" }
    if tile.item.kind == .group, (tile.item.icon ?? "").isEmpty {
      return "group|" + tile.visibleChildren.prefix(4).map(imageKey(for:)).joined(separator: ",")
    }
    return "\(tile.id)|\(tile.item.icon ?? "")|\(tile.url?.path ?? "")|\(iconPixels)"
  }

  /// Edits never overwrite a config file that failed to parse.
  private func edit(_ change: (inout DockConfig) -> Void) {
    loadConfig()
    guard configError == nil else {
      NSSound.beep()
      return
    }
    change(&config)
    persist()
    refresh()
  }

  private func persist() {
    guard configError == nil else { return }
    do {
      try DockConfigFile.write(config, to: configURL)
      configStamp = DockConfigFile.modificationDate(configURL)
    } catch {
      Self.log("could not save \(configURL.path): \(error)")
    }
  }

  private func loadTheme() {
    let stamp = DockConfigFile.modificationDate(BaristaAppearance.stateURL)?.timeIntervalSince1970 ?? 0
    let key = "\(settings.theme)|\(stamp)"
    guard key != themeStamp else { return }
    themeStamp = key
    let theme = DockTheme.named(settings.theme, appearance: BaristaAppearance.load())
    if theme != self.theme { self.theme = theme }
    let defaults = BaristaAppearance.windowDefaults()
    if defaults != windowDefaults { windowDefaults = defaults }
    let levels = BaristaAppearance.windowLevels()
    if levels != windowLevels { windowLevels = levels }
  }

  /// `~/.Trash` is unreadable without Full Disk Access; the last known state stays then.
  private func refreshTrash() {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: Self.trashURL.path) else { return }
    let full = names.contains { $0 != ".DS_Store" }
    if full != trashFull { trashFull = full }
  }

  private func tile(for item: DockItem, section: DockTile.Section, app: NSRunningApplication?) -> DockTile {
    let url = resolvedURL(for: item)
    var tile = DockTile(id: item.key, item: item, url: url, section: section,
                        pid: app?.processIdentifier, isActive: app?.isActive ?? false, isHidden: app?.isHidden ?? false)
    if (item.title ?? "").isEmpty, let url, url.isFileURL {
      tile.fileName = fileNames[url.path] ?? {
        let name = FileManager.default.displayName(atPath: url.path)
        fileNames[url.path] = name
        return name
      }()
    }
    return tile
  }

  /// Apps that moved since they were pinned are found again by bundle id.
  private func resolvedURL(for item: DockItem) -> URL? {
    switch item.kind {
    case .url: return item.url.flatMap(URL.init(string:))
    case .action, .group, .shelf, .controls: return nil
    case .app, .folder, .file:
      if let cached = resolvedURLs[item.key] { return cached }
      var url = item.expandedPath.map { URL(fileURLWithPath: $0) }
      if item.kind == .app, !(url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false),
         let id = item.bundleID {
        url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) ?? url
      }
      resolvedURLs[item.key] = url
      return url
    }
  }

  private func defaultImage(for tile: DockTile) -> TileImage {
    switch tile.item.kind {
    case .action: return .symbol("terminal")
    case .url: return .symbol("globe")
    case .group: return .symbol("square.grid.2x2")
    case .shelf: return .symbol(shelf.entries.isEmpty ? "tray" : "tray.full")
    case .controls: return .symbol("switch.2")
    case .app, .folder, .file: return .image(NSWorkspace.shared.icon(forFile: tile.url?.path ?? "/"))
    }
  }

  /// A plain folder: no icon of its own (an `icon` or a package's), so its
  /// callout lists it in a row instead of a big cell.
  func isPlainFolder(_ tile: DockTile) -> Bool {
    guard tile.item.kind == .folder, tile.item.icon?.isEmpty ?? true else { return false }
    return (try? tile.url?.resourceValues(forKeys: [.isPackageKey]))??.isPackage != true
  }

  private func runningApplication(_ tile: DockTile) -> NSRunningApplication? {
    tile.pid.flatMap(NSRunningApplication.init(processIdentifier:))
  }

  /// Shown tiles' (and their members', at any depth) commands by tile ID.
  private func commands(_ field: KeyPath<DockItem, String?>) -> [String: String] {
    var commands: [String: String] = [:]
    for tile in sections.joined() {
      for tile in [tile] + tile.descendants {
        if let command = tile.item[keyPath: field], !command.isEmpty { commands[tile.id] = command }
      }
    }
    return commands
  }

  private func loadAgents() {
    let stamp = DockConfigFile.modificationDate(AgentFeed.url)
    // A feed that stopped updating ages out without ever changing on disk.
    let expired = agents != AgentSnapshot()
      && Date().timeIntervalSince(stamp ?? .distantPast) >= AgentFeed.staleAfter
    guard stamp != agentStamp || expired else { return }
    agentStamp = stamp
    let snapshot = AgentFeed.load()
    var attention = self.attention
    attention.update(snapshot.sessions, frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    if snapshot != agents { agents = snapshot }
    if attention != self.attention { self.attention = attention }
    let asking = Dictionary(snapshot.sessions.map { ($0.id, $0.needs) }, uniquingKeysWith: { first, _ in first })
    let kept = setAside.filter { asking[$0.key] == $0.value }
    if kept != setAside { setAside = kept }
  }

  /// A drop on a folder asks, at the pointer, whether to copy or move.
  private static func askTransfer(_ urls: [URL], into folder: URL) {
    let what = urls.count == 1 ? "“\(urls[0].lastPathComponent)”" : "\(urls.count) Items"
    let place = FileManager.default.displayName(atPath: folder.path)
    let menu = NSMenu()
    menu.autoenablesItems = false
    for (title, move) in [("Copy \(what) to \(place)", false), ("Move \(what) to \(place)", true)] {
      menu.addItem(MenuChoice.item(title) {
        DispatchQueue.global(qos: .userInitiated).async { transfer(urls, into: folder, move: move) }
      })
    }
    menu.addItem(.separator())
    menu.addItem(MenuChoice.item("Cancel") {})
    // After the drag session ends; the menu tracks its own loop.
    DispatchQueue.main.async { menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
  }

  static func transfer(_ urls: [URL], into folder: URL, move: Bool) {
    var failed = false
    for url in urls where url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL {
      do {
        _ = try FileOperations.place(url, in: folder, move: move)
      } catch {
        failed = true
        log("could not \(move ? "move" : "copy") \(url.path) into \(folder.path): \(error)")
      }
    }
    // The menu that asked is gone; without a sound the drop just did nothing.
    if failed { DispatchQueue.main.async { NSSound.beep() } }
  }

  static func log(_ message: String) {
    FileHandle.standardError.write(Data("barista-agent: \(message)\n".utf8))
  }
}
