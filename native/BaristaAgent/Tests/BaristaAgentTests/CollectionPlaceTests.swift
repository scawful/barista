import XCTest
@testable import barista_agent

final class CollectionPlaceTests: XCTestCase {
  private var folder: URL!
  private var store: CollectionStore!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("barista-collection-places-\(UUID().uuidString)").standardizedFileURL
    store = CollectionStore(url: folder.appendingPathComponent("data/barista_collections.local.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  func testFavoritesIsListedBeforeItIsMade() {
    XCTAssertEqual(CollectionPlace.list(store), [CollectionPlace(name: "Favorites", count: 0, made: false)])
    XCTAssertEqual(CollectionPlace.list(store).first?.symbol, "star")
  }

  func testFavoritesComesFirstThenTheRestInTheFilesOrder() {
    store.create("Trip", urls: pictures(["a.png", "b.png"]))
    store.add(pictures(["c.png"]), to: CollectionStore.favorites)
    store.create("Art")
    XCTAssertEqual(CollectionPlace.list(store), [
      CollectionPlace(name: "Favorites", count: 1, made: true),
      CollectionPlace(name: "Trip", count: 2, made: true),
      CollectionPlace(name: "Art", count: 0, made: true),
    ])
    XCTAssertEqual(CollectionPlace.list(store).map(\.symbol), ["star", "photo.stack", "photo.stack"])
  }

  func testFavoritesSavedInAnotherCaseIsListedOnceUnderItsOwnName() {
    store.create("Trip")
    store.rename("Trip", to: "favorites")
    XCTAssertEqual(CollectionPlace.list(store), [CollectionPlace(name: "favorites", count: 0, made: true)])
  }

  func testOnlyDroppedPicturesAndMoviesAreTaken() {
    let dropped = ["a.png", "notes.md", "clip.mov", "paper.pdf", "photo.JPG", "folder/"]
      .map { folder.appendingPathComponent($0) } + [URL(string: "https://example.com/web.png")!]
    XCTAssertEqual(CollectionPlace.media(dropped).map(\.lastPathComponent), ["a.png", "clip.mov", "photo.JPG"])
  }

  private func pictures(_ names: [String]) -> [URL] { names.map { folder.appendingPathComponent($0) } }
}
