import Foundation

struct DockItem: Codable, Equatable {
  enum Kind: String, Codable {
    case app, folder, file, action, url, group, shelf
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

  enum CodingKeys: String, CodingKey {
    case kind, path, title, icon, command, notify, terminal, lock, disabled, url, items, spaces, expand, sort, menu
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
    }
  }

  /// This item's key plus those of a group's members.
  var allKeys: [String] { [key] + (items ?? []).map(\.key) }

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
  /// A group opens inline while one of its apps is frontmost.
  var expandActiveGroup = true
  /// Days a shelf item stays before it is cleared.
  var shelfDays: Double = 3
  /// `barista` follows the bar's colors; `system` uses plain vibrancy.
  var theme = "barista"

  var clamped: DockSettings {
    var settings = self
    settings.iconSize = min(max(iconSize, 24), 96)
    settings.magnification = min(max(magnification, 1), 2.5)
    settings.spacing = min(max(spacing, 0), 16)
    settings.revealPush = min(max(revealPush, 0), 100)
    settings.revealDelay = min(max(revealDelay, 0), 2)
    settings.hideDelay = min(max(hideDelay, 0), 3)
    settings.shelfDays = min(max(shelfDays, 0.1), 30)
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
    case expandActiveGroup = "expand_active_group"
    case shelfDays = "shelf_days"
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
    expandActiveGroup = try container.decodeIfPresent(Bool.self, forKey: .expandActiveGroup)
      ?? defaults.expandActiveGroup
    shelfDays = try container.decodeIfPresent(Double.self, forKey: .shelfDays) ?? defaults.shelfDays
    theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? defaults.theme
  }
}

/// `pinned` sits left of the running apps, `others` right of them before the
/// Trash, matching the native Dock's apps and stacks sections.
struct DockConfig: Equatable {
  enum List { case pinned, others }

  var settings = DockSettings()
  var pinned: [DockItem] = []
  var others: [DockItem] = []

  subscript(_ list: List) -> [DockItem] {
    get { list == .pinned ? pinned : others }
    set { if list == .pinned { pinned = newValue } else { others = newValue } }
  }

  var groups: [DockItem] { (pinned + others).filter { $0.kind == .group } }

  /// Skips items already in the dock, including inside groups.
  mutating func insert(_ items: [DockItem], at index: Int?, in list: List) {
    var seen = Set((pinned + others).flatMap(\.allKeys))
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

  /// Removes a top-level item, or a member from whichever group holds it.
  mutating func remove(key: String) {
    for list in [List.pinned, .others] {
      self[list] = self[list].compactMap { item in
        guard item.key != key else { return nil }
        var item = item
        item.items?.removeAll { $0.key == key }
        return item
      }
    }
  }

  /// Wraps the item at `key` in a new group in its place, or appends a new
  /// group to the pins when the item is not in the dock yet (a running app).
  mutating func makeGroup(title: String, with item: DockItem) -> Bool {
    let group = DockItem(kind: .group, title: title, items: [item])
    guard !groups.contains(where: { $0.key == group.key }) else { return false }
    for list in [List.pinned, .others] {
      if let index = self[list].firstIndex(where: { $0.key == item.key }) {
        self[list][index] = group
        return true
      }
    }
    remove(key: item.key)
    pinned.append(group)
    return true
  }

  /// Moves an item into a group, from the dock or from another group.
  mutating func add(_ item: DockItem, toGroup groupKey: String) {
    guard item.kind != .group, groups.contains(where: { $0.key == groupKey }) else { return }
    remove(key: item.key)
    updateGroup(groupKey) { group in
      group.items = (group.items ?? []) + [item]
    }
  }

  /// Takes a member out of its group and places it right after the group.
  mutating func takeOut(_ key: String, fromGroup groupKey: String) {
    for list in [List.pinned, .others] {
      guard let index = self[list].firstIndex(where: { $0.key == groupKey }),
            let member = self[list][index].items?.first(where: { $0.key == key })
      else { continue }
      self[list][index].items?.removeAll { $0.key == key }
      self[list].insert(member, at: index + 1)
      return
    }
  }

  /// Replaces a group with its members.
  mutating func ungroup(_ groupKey: String) {
    for list in [List.pinned, .others] {
      guard let index = self[list].firstIndex(where: { $0.key == groupKey }) else { continue }
      let members = self[list][index].items ?? []
      self[list].replaceSubrange(index...index, with: members)
      return
    }
  }

  mutating func renameGroup(_ groupKey: String, to title: String) -> Bool {
    guard !groups.contains(where: { $0.key == "group:\(title)" }) else { return false }
    updateGroup(groupKey) { $0.title = title }
    return true
  }

  mutating func dedupe() {
    var seen = Set<String>()
    func unique(_ items: [DockItem]) -> [DockItem] {
      items.compactMap { item in
        guard seen.insert(item.key).inserted else { return nil }
        var item = item
        if let members = item.items {
          item.items = unique(members.filter { $0.kind != .group })
        }
        return item
      }
    }
    pinned = unique(pinned)
    others = unique(others)
  }

  private mutating func updateGroup(_ groupKey: String, _ change: (inout DockItem) -> Void) {
    for list in [List.pinned, .others] {
      if let index = self[list].firstIndex(where: { $0.key == groupKey && $0.kind == .group }) {
        change(&self[list][index])
        return
      }
    }
  }
}

extension DockConfig: Codable {
  enum CodingKeys: String, CodingKey {
    case version, settings, pinned, others
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    settings = try container.decodeIfPresent(DockSettings.self, forKey: .settings) ?? DockSettings()
    pinned = try container.decodeIfPresent([DockItem].self, forKey: .pinned) ?? []
    others = try container.decodeIfPresent([DockItem].self, forKey: .others) ?? []
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(1, forKey: .version)
    try container.encode(settings, forKey: .settings)
    try container.encode(pinned, forKey: .pinned)
    try container.encode(others, forKey: .others)
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
