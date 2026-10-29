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

  func testFolderSizeCountsEverythingAndStopsWhenCancelled() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-size-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(count: 100).write(to: folder.appendingPathComponent("a.bin"))
    try Data(count: 20).write(to: folder.appendingPathComponent("sub/.hidden"))
    let loose = folder.appendingPathComponent("sub/b.txt")
    try Data(count: 3).write(to: loose)

    let measured = try XCTUnwrap(FolderSize.measure([folder]) { false })
    XCTAssertEqual(measured.bytes, 123)
    XCTAssertEqual(measured.items, 4, "a.bin, sub, and both files in it")
    let selection = try XCTUnwrap(FolderSize.measure([loose, folder.appendingPathComponent("a.bin")]) { false })
    XCTAssertEqual(selection.bytes, 103)
    XCTAssertEqual(selection.items, 2)
    XCTAssertNil(FolderSize.measure([folder]) { true })

    XCTAssertEqual(FileInfo.permissions(0o755, isFolder: true), "drwxr-xr-x")
    XCTAssertEqual(FileInfo.permissions(0o640, isFolder: false), "-rw-r-----")
    XCTAssertTrue(loose.isWithin(folder))
    XCTAssertTrue(folder.isWithin(folder))
    XCTAssertFalse(folder.appendingPathComponent("../barista-size-other").isWithin(folder))
  }

  func testNamesCountUpAsFinderDoes() {
    let taken: Set = ["a copy.txt", "a copy 2.txt", "untitled folder"]
    XCTAssertEqual(FileOperations.available("a copy", ext: "txt", exists: taken.contains), "a copy 3.txt")
    XCTAssertEqual(FileOperations.available("b copy", ext: "txt", exists: taken.contains), "b copy.txt")
    XCTAssertEqual(FileOperations.available("untitled folder", ext: "", exists: taken.contains), "untitled folder 2")
  }

  func testFileOperationsKeepBothAndRefuseClashes() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-ops-\(UUID().uuidString)")
    let inner = folder.appendingPathComponent("lib.d/inner")
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let note = folder.appendingPathComponent("note.txt")
    try Data("x".utf8).write(to: note)

    XCTAssertEqual(try FileOperations.duplicate(note).lastPathComponent, "note copy.txt")
    XCTAssertEqual(try FileOperations.duplicate(note).lastPathComponent, "note copy 2.txt")
    XCTAssertEqual(try FileOperations.duplicate(folder.appendingPathComponent("lib.d")).lastPathComponent,
                   "lib.d copy", "a folder's dot is part of its name")
    XCTAssertEqual(try FileOperations.makeFolder(in: folder).lastPathComponent, "untitled folder")
    XCTAssertEqual(try FileOperations.makeFolder(in: folder).lastPathComponent, "untitled folder 2")

    XCTAssertThrowsError(try FileOperations.rename(note, to: "note copy.txt")) {
      XCTAssertEqual($0 as? FileOperationError, .nameTaken("note copy.txt"))
    }
    XCTAssertThrowsError(try FileOperations.rename(note, to: "a/b")) {
      XCTAssertEqual($0 as? FileOperationError, .invalidName("a/b"))
    }
    let shouted = try FileOperations.rename(note, to: "NOTE.txt")
    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains("NOTE.txt"),
                  "a case-only rename changes the name on disk")
    XCTAssertEqual(try FileOperations.rename(shouted, to: " plan.md ").lastPathComponent, "plan.md")

    XCTAssertThrowsError(try FileOperations.place(folder.appendingPathComponent("lib.d"), in: inner, move: false)) {
      XCTAssertEqual($0 as? FileOperationError, .intoItself("lib.d"))
    }
    let placed = try FileOperations.place(folder.appendingPathComponent("plan.md"),
                                          in: folder.appendingPathComponent("lib.d"), move: true)
    XCTAssertEqual(placed.lastPathComponent, "plan.md")
    XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("plan.md").path))

    XCTAssertNil(FileOperations.repoRoot(of: inner))
    try Data("gitdir: elsewhere".utf8).write(to: folder.appendingPathComponent(".git"))
    XCTAssertEqual(FileOperations.repoRoot(of: inner)?.path, folder.standardizedFileURL.path,
                   "a worktree's .git file marks the root too")
  }

  func testPuttingBackFromTheTrashKeepsWhatTookTheNameSince() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-restore-\(UUID().uuidString)")
    let trash = folder.appendingPathComponent("Trash")
    try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = folder.appendingPathComponent("shot.png")
    let trashed = trash.appendingPathComponent("shot 5.12.03 PM.png")
    try Data("old".utf8).write(to: trashed)

    XCTAssertEqual(try FileOperations.restore(trashed, to: original).lastPathComponent, "shot.png")
    try Data("again".utf8).write(to: trashed)
    XCTAssertEqual(try FileOperations.restore(trashed, to: original).lastPathComponent, "shot 2.png",
                   "a new file took the name, so both stay")
    XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "old")
  }

  func testCompressNamesArchivesAsFinderDoes() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-zip-\(UUID().uuidString)")
    let inner = folder.appendingPathComponent("lib.d")
    try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let note = folder.appendingPathComponent("note.txt")
    let dash = folder.appendingPathComponent("-dash.txt")
    try Data("x".utf8).write(to: note)
    try Data("y".utf8).write(to: dash)

    XCTAssertEqual(try FileOperations.compress([note]).lastPathComponent, "note.txt.zip")
    XCTAssertEqual(try FileOperations.compress([note]).lastPathComponent, "note.txt 2.zip")
    let archive = try FileOperations.compress([note, dash, inner])
    XCTAssertEqual(archive.lastPathComponent, "Archive.zip")
    XCTAssertGreaterThan(try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0, 0)
    XCTAssertThrowsError(try FileOperations.compress([note, inner.appendingPathComponent("x")])) {
      XCTAssertEqual($0 as? FileOperationError, .mixedFolders)
    }
  }

  func testNewFolderStartsNamingAndARenameCommitsOnce() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-rename-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let state = BrowserState(location: folder)
    state.newFolder()
    let made = try XCTUnwrap(state.renaming)
    XCTAssertEqual(made.lastPathComponent, "untitled folder")

    state.commitRename(made, to: "Assets")
    state.commitRename(made, to: "Twice")
    XCTAssertNil(state.renaming)
    XCTAssertNil(state.problem)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Assets"])

    state.beginRename(folder.appendingPathComponent("Assets"))
    state.commitRename(folder.appendingPathComponent("Assets"), to: "")
    XCTAssertNotNil(state.problem, "an empty name is refused, not applied")
  }
}
