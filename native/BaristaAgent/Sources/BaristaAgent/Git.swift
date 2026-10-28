import Foundation

/// What git says about one entry in a listing.
enum GitMark: Equatable {
  case modified, added, deleted, renamed, untracked, conflicted
  /// A folder with changes somewhere inside it.
  case inside

  var letter: String {
    switch self {
    case .modified: return "M"
    case .added: return "A"
    case .deleted: return "D"
    case .renamed: return "R"
    case .untracked: return "?"
    case .conflicted: return "U"
    case .inside: return "•"
    }
  }
}

struct GitStatus: Equatable {
  let root: URL
  /// Nil when HEAD is detached.
  var branch: String?
  var ahead = 0
  var behind = 0
  /// Repo-relative paths. A folder git reports whole (untracked) has no
  /// trailing slash.
  private(set) var changes: [String: GitMark] = [:]
  /// Every folder that holds a change, repo-relative.
  private(set) var changedFolders: Set<String> = []

  init(root: URL) {
    self.root = root.standardizedFileURL
  }

  /// Parses `git status --porcelain=v2 --branch -z`.
  static func parse(_ output: String, root: URL) -> GitStatus {
    var status = GitStatus(root: root)
    var fields = output.split(separator: "\0").map(String.init)[...]
    while let field = fields.popFirst() {
      if let head = field.dropPrefix("# branch.head ") {
        status.branch = head == "(detached)" ? nil : head
      } else if let counts = field.dropPrefix("# branch.ab ") {
        for part in counts.split(separator: " ") {
          if part.hasPrefix("+") { status.ahead = Int(part.dropFirst()) ?? 0 }
          if part.hasPrefix("-") { status.behind = Int(part.dropFirst()) ?? 0 }
        }
      } else if let path = field.dropPrefix("? ") {
        status.record(path, .untracked)
      } else if let kind = field.first, "12u".contains(kind), field.dropFirst().first == " " {
        // Ordinary, renamed, and unmerged entries carry 8, 9, and 10 fields
        // before the path, which may contain spaces.
        let parts = field.split(separator: " ", maxSplits: kind == "1" ? 8 : kind == "2" ? 9 : 10,
                                omittingEmptySubsequences: false)
        guard parts.count >= 2, let path = parts.last else { continue }
        let xy = parts[1]
        let mark: GitMark
        if kind == "u" { mark = .conflicted }
        else if kind == "2" { mark = .renamed }
        else if xy.contains("A") { mark = .added }
        else if xy.contains("D") { mark = .deleted }
        else { mark = .modified }
        status.record(String(path), mark)
        if kind == "2" { _ = fields.popFirst() }
      }
    }
    return status
  }

  private mutating func record(_ path: String, _ mark: GitMark) {
    let path = path.hasSuffix("/") ? String(path.dropLast()) : path
    changes[path] = mark
    var folder = (path as NSString).deletingLastPathComponent
    while !folder.isEmpty, changedFolders.insert(folder).inserted {
      folder = (folder as NSString).deletingLastPathComponent
    }
  }

  func mark(for url: URL, isFolder: Bool) -> GitMark? {
    let base = root.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(base + "/") else { return nil }
    let relative = String(path.dropFirst(base.count + 1))
    if let mark = changes[relative] { return mark }
    return isFolder && changedFolders.contains(relative) ? .inside : nil
  }

  /// Changed paths, not counting the folders that hold them.
  var changeCount: Int { changes.count }
}

struct GitWorktree: Equatable {
  let path: URL
  /// Nil when detached.
  let branch: String?

  /// Parses `git worktree list --porcelain`, leaving out bare and prunable
  /// entries, whose folders are not there to browse.
  static func parse(_ output: String) -> [GitWorktree] {
    output.components(separatedBy: "\n\n").compactMap { block in
      var path: String?
      var branch: String?
      for line in block.split(separator: "\n").map(String.init) {
        if let value = line.dropPrefix("worktree ") { path = value }
        if let value = line.dropPrefix("branch ") { branch = value.dropPrefix("refs/heads/") ?? value }
        if line == "bare" || line.hasPrefix("prunable") { return nil }
      }
      return path.map { GitWorktree(path: URL(fileURLWithPath: $0).standardizedFileURL, branch: branch) }
    }
  }
}

enum Git {
  /// Status and worktrees of the repo holding `folder`, nil outside one.
  /// Blocks while git runs; call it off the main thread.
  static func inspect(_ folder: URL) -> (status: GitStatus, worktrees: [GitWorktree])? {
    // A dotfiles repo at Home would make every folder a full status of Home.
    guard let root = FileOperations.repoRoot(of: folder),
          root.path != FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path,
          let output = run(root, ["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=normal"])
    else { return nil }
    let worktrees = run(root, ["worktree", "list", "--porcelain"]).map(GitWorktree.parse) ?? []
    return (GitStatus.parse(output, root: root),
            worktrees.filter { FileManager.default.fileExists(atPath: $0.path.path) })
  }

  /// The newest commit touching `url`, as "hash · subject · author, age";
  /// nil when it was never committed. Blocking.
  static func lastCommit(of url: URL, in root: URL) -> String? {
    let relative = url.standardizedFileURL.path == root.standardizedFileURL.path
      ? "." : PopoverController.relativePath(url, from: root)
    guard let output = run(root, ["log", "-1", "--format=%h%x1f%s%x1f%an%x1f%ar", "--", relative]) else { return nil }
    let fields = output.trimmingCharacters(in: .newlines).components(separatedBy: "\u{1f}")
    guard fields.count == 4 else { return nil }
    return "\(fields[0]) · \(fields[1]) · \(fields[2]), \(fields[3])"
  }

  /// Without optional locks, so browsing never holds `index.lock` while an
  /// agent commits in the same repo.
  private static func run(_ root: URL, _ arguments: [String]) -> String? {
    Tool.output("/usr/bin/git", ["--no-optional-locks", "-C", root.path] + arguments)
  }
}

enum Tool {
  /// A Homebrew tool's path; the agent runs from launchd without the shell's PATH.
  static func find(_ name: String) -> String? {
    ["/opt/homebrew/bin", "/usr/local/bin"].map { "\($0)/\(name)" }
      .first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  /// Standard output of a successful run, nil otherwise. Blocking.
  static func output(_ executable: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
  }
}

private extension String {
  func dropPrefix(_ prefix: String) -> String? {
    hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
  }
}