import Foundation
import XCTest
@testable import barista_agent

final class FolderViewTests: XCTestCase {
  private var folder: URL!
  private var suite: UserDefaults!
  private var suiteName = ""

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("barista-views-\(UUID().uuidString)").standardizedFileURL
    for name in ["alpha", "beta"] {
      try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    suiteName = "barista-views-\(UUID().uuidString)"
    suite = UserDefaults(suiteName: suiteName)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
    suite.removePersistentDomain(forName: suiteName)
  }

  // MARK: .DS_Store

  private struct Record {
    let name: String
    let code: String
    let type: String
    let payload: Data
  }

  private func u32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) } }
  private func utf16(_ text: String) -> Data { text.data(using: .utf16BigEndian)! }

  private func encode(_ record: Record) -> Data {
    u32(record.name.utf16.count) + utf16(record.name) + Data(record.code.utf8) + Data(record.type.utf8) + record.payload
  }

  private func blob(_ plist: [String: Any]) throws -> Data {
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    return u32(data.count) + data
  }

  /// Finder's layout: a buddy-allocated file whose B-tree root is an
  /// internal node over two leaves; every offset counts from byte 4.
  private func dsStore(left: [Record], middle: Record, right: [Record]) -> Data {
    var file = Data(count: 4 + 0x5000)
    func put(_ data: Data, at offset: Int) { file.replaceSubrange(4 + offset..<4 + offset + data.count, with: data) }
    file.replaceSubrange(0..<20, with: u32(1) + Data("Bud1".utf8) + u32(0x4000) + u32(0x1000) + u32(0x4000))
    let records = left.count + 1 + right.count
    put(u32(1) + u32(1) + u32(records) + u32(3) + u32(0x1000), at: 0x20)
    put(u32(3) + u32(1) + u32(2) + encode(middle), at: 0x1000)
    put(u32(0) + u32(left.count) + left.map(encode).reduce(Data(), +), at: 0x2000)
    put(u32(0) + u32(right.count) + right.map(encode).reduce(Data(), +), at: 0x3000)
    var root = u32(4) + u32(0) + u32(0x20 | 5) + u32(0x1000 | 12) + u32(0x2000 | 12) + u32(0x3000 | 12)
    root += Data(count: 252 * 4)
    root += u32(1) + Data([4]) + Data("DSDB".utf8) + u32(0)
    put(root, at: 0x4000)
    return file
  }

  private func sample() throws -> Data {
    let list = try blob(["sortColumn": "size", "columns": [["identifier": "size", "ascending": true, "visible": true]]])
    return dsStore(
      left: [Record(name: ".", code: "icvp", type: "blob", payload: try blob(["arrangeBy": "dateAdded", "iconSize": 96])),
             Record(name: ".", code: "vSrn", type: "long", payload: u32(1))],
      middle: Record(name: ".", code: "vstl", type: "type", payload: Data("Nlsv".utf8)),
      right: [Record(name: "beta", code: "lsvP", type: "blob", payload: list),
              Record(name: "beta", code: "cmmt", type: "ustr", payload: u32(2) + utf16("hi"))])
  }

  func testADraggedRectangleSelectsTheIconsItTouches() {
    let layout = IconLayout(width: 400, iconSize: 64)
    XCTAssertEqual(layout.columns, 4, "64-point icons fit four across 400 points")
    XCTAssertEqual(layout.frame(at: 0), CGRect(x: 34, y: 4, width: 80, height: 100), "the block is centered")
    XCTAssertEqual(layout.frame(at: 5).origin, CGPoint(x: 118, y: 108))
    XCTAssertEqual(layout.indices(in: CGRect(x: 30, y: 10, width: 10, height: 10), count: 7), [0])
    XCTAssertEqual(layout.indices(in: CGRect(x: 100, y: 50, width: 100, height: 100), count: 7), [0, 1, 4, 5])
    XCTAssertEqual(layout.indices(in: CGRect(x: 300, y: 120, width: 10, height: 10), count: 7), [],
                   "past the last icon of a short row")
    XCTAssertEqual(layout.indices(in: CGRect(x: 0, y: 0, width: 400, height: 2000), count: 7).count, 7)
  }

  func testDSStoreReadsRecordsInEveryNode() throws {
    let data = try sample()
    let own = try XCTUnwrap(DSStore.records(in: data))
    XCTAssertEqual(own["vstl"], .type("Nlsv"), "the internal node's own record")
    XCTAssertEqual(own["vSrn"], .long(1), "a leaf left of it")
    XCTAssertEqual(DSStore.plist(own["icvp"])?["arrangeBy"] as? String, "dateAdded")
    let beta = try XCTUnwrap(DSStore.records(in: data, named: "beta"))
    XCTAssertEqual(beta["cmmt"], .string("hi"), "the rightmost leaf")
    XCTAssertEqual(Set(beta.keys), ["lsvP", "cmmt"])
  }

  func testDSStoreRefusesWhatIsntOne() throws {
    XCTAssertNil(DSStore.records(in: Data("not a store".utf8)))
    let data = try sample()
    XCTAssertNil(DSStore.records(in: data.prefix(0x2010)), "cut off before its leaves")
    var looping = data
    looping.replaceSubrange(4 + 0x1000..<4 + 0x1004, with: u32(1))
    XCTAssertNil(DSStore.records(in: looping), "a node that names itself as a child ends the walk")
  }

  func testFinderSettingsBecomeViews() throws {
    let data = try sample()
    let own = FolderView.Finder(records: try XCTUnwrap(DSStore.records(in: data)))
    XCTAssertEqual(own.layout, .list)
    XCTAssertEqual(own.icons, FolderView(sortKey: .added, ascending: false, iconSize: 96),
                   "Finder arranges by date newest first")
    let beta = FolderView.Finder(records: try XCTUnwrap(DSStore.records(in: data, named: "beta")))
    XCTAssertNil(beta.layout)
    XCTAssertEqual(beta.list, FolderView(sortKey: .size, ascending: true))
    XCTAssertEqual(FolderView.iconSize(900), 512)
    XCTAssertEqual(FolderView.iconSize(500), 512)
    XCTAssertEqual(FolderView.iconSize(20), 32)
    XCTAssertEqual(FolderView.iconSize(70), 64)
    XCTAssertEqual(FolderView.iconSize(128, steppedBy: 1), 160)
    XCTAssertEqual(FolderView.iconSize(512, steppedBy: 1), 512)
    XCTAssertEqual(FolderView.iconSize(48, steppedBy: -3), 32)
  }

  func testFinderSettingsAreReadFromTheFolderAndItsParent() throws {
    try dsStore(left: [], middle: Record(name: "alpha", code: "vstl", type: "type", payload: Data("clmv".utf8)),
                right: []).write(to: folder.appendingPathComponent(".DS_Store"))
    XCTAssertEqual(FolderView.Finder.read(folder.appendingPathComponent("alpha")).layout, .columns)
    XCTAssertNil(FolderView.Finder.read(folder.appendingPathComponent("beta")).layout)
    try sample().write(to: folder.appendingPathComponent("beta/.DS_Store"))
    XCTAssertEqual(FolderView.Finder.read(folder.appendingPathComponent("beta")).layout, .list, "its own `.` record")
  }

  // MARK: Resolution

  func testFolderKeepsTheWindowsLayoutUnlessItHasItsOwn() {
    let views = FolderViews(suite)
    suite.set("icons", forKey: BrowserLayout.defaultsKey)
    let alpha = folder.appendingPathComponent("alpha")
    XCTAssertEqual(views.view(for: alpha, current: nil, finder: nil),
                   FolderView(layout: .icons, sortKey: .name, ascending: true, iconSize: 64),
                   "a new window takes the last layout picked before folders had views")
    XCTAssertEqual(views.view(for: alpha, current: .list, finder: nil).layout, .list)
    var finder = FolderView.Finder(records: [:])
    finder.layout = .icons
    finder.icons = FolderView(sortKey: .kind, ascending: true, iconSize: 128)
    finder.list = FolderView(sortKey: .size, ascending: false)
    XCTAssertEqual(views.view(for: alpha, current: .list, finder: finder),
                   FolderView(layout: .icons, sortKey: .kind, ascending: true, iconSize: 128),
                   "Finder's Always Open In wins over the window's")
    XCTAssertEqual(views.view(for: alpha, current: .columns, finder: finder).layout, .columns,
                   "browsing in columns stays in columns")
    views.update(alpha) { $0.layout = .list }
    XCTAssertEqual(views.view(for: alpha, current: .icons, finder: finder),
                   FolderView(layout: .list, sortKey: .size, ascending: false, iconSize: 128),
                   "Barista's choice wins, and the sort follows the layout it picks")
    views.update(alpha) { $0.sortKey = .modified }
    XCTAssertEqual(views.view(for: alpha, current: nil, finder: finder).sortKey, .modified)
    views.defaults = FolderView(layout: .columns, sortKey: .kind, ascending: false, iconSize: 96)
    XCTAssertEqual(views.view(for: folder.appendingPathComponent("beta"), current: nil, finder: nil),
                   FolderView(layout: .columns, sortKey: .kind, ascending: false, iconSize: 96))
  }

  func testSavedViewsPersistAndTheOldestGoFirst() {
    let views = FolderViews(suite, limit: 2)
    let (a, b, c) = (URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b"), URL(fileURLWithPath: "/c"))
    views.update(a) { $0.sortKey = .size }
    views.update(b) { $0.sortKey = .kind }
    views.update(a) { $0.iconSize = 96 }
    views.update(c) { $0.layout = .icons }
    let reread = FolderViews(suite, limit: 2)
    XCTAssertEqual(reread.saved(for: a), FolderView(sortKey: .size, iconSize: 96), "changing it again makes it recent")
    XCTAssertNil(reread.saved(for: b))
    XCTAssertEqual(reread.saved(for: c), FolderView(layout: .icons))
  }

  func testABrowserRemembersEachFoldersView() {
    let views = FolderViews(suite)
    let state = BrowserState(location: folder, views: views)
    state.reload()
    state.sortKey = .size
    state.layout = .icons
    state.iconSize = 96
    state.go(to: folder.appendingPathComponent("alpha"))
    XCTAssertEqual(state.layout, .icons, "a folder without its own layout keeps the window's")
    XCTAssertEqual(state.sortKey, .name)
    XCTAssertEqual(state.iconSize, 64)
    state.ascending = false
    state.back()
    XCTAssertEqual(state.sortKey, .size)
    XCTAssertEqual(state.iconSize, 96)
    XCTAssertTrue(state.ascending)
    state.forward()
    XCTAssertFalse(state.ascending)
    XCTAssertEqual(views.saved(for: folder.appendingPathComponent("alpha")), FolderView(ascending: false),
                   "only what was chosen there is kept, not the view applied on arrival")
  }

  func testShowingTheLargestFoldersIsntKept() {
    let views = FolderViews(suite)
    let state = BrowserState(location: folder, views: views)
    state.showLargest(in: folder.appendingPathComponent("beta"))
    XCTAssertEqual(state.sortKey, .size)
    XCTAssertNil(views.saved(for: folder.appendingPathComponent("beta")))
    state.measuringSizes = false
  }

  // MARK: Sorting

  func testRankedSortsMatchFindersNameOrder() {
    let names = ["file10", "File2", "alpha", "Beta", "file1", "écrit", "zeta"]
    let entries = names.map { FileListing.entry(folder.appendingPathComponent("unlisted/\($0)")) }
    let ranked = FileListing.ranked(entries)
    for key in FileSortKey.allCases {
      for ascending in [true, false] {
        XCTAssertEqual(FileListing.sorted(ranked, by: key, ascending: ascending).map(\.name),
                       FileListing.sorted(entries, by: key, ascending: ascending).map(\.name), "\(key) \(ascending)")
      }
    }
    XCTAssertEqual(FileListing.sorted(ranked, by: .name).map(\.name),
                   ["alpha", "Beta", "écrit", "file1", "File2", "file10", "zeta"])
    XCTAssertEqual(FileListing.sorted(ranked, by: .name, ascending: false).map(\.name).first, "zeta")
  }

  func testFoldersComeFirstOnlyByName() throws {
    try Data("x".utf8).write(to: folder.appendingPathComponent("aardvark.txt"))
    let listing = try XCTUnwrap(FileListing.load(folder))
    XCTAssertEqual(FileListing.sorted(listing, by: .name).map(\.name), ["alpha", "beta", "aardvark.txt"])
    XCTAssertEqual(FileListing.sorted(listing, by: .kind, ascending: false).map(\.name), ["aardvark.txt", "alpha", "beta"],
                   "folders aren't held first, and tied kinds keep name order either way")
  }

  // MARK: Open With

  func testOpenRulesPreferTheDeepestFolder() throws {
    let file = folder.appendingPathComponent("rules.json")
    let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
    let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
    let asm = folder.appendingPathComponent("alpha/main.ASM")
    try OpenRules.set(textEdit, ext: "asm", folder: nil, in: file)
    XCTAssertEqual(OpenRules.app(for: asm, from: file), textEdit)
    try OpenRules.set(preview, ext: "asm", folder: folder.appendingPathComponent("alpha"), in: file)
    try OpenRules.set(URL(fileURLWithPath: "/Applications/Gone.app"), ext: "asm", folder: folder, in: file)
    XCTAssertEqual(OpenRules.app(for: asm, from: file), preview, "the deepest folder's rule")
    XCTAssertNil(OpenRules.app(for: folder.appendingPathComponent("beta/x.asm"), from: file),
                 "a rule naming an app that's gone opens as if there were none")
    XCTAssertEqual(OpenRules.app(for: URL(fileURLWithPath: "/elsewhere/x.asm"), from: file), textEdit)
    XCTAssertNil(OpenRules.app(for: folder.appendingPathComponent("alpha/main.s"), from: file))
    try OpenRules.set(nil, ext: "ASM", folder: folder.appendingPathComponent("alpha"), in: file)
    XCTAssertNil(OpenRules.app(for: asm, from: file), "the folder above's rule applies, and its app is gone")
    XCTAssertEqual(OpenRules.load(from: file).count, 2)
    let json = try XCTUnwrap(String(data: Data(contentsOf: file), encoding: .utf8))
    XCTAssertTrue(json.contains("\"open_with\""), json)
    XCTAssertTrue(json.contains("\"extension\" : \"asm\""), json)
  }
}
