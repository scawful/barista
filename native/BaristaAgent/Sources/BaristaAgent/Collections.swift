import AppKit
import Combine
import SwiftUI

extension TileLayout: Codable {}

/// A named list of pictures and movies from any folders, in its own order,
/// with how it was last shown. Paths keep a leading `~` so the file reads
/// the same from another home folder.
struct MediaCollection: Codable, Equatable, Identifiable {
  var name: String
  var items: [String]
  var mode = ViewMode.gallery
  var layout = GalleryLayout.justified
  var tileLayout = TileLayout.grid
  var size = GalleryGrid.defaultSize
  var featured: [String] = []
  var share = FeatureShare.half

  var id: String { name }
  var urls: [URL] { items.map(Self.url) }
  var featuredURLs: Set<URL> { Set(featured.map(Self.url)) }

  init(name: String, urls: [URL] = []) {
    self.name = name
    items = urls.map(Self.path)
  }

  static func path(_ url: URL) -> String { (url.standardizedFileURL.path as NSString).abbreviatingWithTildeInPath }
  static func url(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }

  private enum CodingKeys: String, CodingKey {
    case name, items, mode, layout, tileLayout, size, featured, share
  }

  /// Everything but the name has a default, so a hand-written entry needs
  /// only `name` and `items`.
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    name = try values.decode(String.self, forKey: .name)
    items = try values.decodeIfPresent([String].self, forKey: .items) ?? []
    mode = (try? values.decodeIfPresent(ViewMode.self, forKey: .mode)) ?? .gallery
    layout = (try? values.decodeIfPresent(GalleryLayout.self, forKey: .layout)) ?? .justified
    tileLayout = (try? values.decodeIfPresent(TileLayout.self, forKey: .tileLayout)) ?? .grid
    let size = (try? values.decodeIfPresent(Int.self, forKey: .size)) ?? GalleryGrid.defaultSize
    self.size = min(max(size, 0), GalleryGrid.sizes.count - 1)
    featured = (try? values.decodeIfPresent([String].self, forKey: .featured)) ?? []
    share = (try? values.decodeIfPresent(FeatureShare.self, forKey: .share)) ?? .half
  }
}

/// Named collections in `data/barista_collections.local.json` under the
/// Barista config folder. The first rewrite each day copies the file to
/// `<file>.YYYY-MM-DD.bak` first; the newest three copies stay.
final class CollectionStore: ObservableObject {
  static let favorites = "Favorites"
  static let shared = CollectionStore()

  static var defaultURL: URL {
    let dir = ProcessInfo.processInfo.environment["BARISTA_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
      ?? NSHomeDirectory() + "/.config/sketchybar"
    return URL(fileURLWithPath: dir).appendingPathComponent("data/barista_collections.local.json")
  }

  @Published private(set) var collections: [MediaCollection] = []
  let url: URL
  private var stamp: Date?
  /// The file was there but did not parse; it is copied aside before the
  /// first rewrite, whatever the day.
  private var unreadable = false

  private struct File: Codable {
    var version = 1
    var collections: [MediaCollection]
  }

  init(url: URL = CollectionStore.defaultURL) {
    self.url = url
    load()
  }

  /// Picks up edits made to the file since it was read.
  func refresh() {
    if modified != stamp { load() }
  }

  func collection(named name: String) -> MediaCollection? {
    collections.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
  }

  /// `name`, or `name 2`, `name 3`… when that is taken.
  func uniqueName(_ name: String, except current: String? = nil) -> String {
    let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let taken = { (candidate: String) in
      candidate.caseInsensitiveCompare(current ?? "") != .orderedSame && self.collection(named: candidate) != nil
    }
    guard taken(base) else { return base }
    var number = 2
    while taken("\(base) \(number)") { number += 1 }
    return "\(base) \(number)"
  }

  /// The new collection's name, made unique.
  @discardableResult
  func create(_ name: String, urls: [URL] = [], like settings: MediaCollection? = nil) -> String {
    var collection = settings ?? MediaCollection(name: name)
    collection.name = uniqueName(name)
    collection.items = Self.unique(urls).map(MediaCollection.path)
    collections.append(collection)
    save()
    return collection.name
  }

  /// The new name, or nil when there is no such collection.
  @discardableResult
  func rename(_ name: String, to new: String) -> String? {
    guard let index = index(of: name) else { return nil }
    let unique = uniqueName(new, except: collections[index].name)
    guard !unique.isEmpty, unique != collections[index].name else { return collections[index].name }
    collections[index].name = unique
    save()
    return unique
  }

  func delete(_ name: String) {
    guard let index = index(of: name) else { return }
    collections.remove(at: index)
    save()
  }

  /// Adds the ones not already in it, making the collection when there is
  /// none by that name; how many were added.
  @discardableResult
  func add(_ urls: [URL], to name: String) -> Int {
    if index(of: name) == nil { create(name) }
    var added = 0
    update(name) { collection in
      var present = Set(collection.items)
      for path in urls.map(MediaCollection.path) where present.insert(path).inserted {
        collection.items.append(path)
        added += 1
      }
    }
    return added
  }

  func remove(_ urls: [URL], from name: String) {
    let gone = Set(urls.map(MediaCollection.path))
    update(name) { collection in
      collection.items.removeAll(where: gone.contains)
      collection.featured.removeAll(where: gone.contains)
    }
  }

  func contains(_ url: URL, in name: String) -> Bool {
    collection(named: name)?.items.contains(MediaCollection.path(url)) == true
  }

  /// Changes one collection and saves when anything changed.
  func update(_ name: String, _ change: (inout MediaCollection) -> Void) {
    guard let index = index(of: name) else { return }
    var collection = collections[index]
    change(&collection)
    guard collection != collections[index] else { return }
    collections[index] = collection
    save()
  }

  // MARK: Private

  private func index(of name: String) -> Int? {
    collections.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
  }

  private static func unique(_ urls: [URL]) -> [URL] {
    var seen = Set<String>()
    return urls.filter { seen.insert(MediaCollection.path($0)).inserted }
  }

  private var modified: Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
  }

  private func load() {
    stamp = modified
    unreadable = false
    guard let data = try? Data(contentsOf: url) else { return collections = [] }
    do {
      collections = try JSONDecoder().decode(File.self, from: data).collections
    } catch {
      DockStore.log("collections: cannot read \(url.path): \(error)")
      unreadable = true
      collections = []
    }
  }

  private func save() {
    backUp()
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
      try encoder.encode(File(collections: collections)).write(to: url, options: .atomic)
      stamp = modified
    } catch {
      DockStore.log("collections: cannot write \(url.path): \(error)")
    }
  }

  private static let day: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private func backUp() {
    let files = FileManager.default
    guard files.fileExists(atPath: url.path) else { return }
    if unreadable {
      let aside = URL(fileURLWithPath: url.path + ".unreadable-\(Int(Date().timeIntervalSince1970)).bak")
      try? files.copyItem(at: url, to: aside)
      unreadable = false
    }
    let copy = URL(fileURLWithPath: url.path + ".\(Self.day.string(from: Date())).bak")
    guard !files.fileExists(atPath: copy.path) else { return }
    try? files.copyItem(at: url, to: copy)
    // Only the dated copies count toward the three kept.
    let folder = url.deletingLastPathComponent()
    let prefix = url.lastPathComponent + "."
    let dated = ((try? files.contentsOfDirectory(atPath: folder.path)) ?? [])
      .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".bak") && $0.count == prefix.count + 14 }
      .sorted()
    for name in dated.dropLast(3) { try? files.removeItem(at: folder.appendingPathComponent(name)) }
  }
}

/// Alerts for naming and deleting collections. The agent has to be active
/// to show one; focus goes back afterwards.
enum CollectionPrompt {
  static func name(_ title: String, message: String = "", value: String) -> String? {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.addButton(withTitle: "Cancel")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    field.stringValue = value
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard run(alert) == .alertFirstButtonReturn else { return nil }
    let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  static func confirmDelete(_ name: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = "Delete the collection “\(name)”?"
    alert.informativeText = "The pictures and movies stay where they are."
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    alert.buttons.first?.hasDestructiveAction = true
    return run(alert) == .alertFirstButtonReturn
  }

  private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
    let previous = NSWorkspace.shared.frontmostApplication
    NSApp.activate(ignoringOtherApps: true)
    defer { if previous != NSRunningApplication.current { previous?.activate() } }
    return alert.runModal()
  }
}

/// Add to Collection: Favorites, the other collections, then a new one.
/// `done` gets a line for the status capsule.
enum CollectionMenu {
  static func add(_ urls: @escaping () -> [URL], store: CollectionStore = .shared,
                  done: @escaping (String) -> Void) -> NSMenu {
    let menu = NSMenu(title: "Add to Collection")
    for name in names(store) {
      menu.addItem(MenuChoice.item(name) { done(add(urls(), to: name, store: store)) })
    }
    menu.addItem(.separator())
    menu.addItem(MenuChoice.item("New Collection…") {
      if let name = newName(store) { done(add(urls(), to: name, store: store)) }
    })
    return menu
  }

  static func names(_ store: CollectionStore) -> [String] {
    [CollectionStore.favorites] + store.collections.map(\.name).filter { $0 != CollectionStore.favorites }
  }

  static func newName(_ store: CollectionStore) -> String? {
    CollectionPrompt.name("New Collection", value: store.uniqueName("Collection"))
      .map { store.create($0) }
  }

  static func add(_ urls: [URL], to name: String, store: CollectionStore) -> String {
    let added = store.add(urls, to: name)
    if added == 0 { return "Already in \(name)" }
    return added == 1 ? "Added to \(name)" : "Added \(added) to \(name)"
  }
}

/// The SwiftUI form of `CollectionMenu`, for the bars and the gallery's
/// context menu.
struct AddToCollectionMenu: View {
  let urls: () -> [URL]
  let done: (String) -> Void
  @ObservedObject var store = CollectionStore.shared

  var body: some View {
    Menu("Add to Collection") {
      ForEach(CollectionMenu.names(store), id: \.self) { name in
        Button(name) { done(CollectionMenu.add(urls(), to: name, store: store)) }
      }
      Divider()
      Button("New Collection…") {
        if let name = CollectionMenu.newName(store) { done(CollectionMenu.add(urls(), to: name, store: store)) }
      }
    }
  }
}
