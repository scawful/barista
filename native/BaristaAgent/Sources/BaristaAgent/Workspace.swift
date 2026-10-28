import AppKit
import UniformTypeIdentifiers

/// halext-org's task states. Files keep their own keywords (`NEXT`,
/// `CANCELLED`); each one maps to a state.
enum TaskState: String, CaseIterable, Identifiable {
  case todo, doing, blocked, done

  var id: Self { self }

  var title: String {
    switch self {
    case .todo: return "To Do"
    case .doing: return "Doing"
    case .blocked: return "Blocked"
    case .done: return "Done"
    }
  }

  /// Written when a task moves here and its keyword means another state.
  var keyword: String {
    switch self {
    case .todo: return "TODO"
    case .doing: return "ACTIVE"
    case .blocked: return "WAITING"
    case .done: return "DONE"
    }
  }

  init?(keyword: String) {
    switch keyword.uppercased() {
    case "TODO", "NEXT": self = .todo
    case "ACTIVE", "DOING", "STARTED", "IN-PROGRESS": self = .doing
    case "WAITING", "BLOCKED", "HOLD": self = .blocked
    case "DONE", "CANCELLED", "CANCELED": self = .done
    default: return nil
    }
  }
}

struct WorkspaceTask: Identifiable, Equatable {
  let file: URL
  /// 0-based.
  let line: Int
  /// The line as read, so a change can check it's still there.
  let raw: String
  let title: String
  let state: TaskState
  /// The file's own keyword when it says more than the state (`NEXT`).
  let keyword: String?
  let priority: String?
  let tags: [String]
  let due: String?
  /// The heading the task sits under.
  let section: String?

  var id: String { "\(file.path):\(line)" }
}

struct WorkspacePage: Identifiable, Equatable {
  let url: URL
  let title: String
  let excerpt: String?
  let tags: [String]
  let modified: Date
  let isImage: Bool

  var id: URL { url }
}

enum WorkspaceError: LocalizedError {
  case moved(String)

  var errorDescription: String? {
    switch self {
    case .moved(let title): return "“\(title)” changed on disk. Try again now that the board has reloaded."
    }
  }
}

/// A folder with `tasks.org` or `tasks.md` at its top: the tasks in its org
/// and Markdown files, and the pages in its `notes` and `ideas` folders.
struct Workspace: Equatable {
  enum Shelf: String, CaseIterable, Identifiable {
    case tasks, notes, ideas

    var id: Self { self }
    var title: String { rawValue.capitalized }
  }

  static let taskFiles = ["tasks.org", "tasks.md"]
  private static let readLimit = 2_000_000

  let root: URL
  let tasksFile: URL
  var tasks: [WorkspaceTask] = []
  var notes: [WorkspacePage] = []
  var ideas: [WorkspacePage] = []

  /// New pages and captured tasks follow the tasks file's format.
  var org: Bool { tasksFile.pathExtension == "org" }

  static func tasksFile(in folder: URL) -> URL? {
    taskFiles.map { folder.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
  }

  static func load(_ folder: URL) -> Workspace? {
    guard let tasksFile = tasksFile(in: folder) else { return nil }
    let listing = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                options: .skipsHiddenFiles)) ?? []
    let others = listing
      .filter { ["org", "md"].contains($0.pathExtension.lowercased()) && $0.lastPathComponent != tasksFile.lastPathComponent }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    let tasks = ([tasksFile] + others).flatMap { url in read(url).map { TaskFile.parse($0, file: url) } ?? [] }
    return Workspace(root: folder, tasksFile: tasksFile, tasks: tasks,
                     notes: pages(in: folder.appendingPathComponent(Shelf.notes.rawValue)),
                     ideas: pages(in: folder.appendingPathComponent(Shelf.ideas.rawValue)))
  }

  /// Makes `folder` a workspace; an existing tasks file is left alone.
  static func make(in folder: URL) throws {
    if tasksFile(in: folder) == nil {
      try "#+TITLE: \(folder.lastPathComponent)\n\n".write(to: folder.appendingPathComponent("tasks.org"),
                                                         atomically: true, encoding: .utf8)
    }
    for shelf in [Shelf.notes, .ideas] {
      try FileManager.default.createDirectory(at: folder.appendingPathComponent(shelf.rawValue),
                                              withIntermediateDirectories: true)
    }
  }

  /// Appends an open task to the tasks file.
  func capture(task title: String) throws {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    var text = (try? String(contentsOf: tasksFile, encoding: .utf8)) ?? ""
    if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
    text += (org ? "* TODO " : "- [ ] ") + title + "\n"
    try text.write(to: tasksFile, atomically: true, encoding: .utf8)
  }

  /// A new page in `notes` or `ideas`, titled `title`.
  func capture(page title: String, in shelf: Shelf) throws -> URL {
    let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let folder = root.appendingPathComponent(shelf.rawValue)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let stem = (title.isEmpty ? "Untitled" : title)
      .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    let name = FileOperations.available(stem, ext: org ? "org" : "md") {
      FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
    }
    let url = folder.appendingPathComponent(name)
    let heading = title.isEmpty ? stem : title
    try (org ? "#+TITLE: \(heading)\n\n" : "# \(heading)\n\n").write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  private static func read(_ url: URL) -> String? {
    guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= readLimit else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
  }

  /// Newest first; a page's title and first line come from its first 8 KB.
  static func pages(in folder: URL) -> [WorkspacePage] {
    let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                  options: .skipsHiddenFiles) else { return [] }
    let files = urls.compactMap { url -> (URL, Date)? in
      let values = try? url.resourceValues(forKeys: Set(keys))
      return values?.isDirectory == true ? nil : (url, values?.contentModificationDate ?? .distantPast)
    }
    return files.sorted { $0.1 > $1.1 }.prefix(300).map { url, modified in
      let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
      let name = url.deletingPathExtension().lastPathComponent
      guard ["md", "markdown", "org", "txt"].contains(url.pathExtension.lowercased()),
            let handle = try? FileHandle(forReadingFrom: url) else {
        return WorkspacePage(url: url, title: name, excerpt: nil, tags: [], modified: modified, isImage: isImage)
      }
      defer { try? handle.close() }
      let head = String(decoding: (try? handle.read(upToCount: 8192)) ?? Data(), as: UTF8.self)
      let summary = PageSummary.read(head, org: url.pathExtension.lowercased() == "org", name: name)
      return WorkspacePage(url: url, title: summary.title, excerpt: summary.excerpt, tags: summary.tags,
                           modified: modified, isImage: false)
    }
  }
}

enum PageSummary {
  /// The title (`#+TITLE:`, front matter, or the first heading), the first
  /// line of prose, and tags (`#+FILETAGS:` or front matter `tags:`).
  static func read(_ text: String, org: Bool, name: String) -> (title: String, excerpt: String?, tags: [String]) {
    var title: String?
    var excerpt: String?
    var tags: [String] = []
    var frontMatter = false
    for (index, raw) in text.components(separatedBy: "\n").prefix(80).enumerated() {
      let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      let lower = line.lowercased()
      if index == 0 && line == "---" && !org {
        frontMatter = true
        continue
      }
      if frontMatter {
        if line == "---" {
          frontMatter = false
        } else if lower.hasPrefix("title:") {
          title = title ?? unquote(String(line.dropFirst(6)))
        } else if lower.hasPrefix("tags:") {
          tags = String(line.dropFirst(5)).trimmingCharacters(in: CharacterSet(charactersIn: " []"))
            .split(separator: ",").map { unquote(String($0)) }.filter { !$0.isEmpty }
        }
        continue
      }
      if lower.hasPrefix("#+title:") {
        title = title ?? String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
      } else if lower.hasPrefix("#+filetags:") {
        tags = line.dropFirst(11).split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
          .filter { !$0.isEmpty }
      } else if line.isEmpty || line.hasPrefix("#+") {
        continue
      } else if let heading = heading(line, org: org) {
        title = title ?? heading
      } else if excerpt == nil {
        excerpt = String(line.prefix(160))
      }
      if title != nil && excerpt != nil { break }
    }
    return (title ?? name, excerpt, tags)
  }

  private static func heading(_ line: String, org: Bool) -> String? {
    let marker: Character = org ? "*" : "#"
    let level = line.prefix { $0 == marker }.count
    guard level > 0, line.dropFirst(level).first == " " else { return nil }
    return line.dropFirst(level).trimmingCharacters(in: .whitespaces)
  }

  private static func unquote(_ text: String) -> String {
    text.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
  }
}

/// Tasks in org (`* TODO title :tag:`, checkboxes) and Markdown
/// (`- [ ] [NEXT] title #tag due:2026-10-30`), read and changed line by line.
enum TaskFile {
  private static let orgHeading = regex(#"^(\*+)\s+(.*)$"#)
  private static let mdHeading = regex(#"^#{1,6}\s+(.*?)\s*$"#)
  private static let checkbox = regex(#"^(\s*(?:[-*+]|\d+[.)])\s+\[)([ xX/-])(\]\s+)(.*)$"#)
  private static let bracketKeyword = regex(#"^\[([A-Za-z-]+)\]\s+"#)
  private static let priority = regex(#"^\[#([A-Za-z0-9])\]\s+"#)
  private static let orgTags = regex(#"\s+:([\w@#%:]+):\s*$"#)
  private static let hashTag = regex(#"(?:^|\s)#([A-Za-z][\w/-]*)"#)
  private static let dueMark = regex(#"\s*(?:due:|📅\s*)(\d{4}-\d{2}-\d{2})"#)
  private static let planning = regex(#"(DEADLINE|SCHEDULED):\s*<(\d{4}-\d{2}-\d{2})"#)

  static func parse(_ text: String, file: URL) -> [WorkspaceTask] {
    let org = file.pathExtension.lowercased() == "org"
    let raws = text.components(separatedBy: "\n")
    let lines = raws.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
    var tasks: [WorkspaceTask] = []
    var section: String?
    var sectionLevel = 0
    var inBlock = false
    for (index, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
      if org ? (trimmed.hasPrefix("#+begin_") || trimmed.hasPrefix("#+end_")) : (trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")) {
        inBlock = org ? trimmed.hasPrefix("#+begin_") : !inBlock
        continue
      }
      guard !inBlock else { continue }
      let raw = raws[index]
      if org, let match = groups(orgHeading, line) {
        let level = match[0].count
        guard let (keyword, rest) = leadingKeyword(match[1]) else {
          section = stripOrgTags(match[1]).text
          sectionLevel = level
          continue
        }
        if level <= sectionLevel {
          section = nil
          sectionLevel = 0
        }
        let state = TaskState(keyword: keyword)!
        let following = lines.dropFirst(index + 1).prefix(2).prefix { !$0.hasPrefix("*") }
        let due = following.compactMap { groups(planning, $0) }.sorted { $0[0] < $1[0] }.first?[1]
        tasks.append(task(rest, file: file, line: index, raw: raw, state: state, keyword: keyword,
                          section: section, due: due, org: true))
      } else if !org, let match = groups(mdHeading, line) {
        section = match[0]
      } else if let match = groups(checkbox, line) {
        var rest = match[3]
        var keyword: String?
        if let tag = groups(bracketKeyword, rest), TaskState(keyword: tag[0]) != nil {
          keyword = tag[0]
          rest = removeFirst(bracketKeyword, rest)
        }
        let state: TaskState
        switch match[1] {
        case "x", "X": state = .done
        case "-", "/": state = .doing
        default: state = keyword.flatMap(TaskState.init(keyword:)) ?? .todo
        }
        tasks.append(task(rest, file: file, line: index, raw: raw, state: state, keyword: keyword,
                          section: section, due: nil, org: org))
      }
    }
    return tasks
  }

  /// `line` with the task moved to `state`, or nil when it isn't a task.
  /// A keyword that already means `state` stays; a ticked box keeps its tag.
  static func rewrite(_ line: String, to state: TaskState, org: Bool) -> String? {
    let ending = line.hasSuffix("\r") ? "\r" : ""
    let line = ending.isEmpty ? line : String(line.dropLast())
    if org, let match = groups(orgHeading, line) {
      guard let (keyword, rest) = leadingKeyword(match[1]) else { return nil }
      let written = TaskState(keyword: keyword) == state ? keyword : state.keyword
      return "\(match[0]) \(written)" + (rest.isEmpty ? "" : " \(rest)") + ending
    }
    guard let match = groups(checkbox, line) else { return nil }
    var rest = match[3]
    var tag: String?
    if let found = groups(bracketKeyword, rest), TaskState(keyword: found[0]) != nil {
      tag = found[0]
      rest = removeFirst(bracketKeyword, rest)
    }
    switch state {
    case .done: break
    case .todo: tag = tag.flatMap { TaskState(keyword: $0) == .todo ? $0 : nil }
    case .doing, .blocked: tag = tag.flatMap { TaskState(keyword: $0) == state ? $0 : nil } ?? state.keyword
    }
    return match[0] + (state == .done ? "x" : " ") + match[2] + (tag.map { "[\($0)] " } ?? "") + rest + ending
  }

  /// Rewrites the task's line; if lines above it moved, finds it by content.
  static func set(_ task: WorkspaceTask, to state: TaskState) throws {
    var lines = try String(contentsOf: task.file, encoding: .utf8).components(separatedBy: "\n")
    let index: Int?
    if lines.indices.contains(task.line) && lines[task.line] == task.raw {
      index = task.line
    } else {
      let matches = lines.indices.filter { lines[$0] == task.raw }
      index = matches.count == 1 ? matches[0] : nil
    }
    let org = task.file.pathExtension.lowercased() == "org"
    guard let index, let changed = rewrite(lines[index], to: state, org: org) else {
      throw WorkspaceError.moved(task.title)
    }
    lines[index] = changed
    try lines.joined(separator: "\n").write(to: task.file, atomically: true, encoding: .utf8)
  }

  private static func task(_ text: String, file: URL, line: Int, raw: String, state: TaskState, keyword: String?,
                           section: String?, due: String?, org: Bool) -> WorkspaceTask {
    var text = text
    var priorityMark: String?
    if let found = groups(priority, text) {
      priorityMark = found[0].uppercased()
      text = removeFirst(priority, text)
    }
    var tags: [String] = []
    if org {
      let stripped = stripOrgTags(text)
      text = stripped.text
      tags = stripped.tags
    }
    var due = due
    if let found = groups(dueMark, text) {
      due = due ?? found[0]
      text = removeFirst(dueMark, text)
    }
    let hashes = matches(hashTag, text)
    tags += hashes
    if !hashes.isEmpty {
      text = hashTag.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }
    let shown = keyword.flatMap { TaskState(keyword: $0) == state && $0.uppercased() != state.keyword ? $0.uppercased() : nil }
    return WorkspaceTask(file: file, line: line, raw: raw,
                         title: text.trimmingCharacters(in: .whitespaces), state: state, keyword: shown,
                         priority: priorityMark, tags: tags, due: due, section: section)
  }

  /// An org heading's TODO keyword (upper case, as org writes it) and the rest.
  private static func leadingKeyword(_ text: String) -> (String, String)? {
    let word = String(text.prefix { !$0.isWhitespace })
    guard !word.isEmpty, word == word.uppercased(), TaskState(keyword: word) != nil else { return nil }
    return (word, text.dropFirst(word.count).trimmingCharacters(in: .whitespaces))
  }

  private static func stripOrgTags(_ text: String) -> (text: String, tags: [String]) {
    guard let found = groups(orgTags, text) else { return (text.trimmingCharacters(in: .whitespaces), []) }
    return (removeFirst(orgTags, text).trimmingCharacters(in: .whitespaces),
            found[0].split(separator: ":").map(String.init))
  }

  private static func regex(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }

  /// The capture groups of the first match.
  private static func groups(_ regex: NSRegularExpression, _ text: String) -> [String]? {
    guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (1..<match.numberOfRanges).map { index in
      Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
    }
  }

  private static func matches(_ regex: NSRegularExpression, _ text: String) -> [String] {
    regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
      Range($0.range(at: 1), in: text).map { String(text[$0]) }
    }
  }

  private static func removeFirst(_ regex: NSRegularExpression, _ text: String) -> String {
    guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range, in: text) else { return text }
    return text.replacingCharacters(in: range, with: "")
  }
}

/// Opens a file for writing, at a line when the editor takes one.
enum Editor {
  private static let cursor: String? = {
    let bundled = PopoverController.editors.first { $0.name == "Cursor" }?.app
      .appendingPathComponent("Contents/Resources/app/bin/cursor").path
    return bundled.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? Tool.find("cursor")
  }()

  /// 1-based `line`.
  static func edit(_ url: URL, line: Int? = nil) {
    if let cursor {
      launch(cursor, ["-g", url.path + (line.map { ":\($0)" } ?? "")])
    } else if let emacs = Tool.find("emacsclient") {
      launch(emacs, ["-n"] + (line.map { ["+\($0)"] } ?? []) + [url.path])
    } else {
      NSWorkspace.shared.open(url)
    }
  }

  private static func launch(_ executable: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      DockStore.log("could not run \(executable): \(error)")
    }
  }
}
