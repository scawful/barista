import Foundation

/// One tab's place and its back/forward history.
struct BrowserTab: Identifiable, Equatable {
  static let historyLimit = 100

  let id: UUID
  private(set) var history: [URL]
  private(set) var position = 0

  init(_ location: URL, id: UUID = UUID()) {
    self.id = id
    history = [location.standardizedFileURL]
  }

  var location: URL { history[position] }
  var canGoBack: Bool { position > 0 }
  var canGoForward: Bool { position < history.count - 1 }
  /// The enclosing folder, nil at the root.
  var parent: URL? { location.path == "/" ? nil : location.deletingLastPathComponent() }

  /// Going somewhere new drops the forward history, as in a browser.
  mutating func go(to url: URL) {
    let url = url.standardizedFileURL
    guard url != location else { return }
    history = Array(history.prefix(position + 1)) + [url]
    if history.count > Self.historyLimit { history.removeFirst(history.count - Self.historyLimit) }
    position = history.count - 1
  }

  mutating func back() { if canGoBack { position -= 1 } }
  mutating func forward() { if canGoForward { position += 1 } }
}

/// A browser window's tabs. They live inside the one window, so the tiling
/// window manager sees a single window however many tabs are open; native
/// macOS tabs are separate windows to yabai, which is what breaks Finder.
struct BrowserTabs: Equatable {
  private(set) var tabs: [BrowserTab]
  private(set) var selectedID: UUID

  init(_ location: URL) {
    let tab = BrowserTab(location)
    tabs = [tab]
    selectedID = tab.id
  }

  var selected: BrowserTab {
    get { tabs.first { $0.id == selectedID } ?? tabs[0] }
    set {
      guard let index = tabs.firstIndex(where: { $0.id == newValue.id }) else { return }
      tabs[index] = newValue
    }
  }

  /// Opens a tab right after the selected one.
  @discardableResult
  mutating func open(_ location: URL, select: Bool = true) -> UUID {
    let tab = BrowserTab(location)
    let index = (tabs.firstIndex { $0.id == selectedID } ?? tabs.count - 1) + 1
    tabs.insert(tab, at: index)
    if select { selectedID = tab.id }
    return tab.id
  }

  /// Returns false for the last tab: closing it closes the window instead.
  mutating func close(_ id: UUID) -> Bool {
    guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
    tabs.remove(at: index)
    if selectedID == id { selectedID = tabs[min(index, tabs.count - 1)].id }
    return true
  }

  mutating func select(_ id: UUID) {
    if tabs.contains(where: { $0.id == id }) { selectedID = id }
  }

  /// The next (+1) or previous (-1) tab, wrapping around.
  mutating func selectNeighbor(_ offset: Int) {
    guard let index = tabs.firstIndex(where: { $0.id == selectedID }) else { return }
    selectedID = tabs[((index + offset) % tabs.count + tabs.count) % tabs.count].id
  }

  mutating func move(_ id: UUID, to destination: Int) {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
    let tab = tabs.remove(at: index)
    tabs.insert(tab, at: max(0, min(destination, tabs.count)))
  }

  mutating func go(to url: URL) { selected.go(to: url) }
  mutating func back() { selected.back() }
  mutating func forward() { selected.forward() }
}

struct FileEntry: Identifiable, Equatable {
  let url: URL
  let name: String
  /// A folder you browse into; packages such as apps open instead.
  let isFolder: Bool
  let modified: Date
  /// Nil for folders, whose size would mean walking them.
  let size: Int64?
  let kind: String
  var id: URL { url }
}

enum FileSortKey: String, CaseIterable {
  case name, modified, size, kind
}

enum FileListing {
  /// Nil when the folder cannot be read (missing, or privacy access denied).
  static func load(_ folder: URL, hidden: Bool = false) -> [FileEntry]? {
    let keys: [URLResourceKey] = [.localizedNameKey, .isDirectoryKey, .isPackageKey, .contentModificationDateKey,
                                  .fileSizeKey, .localizedTypeDescriptionKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: keys, options: hidden ? [] : [.skipsHiddenFiles])
    else { return nil }
    return urls.map { url in
      let values = try? url.resourceValues(forKeys: Set(keys))
      let isFolder = values?.isDirectory == true && values?.isPackage != true
      return FileEntry(url: url, name: values?.localizedName ?? url.lastPathComponent, isFolder: isFolder,
                       modified: values?.contentModificationDate ?? .distantPast,
                       size: isFolder ? nil : values?.fileSize.map(Int64.init),
                       kind: values?.localizedTypeDescription ?? "")
    }
  }

  /// Folders come first for a name sort, as in Finder; ties fall back to name.
  static func sorted(_ entries: [FileEntry], by key: FileSortKey, ascending: Bool = true) -> [FileEntry] {
    func byName(_ a: FileEntry, _ b: FileEntry) -> Bool {
      a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
    return entries.sorted { a, b in
      if key == .name, a.isFolder != b.isFolder { return a.isFolder }
      let order: ComparisonResult
      switch key {
      case .name: order = a.name.localizedStandardCompare(b.name)
      case .modified: order = a.modified == b.modified ? .orderedSame : a.modified < b.modified ? .orderedAscending : .orderedDescending
      case .size:
        let (left, right) = (a.size ?? -1, b.size ?? -1)
        order = left == right ? .orderedSame : left < right ? .orderedAscending : .orderedDescending
      case .kind: order = a.kind.localizedStandardCompare(b.kind)
      }
      if order == .orderedSame { return byName(a, b) }
      return ascending ? order == .orderedAscending : order == .orderedDescending
    }
  }

  static func filtered(_ entries: [FileEntry], query: String) -> [FileEntry] {
    let query = query.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return entries }
    return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }
}
