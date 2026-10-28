import XCTest
@testable import barista_agent

final class GitAndJumpTests: XCTestCase {
  private let root = URL(fileURLWithPath: "/tmp/repo")

  func testStatusMarksFilesAndTheFoldersHoldingThem() {
    let output = [
      "# branch.oid abc", "# branch.head main", "# branch.upstream origin/main", "# branch.ab +2 -1",
      "1 .M N... 100644 100644 100644 aaa bbb Core/sprite file.asm",
      "1 A. N... 000000 100644 100644 000 ccc new.md",
      "1 .D N... 100644 100644 000000 ddd ddd gone.txt",
      "2 R. N... 100644 100644 100644 eee eee R100 Docs/after name.md", "Docs/before.md",
      "u UU N... 100644 100644 100644 100644 f1 f2 f3 merge.c",
      "? Scratch/",
      "? notes.txt",
    ].joined(separator: "\0") + "\0"
    let status = GitStatus.parse(output, root: root)
    XCTAssertEqual(status.branch, "main")
    XCTAssertEqual(status.ahead, 2)
    XCTAssertEqual(status.behind, 1)
    XCTAssertEqual(status.changeCount, 7)

    func mark(_ path: String, folder: Bool = false) -> GitMark? {
      status.mark(for: root.appendingPathComponent(path), isFolder: folder)
    }
    XCTAssertEqual(mark("Core/sprite file.asm"), .modified, "paths keep their spaces")
    XCTAssertEqual(mark("new.md"), .added)
    XCTAssertEqual(mark("gone.txt"), .deleted)
    XCTAssertEqual(mark("Docs/after name.md"), .renamed)
    XCTAssertNil(mark("Docs/before.md"), "a rename's old path is not an entry")
    XCTAssertEqual(mark("merge.c"), .conflicted)
    XCTAssertEqual(mark("Scratch", folder: true), .untracked, "a whole untracked folder")
    XCTAssertEqual(mark("Core", folder: true), .inside)
    XCTAssertNil(mark("Core", folder: false))
    XCTAssertNil(mark("Clean", folder: true))
    XCTAssertNil(status.mark(for: URL(fileURLWithPath: "/tmp/other/new.md"), isFolder: false))
    XCTAssertNil(GitStatus.parse("# branch.head (detached)\0", root: root).branch)
  }

  func testWorktreesSkipBareAndPrunableEntries() {
    let output = """
    worktree /src/oos
    HEAD 111
    branch refs/heads/master

    worktree /tmp/wt-gone
    HEAD 222
    branch refs/heads/old
    prunable gitdir file points to non-existent location

    worktree /src/oos-wt
    HEAD 333
    detached

    """
    XCTAssertEqual(GitWorktree.parse(output), [
      GitWorktree(path: URL(fileURLWithPath: "/src/oos"), branch: "master"),
      GitWorktree(path: URL(fileURLWithPath: "/src/oos-wt"), branch: nil),
    ])
  }

  func testInspectReadsARealRepository() throws {
    let repo = FileManager.default.temporaryDirectory.appendingPathComponent("barista-git-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: repo.appendingPathComponent("Core"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: repo) }
    func git(_ arguments: String...) {
      let ok = Tool.output("/usr/bin/git", ["-C", repo.path, "-c", "user.name=t", "-c", "user.email=t@t"] + arguments)
      XCTAssertNotNil(ok, "git \(arguments.joined(separator: " "))")
    }
    git("init", "-q", "-b", "trunk")
    try Data("a".utf8).write(to: repo.appendingPathComponent("Core/a b.asm"))
    try Data("b".utf8).write(to: repo.appendingPathComponent("keep.md"))
    git("add", ".")
    git("commit", "-q", "-m", "init")
    try Data("changed".utf8).write(to: repo.appendingPathComponent("Core/a b.asm"))
    git("mv", "keep.md", "kept.md")
    try Data().write(to: repo.appendingPathComponent("new.txt"))

    let (status, worktrees) = try XCTUnwrap(Git.inspect(repo.appendingPathComponent("Core")))
    XCTAssertEqual(status.root.path, repo.standardizedFileURL.path)
    XCTAssertEqual(status.branch, "trunk")
    XCTAssertEqual(status.mark(for: repo.appendingPathComponent("Core/a b.asm"), isFolder: false), .modified)
    XCTAssertEqual(status.mark(for: repo.appendingPathComponent("kept.md"), isFolder: false), .renamed)
    XCTAssertEqual(status.mark(for: repo.appendingPathComponent("new.txt"), isFolder: false), .untracked)
    XCTAssertEqual(status.mark(for: repo.appendingPathComponent("Core"), isFolder: true), .inside)
    XCTAssertEqual(worktrees.count, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git/index.lock").path))
  }

  func testJumpPrefersNameMatchesThenFrecency() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    func candidate(_ path: String, _ weight: Double) -> JumpCandidate {
      JumpCandidate(url: home.appendingPathComponent(path), weight: weight)
    }
    let core = candidate("src/hobby/oracle-of-secrets/Core", 2)
    let oracle = candidate("src/hobby/oracle-of-secrets", 11)
    let yaze = candidate("src/hobby/yaze", 13)
    let notes = candidate("src/folio/my-core-notes", 1)
    let all = [core, oracle, yaze, notes]

    XCTAssertEqual(JumpRanking.rank(all, query: "").first, yaze, "no query: zoxide's order")
    XCTAssertEqual(JumpRanking.rank(all, query: "oracle core").first, core)
    XCTAssertEqual(JumpRanking.rank(all, query: "core").first, core, "a name prefix beats a name substring")
    XCTAssertEqual(JumpRanking.rank(all, query: "yz"), [yaze], "letters in order still match")
    XCTAssertEqual(JumpRanking.rank(all, query: "zzz"), [])
    XCTAssertFalse(JumpRanking.rank(all, query: "users").contains(yaze), "Home's own path is not matched")

    let merged = JumpRanking.merge([[candidate("src/hobby/yaze", 5)], [yaze]])
    XCTAssertEqual(merged, [yaze], "one entry per folder at its best weight")
    XCTAssertEqual(JumpRanking.parseZoxide("9999.0 /a b\n  72.2 /src\nbad\n"),
                   [JumpCandidate(url: URL(fileURLWithPath: "/a b"), weight: 9999),
                    JumpCandidate(url: URL(fileURLWithPath: "/src"), weight: 72.2)])
  }
}