import Foundation
import UniformTypeIdentifiers

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
  var created = Date.distantPast
  /// When it was put in this folder, as Finder's Date Added.
  var added = Date.distantPast
  /// Nil for folders, whose size means walking them, until Calculate All
  /// Sizes measures them.
  var size: Int64?
  let kind: String
  /// A contents search's first match in the file: its line number and text.
  var line: Int?
  var match: String?
  /// Its place in Finder's name order among the rows it was listed with.
  var nameOrder: Int?
  var id: URL { url }
}

enum FileSortKey: String, CaseIterable, Identifiable, Codable {
  case name, modified, created, added, size, kind

  var id: Self { self }

  var title: String {
    switch self {
    case .name: return "Name"
    case .modified: return "Date Modified"
    case .created: return "Date Created"
    case .added: return "Date Added"
    case .size: return "Size"
    case .kind: return "Kind"
    }
  }

  /// Finder's direction when it arranges by this: newest and largest first.
  var ascendsByDefault: Bool { self == .name || self == .kind }
}

/// How a browser draws its folder, as Finder's View menu offers.
enum BrowserLayout: String, CaseIterable, Identifiable, Codable {
  case list, icons, columns

  /// The layout picked last before folders had views of their own; the
  /// default until View → Use as Defaults sets one.
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
  /// Not the localized type description: asked per file, it costs more than
  /// every other key together, and files with one extension share it.
  private static let keys: [URLResourceKey] = [.localizedNameKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
                                               .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey,
                                               .fileSizeKey, .isExecutableKey]
  private static let kindLock = NSLock()
  private static var kinds: [String: String] = [:]

  /// Finder's Kind, looked up once per extension.
  static func kind(of url: URL, isFolder: Bool, isExecutable: Bool) -> String {
    if isFolder { return "Folder" }
    let ext = url.pathExtension.lowercased()
    if ext.isEmpty { return isExecutable ? "Unix Executable File" : "Document" }
    if let kind = kindLock.withLock({ kinds[ext] }) { return kind }
    let kind = UTType(filenameExtension: ext)?.localizedDescription ?? "Document"
    kindLock.withLock { kinds[ext] = kind }
    return kind
  }

  /// Nil when the folder cannot be read (missing, or privacy access denied).
  static func load(_ folder: URL, hidden: Bool = false) -> [FileEntry]? {
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: keys, options: hidden ? [] : [.skipsHiddenFiles])
    else { return nil }
    return ranked(urls.map { entry($0) })
  }

  /// `entries` with their `nameOrder`, worked out once off the main thread.
  /// Finder's name comparison is most of a sort's cost, and the rows sort
  /// again on every filter keystroke and every folder size measured.
  static func ranked(_ entries: [FileEntry]) -> [FileEntry] {
    let order = entries.indices.sorted { entries[$0].name.localizedStandardCompare(entries[$1].name) == .orderedAscending }
    var ranked = entries
    for (rank, index) in order.enumerated() { ranked[index].nameOrder = rank }
    return ranked
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
                     created: values?.creationDate ?? .distantPast,
                     added: values?.addedToDirectoryDate ?? .distantPast,
                     size: isFolder ? nil : values?.fileSize.map(Int64.init),
                     kind: kind(of: url, isFolder: isFolder, isExecutable: values?.isExecutable == true))
  }

  /// Folders come first for a name sort, as in Finder; ties fall back to name.
  /// Sorts positions by plain numbers taken out first: rows are big structs
  /// that cost retains to move, and string keys cost a hash per comparison.
  static func sorted(_ entries: [FileEntry], by key: FileSortKey, ascending: Bool = true) -> [FileEntry] {
    let names = (entries.allSatisfy { $0.nameOrder != nil } ? entries : ranked(entries)).map { $0.nameOrder ?? 0 }
    let value: [Double]
    switch key {
    case .name: value = names.map(Double.init)
    case .modified: value = entries.map { $0.modified.timeIntervalSinceReferenceDate }
    case .created: value = entries.map { $0.created.timeIntervalSinceReferenceDate }
    case .added: value = entries.map { $0.added.timeIntervalSinceReferenceDate }
    case .size: value = entries.map { Double($0.size ?? -1) }
    case .kind:
      // Few kinds, however many rows: each compared once here, not per pair.
      let kinds = Dictionary(uniqueKeysWithValues: Set(entries.map(\.kind))
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }.enumerated().map { ($1, Double($0)) })
      value = entries.map { kinds[$0.kind] ?? 0 }
    }
    let folders = key == .name ? entries.map(\.isFolder) : []
    let order = entries.indices.sorted { a, b in
      if key == .name, folders[a] != folders[b] { return folders[a] }
      if value[a] != value[b] { return ascending ? value[a] < value[b] : value[a] > value[b] }
      return names[a] < names[b]
    }
    return order.map { entries[$0] }
  }

  static func filtered(_ entries: [FileEntry], query: String) -> [FileEntry] {
    let query = query.trimmingCharacters(in: .whitespaces)
    guard !query.isEmpty else { return entries }
    return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
  }
}

/// The last listing of recent folders, shown at once when you come back to
/// one while it is read again. Main thread only.
struct ListingCache {
  static var shared = ListingCache()

  let limit: Int
  private var listings: [String: [FileEntry]] = [:]
  /// Least recently stored first.
  private var order: [String] = []

  init(limit: Int = 48) { self.limit = limit }

  private static func key(_ folder: URL, _ hidden: Bool) -> String {
    "\(hidden ? 1 : 0)|\(folder.standardizedFileURL.path)"
  }

  func entries(for folder: URL, hidden: Bool) -> [FileEntry]? { listings[Self.key(folder, hidden)] }

  mutating func store(_ entries: [FileEntry], for folder: URL, hidden: Bool) {
    let key = Self.key(folder, hidden)
    order.removeAll { $0 == key }
    order.append(key)
    listings[key] = entries
    while order.count > limit { listings[order.removeFirst()] = nil }
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

  static func makeFolder(in folder: URL, named name: String = "untitled folder") throws -> URL {
    let url = folder.appendingPathComponent(available(name, ext: "", exists: free(in: folder)))
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
    return path == base || path.hasPrefix(base == "/" ? "/" : base + "/")
  }
}
