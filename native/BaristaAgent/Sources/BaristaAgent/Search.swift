import Foundation

/// Where the search field looks. The folder filter is instant; the other two
/// run fd and rg under the shown folder.
enum SearchScope: String, CaseIterable, Identifiable {
  case folder, subfolders, contents

  var id: Self { self }

  var title: String {
    switch self {
    case .folder: return "This Folder"
    case .subfolders: return "Subfolders"
    case .contents: return "Contents"
    }
  }

  var tool: String? {
    switch self {
    case .folder: return nil
    case .subfolders: return "fd"
    case .contents: return "rg"
    }
  }
}

enum FileSearch {
  static let limit = 1000

  /// The fd or rg run for `query` under `root`; nil for the folder filter, an
  /// empty query, or a missing tool. Names must hold every word of the query;
  /// contents hold the query as one phrase. Both skip `.git`, and skip what
  /// `.gitignore` ignores unless `everything` (hidden files shown).
  static func command(_ scope: SearchScope, query: String, in root: URL, everything: Bool,
                      find: (String) -> String? = Tool.find) -> (tool: String, arguments: [String])? {
    let phrase = query.trimmingCharacters(in: .whitespaces)
    let words = phrase.split(whereSeparator: \.isWhitespace).map(String.init)
    guard let first = words.first, let name = scope.tool, let tool = find(name) else { return nil }
    let all = everything ? ["--hidden", "--no-ignore"] : []
    if scope == .subfolders {
      let more = words.dropFirst().flatMap { ["--and", $0] }
      return (tool, ["--color", "never", "--fixed-strings", "--exclude", ".git", "--max-results", String(limit)]
                + all + more + ["--", first, root.path])
    }
    return (tool, ["--color", "never", "--null", "--line-number", "--no-heading", "--with-filename",
                   "--max-count", "1", "--max-columns", "240", "--max-columns-preview", "--fixed-strings",
                   "--smart-case", "--max-filesize", "4M", "--glob", "!.git"]
              + all + ["--", phrase, root.path])
  }

  /// One line of fd output (a path; folders end in `/`) or rg output
  /// (`path`, NUL, `line:text`).
  static func hit(_ line: String) -> (url: URL, line: Int?, text: String?)? {
    let parts = line.split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false)
    guard let path = parts.first, !path.isEmpty else { return nil }
    let url = URL(fileURLWithPath: path.hasSuffix("/") && path.count > 1 ? String(path.dropLast()) : String(path))
    guard parts.count == 2 else { return (url, nil, nil) }
    let match = parts[1].split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    let text = match.count == 2 ? match[1].trimmingCharacters(in: .whitespaces) : nil
    return (url, match.first.flatMap { Int($0) }, text)
  }

  /// Listing entries for the hits, named by their path under `root`.
  /// Blocking: one stat per hit.
  static func entries(_ lines: [String], root: URL) -> [FileEntry] {
    FileListing.ranked(lines.compactMap(hit).map { hit in
      var entry = FileListing.entry(hit.url, name: PopoverController.relativePath(hit.url, from: root))
      entry.line = hit.line
      entry.match = hit.text
      return entry
    })
  }
}

/// A tool run whose output arrives line by line and that `cancel` stops at
/// once, so a search replaced by the next keystroke doesn't keep walking.
final class ToolRun {
  private let process = Process()
  private let lock = NSLock()
  private var cancelled = false

  func cancel() {
    lock.lock()
    defer { lock.unlock() }
    cancelled = true
    if process.isRunning { process.terminate() }
  }

  /// Blocking. Standard output's lines until the tool ends or `limit` lines
  /// arrive (`complete` false); nil when it didn't start or was cancelled.
  func lines(_ executable: String, _ arguments: [String], limit: Int) -> (lines: [String], complete: Bool)? {
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    lock.lock()
    let started = !cancelled && (try? process.run()) != nil
    lock.unlock()
    guard started else { return nil }
    var lines: [String] = []
    var buffer = Data()
    var complete = true
    let handle = pipe.fileHandleForReading
    reading: while case let chunk = handle.availableData, !chunk.isEmpty {
      buffer.append(chunk)
      var start = buffer.startIndex
      while let newline = buffer[start...].firstIndex(of: 0x0A) {
        lines.append(String(decoding: buffer[start..<newline], as: UTF8.self))
        start = buffer.index(after: newline)
        if lines.count >= limit {
          complete = false
          process.terminate()
          break reading
        }
      }
      buffer.removeSubrange(buffer.startIndex..<start)
    }
    process.waitUntilExit()
    lock.lock()
    defer { lock.unlock() }
    return cancelled ? nil : (lines, complete)
  }
}
