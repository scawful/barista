import AppKit
import UniformTypeIdentifiers
import XCTest
@testable import barista_agent

final class FinderParityTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("barista-finder-\(UUID().uuidString)").standardizedFileURL
    for name in ["alpha", "beta", "Gamma"] {
      try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    for name in ["notes.md", "build.sh", "README"] {
      try Data("x".utf8).write(to: folder.appendingPathComponent(name))
    }
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertTrue(condition())
  }

  private func listed(_ state: BrowserState) {
    state.reload()
    wait { !state.loading && state.shown.contains { $0.name == "alpha" } }
  }

  // MARK: Favorites

  private func favoritesList(_ items: [(URL, hidden: Bool)]) throws -> Data {
    let entries: [[String: Any]] = try items.map { url, hidden in
      [
        "Bookmark": try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
        "CustomItemProperties": hidden ? ["com.apple.LSSharedFileList.ItemIsHidden": 1] : [:],
        "uuid": UUID().uuidString,
        "visibility": 0,
      ]
    }
    return try NSKeyedArchiver.archivedData(withRootObject: ["items": entries, "properties": [:]],
                                            requiringSecureCoding: false)
  }

  func testFinderFavoritesKeepFinderOrderAndSkipHiddenItems() throws {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let data = try favoritesList([(folder.appendingPathComponent("beta"), false), (home, false),
                                  (folder.appendingPathComponent("alpha"), true)])
    let places = try XCTUnwrap(FinderFavorites.places(in: data))
    XCTAssertEqual(places.map(\.url.path), [folder.appendingPathComponent("beta").path, home.standardizedFileURL.path])
    XCTAssertEqual(places.map(\.symbol), ["folder", "house"])
    XCTAssertEqual(places.last?.name, NSUserName(), "Home goes by the user's name, as in Finder")
    XCTAssertNil(FinderFavorites.places(in: Data("not an archive".utf8)))
  }

  func testFavoriteSymbolsFollowFinder() {
    let home = URL(fileURLWithPath: "/Users/someone")
    let symbol = { FinderFavorites.symbol(for: URL(fileURLWithPath: $0), home: home) }
    XCTAssertEqual(symbol("/Users/someone/Downloads"), "arrow.down.circle")
    XCTAssertEqual(symbol("/Users/someone/src/Downloads"), "folder", "only Home's own Downloads")
    XCTAssertEqual(symbol("/Applications"), "square.grid.3x3")
    XCTAssertEqual(symbol("/Users/someone/Library/Mobile Documents/com~apple~CloudDocs/Chris"), "icloud")
  }

  // MARK: Loading

  func testListingCacheForgetsTheLeastRecentlyStoredFolder() {
    var cache = ListingCache(limit: 2)
    let entry = FileListing.entry(folder.appendingPathComponent("notes.md"))
    let (a, b, c) = (URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b"), URL(fileURLWithPath: "/c"))
    cache.store([entry], for: a, hidden: false)
    cache.store([], for: b, hidden: false)
    cache.store([entry], for: a, hidden: false)
    cache.store([], for: c, hidden: false)
    XCTAssertNotNil(cache.entries(for: a, hidden: false), "storing again makes it recent")
    XCTAssertNil(cache.entries(for: b, hidden: false))
    XCTAssertNil(cache.entries(for: a, hidden: true), "hidden files make a different listing")
  }

  func testKindComesFromTheExtensionWithoutAskingEachFile() throws {
    let entries = try XCTUnwrap(FileListing.load(folder))
    let kinds = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.kind) })
    XCTAssertEqual(kinds["alpha"], "Folder")
    XCTAssertEqual(kinds["README"], "Document")
    XCTAssertEqual(kinds["notes.md"], UTType(filenameExtension: "md")?.localizedDescription)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.appendingPathComponent("README").path)
    XCTAssertEqual(FileListing.entry(folder.appendingPathComponent("README")).kind, "Unix Executable File")
  }

  func testRememberedRowsDontDropASelectionTheyCantShowYet() throws {
    let state = BrowserState(location: folder)
    listed(state)
    state.go(to: folder.appendingPathComponent("alpha"))
    wait { state.shown.isEmpty && !state.loading }
    let made = folder.appendingPathComponent("made.txt")
    try Data().write(to: made)
    // The remembered listing of `folder` lacks the new file; the real one has it.
    state.go(to: folder, selecting: made)
    wait { state.selection.map(\.lastPathComponent) == ["made.txt"] }
  }

  func testComingBackShowsTheRememberedRowsAtOnce() {
    let state = BrowserState(location: folder)
    listed(state)
    state.go(to: folder.appendingPathComponent("beta"))
    wait { state.shown.isEmpty && !state.loading }
    state.back()
    XCTAssertTrue(state.shown.contains { $0.name == "alpha" }, "no wait for the disk")
    XCTAssertEqual(state.selection.map(\.lastPathComponent), ["beta"], "the folder you left is selected")
  }

  // MARK: Finder commands

  func testNewFolderWithSelectionMovesTheItemsAndNamesTheFolder() throws {
    let state = BrowserState(location: folder)
    listed(state)
    state.selection = Set(state.shown.filter { ["notes.md", "beta"].contains($0.name) }.map(\.url))
    state.newFolderWithSelection()
    let made = folder.appendingPathComponent("New Folder With Items")
    wait { state.selection.map(\.lastPathComponent) == [made.lastPathComponent] }
    let row = try XCTUnwrap(state.shown.first { $0.name == made.lastPathComponent })
    XCTAssertTrue(state.isRenaming(row.url), "the folder's own row shows the name field")
    XCTAssertTrue(FileManager.default.fileExists(atPath: made.appendingPathComponent("notes.md").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: made.appendingPathComponent("beta").path))
    XCTAssertFalse(state.shown.contains { $0.name == "notes.md" })
  }

  func testTypingANameSelectsTheFirstRowItStarts() {
    let state = BrowserState(location: folder)
    listed(state)
    state.typeSelect("g")
    XCTAssertEqual(state.selection.map(\.lastPathComponent), ["Gamma"], "case doesn't matter")
    state.typeSelect("b")
    XCTAssertEqual(state.selection.map(\.lastPathComponent), ["Gamma"], "\"gb\" starts nothing; the selection stays")
  }

  // MARK: Locations

  func testVolumesKnowTheirKindAndWhatHoldsAPath() {
    let root = Volume(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", total: 10, available: 5, ejectable: false)
    let drive = Volume(url: URL(fileURLWithPath: "/Volumes/LaCie"), name: "LaCie", total: 10, available: 5,
                       ejectable: false, isInternal: false)
    let remote = Volume(url: URL(fileURLWithPath: "/Users/x/Mounts/mm"), name: "MM", total: 0, available: 0,
                        ejectable: false, isLocal: false, isInternal: false, responding: false)
    XCTAssertFalse(root.canEject)
    XCTAssertTrue(drive.canEject, "an external drive ejects though it doesn't say it's ejectable")
    XCTAssertTrue(remote.canEject)
    XCTAssertEqual([root, drive, remote].map(\.symbol), ["internaldrive", "externaldrive", "externaldrive.badge.xmark"])
    let all = [root, drive, remote]
    XCTAssertEqual(Volume.holding(URL(fileURLWithPath: "/Volumes/LaCie/Music"), in: all)?.name, "LaCie")
    XCTAssertEqual(Volume.holding(URL(fileURLWithPath: "/Volumes/LaCie2"), in: all)?.name, "Macintosh HD")
  }

  func testGoShortcutsAreUnique() {
    let shortcuts = BrowserState.goPlaces.map { "\($0.modifiers.rawValue)\($0.key)" }
    XCTAssertEqual(Set(shortcuts).count, shortcuts.count)
  }
}
