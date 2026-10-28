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
    // Paths, not URLs: one built from a folder's path ends in `/`.
    guard url.path != location.path else { return }
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
  /// Nil for folders, whose size means walking them, until Calculate All
  /// Sizes measures them.
  var size: Int64?
  let kind: String
  /// A contents search's first match in the file: its line number and text.
  var line: Int?
  var match: String?
  var id: URL { url }
}

enum FileSortKey: String, CaseIterable, Identifiable {
  case name, modified, size, kind

  var id: Self { self }

  var title: String {
    switch self {
    case .name: return "Name"
    case .modified: return "Date Modified"
    case .size: return "Size"
    case .kind: return "Kind"
    }
  }
}

/// How a browser draws its folder, as Finder's View menu offers.
enum BrowserLayout: String, CaseIterable, Identifiable {
  case list, icons, columns

  static let defaultsKey = "BaristaFilesLayout"

  var id: Self { self }

  var title: String {
    switch self {
    case .list: return "as List"
    case .icons: return "as Icons"
    case .columns: return "as Columns"
    }
  }

  var symbol: String {
    switch self {
    case .list: return "list.bullet"
    case .icons: return "square.grid.2x2"
    case .columns: return "rectangle.split.3x1"
    }
  }

  /// The last one chosen, for new windows.
  static var remembered: BrowserLayout {
    UserDefaults.standard.string(forKey: defaultsKey).flatMap(BrowserLayout.init) ?? .list
  }

  /// The folders drawn as columns before `location`'s own: its enclosing
  /// folders from Home, or from the volume root outside Home.
  static func columnFolders(for location: URL, home: URL) -> [URL] {
    let location = location.standardizedFileURL
    let start = location.isWithin(home) ? home.standardizedFileURL : URL(fileURLWithPath: "/")
    var folders: [URL] = []
    var folder = location
    while folder.path != start.path && folder.path != "/" {
      folder.deleteLastPathComponent()
      folders.insert(URL(fileURLWithPath: folder.path), at: 0)
    }
    return folders
  }

  /// The icon an arrow key moves to in a grid `columns` wide: left and right
  /// step, up and down move a row, and down from a short last row's row
  /// above lands on the last icon, as in Finder. The first press picks the
  /// first icon.
  static func step(from index: Int?, count: Int, columns: Int, keyCode: UInt16) -> Int? {
    guard count > 0 else { return nil }
    guard let index else { return 0 }
    let columns = max(1, columns)
    let next: Int
    switch keyCode {
    case 123: next = index - 1
    case 124: next = index + 1
    case 125: next = index / columns < (count - 1) / columns ? min(index + columns, count - 1) : index
    case 126: next = index - columns
    default: return index
    }
    return (0..<count).contains(next) ? next : index
  }
}

enum FileListing {
  /// Nil when the folder cannot be read (missing, or privacy access denied).
  private static let keys: [URLResourceKey] = [.localizedNameKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
                                               .contentModificationDateKey, .fileSizeKey, .localizedTypeDescriptionKey]

  static func load(_ folder: URL, hidden: Bool = false) -> [FileEntry]? {
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: keys, options: hidden ? [] : [.skipsHiddenFiles])
    else { return nil }
    return urls.map { entry($0) }
  }

  /// `url` as a row, under its localized name unless `name` is given.
  static func entry(_ url: URL, name: String? = nil) -> FileEntry {
    let values = try? url.resourceValues(forKeys: Set(keys))
    // Resource values describe a symlink itself; its target decides whether it browses.
    let target = values?.isSymbolicLink == true
      ? try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
      : values
    let isFolder = target?.isDirectory == true && target?.isPackage != true
    return FileEntry(url: url, name: name ?? values?.localizedName ?? url.lastPathComponent, isFolder: isFolder,
                     modified: values?.contentModificationDate ?? .distantPast,
                     size: isFolder ? nil : values?.fileSize.map(Int64.init),
                     kind: values?.localizedTypeDescription ?? "")
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

enum FileOperationError: LocalizedError, Equatable {
  case invalidName(String)
  case nameTaken(String)
  case intoItself(String)

  var errorDescription: String? {
    switch self {
    case .invalidName(let name): return "“\(name)” can't be used as a name."
    case .nameTaken(let name): return "The name “\(name)” is already taken."
    case .intoItself(let name): return "“\(name)” can't be put inside itself."
    }
  }
}

/// Finder's file operations, with Finder's names for what they make.
enum FileOperations {
  /// `stem` (plus `ext`) when free, else `stem 2`, `stem 3`, … as Finder
  /// names a second copy.
  static func available(_ stem: String, ext: String, exists: (String) -> Bool) -> String {
    func name(_ base: String) -> String { ext.isEmpty ? base : "\(base).\(ext)" }
    guard exists(name(stem)) else { return name(stem) }
    var number = 2
    while exists(name("\(stem) \(number)")) { number += 1 }
    return name("\(stem) \(number)")
  }

  /// A folder's name has no extension to keep apart; a package's does.
  private static func split(_ url: URL) -> (stem: String, ext: String) {
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
    let name = url.lastPathComponent
    if values?.isDirectory == true && values?.isPackage != true { return (name, "") }
    return ((name as NSString).deletingPathExtension, (name as NSString).pathExtension)
  }

  private static func free(in folder: URL) -> (String) -> Bool {
    { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
  }

  static func makeFolder(in folder: URL) throws -> URL {
    let url = folder.appendingPathComponent(available("untitled folder", ext: "", exists: free(in: folder)))
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
  }

  /// `name copy.ext` next to the original, then `name copy 2.ext`.
  static func duplicate(_ url: URL) throws -> URL {
    let folder = url.deletingLastPathComponent()
    let (stem, ext) = split(url)
    let copy = folder.appendingPathComponent(available("\(stem) copy", ext: ext, exists: free(in: folder)))
    try FileManager.default.copyItem(at: url, to: copy)
    return copy
  }

  /// Copies or moves `url` into `folder`, keeping both when the name is taken.
  static func place(_ url: URL, in folder: URL, move: Bool) throws -> URL {
    if folder.isWithin(url) {
      throw FileOperationError.intoItself(url.lastPathComponent)
    }
    let (stem, ext) = split(url)
    let destination = folder.appendingPathComponent(available(stem, ext: ext, exists: free(in: folder)))
    if move {
      try FileManager.default.moveItem(at: url, to: destination)
    } else {
      try FileManager.default.copyItem(at: url, to: destination)
    }
    return destination
  }

  /// What Finder selects when a rename begins: a file's name up to its
  /// extension, so typing keeps `.asm`; all of a folder's or a dotfile's.
  static func stem(_ name: String, isFolder: Bool) -> NSRange {
    let whole = NSRange(location: 0, length: (name as NSString).length)
    let ext = (name as NSString).pathExtension
    guard !isFolder, !ext.isEmpty else { return whole }
    let length = whole.length - (ext as NSString).length - 1
    return length > 0 ? NSRange(location: 0, length: length) : whole
  }

  static func rename(_ url: URL, to newName: String) throws -> URL {
    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !name.contains("/"), !name.contains(":"), name != ".", name != ".." else {
      throw FileOperationError.invalidName(newName)
    }
    guard name != url.lastPathComponent else { return url }
    let destination = url.deletingLastPathComponent().appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: destination.path) {
      // On a case-insensitive volume a case-only rename finds the file itself.
      let key: Set<URLResourceKey> = [.fileResourceIdentifierKey]
      let mine = try? url.resourceValues(forKeys: key).fileResourceIdentifier
      let theirs = try? destination.resourceValues(forKeys: key).fileResourceIdentifier
      guard let mine, let theirs, mine.isEqual(theirs) else { throw FileOperationError.nameTaken(name) }
      guard Darwin.rename(url.path, destination.path) == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
      }
      return destination
    }
    try FileManager.default.moveItem(at: url, to: destination)
    return destination
  }

  /// The nearest enclosing folder with a `.git` (a folder, or a file in a
  /// worktree), for repo-relative paths.
  static func repoRoot(of url: URL) -> URL? {
    var folder = url.standardizedFileURL
    while folder.path != "/" {
      if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) { return folder }
      folder.deleteLastPathComponent()
    }
    return nil
  }
}

extension URL {
  /// True for `folder` itself and anything under it.
  func isWithin(_ folder: URL) -> Bool {
    let path = standardizedFileURL.path, base = folder.standardizedFileURL.path
    return path == base || path.hasPrefix(base + "/")
  }
}
