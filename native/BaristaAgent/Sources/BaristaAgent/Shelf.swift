import Foundation

/// A scratch space on the dock: files dropped on the shelf tile are kept as
/// references (nothing moves), and dropped text becomes a snippet file the
/// shelf owns. Items are cleared after `shelf_days`.
final class Shelf: ObservableObject {
  struct Entry: Codable, Equatable {
    var path: String
    var added: Date
  }

  @Published private(set) var entries: [Entry] = []

  static let stateURL: URL = {
    let env = ProcessInfo.processInfo.environment
    if let override = env["BARISTA_SHELF_FILE"], !override.isEmpty {
      return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
    }
    let base = env["XDG_STATE_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory() + "/.local/state"
    return URL(fileURLWithPath: base).appendingPathComponent("barista/shelf.json")
  }()

  /// Snippets live next to the state file, so the shelf can delete them.
  static var snippetDirectory: URL {
    stateURL.deletingPathExtension().appendingPathComponent("snippets")
  }

  var urls: [URL] { entries.map { URL(fileURLWithPath: $0.path) } }

  /// Drops missing files and expired entries, deleting expired snippets.
  func load(maxAge: TimeInterval, now: Date = Date()) {
    let stored = (try? Data(contentsOf: Self.stateURL)).flatMap { try? Self.decoder.decode([Entry].self, from: $0) } ?? []
    let kept = Self.pruned(stored, now: now, maxAge: maxAge) { FileManager.default.fileExists(atPath: $0) }
    for entry in stored where !kept.contains(entry) && Self.ownsSnippet(entry.path) {
      try? FileManager.default.removeItem(atPath: entry.path)
    }
    if kept != stored { save(kept) }
    if kept != entries { entries = kept }
  }

  func add(_ urls: [URL], now: Date = Date()) {
    let paths = Set(entries.map(\.path))
    let fresh = urls.filter(\.isFileURL).map(\.path).filter { !paths.contains($0) }
    guard !fresh.isEmpty else { return }
    update(fresh.map { Entry(path: $0, added: now) } + entries)
  }

  func add(text: String, now: Date = Date()) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let formatter = DateFormatter()
    // Fixed: a 12-hour or non-Gregorian setting would otherwise rewrite the pattern.
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    let stamp = "Snippet \(formatter.string(from: now))"
    var file = Self.snippetDirectory.appendingPathComponent("\(stamp).txt")
    var copy = 2
    while FileManager.default.fileExists(atPath: file.path) {
      file = Self.snippetDirectory.appendingPathComponent("\(stamp) \(copy).txt")
      copy += 1
    }
    do {
      try FileManager.default.createDirectory(at: Self.snippetDirectory, withIntermediateDirectories: true)
      try Data((trimmed + "\n").utf8).write(to: file)
    } catch {
      DockStore.log("could not save a shelf snippet: \(error)")
      return
    }
    add([file], now: now)
  }

  func remove(_ url: URL) {
    if Self.ownsSnippet(url.path) { try? FileManager.default.removeItem(at: url) }
    update(entries.filter { $0.path != url.path })
  }

  func clear() {
    for entry in entries where Self.ownsSnippet(entry.path) {
      try? FileManager.default.removeItem(atPath: entry.path)
    }
    update([])
  }

  /// Newest first; drops entries older than `maxAge` or whose file is gone.
  static func pruned(_ entries: [Entry], now: Date, maxAge: TimeInterval,
                     exists: (String) -> Bool) -> [Entry] {
    entries.filter { now.timeIntervalSince($0.added) < maxAge && exists($0.path) }
      .sorted { $0.added > $1.added }
  }

  // MARK: Private

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    return decoder
  }()

  private static func ownsSnippet(_ path: String) -> Bool {
    URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path
      == snippetDirectory.standardizedFileURL.path
  }

  private func update(_ next: [Entry]) {
    save(next)
    entries = next
  }

  private func save(_ entries: [Entry]) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    do {
      try FileManager.default.createDirectory(at: Self.stateURL.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)
      try encoder.encode(entries).write(to: Self.stateURL, options: .atomic)
    } catch {
      DockStore.log("could not save \(Self.stateURL.path): \(error)")
    }
  }
}
