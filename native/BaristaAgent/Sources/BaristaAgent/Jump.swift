import AppKit
import SwiftUI

/// A folder ⌘K can go to. `weight` orders folders before a query does:
/// zoxide's frecency score, or a fixed weight for places and repos.
struct JumpCandidate: Equatable, Identifiable {
  let url: URL
  let weight: Double
  var id: URL { url }
}

enum JumpRanking {
  /// Each whitespace-separated token must be found in the path under Home,
  /// at worst as letters in order. A token in the folder's own name counts
  /// most, so `oos core` finds `oracle-of-secrets/Core`.
  static func score(_ candidate: JumpCandidate, tokens: [String]) -> Double? {
    let path = (candidate.url.path as NSString).abbreviatingWithTildeInPath.lowercased()
    let name = candidate.url.lastPathComponent.lowercased()
    var total = 0.0
    for token in tokens {
      if name.hasPrefix(token) { total += 5 }
      else if name.contains(token) { total += 3 }
      else if path.contains(token) { total += 1.5 }
      else if isSubsequence(token, of: path) { total += 0.5 }
      else { return nil }
    }
    return total + log1p(max(candidate.weight, 0)) * 0.5 - Double(candidate.url.pathComponents.count) * 0.05
  }

  static func rank(_ candidates: [JumpCandidate], query: String, limit: Int = 40) -> [JumpCandidate] {
    let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    return candidates
      .compactMap { candidate in score(candidate, tokens: tokens).map { (candidate, $0) } }
      .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.url.path < $1.0.url.path }
      .prefix(limit)
      .map(\.0)
  }

  /// Each folder once, at the highest weight any source gave it.
  static func merge(_ lists: [[JumpCandidate]]) -> [JumpCandidate] {
    var best: [URL: Double] = [:]
    for candidate in lists.joined() {
      let url = candidate.url.standardizedFileURL
      best[url] = max(best[url] ?? -.infinity, candidate.weight)
    }
    return best.map { JumpCandidate(url: $0.key, weight: $0.value) }
  }

  private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
    var rest = haystack[...]
    for character in needle {
      guard let index = rest.firstIndex(of: character) else { return false }
      rest = rest[rest.index(after: index)...]
    }
    return true
  }

  /// `zoxide query --list --score` lines: a right-aligned score, a space, a path.
  static func parseZoxide(_ output: String) -> [JumpCandidate] {
    output.split(separator: "\n").compactMap { line in
      let parts = line.drop { $0 == " " }.split(separator: " ", maxSplits: 1)
      guard parts.count == 2, let score = Double(parts[0]) else { return nil }
      return JumpCandidate(url: URL(fileURLWithPath: String(parts[1])), weight: score)
    }
  }
}

/// The folders ⌘K offers: dock and standard places, zoxide's list, and every
/// repo under ~/src. Shared by all browsers and read again after five minutes.
final class JumpIndex: ObservableObject {
  static let shared = JumpIndex()
  @Published private(set) var candidates: [JumpCandidate] = []
  private var loadedAt: Date?
  private var loading = false

  func refresh(places: [URL]) {
    guard !loading, loadedAt.map({ -$0.timeIntervalSinceNow > 300 }) ?? true else { return }
    loading = true
    DispatchQueue.global(qos: .userInitiated).async {
      let found = Self.load(places: places)
      DispatchQueue.main.async {
        self.candidates = found
        self.loadedAt = Date()
        self.loading = false
      }
    }
  }

  private static func load(places: [URL]) -> [JumpCandidate] {
    var lists = [places.map { JumpCandidate(url: $0, weight: 20) }]
    if let zoxide = Tool.find("zoxide"), let output = Tool.output(zoxide, ["query", "--list", "--score"]) {
      lists.append(JumpRanking.parseZoxide(output))
    }
    let src = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("src")
    if let fd = Tool.find("fd"),
       let output = Tool.output(fd, ["--hidden", "--max-depth", "5", "--glob", ".git", src.path]) {
      lists.append(output.split(separator: "\n").map {
        JumpCandidate(url: URL(fileURLWithPath: String($0)).deletingLastPathComponent(), weight: 5)
      })
    }
    return JumpRanking.merge(lists).filter { FileManager.default.fileExists(atPath: $0.url.path) }
  }

  /// Folders browsed here count in zoxide, as `cd` does in the shell.
  static func remember(_ url: URL) {
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue,
          let zoxide = Tool.find("zoxide") else { return }
    launch(zoxide, ["add", url.path], quiet: true)
  }
}

/// ⌘K (or ⇧⌘G): type part of a folder's name or path. Return goes there,
/// ⌘Return opens it in a tab, ↑ and ↓ choose, Escape closes. A path that
/// starts with / or ~ goes to that folder.
struct JumpView: View {
  @ObservedObject var state: BrowserState
  @ObservedObject private var index = JumpIndex.shared
  @State private var query = ""
  @State private var highlighted = 0
  @FocusState private var focused: Bool

  private var typedFolder: URL? {
    let text = query.trimmingCharacters(in: .whitespaces)
    guard text.hasPrefix("/") || text.hasPrefix("~") else { return nil }
    let url = URL(fileURLWithPath: (text as NSString).expandingTildeInPath).standardizedFileURL
    var isFolder: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue ? url : nil
  }

  private var results: [JumpCandidate] {
    var ranked = JumpRanking.rank(index.candidates, query: query)
    if let typed = typedFolder {
      ranked.removeAll { $0.url == typed }
      ranked.insert(JumpCandidate(url: typed, weight: 0), at: 0)
    }
    return ranked
  }

  var body: some View {
    let results = self.results
    VStack(spacing: 0) {
      TextField("Jump to a folder", text: $query)
        .textFieldStyle(.plain)
        .font(.title3)
        .padding(12)
        .focused($focused)
        .onSubmit { choose(results, newTab: NSEvent.modifierFlags.contains(.command)) }
        .onKeyPress(.downArrow) {
          highlighted = min(highlighted + 1, max(results.count - 1, 0))
          return .handled
        }
        .onKeyPress(.upArrow) {
          highlighted = max(highlighted - 1, 0)
          return .handled
        }
        .onExitCommand { state.jumping = false }
        .onChange(of: query) { highlighted = 0 }
      Divider()
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { offset, candidate in
              row(candidate.url, selected: offset == highlighted)
                .id(candidate.id)
                .onTapGesture {
                  highlighted = offset
                  choose(results, newTab: false)
                }
            }
          }
        }
        .onChange(of: highlighted) {
          if results.indices.contains(highlighted) { proxy.scrollTo(results[highlighted].id) }
        }
      }
      if index.candidates.isEmpty {
        Text("Reading zoxide and ~/src…").font(.caption).foregroundStyle(.secondary).padding(8)
      }
    }
    .frame(width: 560, height: 380)
    .onAppear {
      index.refresh(places: PlacesMonitor.shared.favorites.map(\.url) + state.places().map(\.url))
      DispatchQueue.main.async { focused = true }
    }
  }

  private func row(_ url: URL, selected: Bool) -> some View {
    HStack(spacing: 8) {
      FileIcon(url: url, points: 18)
      Text(url.lastPathComponent).fontWeight(.medium).lineLimit(1)
      Text((url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
        .foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 5)
    .background(selected ? Color.accentColor.opacity(0.25) : Color.clear)
    .contentShape(Rectangle())
  }

  private func choose(_ results: [JumpCandidate], newTab: Bool) {
    guard results.indices.contains(highlighted) else { return }
    let url = results[highlighted].url
    state.jumping = false
    if newTab { state.newTab(at: url) } else { state.go(to: url) }
  }
}