import AppKit
import SwiftUI

/// A folder's AFS `.context`, read from its entry points only: a scratchpad
/// can hold hundreds of thousands of files and hivemind thousands of messages,
/// so nothing here walks a tree.
struct AFSContext: Equatable {
  struct Item: Equatable, Identifiable {
    let url: URL
    let title: String
    let status: String
    let owner: String?
    let priority: Int?
    var id: URL { url }
  }

  struct Message: Equatable, Identifiable {
    let url: URL
    let from: String
    let to: String
    let type: String
    let text: String
    let date: Date
    var id: URL { url }
  }

  let root: URL
  var state: [MarkdownBlock] = []
  /// Items not yet finished, by priority.
  var active: [Item] = []
  var finishedCount = 0
  /// The newest hivemind messages.
  var messages: [Message] = []
  /// The newest files at the top of the scratchpad, besides `state.md`.
  var notes: [URL] = []
  /// The newest entries in `handoffs/` and `scratchpad/handoffs/`.
  var handoffs: [URL] = []

  static let finished: Set<String> = ["done", "closed", "cancelled", "canceled", "archived", "completed"]
  static let shown = 6

  var isEmpty: Bool { state.isEmpty && active.isEmpty && messages.isEmpty && notes.isEmpty && handoffs.isEmpty }

  /// The nearest `.context` folder at or above `folder`. Home's own is left
  /// out: it is the global context, not this folder's. An empty scaffold
  /// (only `.keep` files) doesn't hide the project's context above it.
  static func find(from folder: URL) -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    var current = folder.standardizedFileURL
    while current.path != "/" && current.path != home {
      let candidate = current.appendingPathComponent(".context")
      var isFolder: ObjCBool = false
      if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isFolder), isFolder.boolValue,
         ["scratchpad", "items", "hivemind", "handoffs"].contains(where: {
           !listing(candidate.appendingPathComponent($0)).isEmpty
         }) {
        return candidate
      }
      current.deleteLastPathComponent()
    }
    return nil
  }

  /// Blocking; call it off the main thread.
  static func load(_ root: URL) -> AFSContext {
    var context = AFSContext(root: root)
    let scratchpad = root.appendingPathComponent("scratchpad")
    if let handle = try? FileHandle(forReadingFrom: scratchpad.appendingPathComponent("state.md")) {
      let head = (try? handle.read(upToCount: 20_000)) ?? nil
      try? handle.close()
      context.state = Markdown.parse(head.flatMap(Preview.decodeText) ?? "")
    }

    var items: [Item] = []
    for url in listing(root.appendingPathComponent("items")).prefix(500) where url.pathExtension == "json" {
      guard let object = json(url) else { continue }
      let status = (object["status"] as? String ?? "").lowercased()
      if finished.contains(status) {
        context.finishedCount += 1
      } else {
        items.append(Item(url: url, title: object["title"] as? String ?? url.deletingPathExtension().lastPathComponent,
                          status: status.isEmpty ? "open" : status, owner: (object["assigned_to"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                          priority: object["priority"] as? Int))
      }
    }
    context.active = items.sorted {
      ($0.priority ?? .max, $0.title.localizedLowercase) < ($1.priority ?? .max, $1.title.localizedLowercase)
    }

    let hivemind = root.appendingPathComponent("hivemind")
    let messageFiles = listing(hivemind).flatMap { url in
      AFSContext.isFolder(url) ? listing(url).filter { $0.pathExtension == "json" } : (url.pathExtension == "json" ? [url] : [])
    }
    context.messages = newest(messageFiles, count: shown).compactMap { url, modified in
      guard let object = json(url) else { return nil }
      let payload = object["payload"]
      let text = (payload as? [String: Any])?["text"] as? String ?? payload as? String ?? ""
      let stamp = (object["timestamp"] as? String).flatMap { ISO8601DateFormatter.fractional.date(from: $0)
        ?? ISO8601DateFormatter().date(from: $0) }
      return Message(url: url, from: object["from"] as? String ?? "?", to: object["to"] as? String ?? "",
                     type: object["type"] as? String ?? "", text: text, date: stamp ?? modified)
    }

    let notes = listing(scratchpad).filter {
      !isFolder($0) && $0.lastPathComponent != "state.md" && ["md", "org", "txt"].contains($0.pathExtension)
    }
    context.notes = newest(notes, count: shown).map(\.0)
    let handoffs = listing(root.appendingPathComponent("handoffs")) + listing(scratchpad.appendingPathComponent("handoffs"))
    context.handoffs = newest(handoffs, count: shown).map(\.0)
    return context
  }

  static func isFolder(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
  }

  /// One folder's entries; empty when it is missing.
  private static func listing(_ folder: URL) -> [URL] {
    (try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
      options: [.skipsHiddenFiles])) ?? []
  }

  private static func newest(_ urls: [URL], count: Int) -> [(URL, Date)] {
    urls.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) }
      .sorted { $0.1 > $1.1 }
      .prefix(count)
      .map { $0 }
  }

  private static func json(_ url: URL) -> [String: Any]? {
    (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
  }
}

private extension ISO8601DateFormatter {
  static let fractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

/// The preview pane with nothing selected inside a folder that has an AFS
/// context: its scratchpad state, open items, latest messages, notes, and
/// handoffs. Items and messages open in a tab with the file selected.
struct ContextPanel: View {
  let root: URL
  let state: BrowserState
  @State private var context: AFSContext?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        if let context {
          if context.isEmpty {
            Text("Nothing in this context yet.").foregroundStyle(.secondary)
          }
          if !context.state.isEmpty {
            section("Scratchpad State") {
              ForEach(Array(context.state.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, base: root.appendingPathComponent("scratchpad"))
              }
            }
          }
          if !context.active.isEmpty || context.finishedCount > 0 {
            section("Items · \(context.active.count) active, \(context.finishedCount) done") {
              ForEach(context.active.prefix(12)) { item in
                Button { reveal(item.url) } label: { itemRow(item) }.buttonStyle(.plain)
              }
            }
          }
          if !context.messages.isEmpty {
            section("Hivemind") {
              ForEach(context.messages) { message in
                Button { reveal(message.url) } label: { messageRow(message) }.buttonStyle(.plain)
              }
            }
          }
          if !context.notes.isEmpty {
            section("Scratchpad Notes") { ForEach(context.notes, id: \.self) { fileRow($0) } }
          }
          if !context.handoffs.isEmpty {
            section("Handoffs") { ForEach(context.handoffs, id: \.self) { fileRow($0) } }
          }
        } else {
          ProgressView().controlSize(.small)
        }
      }
      .textSelection(.enabled)
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .environment(\.openURL, OpenURLAction { url in
      LinkRoute.of(url, base: root.appendingPathComponent("scratchpad")).perform()
      return .handled
    })
    .task(id: root) {
      let root = self.root
      // The panel stays when the root changes; another project's context mustn't show meanwhile.
      if context?.root != root { context = nil }
      let loaded = await Task.detached(priority: .userInitiated) { AFSContext.load(root) }.value
      guard !Task.isCancelled else { return }
      context = loaded
    }
  }

  private var header: some View {
    HStack {
      Label("AFS Context", systemImage: "square.stack.3d.up").font(.headline)
      Spacer()
      Button("Browse") { state.newTab(at: root) }.buttonStyle(.link)
    }
    .help((root.path as NSString).abbreviatingWithTildeInPath)
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
      content()
    }
  }

  private func itemRow(_ item: AFSContext.Item) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(item.priority.map { "P\($0)" } ?? "–").font(.caption.monospaced()).foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title).lineLimit(2)
        Text([item.status.replacingOccurrences(of: "_", with: " "), item.owner].compactMap { $0 }.joined(separator: " · "))
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .contentShape(Rectangle())
  }

  private func messageRow(_ message: AFSContext.Message) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("\(message.from) → \(message.to.isEmpty ? "all" : message.to)").font(.callout.weight(.medium)).lineLimit(1)
      Text(message.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
      Text([message.type, message.date.formatted(.relative(presentation: .named))].filter { !$0.isEmpty }
        .joined(separator: " · "))
        .font(.caption2).foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
  }

  private func fileRow(_ url: URL) -> some View {
    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    return Button {
      if AFSContext.isFolder(url) { state.newTab(at: url) } else { PopoverController.open(url) }
    } label: {
      HStack(spacing: 6) {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 4)
        if let modified {
          Text(modified, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func reveal(_ url: URL) {
    state.newTab(at: url.deletingLastPathComponent(), selecting: url)
  }
}