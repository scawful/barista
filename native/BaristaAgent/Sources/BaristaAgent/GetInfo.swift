import AppKit
import SwiftUI

/// Get Info's facts about one item.
struct FileInfo: Equatable {
  let url: URL
  var kind = ""
  var isFolder = false
  /// A file's bytes; folders are measured by `FolderSize`.
  var size: Int64?
  var created: Date?
  var modified: Date?
  /// `drwxr-xr-x` and the owner.
  var permissions = ""
  var linkTarget: String?
  var lastCommit: String?

  /// Blocking; call it off the main thread.
  static func load(_ url: URL, repo: URL?) -> FileInfo {
    var info = FileInfo(url: url)
    let values = try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey, .isDirectoryKey, .fileSizeKey,
                                                   .creationDateKey, .contentModificationDateKey, .isSymbolicLinkKey])
    info.kind = values?.localizedTypeDescription ?? ""
    info.isFolder = values?.isDirectory == true
    info.size = info.isFolder ? nil : values?.fileSize.map(Int64.init)
    info.created = values?.creationDate
    info.modified = values?.contentModificationDate
    if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
       let mode = attributes[.posixPermissions] as? Int {
      let owner = attributes[.ownerAccountName] as? String
      info.permissions = permissions(mode, isFolder: info.isFolder) + (owner.map { " \($0)" } ?? "")
    }
    if values?.isSymbolicLink == true {
      info.linkTarget = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }
    if let repo, url.isWithin(repo) { info.lastCommit = Git.lastCommit(of: url, in: repo) }
    return info
  }

  static func permissions(_ mode: Int, isFolder: Bool) -> String {
    (isFolder ? "d" : "-") + String("rwxrwxrwx".enumerated().map { bit, letter in
      mode & (1 << (8 - bit)) != 0 ? letter : "-"
    })
  }
}

enum FolderSize {
  /// Bytes of every file in `urls` and under them, and how many items that
  /// is, hidden files and package contents included. Nil once `cancelled`
  /// says so; a large tree takes a while.
  static func measure(_ urls: [URL], cancelled: () -> Bool) -> (bytes: Int64, items: Int)? {
    var bytes: Int64 = 0
    var items = 0
    let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
    func add(_ url: URL) {
      items += 1
      if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
        bytes += Int64(values.fileSize ?? 0)
      }
    }
    for url in urls {
      guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
        add(url)
        continue
      }
      let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [],
                                                  errorHandler: { _, _ in true })
      while let next = walker?.nextObject() as? URL {
        if items % 512 == 0, cancelled() { return nil }
        add(next)
      }
    }
    return (bytes, items)
  }
}

/// ⌘I: what Finder's Get Info says that matters here, plus the last commit.
/// Several items show their count and total size.
struct GetInfoView: View {
  let urls: [URL]
  let repo: URL?
  let close: () -> Void
  @State private var info: FileInfo?
  @State private var measured: (bytes: Int64, items: Int)?

  private var single: URL? { urls.count == 1 ? urls.first : nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 12) {
        Image(nsImage: NSWorkspace.shared.icon(forFiles: urls.map(\.path))
              ?? NSWorkspace.shared.icon(for: .folder))
          .resizable().frame(width: 48, height: 48)
        VStack(alignment: .leading, spacing: 2) {
          Text(single?.lastPathComponent ?? "\(urls.count) items").font(.headline).lineLimit(2)
          Text(single == nil ? "Selection" : info?.kind ?? "").foregroundStyle(.secondary)
        }
      }
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
        row("Size", size)
        row("Where", parentFolder)
        if let info {
          if let created = info.created { row("Created", created.formatted(date: .abbreviated, time: .shortened)) }
          if let modified = info.modified { row("Modified", modified.formatted(date: .abbreviated, time: .shortened)) }
          if !info.permissions.isEmpty { row("Permissions", info.permissions, mono: true) }
          if let target = info.linkTarget { row("Links to", target) }
          if let commit = info.lastCommit { row("Last commit", commit) }
        }
      }
      .font(.callout)
      .textSelection(.enabled)
      HStack {
        Spacer()
        Button("Done", action: close).keyboardShortcut(.defaultAction)
      }
    }
    .padding(18)
    .frame(width: 460)
    .onExitCommand(perform: close)
    .task {
      guard let single else { return }
      let repo = self.repo
      info = await Task.detached(priority: .userInitiated) { FileInfo.load(single, repo: repo) }.value
    }
    .task {
      let urls = self.urls
      // A detached task doesn't see this one's cancellation; pass it on.
      let worker = Task.detached(priority: .utility) { FolderSize.measure(urls) { Task.isCancelled } }
      measured = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    }
  }

  private var size: String {
    if let bytes = info?.size, !(info?.isFolder ?? true) {
      return Preview.byteCount(Int(bytes)) + (bytes < 1000 ? "" : " (\(bytes.formatted()) bytes)")
    }
    guard let measured else { return "Calculating…" }
    return Preview.byteCount(Int(measured.bytes))
      + " · \(measured.items.formatted()) item\(measured.items == 1 ? "" : "s")"
  }

  private var parentFolder: String {
    let parents = Set(urls.map { $0.deletingLastPathComponent().path })
    guard parents.count == 1, let parent = parents.first else { return "Several folders" }
    return (parent as NSString).abbreviatingWithTildeInPath
  }

  private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
    GridRow(alignment: .firstTextBaseline) {
      Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
      Text(value).font(mono ? .callout.monospaced() : .callout).fixedSize(horizontal: false, vertical: true)
    }
  }
}
