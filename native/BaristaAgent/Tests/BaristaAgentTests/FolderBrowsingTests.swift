import Foundation
import XCTest
@testable import barista_agent

final class FolderBrowsingTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-folder-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("Core"), withIntermediateDirectories: true)
    for index in 0..<(StackContents.limit + 5) {
      try Data().write(to: folder.appendingPathComponent(String(format: "file%03d.asm", index)))
    }
    try Data().write(to: folder.appendingPathComponent(".hidden"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  func testListingIsWholeAndHidesDotFilesUnlessAsked() throws {
    let listing = try XCTUnwrap(StackContents.load(folder, sort: .name))
    XCTAssertEqual(listing.count, StackContents.limit + 6)
    XCTAssertEqual(listing.first?.name, "Core")
    XCTAssertTrue(listing.first?.isFolder == true)
    XCTAssertFalse(listing.contains { $0.name == ".hidden" })
    let everything = try XCTUnwrap(StackContents.load(folder, sort: .name, hidden: true))
    XCTAssertTrue(everything.contains { $0.name == ".hidden" })
  }

  func testRelativePathsStartAtTheBrowsedRoot() {
    let file = folder.appendingPathComponent("Core/a.asm")
    XCTAssertEqual(PopoverController.relativePath(file, from: folder), "Core/a.asm")
    XCTAssertEqual(PopoverController.relativePath(URL(fileURLWithPath: "/etc/hosts"), from: folder), "/etc/hosts")
    let sibling = URL(fileURLWithPath: folder.path + "-other/x")
    XCTAssertEqual(PopoverController.relativePath(sibling, from: folder), sibling.path)
  }

  func testTransferCopiesOrMovesAsChosen() throws {
    let source = folder.appendingPathComponent("file000.asm")
    let target = folder.appendingPathComponent("Core")
    DockStore.transfer([source], into: target, move: false)
    XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("file000.asm").path))
    DockStore.transfer([source], into: target, move: true)
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("file000 2.asm").path))
  }
}
