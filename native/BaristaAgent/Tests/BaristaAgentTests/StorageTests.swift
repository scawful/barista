import Foundation
import XCTest
@testable import barista_agent

final class StorageTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-storage-\(UUID().uuidString)")
    for (name, bytes) in [("small", 10), ("big", 50_000), ("medium", 2_000)] {
      let sub = folder.appendingPathComponent(name)
      try FileManager.default.createDirectory(at: sub.appendingPathComponent("nested"), withIntermediateDirectories: true)
      try Data(count: bytes).write(to: sub.appendingPathComponent("nested/data.bin"))
    }
    try Data(count: 5).write(to: folder.appendingPathComponent("loose.txt"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func wait(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    XCTAssertTrue(condition())
  }

  func testCalculatingSizesRanksFoldersAndHidingThemClears() {
    let state = BrowserState(location: folder)
    state.reload()
    wait { state.shown.count == 4 }
    XCTAssertEqual(state.shown.filter(\.isFolder).compactMap(\.size), [], "folders aren't walked unless asked")

    state.sortKey = .size
    state.ascending = false
    state.measuringSizes = true
    wait { state.sizesPending == 0 && state.shown.filter(\.isFolder).allSatisfy { $0.size != nil } }
    XCTAssertEqual(state.shown.map(\.name), ["big", "medium", "small", "loose.txt"])
    XCTAssertEqual(state.shown.first?.size, 50_000)
    XCTAssertEqual(state.largestSize, 50_000)

    state.measuringSizes = false
    XCTAssertEqual(state.shown.filter(\.isFolder).compactMap(\.size), [])
    XCTAssertEqual(state.largestSize, 5)
  }

  func testTheStartupVolumeReportsItsSpace() throws {
    let root = try XCTUnwrap(Volume.mounted().first { $0.url.path == "/" })
    XCTAssertGreaterThan(root.total, 0)
    XCTAssertGreaterThan(root.available, 0)
    XCTAssertTrue((0...1).contains(root.fraction))
    XCTAssertNotNil(Volume.available(at: folder))
  }

  func testRemotesComeFromTheMountsToolsStatus() {
    let status = """
    === SSHFS Mount Status ===
    halext       not-mounted  Halext      halext-nj:/home/halext
    mm-d         stale        MM-D        mm:/D:/
    mm-e         mounted      MM-E        mm:/E:/

    Mount points: /Users/someone/Mounts
    """
    let remotes = RemoteMount.parse(status)
    XCTAssertEqual(remotes.map(\.name), ["halext", "mm-d", "mm-e"], "stale and mounted remotes are listed too")
    XCTAssertEqual(remotes.first?.title, "Halext")
    XCTAssertEqual(remotes.first?.source, "halext-nj:/home/halext")
    XCTAssertEqual(remotes.last?.url.path, "/Users/someone/Mounts/mm-e")
    XCTAssertEqual(RemoteMount.parse("halext not-mounted Halext halext-nj:/home/halext"), [],
                   "without the mount folder there's nowhere to look")
  }
}
