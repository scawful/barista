import AppKit
import XCTest
@testable import barista_agent

final class FileViewsTests: XCTestCase {
  func testRenameSelectsTheStemAsFinderDoes() {
    XCTAssertEqual(FileOperations.stem("sram.asm", isFolder: false), NSRange(location: 0, length: 4))
    XCTAssertEqual(FileOperations.stem("oos.tar.gz", isFolder: false), NSRange(location: 0, length: 7))
    XCTAssertEqual(FileOperations.stem("v1.2", isFolder: true), NSRange(location: 0, length: 4),
                   "a folder's dot isn't an extension")
    XCTAssertEqual(FileOperations.stem(".zshrc", isFolder: false), NSRange(location: 0, length: 6))
    XCTAssertEqual(FileOperations.stem("Makefile", isFolder: false), NSRange(location: 0, length: 8))
    XCTAssertEqual(FileOperations.stem("é.txt", isFolder: false), NSRange(location: 0, length: 1))
  }

  func testImagesAndVideosGetThumbnailsAndOtherFilesKeepTheirIcon() async throws {
    for name in ["shot.png", "scan.HEIC", "raw.dng", "clip.mov", "clip.mp4", "clip.mkv", "clip.webm"] {
      XCTAssertTrue(FileIcons.hasThumbnail(URL(fileURLWithPath: "/tmp/\(name)")), name)
    }
    for name in ["song.mp3", "notes.md", "doc.pdf", "Folder"] {
      XCTAssertFalse(FileIcons.hasThumbnail(URL(fileURLWithPath: "/tmp/\(name)")), name)
    }

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let wide = folder.appendingPathComponent("wide.png")
    let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 100,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: wide)
    let text = folder.appendingPathComponent("notes.txt")
    try Data("hi".utf8).write(to: text)

    let modified = Date(timeIntervalSince1970: 1_000)
    let thumbnail = await FileIcons.shared.icon(for: wide, points: 64, modified: modified)
    let size = try XCTUnwrap(thumbnail?.size)
    XCTAssertEqual(size.width / size.height, 2, accuracy: 0.1, "the picture's own shape, not a square icon")
    XCTAssertNotNil(FileIcons.shared.cached(wide, points: 64, modified: modified))
    XCTAssertNil(FileIcons.shared.cached(wide, points: 64, modified: modified.addingTimeInterval(1)),
                 "an edited file draws a new thumbnail")

    let icon = await FileIcons.shared.icon(for: text, points: 64)
    let iconSize = try XCTUnwrap(icon?.size)
    XCTAssertEqual(iconSize.width, iconSize.height)
  }

  func testColumnsStartAtHomeOrTheRoot() {
    let home = URL(fileURLWithPath: "/Users/me")
    XCTAssertEqual(BrowserLayout.columnFolders(for: URL(fileURLWithPath: "/Users/me/src/oos/Core"), home: home).map(\.path),
                   ["/Users/me", "/Users/me/src", "/Users/me/src/oos"])
    XCTAssertEqual(BrowserLayout.columnFolders(for: home, home: home), [])
    XCTAssertEqual(BrowserLayout.columnFolders(for: URL(fileURLWithPath: "/Applications/Utilities"), home: home).map(\.path),
                   ["/", "/Applications"])
    XCTAssertEqual(BrowserLayout.columnFolders(for: URL(fileURLWithPath: "/"), home: home), [])
  }

  func testGridArrows() {
    // Seven icons, three to a row:  0 1 2 / 3 4 5 / 6
    func step(_ index: Int?, _ key: UInt16) -> Int? { BrowserLayout.step(from: index, count: 7, columns: 3, keyCode: key) }
    let (left, right, down, up): (UInt16, UInt16, UInt16, UInt16) = (123, 124, 125, 126)
    XCTAssertEqual(step(nil, down), 0, "the first press picks the first icon")
    XCTAssertEqual(step(0, left), 0)
    XCTAssertEqual(step(2, right), 3, "right wraps onto the next row")
    XCTAssertEqual(step(1, down), 4)
    XCTAssertEqual(step(5, down), 6, "down from above a short last row lands on the last icon")
    XCTAssertEqual(step(6, down), 6)
    XCTAssertEqual(step(4, up), 1)
    XCTAssertEqual(step(1, up), 1)
    XCTAssertNil(BrowserLayout.step(from: nil, count: 0, columns: 3, keyCode: down))
  }

  // MARK: Browser state

  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-views-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("Core"), withIntermediateDirectories: true)
    for name in ["a.asm", "b.asm", "c.asm", "d.asm"] {
      try Data().write(to: folder.appendingPathComponent(name))
    }
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func loaded() -> BrowserState {
    let state = BrowserState(location: folder)
    state.reload()
    let deadline = Date().addingTimeInterval(5)
    while state.shown.count < 5 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertEqual(state.shown.map(\.name), ["Core", "a.asm", "b.asm", "c.asm", "d.asm"])
    return state
  }

  private func url(_ state: BrowserState, _ name: String) -> URL { state.shown.first { $0.name == name }!.url }

  func testReturnRenamesOnlyASingleSelection() {
    let state = loaded()
    state.selection = [url(state, "a.asm"), url(state, "b.asm")]
    state.renameSelection()
    XCTAssertNil(state.renaming)
    state.selection = [url(state, "b.asm")]
    state.renameSelection()
    XCTAssertEqual(state.renaming, url(state, "b.asm"))
  }

  func testIconClicks() {
    let state = loaded()
    state.click(url(state, "a.asm"), modifiers: [])
    state.click(url(state, "c.asm"), modifiers: .shift)
    XCTAssertEqual(state.selectedURLs.map(\.lastPathComponent), ["a.asm", "b.asm", "c.asm"])
    state.click(url(state, "b.asm"), modifiers: .command)
    XCTAssertEqual(state.selectedURLs.map(\.lastPathComponent), ["a.asm", "c.asm"])
    state.click(url(state, "d.asm"), modifiers: .shift)
    XCTAssertEqual(state.selectedURLs.map(\.lastPathComponent), ["b.asm", "c.asm", "d.asm"],
                   "a ⌘-click moves where the next ⇧-click's range starts")
    state.click(url(state, "Core"), modifiers: [])
    XCTAssertEqual(state.selectedURLs.map(\.lastPathComponent), ["Core"])
  }

  func testIconArrowsAndEnteringAFolder() {
    let state = loaded()
    state.layout = .columns
    state.moveSelection(keyCode: 125)
    state.moveSelection(keyCode: 125)
    XCTAssertEqual(state.selectedURLs.map(\.lastPathComponent), ["a.asm"], "a list moves one row at a time")

    state.layout = .icons
    state.gridColumns = 2
    state.selection = []
    state.moveSelection(keyCode: 125)
    XCTAssertEqual(state.selectedURLs.map(\.lastPathComponent), ["Core"])
    XCTAssertEqual(state.selectedFolder?.lastPathComponent, "Core")
    state.moveSelection(keyCode: 125)
    XCTAssertEqual(state.selectedURLs.map(\.lastPathComponent), ["b.asm"])
    XCTAssertNil(state.selectedFolder, "a file isn't a folder to preview or enter")
    state.enterSelectedFolder()
    XCTAssertEqual(state.location.path, folder.path)

    state.selection = [url(state, "Core")]
    state.enterSelectedFolder()
    XCTAssertEqual(state.location.lastPathComponent, "Core")
    let deadline = Date().addingTimeInterval(5)
    while !state.shown.isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }

    state.up()
    while state.selection.isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertEqual(state.selectedURLs.map(\.lastPathComponent), ["Core"], "← selects the folder you left")
  }
}
