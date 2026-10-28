import XCTest
@testable import barista_agent

final class SearchTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-search-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func write(_ name: String, _ text: String = "") throws {
    let url = folder.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
  }

  private let root = URL(fileURLWithPath: "/repo")
  private func found(_ name: String) -> String? { "/bin/\(name)" }

  func testCommands() throws {
    let names = try XCTUnwrap(FileSearch.command(.subfolders, query: " sram  map ", in: root, everything: false,
                                                 find: found))
    XCTAssertEqual(names.tool, "/bin/fd")
    XCTAssertEqual(Array(names.arguments.suffix(5)), ["--and", "map", "--", "sram", "/repo"],
                   "every word must match, and a word can't be taken for an option")
    XCTAssertFalse(names.arguments.contains("--no-ignore"), ".gitignore applies while hidden files are hidden")

    let text = try XCTUnwrap(FileSearch.command(.contents, query: "LDA #$01 ", in: root, everything: true,
                                                find: found))
    XCTAssertEqual(text.tool, "/bin/rg")
    XCTAssertEqual(Array(text.arguments.suffix(2)), ["LDA #$01", "/repo"], "contents match the phrase")
    XCTAssertTrue(text.arguments.contains("--no-ignore") && text.arguments.contains("--hidden"))
    XCTAssertTrue(text.arguments.contains("--fixed-strings"), "$ and # are not regex")

    XCTAssertNil(FileSearch.command(.folder, query: "x", in: root, everything: false, find: found))
    XCTAssertNil(FileSearch.command(.contents, query: "  ", in: root, everything: false, find: found))
    XCTAssertNil(FileSearch.command(.contents, query: "x", in: root, everything: false, find: { _ in nil }))
  }

  func testHitsFromToolOutput() throws {
    let folderHit = try XCTUnwrap(FileSearch.hit("/repo/Core/"))
    XCTAssertEqual(folderHit.url.path, "/repo/Core")
    XCTAssertNil(folderHit.line)

    let textHit = try XCTUnwrap(FileSearch.hit("/repo/a b.asm\u{0}12:  LDA #$01 : STA $00"))
    XCTAssertEqual(textHit.url.path, "/repo/a b.asm")
    XCTAssertEqual(textHit.line, 12)
    XCTAssertEqual(textHit.text, "LDA #$01 : STA $00", "only the first colon splits")
    XCTAssertNil(FileSearch.hit(""))
  }

  func testSearchRunsFdAndRg() throws {
    try XCTSkipIf(Tool.find("fd") == nil || Tool.find("rg") == nil, "fd and rg are not installed")
    try write("Core/sram.asm", "; header\nLDA #$01\n")
    try write("Core/Sub/SRAM_map.txt", "nothing here\n")
    try write("notes.md", "lda #$01 in prose\n")

    let names = try XCTUnwrap(FileSearch.command(.subfolders, query: "sram map", in: folder, everything: false))
    let nameLines = try XCTUnwrap(ToolRun().lines(names.tool, names.arguments, limit: 50))
    XCTAssertTrue(nameLines.complete)
    XCTAssertEqual(FileSearch.entries(nameLines.lines, root: folder).map(\.name), ["Core/Sub/SRAM_map.txt"],
                   "named by the path under the search's folder")

    let text = try XCTUnwrap(FileSearch.command(.contents, query: "LDA #$01", in: folder, everything: false))
    let textLines = try XCTUnwrap(ToolRun().lines(text.tool, text.arguments, limit: 50))
    let hits = FileSearch.entries(textLines.lines, root: folder)
    XCTAssertEqual(hits.map(\.name), ["Core/sram.asm"], "an uppercase letter makes the search case-sensitive")
    XCTAssertEqual(hits.first?.line, 2)
    XCTAssertEqual(hits.first?.match, "LDA #$01")
  }

  func testRunStopsAtTheLimitAndWhenCancelled() throws {
    let endless = try XCTUnwrap(ToolRun().lines("/usr/bin/yes", ["hit"], limit: 3), "an endless tool still ends")
    XCTAssertEqual(endless.lines, ["hit", "hit", "hit"])
    XCTAssertFalse(endless.complete)

    let run = ToolRun()
    let started = Date()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { run.cancel() }
    XCTAssertNil(run.lines("/bin/sleep", ["10"], limit: 10), "a cancelled run has no results")
    XCTAssertLessThan(Date().timeIntervalSince(started), 5)

    let early = ToolRun()
    early.cancel()
    XCTAssertNil(early.lines("/bin/echo", ["x"], limit: 10), "cancelled before it starts, it never does")
  }

  func testLineRange() {
    let text = "one\ntwo\r\nthree"
    XCTAssertEqual(Preview.range(ofLine: 2, in: text).map { (text as NSString).substring(with: $0) }, "two")
    XCTAssertEqual(Preview.range(ofLine: 3, in: text).map { (text as NSString).substring(with: $0) }, "three")
    XCTAssertNil(Preview.range(ofLine: 4, in: text))
  }

  func testSyntaxByFileName() {
    func tokens(_ name: String, _ source: String) -> [SyntaxToken] {
      Syntax.of(URL(fileURLWithPath: "/x/\(name)"))?.spans(source).map(\.token) ?? []
    }
    XCTAssertEqual(tokens("yabairc", "# rules\nyabai -m rule --add app=\"^Cursor$\""), [.comment, .string])
    XCTAssertEqual(tokens(".zshrc", "export X=1 # set"), [.keyword, .number, .comment])
    XCTAssertEqual(tokens("init.el", "(setq fill-column 80) ; wrap\n'symbol \"s\""),
                   [.keyword, .number, .comment, .string], "a quoted symbol isn't a string")
    XCTAssertNil(Syntax.of(URL(fileURLWithPath: "/x/README")))
  }

  /// Spins the main run loop until `condition` holds, as the browser's
  /// background listing and search report back on the main queue.
  private func wait(_ what: String, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertTrue(condition(), what)
  }

  func testRenamingASearchResultKeepsItSelected() throws {
    try XCTSkipIf(Tool.find("fd") == nil, "fd is not installed")
    try write("Core/sram.asm", "x")
    let state = BrowserState(location: folder)
    state.reload()
    state.scope = .subfolders
    state.query = "sram"
    wait("the search finds the file") { state.shown.map(\.name) == ["Core/sram.asm"] }
    XCTAssertFalse(state.acceptsDrops, "a drop on results from many folders has no one place to go")

    let found = try XCTUnwrap(state.shown.first?.url)
    state.beginRename(found)
    state.commitRename(found, to: "sram2.asm")
    wait("the renamed result is selected once the search runs again") {
      state.shown.map(\.name) == ["Core/sram2.asm"] && state.selectedURLs.map(\.lastPathComponent) == ["sram2.asm"]
    }
    state.query = ""
    XCTAssertTrue(state.acceptsDrops)
  }

  func testTabHistoryIgnoresATrailingSlash() {
    var tab = BrowserTab(URL(fileURLWithPath: "/tmp/a"))
    tab.go(to: URL(string: "file:///tmp/a/")!)
    XCTAssertFalse(tab.canGoBack, "the same folder is not a new place")
  }
}
