import XCTest
@testable import barista_agent

final class FileBrowserModelTests: XCTestCase {
  private let root = URL(fileURLWithPath: "/tmp/root")

  func testHistoryDropsForwardEntriesWhenGoingSomewhereNew() {
    var tab = BrowserTab(root)
    tab.go(to: root.appendingPathComponent("a"))
    tab.go(to: root.appendingPathComponent("a/b"))
    tab.back()
    tab.back()
    XCTAssertEqual(tab.location, root)
    XCTAssertTrue(tab.canGoForward)
    tab.go(to: root.appendingPathComponent("c"))
    XCTAssertFalse(tab.canGoForward)
    XCTAssertEqual(tab.history.map(\.lastPathComponent), ["root", "c"])
    tab.go(to: root.appendingPathComponent("c"))
    XCTAssertEqual(tab.history.count, 2, "going to the current place is not a step")
    XCTAssertEqual(BrowserTab(URL(fileURLWithPath: "/")).parent, nil)
    XCTAssertEqual(tab.parent?.path, "/tmp/root")
  }

  func testTabsOpenAfterTheSelectedOneAndCloseToANeighbor() {
    var tabs = BrowserTabs(root)
    let first = tabs.selectedID
    let third = tabs.open(root.appendingPathComponent("3"))
    tabs.select(first)
    let second = tabs.open(root.appendingPathComponent("2"))
    XCTAssertEqual(tabs.tabs.map(\.id), [first, second, third])

    tabs.selectNeighbor(1)
    XCTAssertEqual(tabs.selectedID, third)
    tabs.selectNeighbor(1)
    XCTAssertEqual(tabs.selectedID, first, "wraps around")

    tabs.select(second)
    XCTAssertTrue(tabs.close(second))
    XCTAssertEqual(tabs.selectedID, third)
    tabs.move(third, to: 0)
    XCTAssertEqual(tabs.tabs.map(\.id), [third, first])
    XCTAssertTrue(tabs.close(third))
    XCTAssertFalse(tabs.close(first), "the last tab closes the window instead")

    tabs.go(to: root.appendingPathComponent("x"))
    XCTAssertEqual(tabs.selected.location.lastPathComponent, "x")
    tabs.back()
    XCTAssertEqual(tabs.selected.location, root)
  }

  func testListingSortsFoldersFirstAndFilters() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-browser-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("zeta"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(count: 10).write(to: folder.appendingPathComponent("file10.txt"))
    try Data(count: 300).write(to: folder.appendingPathComponent("file2.txt"))
    try Data().write(to: folder.appendingPathComponent(".hidden"))

    let entries = try XCTUnwrap(FileListing.load(folder))
    XCTAssertFalse(entries.contains { $0.name == ".hidden" })
    XCTAssertEqual(FileListing.sorted(entries, by: .name).map(\.name), ["zeta", "file2.txt", "file10.txt"])
    XCTAssertEqual(FileListing.sorted(entries, by: .size, ascending: false).map(\.name),
                   ["file2.txt", "file10.txt", "zeta"])
    XCTAssertNil(entries.first { $0.name == "zeta" }?.size)
    XCTAssertEqual(FileListing.filtered(entries, query: " FILE1 ").map(\.name), ["file10.txt"])
    XCTAssertEqual(try XCTUnwrap(FileListing.load(folder, hidden: true)).count, 4)
    XCTAssertNil(FileListing.load(folder.appendingPathComponent("missing")))
  }

  func testSearchEndsWhenTheShownFolderChanges() {
    let state = BrowserState(location: root)
    let first = state.tabs.selectedID
    state.newTab(at: root.appendingPathComponent("a"))
    let second = state.tabs.selectedID
    state.query = "x"
    state.select(tab: first)
    XCTAssertEqual(state.query, "")
    state.query = "x"
    state.selectNeighborTab(1)
    XCTAssertEqual(state.query, "")
    state.go(to: root.appendingPathComponent("a/b"))
    state.query = "x"
    state.back()
    XCTAssertEqual(state.query, "")
    state.query = "x"
    state.forward()
    XCTAssertEqual(state.query, "")
    state.query = "x"
    state.closeTab(first)
    XCTAssertEqual(state.query, "x", "closing another tab keeps this tab's search")
    state.newTab(at: root)
    state.query = "x"
    state.closeTab(state.tabs.selectedID)
    XCTAssertEqual(state.tabs.selectedID, second)
    XCTAssertEqual(state.query, "")
  }

  func testSymlinkedFoldersBrowseAndPackagesDoNot() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-browser-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("real"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("Tool.app/Contents"),
                                            withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data().write(to: folder.appendingPathComponent("note.txt"))
    try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("linked").path,
                                               withDestinationPath: "real")
    try FileManager.default.createSymbolicLink(atPath: folder.appendingPathComponent("note-link").path,
                                               withDestinationPath: "note.txt")

    let entries = try XCTUnwrap(FileListing.load(folder))
    let folders = Set(entries.filter(\.isFolder).map(\.name))
    XCTAssertEqual(folders, ["real", "linked"])
  }
}
