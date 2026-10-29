import AppKit

/// A folder in the sidebar's Favorites.
struct Place: Equatable {
  let name: String
  let url: URL
  let symbol: String
}

/// Finder's sidebar Favorites, in Finder's order, from the shared file list
/// Finder keeps them in. Finder draws them as template symbols, and so does
/// the sidebar: no icon is read from disk, which matters on a network mount.
enum FinderFavorites {
  static let folder = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
  /// Newest format first; macOS moves to a new extension every few releases.
  static let lists = ["sfl4", "sfl3"].map {
    folder.appendingPathComponent("com.apple.LSSharedFileList.FavoriteItems.\($0)")
  }

  static var list: URL? { lists.first { FileManager.default.fileExists(atPath: $0.path) } }

  /// Nil when the list is missing or can't be read.
  static func load(from list: URL? = list) -> [Place]? {
    guard let list, let data = try? Data(contentsOf: list) else { return nil }
    return places(in: data).map(distinct)
  }

  /// Folders that share a name (`/Applications` and `~/Applications`) are
  /// told apart by their paths.
  static func distinct(_ places: [Place]) -> [Place] {
    let counts = Dictionary(places.map { ($0.name, 1) }, uniquingKeysWith: +)
    return places.map { place in
      guard counts[place.name, default: 0] > 1 else { return place }
      return Place(name: (place.url.path as NSString).abbreviatingWithTildeInPath, url: place.url, symbol: place.symbol)
    }
  }

  static func places(in data: Data) -> [Place]? {
    let classes = [NSDictionary.self, NSArray.self, NSString.self, NSData.self, NSNumber.self, NSUUID.self, NSDate.self]
    guard let root = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as? [String: Any],
          let items = root["items"] as? [[String: Any]]
    else { return nil }
    return items.compactMap { item in
      let properties = item["CustomItemProperties"] as? [String: Any]
      guard (properties?["com.apple.LSSharedFileList.ItemIsHidden"] as? NSNumber)?.boolValue != true,
            let bookmark = item["Bookmark"] as? Data
      else { return nil }
      var stale = false
      guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                               bookmarkDataIsStale: &stale), url.isFileURL
      else { return nil }
      return place(url.standardizedFileURL)
    }
  }

  static func place(_ url: URL) -> Place {
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    let name = url.path == home.path ? NSUserName() : DisplayNames.name(of: url)
    return Place(name: name, url: url, symbol: symbol(for: url, home: home))
  }

  static func symbol(for url: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL) -> String {
    let path = url.path
    if path == home.path { return "house" }
    if path.contains("/Library/Mobile Documents/") { return "icloud" }
    if url.lastPathComponent == "Applications" { return "square.grid.3x3" }
    guard url.deletingLastPathComponent().path == home.path else { return "folder" }
    switch url.lastPathComponent {
    case "Desktop": return "menubar.dock.rectangle"
    case "Documents": return "doc"
    case "Downloads": return "arrow.down.circle"
    case "Pictures": return "photo"
    case "Music": return "music.note"
    case "Movies": return "film"
    case "Library": return "building.columns"
    case "src", "code", "dev", "Developer": return "curlybraces"
    case "Projects", "work", "folio": return "briefcase"
    case "Games", "Zelda": return "gamecontroller"
    default: return "folder"
    }
  }

  /// When Finder's list can't be read.
  static let standard: [Place] = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [home, URL(fileURLWithPath: "/Applications")]
      + ["Desktop", "Documents", "Downloads", "src"].map { home.appendingPathComponent($0) }
  }().filter { FileManager.default.fileExists(atPath: $0.path) }.map(place)
}

/// The sidebar's Favorites, read off the main thread and again whenever
/// Finder's list changes, for every browser window.
final class PlacesMonitor: ObservableObject {
  static let shared = PlacesMonitor()

  @Published private(set) var favorites: [Place] = FinderFavorites.standard
  private var loadedStamp: Date?
  private var loading = false

  /// A stat when nothing changed; called as browsers load folders.
  func refresh() {
    guard !loading else { return }
    let list = FinderFavorites.list
    let stamp = list.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
    guard stamp != loadedStamp else { return }
    loading = true
    DispatchQueue.global(qos: .userInitiated).async {
      let favorites = FinderFavorites.load(from: list)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.loading = false
        self.loadedStamp = stamp
        let places = favorites?.isEmpty == false ? favorites! : FinderFavorites.standard
        if places != self.favorites { self.favorites = places }
      }
    }
  }
}

/// Finder's names for folders, which a Launch Services lookup gives at a
/// cost of up to milliseconds; path bars and tabs read them on every redraw.
enum DisplayNames {
  private static let lock = NSLock()
  private static var names: [String: String] = [:]

  static func name(of url: URL) -> String {
    let path = url.standardizedFileURL.path
    if let name = lock.withLock({ names[path] }) { return name }
    let name = FileManager.default.displayName(atPath: path)
    lock.withLock {
      if names.count > 2000 { names.removeAll() }
      names[path] = name
    }
    return name
  }
}
