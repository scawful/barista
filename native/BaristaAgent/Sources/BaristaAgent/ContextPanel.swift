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
    /// The AFS task ID, when the file is a task queue entry it can update.
    var taskID: String?
    var id: URL { url }
  }

  struct Message: Equatable, Identifiable {
    let url: URL
    let messageID: String
    let from: String
    let to: String
    let type: String
    let text: String
    let date: Date
    /// `read` or `done` by recipient, from `hivemind/.acks`, by normalized name.
    var acks: [String: String] = [:]
    var id: URL { url }

    /// Named recipients; a broadcast has none.
    var recipients: [String] {
      to.components(separatedBy: CharacterSet(charactersIn: ",/;"))
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && $0.lowercased() != "all" }
    }

    func state(of recipient: String) -> String { acks[AFSContext.agentName(recipient)] ?? "unread" }
  }

  /// The task statuses AFS's queue accepts.
  static let statuses = ["pending", "in_progress", "done", "failed"]

  /// AFS's comparable agent name: `Codex RC_Planning` is `codex-rc-planning`.
  static func agentName(_ name: String) -> String {
    name.lowercased().trimmingCharacters(in: .whitespaces)
      .replacingOccurrences(of: #"[\s_]+"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
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
                          priority: object["priority"] as? Int, taskID: taskID(url, object)))
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
      let messageID = object["id"] as? String ?? url.deletingPathExtension().lastPathComponent
      return Message(url: url, messageID: messageID, from: object["from"] as? String ?? "?",
                     to: object["to"] as? String ?? "", type: object["type"] as? String ?? "", text: text,
                     date: stamp ?? modified, acks: acks(messageID, in: hivemind))
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

  /// A recipient's `done` outranks a later `read`, as AFS reads them.
  private static func acks(_ messageID: String, in hivemind: URL) -> [String: String] {
    guard !messageID.contains("/"),
          let records = json(hivemind.appendingPathComponent(".acks/\(messageID).json"))?["acks"] as? [[String: Any]]
    else { return [:] }
    var states: [String: String] = [:]
    for record in records {
      guard let by = record["by"] as? String, let status = record["status"] as? String else { continue }
      let name = agentName(by)
      if states[name] != "done" { states[name] = status }
    }
    return states
  }

  /// AFS only touches `task-<id>.json` whose `id` matches its name.
  static func taskID(_ url: URL, _ object: [String: Any]) -> String? {
    guard let id = object["id"] as? String, url.lastPathComponent == "task-\(id).json",
          id.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$"#, options: .regularExpression) != nil
    else { return nil }
    return id
  }
}

/// Changes to a `.context`, made the way AFS makes them.
enum AFSActions {
  /// `scripts/afs` from `AFS_ROOT`, the PATH folders, or a checkout under `~/src`.
  static let cli: String? = {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let root = ProcessInfo.processInfo.environment["AFS_ROOT"].flatMap { $0.isEmpty ? nil : $0 + "/scripts/afs" }
    let candidates = [root, Tool.find("afs")].compactMap { $0 }
      + ["src/runtime/afs", "src/lab/afs", "src/afs"].map { "\(home)/\($0)/scripts/afs" }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
  }()

  enum Failure: LocalizedError, Equatable {
    case status(String)
    case notATask(String)

    var errorDescription: String? {
      switch self {
      case .status(let status): return "AFS tasks can't be “\(status)”."
      case .notATask(let name): return "“\(name)” isn't an AFS task file."
      }
    }
  }

  /// As AFS's `TaskQueue.update_status`: the status and `updated_at`, nothing else.
  static func setStatus(_ item: URL, to status: String, now: Date = Date()) throws {
    guard AFSContext.statuses.contains(status) else { throw Failure.status(status) }
    let data = try Data(contentsOf: item)
    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          AFSContext.taskID(item, object) != nil
    else { throw Failure.notATask(item.lastPathComponent) }
    object["status"] = status
    object["updated_at"] = timestamp(now)
    let written = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try written.write(to: item, options: .atomic)
  }

  /// Python's `datetime.now(timezone.utc).isoformat()`, which AFS writes.
  static func timestamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSxxx"
    return formatter.string(from: date)
  }

  /// `afs messages ack --done` for one recipient: the message leaves that
  /// agent's inbox. Blocking; returns AFS's error output when it fails.
  static func markDone(_ message: AFSContext.Message, for recipient: String, project: URL) -> String? {
    guard let cli else { return "The afs command wasn't found; set AFS_ROOT." }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cli)
    process.arguments = ["messages", "ack", message.messageID, "--by", recipient, "--done",
                         "--note", "Marked done from Barista Files", "--path", project.path]
    process.currentDirectoryURL = project
    let errors = Pipe()
    process.standardOutput = FileHandle.nullDevice
    process.standardError = errors
    do { try process.run() } catch { return error.localizedDescription }
    let output = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus != 0 else { return nil }
    let text = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? "afs exited with status \(process.terminationStatus)." : text
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
  /// Bumped after a change, to read the context again.
  @State private var changes = 0

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
                  .contextMenu { itemMenu(item) }
              }
            }
          }
          if !context.messages.isEmpty {
            section("Hivemind") {
              ForEach(context.messages) { message in
                Button { reveal(message.url) } label: { messageRow(message) }.buttonStyle(.plain)
                  .contextMenu { messageMenu(message) }
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
    .task(id: "\(root.path)\0\(changes)") {
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
      // Whether each recipient has picked it up: a stale chat never will.
      let states = message.recipients.map { "\($0) \(message.state(of: $0))" }
      Text(([message.type, message.date.formatted(.relative(presentation: .named))] + states)
        .filter { !$0.isEmpty }.joined(separator: " · "))
        .font(.caption2).foregroundStyle(.tertiary)
    }
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func itemMenu(_ item: AFSContext.Item) -> some View {
    if item.taskID != nil {
      ForEach(AFSContext.statuses.filter { $0 != item.status }, id: \.self) { status in
        Button("Mark \(status.replacingOccurrences(of: "_", with: " ").capitalized)") { setStatus(item, status) }
      }
      Divider()
    }
    Button("Open") { PopoverController.open(item.url) }
    Button("Show in Folder") { reveal(item.url) }
    if let id = item.taskID { Button("Copy Task ID") { copyText(id) } }
  }

  @ViewBuilder
  private func messageMenu(_ message: AFSContext.Message) -> some View {
    let open = message.recipients.filter { message.state(of: $0) != "done" }
    if AFSActions.cli != nil, !open.isEmpty {
      ForEach(open, id: \.self) { recipient in
        Button("Mark Done for \(recipient)") { markDone(message, for: recipient) }
      }
      Divider()
    }
    Button("Open") { PopoverController.open(message.url) }
    Button("Show in Folder") { reveal(message.url) }
    Button("Copy Message ID") { copyText(message.messageID) }
    Button("Copy Text") { copyText(message.text) }
  }

  private func setStatus(_ item: AFSContext.Item, _ status: String) {
    do {
      try AFSActions.setStatus(item.url, to: status)
      changes += 1
    } catch {
      state.problem = error.localizedDescription
    }
  }

  private func markDone(_ message: AFSContext.Message, for recipient: String) {
    let project = root.deletingLastPathComponent()
    DispatchQueue.global(qos: .userInitiated).async {
      let failure = AFSActions.markDone(message, for: recipient, project: project)
      DispatchQueue.main.async {
        if let failure { state.problem = failure }
        changes += 1
      }
    }
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