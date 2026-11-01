import XCTest
@testable import barista_agent

final class TagsTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-tags-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func file(_ name: String) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try Data("x".utf8).write(to: url)
    return url
  }

  private let red = FinderTag(name: "Red", color: 6)
  private let zelda = FinderTag(name: "zelda", color: 0)

  func testTagsKeepTheirColorsOnDisk() throws {
    let note = try file("note.txt")
    XCTAssertEqual(FinderTags.read(note), [])
    try FinderTags.write([red, zelda], to: note)
    XCTAssertEqual(FinderTags.read(note), [red, zelda])
    XCTAssertEqual(FinderTags.read(note).first?.nsColor, .systemRed)

    try FinderTags.write([], to: note)
    XCTAssertEqual(FinderTags.read(note), [])
    XCTAssertNoThrow(try FinderTags.write([], to: note), "removing no tags is no error")
  }

  func testDecodeTakesFinderValuesWithAndWithoutAColor() throws {
    let data = try PropertyListSerialization.data(fromPropertyList: ["Work\n4", "plain", "two\nlines\n3", ""],
                                                  format: .binary, options: 0)
    XCTAssertEqual(FinderTags.decode(data), [FinderTag(name: "Work", color: 4), FinderTag(name: "plain", color: 0),
                                             FinderTag(name: "two\nlines", color: 3)])
    XCTAssertEqual(FinderTags.decode(Data("junk".utf8)), [])
  }

  func testToggleAddsToTheRestThenRemovesFromAll() throws {
    let a = try file("a.txt"), b = try file("b.txt")
    try FinderTags.write([FinderTag(name: "red", color: 6), zelda], to: a)

    try FinderTags.toggle(red, on: [a, b])
    XCTAssertEqual(FinderTags.read(a).map(\.name), ["red", "zelda"], "Red and red are one tag")
    XCTAssertEqual(FinderTags.read(b), [red])

    try FinderTags.toggle(red, on: [a, b])
    XCTAssertEqual(FinderTags.read(a), [zelda])
    XCTAssertEqual(FinderTags.read(b), [])
  }

  func testCatalogListsFindersSevenThenTheRestByName() {
    let merged = TagCatalog.merged(FinderTag.standard, [FinderTag(name: "zelda", color: 0),
                                                        FinderTag(name: "red", color: 6),
                                                        FinderTag(name: "Archive", color: 4)])
    XCTAssertEqual(merged.map(\.name), ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray", "Archive",
                                        "zelda"])
  }
}
