import Foundation

/// How a folder is drawn. A field left out falls through to the next
/// source: Barista's choice for the folder, then Finder's, then the defaults.
struct FolderView: Codable, Equatable {
  var layout: BrowserLayout?
  var sortKey: FileSortKey?
  var ascending: Bool?
  var iconSize: Double?

  static let iconSizes: ClosedRange<Double> = 32...128
  static let iconStep: Double = 16
  static let fallback = FolderView(layout: .list, sortKey: .name, ascending: true, iconSize: 64)

  /// Icons come in steps, so a few sizes are drawn and cached, not one per
  /// slider position.
  static func iconSize(_ points: Double) -> Double {
    min(max((points / iconStep).rounded() * iconStep, iconSizes.lowerBound), iconSizes.upperBound)
  }

  /// `self`, with what it leaves out taken from `other`.
  func filled(from other: FolderView) -> FolderView {
    FolderView(layout: layout ?? other.layout, sortKey: sortKey ?? other.sortKey,
               ascending: ascending ?? other.ascending, iconSize: iconSize ?? other.iconSize)
  }

  /// What Finder recorded for a folder: its "Always open in" view, and how
  /// its icon and list views are arranged.
  struct Finder: Equatable {
    var layout: BrowserLayout?
    var icons = FolderView()
    var list = FolderView()

    init(records: [String: DSStore.Value]) {
      if case .type(let style) = records["vstl"] {
        switch style {
        case "icnv", "Flwv", "glyv": layout = .icons
        case "Nlsv": layout = .list
        case "clmv": layout = .columns
        default: break
        }
      }
      if let icon = DSStore.plist(records["icvp"]) {
        if let arrange = icon["arrangeBy"] as? String, let key = Self.sortKey(arrange) {
          icons.sortKey = key
          icons.ascending = key.ascendsByDefault
        }
        if let size = icon["iconSize"] as? Double { icons.iconSize = FolderView.iconSize(size) }
      }
      if let listed = DSStore.plist(records["lsvP"] ?? records["lsvp"]),
         let column = listed["sortColumn"] as? String, let key = Self.sortKey(column) {
        list.sortKey = key
        list.ascending = Self.column(column, in: listed)?["ascending"] as? Bool ?? key.ascendsByDefault
      }
    }

    /// Finder keeps most folders' settings in the parent's `.DS_Store` under
    /// the folder's name, and some (a volume's top, `/Applications`) in the
    /// folder's own under `.`. Blocking: a network folder's file comes over
    /// the wire.
    static func read(_ folder: URL) -> Finder {
      let folder = folder.standardizedFileURL
      func records(in store: URL, named name: String) -> [String: DSStore.Value] {
        let file = store.appendingPathComponent(".DS_Store")
        return (try? Data(contentsOf: file, options: .mappedIfSafe)).flatMap { DSStore.records(in: $0, named: name) } ?? [:]
      }
      var found = records(in: folder, named: ".")
      if folder.path != "/" {
        found.merge(records(in: folder.deletingLastPathComponent(), named: folder.lastPathComponent)) { own, _ in own }
      }
      return Finder(records: found)
    }

    private static func sortKey(_ finder: String) -> FileSortKey? {
      switch finder {
      case "name": return .name
      case "dateModified": return .modified
      case "dateCreated": return .created
      case "dateAdded": return .added
      case "size": return .size
      case "kind": return .kind
      default: return nil
      }
    }

    /// `lsvp` keys its columns by name; `lsvP` lists them with an identifier.
    private static func column(_ name: String, in settings: [String: Any]) -> [String: Any]? {
      if let columns = settings["columns"] as? [String: Any] { return columns[name] as? [String: Any] }
      let columns = settings["columns"] as? [[String: Any]] ?? []
      return columns.first { $0["identifier"] as? String == name }
    }
  }
}

/// Barista's own view choices, by folder, in its defaults. Finder's
/// `.DS_Store` is read, never written. Main thread only.
final class FolderViews {
  static let shared = FolderViews(.standard)
  private static let savedKey = "BaristaFilesFolderViews"
  private static let defaultsKey = "BaristaFilesDefaultView"

  private struct Saved: Codable {
    let path: String
    let view: FolderView
  }

  private let store: UserDefaults
  private let limit: Int
  private var views: [String: FolderView] = [:]
  /// Least recently changed first.
  private var order: [String] = []

  init(_ store: UserDefaults, limit: Int = 2000) {
    self.store = store
    self.limit = limit
    let saved = store.data(forKey: Self.savedKey).flatMap { try? JSONDecoder().decode([Saved].self, from: $0) } ?? []
    for entry in saved {
      views[entry.path] = entry.view
      order.append(entry.path)
    }
  }

  private static func key(_ folder: URL) -> String { folder.standardizedFileURL.path }

  func saved(for folder: URL) -> FolderView? { views[Self.key(folder)] }

  func update(_ folder: URL, _ change: (inout FolderView) -> Void) {
    let key = Self.key(folder)
    var view = views[key] ?? FolderView()
    change(&view)
    views[key] = view
    order.removeAll { $0 == key }
    order.append(key)
    while order.count > limit { views[order.removeFirst()] = nil }
    let saved = order.compactMap { path in views[path].map { Saved(path: path, view: $0) } }
    store.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
  }

  /// View → Use as Defaults: new windows, and folders without a choice of
  /// their own. Until then, the last layout picked before folders had views.
  var defaults: FolderView {
    get {
      let set = store.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(FolderView.self, from: $0) }
      let legacy = FolderView(layout: store.string(forKey: BrowserLayout.defaultsKey).flatMap(BrowserLayout.init))
      return (set ?? legacy).filled(from: .fallback)
    }
    set { store.set(try? JSONEncoder().encode(newValue), forKey: Self.defaultsKey) }
  }

  /// `folder`'s view in a window showing `current` (nil for a new window).
  /// The window keeps its layout unless the folder has one of its own, as
  /// Finder's "Always open in" works; columns stay columns while browsing.
  /// Sort and icon size are always the folder's.
  func view(for folder: URL, current: BrowserLayout?, finder: FolderView.Finder?) -> FolderView {
    let own = saved(for: folder) ?? FolderView()
    let defaults = self.defaults
    let layout = current == .columns ? .columns : own.layout ?? finder?.layout ?? current ?? defaults.layout ?? .list
    var recorded = FolderView()
    if let finder {
      recorded = layout == .list ? finder.list : layout == .icons ? finder.icons : FolderView()
      recorded.iconSize = finder.icons.iconSize
    }
    var view = own.filled(from: recorded).filled(from: defaults)
    view.layout = layout
    return view
  }
}
