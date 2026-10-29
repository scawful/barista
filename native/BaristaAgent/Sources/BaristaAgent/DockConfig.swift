import Foundation

struct DockItem: Codable, Equatable {
  enum Kind: String, Codable {
    case app, folder, file, action, url, group, shelf, controls
  }

  enum Sort: String, Codable {
    case added, name, modified
  }

  var kind: Kind
  var path: String?
  var bundleID: String?
  var title: String?
  /// `sf:<symbol name>` or a path to an image or app.
  var icon: String?
  /// Run with `zsh -lc`; files dropped on the tile arrive as `$1`, `$2`, ...
  var command: String?
  /// An action also posts a notification when its command finishes.
  var notify: Bool?
  /// An action runs in a new terminal window instead of in the background.
  var terminal: Bool?
  /// Actions sharing a lock name never run at the same time; the dock
  /// refuses the second one instead of starting it.
  var lock: String?
  /// A menu entry shown greyed out, with this reason.
  var disabled: String?
  var url: String?
  /// A group's members, shown in a popover when the group is clicked.
  var items: [DockItem]?
  /// A group also opens inline on these yabai spaces (index or label).
  var spaces: [String]?
  /// `false` keeps a group closed even while one of its apps is frontmost.
  var expand: Bool?
  /// Run with `zsh -lc` on reveal; the first line of output is the tile's badge.
  var badgeCommand: String?
  /// Run with `zsh -lc` on reveal; prints `{"rows": [...]}` for a group's popover.
  var infoCommand: String?
  /// A folder stack's order; Downloads-style `added` by default.
  var sort: Sort?
  /// Extra right-click entries: titled actions, or groups of them as submenus.
  var menu: [DockItem]?
  /// Run with `zsh -lc` on reveal; prints `{"menu": [...]}`, entries shown
  /// after `menu`'s.
  var menuCommand: String?
  /// A group member kept out of its group's grid and inline tiles; Show
  /// Hidden and the group's search still find it.
  var hidden: Bool?

  enum CodingKeys: String, CodingKey {
    case kind, path, title, icon, command, notify, terminal, lock, disabled, url, items, spaces, expand, sort, menu
    case hidden
    case bundleID = "bundle_id"
    case badgeCommand = "badge_command"
    case infoCommand = "info_command"
    case menuCommand = "menu_command"
  }

  init(kind: Kind, path: String? = nil, bundleID: String? = nil, title: String? = nil,
       icon: String? = nil, command: String? = nil, url: String? = nil, items: [DockItem]? = nil) {
    self.kind = kind
    self.path = path
    self.bundleID = bundleID
    self.title = title
    self.icon = icon
    self.command = command
    self.url = url
    self.items = items
  }

  /// An item for something dropped on the dock: an app, folder, or file from
  /// Finder, or a link from a browser.
  init(droppedURL url: URL) {
    guard url.isFileURL else {
      self.init(kind: .url, title: url.host ?? url.absoluteString, url: url.absoluteString)
      return
    }
    let path = DockConfigFile.tilde(url.path)
    if url.pathExtension == "app" {
      self.init(kind: .app, path: path, bundleID: Bundle(url: url)?.bundleIdentifier)
    } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
      self.init(kind: .folder, path: path)
    } else {
      self.init(kind: .file, path: path)
    }
  }

  /// Identity used to match running apps and to keep each tile unique.
  var key: String {
    switch kind {
    case .app: return bundleID ?? expandedPath ?? ""
    case .folder, .file: return "\(kind.rawValue):\(expandedPath ?? "")"
    case .action:
      // Groups can each hold a same-titled action with its own command.
      if let title, let command { return "action:\(title)\t\(command)" }
      return "action:\(title ?? command ?? "")"
    case .url: return "url:\(url ?? "")"
    case .group: return "group:\(title ?? "")"
    case .shelf: return "shelf"
    case .controls: return "controls"
    }
  }

  /// This item's key plus those of a group's members, through subgroups.
  var allKeys: [String] { [key] + (items ?? []).flatMap(\.allKeys) }

  var expandedPath: String? {
    guard let path, !path.isEmpty else { return nil }
    return (path as NSString).expandingTildeInPath
  }
}

struct DockSettings: Equatable {
  var iconSize: Double = 44
  /// Peak icon scale under the pointer; 1 turns magnification off.
  var magnification: Double = 1.6
  var spacing: Double = 4
  /// Points the pointer must keep pushing down once it is pinned at the
  /// bottom edge; 0 reveals on touch.
  var revealPush: Double = 10
  /// Seconds of resting against the bottom edge that also reveal; 0 reveals on touch.
  var revealDelay: Double = 0.5
  var hideDelay: Double = 0.3
  var showRunning = true
  var showTrash = true
  /// Minimized windows get tiles of their own before the Trash, as in the native Dock.
  var showMinimized = true
  /// A group opens inline while one of its apps is frontmost.
  var expandActiveGroup = true
  /// Days a shelf item stays before it is cleared.
  var shelfDays: Double = 3
  /// `barista` follows the bar's colors; `system` uses plain vibrancy.
  var theme = "barista"
  /// `barista` makes the Finder tile open Barista Files (⌥-click opens
  /// Finder); `finder` keeps Finder.
  var filesBrowser = "barista"
  /// A Shortcuts shortcut the controls callout's Focus switch runs; macOS
  /// has no API to switch a Focus. Empty opens Focus settings instead.
  var focusShortcut = ""
  /// How fast scrolling over a picture in the viewer zooms it: `off`
  /// scrolls instead, else `fine`, `normal`, or `fast`.
  var viewerScrollZoom = "normal"
  /// Movies in the viewer start over when they end.
  var viewerLoopsMovies = true
  /// The size an app's new windows take when they float, by the name yabai
  /// knows the app by: `small`, `medium`, or `large` (`WindowSize`).
  var windowSizes: [String: String] = [:]

  var clamped: DockSettings {
    var settings = self
    settings.iconSize = min(max(iconSize, 24), 96)
    settings.magnification = min(max(magnification, 1), 2.5)
    settings.spacing = min(max(spacing, 0), 16)
    settings.revealPush = min(max(revealPush, 0), 100)
    settings.revealDelay = min(max(revealDelay, 0), 2)
    settings.hideDelay = min(max(hideDelay, 0), 3)
    settings.shelfDays = min(max(shelfDays, 0.1), 30)
    settings.windowSizes = windowSizes.filter { WindowSize(rawValue: $0.value) != nil }
    return settings
  }
}

extension DockSettings: Codable {
  enum CodingKeys: String, CodingKey {
    case magnification, spacing, theme
    case iconSize = "icon_size"
    case revealPush = "reveal_push"
    case revealDelay = "reveal_delay"
    case hideDelay = "hide_delay"
    case showRunning = "show_running"
    case showTrash = "show_trash"
    case showMinimized = "show_minimized"
    case expandActiveGroup = "expand_active_group"
    case shelfDays = "shelf_days"
    case filesBrowser = "files_browser"
    case focusShortcut = "focus_shortcut"
    case viewerScrollZoom = "viewer_scroll_zoom"
    case viewerLoopsMovies = "viewer_loops_movies"
    case windowSizes = "window_sizes"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = DockSettings()
    iconSize = try container.decodeIfPresent(Double.self, forKey: .iconSize) ?? defaults.iconSize
    magnification = try container.decodeIfPresent(Double.self, forKey: .magnification) ?? defaults.magnification
    spacing = try container.decodeIfPresent(Double.self, forKey: .spacing) ?? defaults.spacing
    revealPush = try container.decodeIfPresent(Double.self, forKey: .revealPush) ?? defaults.revealPush
    revealDelay = try container.decodeIfPresent(Double.self, forKey: .revealDelay) ?? defaults.revealDelay
    hideDelay = try container.decodeIfPresent(Double.self, forKey: .hideDelay) ?? defaults.hideDelay
    showRunning = try container.decodeIfPresent(Bool.self, forKey: .showRunning) ?? defaults.showRunning
    showTrash = try container.decodeIfPresent(Bool.self, forKey: .showTrash) ?? defaults.showTrash
    showMinimized = try container.decodeIfPresent(Bool.self, forKey: .showMinimized) ?? defaults.showMinimized
    expandActiveGroup = try container.decodeIfPresent(Bool.self, forKey: .expandActiveGroup)
      ?? defaults.expandActiveGroup
    shelfDays = try container.decodeIfPresent(Double.self, forKey: .shelfDays) ?? defaults.shelfDays
    theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? defaults.theme
    filesBrowser = try container.decodeIfPresent(String.self, forKey: .filesBrowser) ?? defaults.filesBrowser
    focusShortcut = try container.decodeIfPresent(String.self, forKey: .focusShortcut) ?? defaults.focusShortcut
    viewerScrollZoom = try container.decodeIfPresent(String.self, forKey: .viewerScrollZoom) ?? defaults.viewerScrollZoom
    viewerLoopsMovies = try container.decodeIfPresent(Bool.self, forKey: .viewerLoopsMovies)
      ?? defaults.viewerLoopsMovies
    windowSizes = try container.decodeIfPresent([String: String].self, forKey: .windowSizes) ?? defaults.windowSizes
  }
}

/// `pinned` sits left of the running apps, `others` right of them, matching
/// the native Dock's apps and stacks sections. `system` holds the shelf and
/// the controls, beside the Trash.
struct DockConfig: Equatable {
  enum List { case pinned, others, system }

  var settings = DockSettings()
  var pinned: [DockItem] = []
  var others: [DockItem] = []
  var system: [DockItem] = []

  subscript(_ list: List) -> [DockItem] {
    get {
      switch list {
      case .pinned: return pinned
      case .others: return others
      case .system: return system
      }
    }
    set {
      switch list {
      case .pinned: pinned = newValue
      case .others: others = newValue
      case .system: system = newValue
      }
    }
  }

  /// Every group, subgroups included; titles are unique across all of them.
  var groups: [DockItem] { Self.groups(in: pinned + others + system) }

  private static func groups(in items: [DockItem]) -> [DockItem] {
    items.flatMap { $0.kind == .group ? [$0] + groups(in: $0.items ?? []) : [] }
  }

  /// Skips items already in the dock, including inside groups.
  mutating func insert(_ items: [DockItem], at index: Int?, in list: List) {
    var seen = Set((pinned + others + system).flatMap(\.allKeys))
    let fresh = items.filter { seen.insert($0.key).inserted }
    guard !fresh.isEmpty else { return }
    let position = min(max(index ?? self[list].count, 0), self[list].count)
    self[list].insert(contentsOf: fresh, at: position)
  }

  mutating func move(key: String, to index: Int, in list: List) {
    guard let from = self[list].firstIndex(where: { $0.key == key }) else { return }
    let item = self[list].remove(at: from)
    self[list].insert(item, at: min(max(index, 0), self[list].count))
  }

  /// Removes an item wherever it is: at the top level or in any group.
  mutating func remove(key: String) {
    func strip(_ items: [DockItem]) -> [DockItem] {
      items.compactMap { item in
        guard item.key != key else { return nil }
        var item = item
        if let members = item.items { item.items = strip(members) }
        return item
      }
    }
    pinned = strip(pinned)
    others = strip(others)
    system = strip(system)
  }

  /// Wraps the item at `key` in a new group in its place (a subgroup when
  /// it is a group's member), or appends a new group to the pins when the
  /// item is not in the dock yet (a running app).
  mutating func makeGroup(title: String, with item: DockItem) -> Bool {
    let group = DockItem(kind: .group, title: title, items: [item])
    guard !groups.contains(where: { $0.key == group.key }) else { return false }
    if editList(holding: item.key, { items, index in items[index] = group }) { return true }
    pinned.append(group)
    return true
  }

  /// Moves an item into a group, from the dock or from another group. A
  /// group can move into another group, but not into itself or one of its own.
  mutating func add(_ item: DockItem, toGroup groupKey: String) {
    guard groups.contains(where: { $0.key == groupKey }), !item.allKeys.contains(groupKey) else { return }
    remove(key: item.key)
    updateGroup(groupKey) { group in
      group.items = (group.items ?? []) + [item]
    }
  }

  /// Takes a member out of its group and places it right after the group,
  /// in the group's own parent for a subgroup.
  mutating func takeOut(_ key: String, fromGroup groupKey: String) {
    editList(holding: groupKey) { items, index in
      guard let member = items[index].items?.first(where: { $0.key == key }) else { return }
      items[index].items?.removeAll { $0.key == key }
      items.insert(member, at: index + 1)
    }
  }

  /// Moves a member before another member of its group, or to the group's end.
  mutating func place(_ key: String, before target: String?, inGroup groupKey: String) {
    guard key != target else { return }
    updateGroup(groupKey) { group in
      var items = group.items ?? []
      guard let from = items.firstIndex(where: { $0.key == key }) else { return }
      let item = items.remove(at: from)
      items.insert(item, at: target.flatMap { target in items.firstIndex { $0.key == target } } ?? items.count)
      group.items = items
    }
  }

  /// Replaces a group with its members.
  mutating func ungroup(_ groupKey: String) {
    editList(holding: groupKey) { items, index in
      let members = items[index].items ?? []
      items.replaceSubrange(index...index, with: members)
    }
  }

  mutating func renameGroup(_ groupKey: String, to title: String) -> Bool {
    guard !groups.contains(where: { $0.key == "group:\(title)" }) else { return false }
    updateGroup(groupKey) { $0.title = title }
    return true
  }

  /// Keeps a group member out of its group's grid, or shows it again.
  mutating func setHidden(_ key: String, _ hidden: Bool) {
    editList(holding: key) { items, index in items[index].hidden = hidden ? true : nil }
  }

  mutating func dedupe() {
    var seen = Set<String>()
    func unique(_ items: [DockItem]) -> [DockItem] {
      items.compactMap { item in
        guard seen.insert(item.key).inserted else { return nil }
        var item = item
        if let members = item.items { item.items = unique(members) }
        return item
      }
    }
    pinned = unique(pinned)
    others = unique(others)
    system = unique(system)
  }

  private mutating func updateGroup(_ groupKey: String, _ change: (inout DockItem) -> Void) {
    editList(holding: groupKey) { items, index in
      if items[index].kind == .group { change(&items[index]) }
    }
  }

  /// Runs `change` on the list holding `key`, top level or inside a group,
  /// with that item's index. False when no list holds it.
  @discardableResult
  private mutating func editList(holding key: String, _ change: (inout [DockItem], Int) -> Void) -> Bool {
    func edit(_ items: inout [DockItem]) -> Bool {
      if let index = items.firstIndex(where: { $0.key == key }) {
        change(&items, index)
        return true
      }
      for index in items.indices where items[index].kind == .group {
        var members = items[index].items ?? []
        if edit(&members) {
          items[index].items = members
          return true
        }
      }
      return false
    }
    return edit(&pinned) || edit(&others) || edit(&system)
  }
}

extension DockConfig: Codable {
  enum CodingKeys: String, CodingKey {
    case version, settings, pinned, others, system
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    settings = try container.decodeIfPresent(DockSettings.self, forKey: .settings) ?? DockSettings()
    pinned = try container.decodeIfPresent([DockItem].self, forKey: .pinned) ?? []
    others = try container.decodeIfPresent([DockItem].self, forKey: .others) ?? []
    if let system = try container.decodeIfPresent([DockItem].self, forKey: .system) {
      self.system = system
    } else {
      // Older configs kept the shelf and the controls with the stacks.
      let isSystem = { (item: DockItem) in item.kind == .shelf || item.kind == .controls }
      system = (pinned + others).filter(isSystem)
      pinned.removeAll(where: isSystem)
      others.removeAll(where: isSystem)
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .version)
    try container.encode(settings, forKey: .settings)
    try container.encode(pinned, forKey: .pinned)
    try container.encode(others, forKey: .others)
    try container.encode(system, forKey: .system)
  }
}

enum DockConfigFile {
  static let url: URL = {
    let env = ProcessInfo.processInfo.environment
    if let override = env["BARISTA_DOCK_CONFIG"], !override.isEmpty {
      return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
    }
    let base = env["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory() + "/.config"
    return URL(fileURLWithPath: base).appendingPathComponent("barista/dock.json")
  }()

  static func decode(_ data: Data) throws -> DockConfig {
    var config = try JSONDecoder().decode(DockConfig.self, from: data)
    config.settings = config.settings.clamped
    config.dedupe()
    return config
  }

  static func encode(_ config: DockConfig) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(config) + Data("\n".utf8)
  }

  static func write(_ config: DockConfig, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try encode(config).write(to: url, options: .atomic)
  }

  static func modificationDate(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
  }

  /// Copies the native Dock's apps and stacks so the Barista dock starts out matching it.
  static func seedFromNativeDock() -> DockConfig {
    let domain = "com.apple.dock" as CFString
    CFPreferencesAppSynchronize(domain)
    let apps = CFPreferencesCopyAppValue("persistent-apps" as CFString, domain) as? [[String: Any]] ?? []
    let others = CFPreferencesCopyAppValue("persistent-others" as CFString, domain) as? [[String: Any]] ?? []
    var config = DockConfig(pinned: items(fromNativeTiles: apps), others: items(fromNativeTiles: others))
    config.dedupe()
    return config
  }

  static func items(fromNativeTiles tiles: [[String: Any]]) -> [DockItem] {
    tiles.compactMap { tile in
      guard let data = tile["tile-data"] as? [String: Any] else { return nil }
      switch tile["tile-type"] as? String {
      case "file-tile"?, nil:
        guard let url = fileURL(data["file-data"]) else { return nil }
        if url.pathExtension == "app" {
          return DockItem(kind: .app, path: tilde(url.path), bundleID: data["bundle-identifier"] as? String)
        }
        return DockItem(kind: .file, path: tilde(url.path))
      case "directory-tile"?:
        guard let url = fileURL(data["file-data"]) else { return nil }
        return DockItem(kind: .folder, path: tilde(url.path))
      case "url-tile"?:
        guard let link = (data["url"] as? [String: Any])?["_CFURLString"] as? String else { return nil }
        return DockItem(kind: .url, title: data["label"] as? String, url: link)
      default:
        return nil
      }
    }
  }

  static func tilde(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
  }

  private static func fileURL(_ value: Any?) -> URL? {
    guard let string = (value as? [String: Any])?["_CFURLString"] as? String else { return nil }
    if let url = URL(string: string), url.isFileURL { return url }
    return string.hasPrefix("/") ? URL(fileURLWithPath: string) : nil
  }
}
