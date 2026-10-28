import Foundation
import XCTest
@testable import barista_agent

final class WorkspaceTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-workspace-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  func testOrgTasksTakeKeywordsPriorityTagsDueAndSection() {
    let text = """
    #+TITLE: Oracle
    * Inbox
    ** NEXT [#A] Wire the shelf :dock:ui:
       DEADLINE: <2026-10-30 Fri>
    ** WAITING Review from Codex
    #+begin_src org
    * TODO not a task
    #+end_src
    * DONE Shipped icons
    * CANCELLED Old idea
    * Todo list heading
    - [ ] org checkbox
    """
    let tasks = TaskFile.parse(text, file: folder.appendingPathComponent("tasks.org"))
    XCTAssertEqual(tasks.map(\.title), ["Wire the shelf", "Review from Codex", "Shipped icons", "Old idea", "org checkbox"])
    XCTAssertEqual(tasks.map(\.state), [.todo, .blocked, .done, .done, .todo])
    XCTAssertEqual(tasks[0].keyword, "NEXT")
    XCTAssertEqual(tasks[0].priority, "A")
    XCTAssertEqual(tasks[0].tags, ["dock", "ui"])
    XCTAssertEqual(tasks[0].due, "2026-10-30")
    XCTAssertEqual(tasks[0].section, "Inbox")
    XCTAssertEqual(tasks[0].line, 2)
    XCTAssertNil(tasks[1].keyword, "WAITING is blocked's own keyword")
    XCTAssertNil(tasks[2].section, "a level-1 task ends the Inbox section")
    XCTAssertEqual(tasks[3].keyword, "CANCELLED")
    XCTAssertEqual(tasks[4].section, "Todo list heading")
  }

  func testMarkdownChecklistsTakeTagsAndSkipCode() {
    let text = """
    ## Current Focus
    - [ ] [ACTIVE] Oracle dialogue map #oracle
    - [x] [NEXT] Stabilize Barista due:2026-11-01
    - [/] Half done
    * [ ] [WAITING] gcalcli OAuth, see #12
    ```
    - [ ] code, not a task
    ```
    - plain bullet
    """
    let tasks = TaskFile.parse(text, file: folder.appendingPathComponent("active.md"))
    XCTAssertEqual(tasks.map(\.title), ["Oracle dialogue map", "Stabilize Barista", "Half done", "gcalcli OAuth, see #12"])
    XCTAssertEqual(tasks.map(\.state), [.doing, .done, .doing, .blocked])
    XCTAssertEqual(tasks[0].tags, ["oracle"])
    XCTAssertNil(tasks[1].keyword, "a ticked box is done whatever its tag says")
    XCTAssertEqual(tasks[1].due, "2026-11-01")
    XCTAssertEqual(tasks.map(\.section), Array(repeating: "Current Focus", count: 4))
  }

  func testRewritesKeepTheFilesVocabulary() {
    XCTAssertEqual(TaskFile.rewrite("** NEXT [#A] Wire it :ui:", to: .done, org: true), "** DONE [#A] Wire it :ui:")
    XCTAssertEqual(TaskFile.rewrite("* DONE Ship", to: .doing, org: true), "* ACTIVE Ship")
    XCTAssertEqual(TaskFile.rewrite("* NEXT Ship", to: .todo, org: true), "* NEXT Ship", "NEXT already means to do")
    XCTAssertNil(TaskFile.rewrite("* Inbox", to: .done, org: true))
    XCTAssertEqual(TaskFile.rewrite("  - [ ] [NEXT] Fix", to: .done, org: false), "  - [x] [NEXT] Fix")
    XCTAssertEqual(TaskFile.rewrite("- [x] [NEXT] Fix", to: .todo, org: false), "- [ ] [NEXT] Fix")
    XCTAssertEqual(TaskFile.rewrite("- [x] [ACTIVE] Fix", to: .todo, org: false), "- [ ] Fix")
    XCTAssertEqual(TaskFile.rewrite("- [ ] Fix", to: .blocked, org: false), "- [ ] [WAITING] Fix")
    XCTAssertEqual(TaskFile.rewrite("- [ ] [WAITING] Fix\r", to: .doing, org: false), "- [ ] [ACTIVE] Fix\r")
    XCTAssertNil(TaskFile.rewrite("- plain", to: .done, org: false))
  }

  func testSettingAStateFindsTheLineAfterEditsAbove() throws {
    let file = folder.appendingPathComponent("tasks.md")
    try "- [ ] First\n- [ ] Second\n".write(to: file, atomically: true, encoding: .utf8)
    let second = try XCTUnwrap(TaskFile.parse(try String(contentsOf: file), file: file).last)
    try "New line\n- [ ] First\n- [ ] Second\n".write(to: file, atomically: true, encoding: .utf8)
    try TaskFile.set(second, to: .done)
    XCTAssertEqual(try String(contentsOf: file), "New line\n- [ ] First\n- [x] Second\n")
    XCTAssertThrowsError(try TaskFile.set(second, to: .blocked), "the line no longer reads as it did")
  }

  func testMakeLoadAndCapture() throws {
    try Workspace.make(in: folder)
    XCTAssertNil(Workspace.load(folder.appendingPathComponent("notes")))
    var workspace = try XCTUnwrap(Workspace.load(folder))
    XCTAssertTrue(workspace.org)
    XCTAssertEqual(workspace.tasks, [])
    try workspace.capture(task: "  Wire the dock :ui:  ")
    try workspace.capture(task: "   ")
    let note = try workspace.capture(page: "Design: dock", in: .notes)
    XCTAssertEqual(note.lastPathComponent, "Design- dock.org")
    XCTAssertEqual(try workspace.capture(page: "Design: dock", in: .notes).lastPathComponent, "Design- dock 2.org")
    try "# Ideas\nA dock that tiles\n".write(to: folder.appendingPathComponent("ideas/tiles.md"), atomically: true,
                                         encoding: .utf8)
    workspace = try XCTUnwrap(Workspace.load(folder))
    XCTAssertEqual(workspace.tasks.map(\.title), ["Wire the dock"])
    XCTAssertEqual(workspace.tasks.first?.tags, ["ui"])
    XCTAssertEqual(Set(workspace.notes.map(\.title)), ["Design: dock"])
    XCTAssertEqual(workspace.ideas.first?.title, "Ideas")
    XCTAssertEqual(workspace.ideas.first?.excerpt, "A dock that tiles")
    try Workspace.make(in: folder)
    XCTAssertEqual(try XCTUnwrap(Workspace.load(folder)).tasks.count, 1, "making it again keeps the tasks")
  }

  func testTheBoardShowsInEachWorkspaceUntilALayoutIsChosen() throws {
    try Workspace.make(in: folder)
    try "- [ ] Draft the dock\n".write(to: folder.appendingPathComponent("plan.md"), atomically: true, encoding: .utf8)
    let state = BrowserState(location: folder)
    state.reload()
    wait { state.workspace != nil }
    XCTAssertTrue(state.boardShown)
    XCTAssertEqual(state.workspace?.tasks.map(\.title), ["Draft the dock"])

    state.move(state.workspace?.tasks ?? [], to: .doing)
    wait { state.workspace?.tasks.first?.state == .doing }
    XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("plan.md")), "- [ ] [ACTIVE] Draft the dock\n")

    state.layout = .list
    XCTAssertFalse(state.boardShown)
    state.go(to: folder.appendingPathComponent("notes"))
    wait { state.workspace == nil }
    state.up()
    wait { state.workspace != nil }
    XCTAssertTrue(state.boardShown, "entering a workspace shows its board again")
  }

  private func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertTrue(condition())
  }

  func testPageSummaries() {
    let front = PageSummary.read("---\ntitle: \"Dock\"\ntags: [ui, dock]\n---\nBody line\n", org: false, name: "f")
    XCTAssertEqual(front.title, "Dock")
    XCTAssertEqual(front.tags, ["ui", "dock"])
    XCTAssertEqual(front.excerpt, "Body line")
    let org = PageSummary.read("#+FILETAGS: :idea:music:\n* Heading\ntext\n", org: true, name: "f")
    XCTAssertEqual(org.title, "Heading")
    XCTAssertEqual(org.tags, ["idea", "music"])
    XCTAssertEqual(PageSummary.read("", org: false, name: "fallback").title, "fallback")
  }
}
