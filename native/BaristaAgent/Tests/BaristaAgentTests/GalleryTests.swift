import AppKit
import XCTest
@testable import barista_agent

final class GalleryTests: XCTestCase {
  private var folder: URL!
  private var suite: UserDefaults!
  private var suiteName = ""
  private var store: CollectionStore!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("barista-gallery-\(UUID().uuidString)").standardizedFileURL
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("shots"), withIntermediateDirectories: true)
    suiteName = "barista-gallery-\(UUID().uuidString)"
    suite = UserDefaults(suiteName: suiteName)
    store = CollectionStore(url: folder.appendingPathComponent("data/barista_collections.local.json"))
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
    suite.removePersistentDomain(forName: suiteName)
  }

  // MARK: Layouts

  func testEvenGridFillsTheWidthWithSquares() {
    let placed = GalleryGrid.frames(aspects: [1, 2, 0.5, 1, 1], width: 310, layout: .grid, target: 100)
    let side = (310 - 2 * GalleryGrid.gap) / 3
    XCTAssertEqual(placed.frames.count, 5)
    XCTAssertEqual(placed.frames[2].maxX, 310, accuracy: 0.001, "three columns end flush")
    XCTAssertEqual(placed.frames[3], CGRect(x: 0, y: side + GalleryGrid.gap, width: side, height: side))
    XCTAssertEqual(placed.height, 2 * side + GalleryGrid.gap, accuracy: 0.001)
  }

  func testJustifiedRowsEndFlushAndTheLastRowKeepsItsHeight() {
    let placed = GalleryGrid.frames(aspects: [1, 1, 1, 1, 2], width: 404, layout: .justified, target: 100)
    XCTAssertEqual(placed.frames[0...3].map(\.height), [98, 98, 98, 98], "four squares fit nearest 100 high")
    XCTAssertEqual(placed.frames[3].maxX, 404, accuracy: 0.001)
    XCTAssertEqual(placed.frames[4], CGRect(x: 0, y: 102, width: 200, height: 100), "the last row is not stretched")
    XCTAssertEqual(placed.height, 202, accuracy: 0.001)
  }

  func testColumnsStackUnderTheShortest() {
    let placed = GalleryGrid.frames(aspects: [1, 2, 0.5, 1], width: 204, layout: .columns, target: 100)
    XCTAssertEqual(placed.frames.map(\.minX), [0, 104, 104, 0])
    XCTAssertEqual(placed.frames.map(\.minY), [0, 0, 54, 104])
    XCTAssertEqual(placed.frames[2].height, 200, "a tall picture keeps its shape")
    XCTAssertEqual(placed.height, 254, accuracy: 0.001)
  }

  func testFeaturedTakesHalfOrTwoThirdsAndSmallOnesFillBesideIt() {
    let half = GalleryGrid.frames(aspects: [1, 1, 1, 1, 1], width: 412, layout: .featured, target: 100)
    XCTAssertEqual(half.frames[0], CGRect(x: 0, y: 0, width: 204, height: 204), "with none chosen, the first")
    XCTAssertEqual(half.frames[1...4].map(\.origin),
                   [CGPoint(x: 208, y: 0), CGPoint(x: 312, y: 0), CGPoint(x: 208, y: 104), CGPoint(x: 312, y: 104)])
    XCTAssertEqual(half.height, 204, accuracy: 0.001)

    let wide = GalleryGrid.frames(aspects: [1, 1, 1, 1, 1], width: 412, layout: .featured, target: 100,
                                  featured: [2], share: .twoThirds)
    XCTAssertEqual(wide.frames[2].width, 308, accuracy: 0.001, "three of four columns")
    XCTAssertEqual(wide.frames[0...1].map(\.minY), [0, 0], "the ones before it stay in the first row")
  }

  func testArrowsAndDropsUseTheSameFrames() {
    let frames = GalleryGrid.frames(aspects: Array(repeating: 1, count: 7), width: 310, layout: .grid, target: 100).frames
    XCTAssertEqual(GalleryGrid.neighbor(of: 1, in: frames, direction: .down), 4)
    XCTAssertEqual(GalleryGrid.neighbor(of: 4, in: frames, direction: .up), 1)
    XCTAssertEqual(GalleryGrid.neighbor(of: 5, in: frames, direction: .down), 6, "the short last row, nearest across")
    XCTAssertNil(GalleryGrid.neighbor(of: 0, in: frames, direction: .left))
    XCTAssertNil(GalleryGrid.neighbor(of: 6, in: frames, direction: .right))
    XCTAssertEqual(GalleryGrid.insertion(at: CGPoint(x: frames[1].maxX - 5, y: 50), in: frames)?.index, 2)
    XCTAssertEqual(GalleryGrid.insertion(at: CGPoint(x: 5, y: 50), in: frames)?.index, 0)
    XCTAssertEqual(GalleryGrid.insertion(at: CGPoint(x: 10, y: 900), in: frames)?.index, 6, "below the last row")
    XCTAssertEqual(GalleryGrid.index(at: CGPoint(x: frames[4].midX, y: frames[4].midY), in: frames), 4)
  }

  // MARK: A folder's gallery

  func testAFolderGalleryRearrangesAndRemovesWithoutTouchingFiles() throws {
    let urls = try pictures(["a.png", "b.png", "c.png", "d.png"])
    try Data().write(to: folder.appendingPathComponent("shots/notes.md"))
    let gallery = GalleryModel(folder: folder.appendingPathComponent("shots"), store: store, defaults: suite)
    let undo = UndoManager()
    undo.groupsByEvent = false
    gallery.undoManager = undo
    XCTAssertEqual(names(gallery.items), ["a.png", "b.png", "c.png", "d.png"], "pictures and movies only, by name")

    grouped(undo) { gallery.move([urls[2]], to: 0) }
    XCTAssertEqual(names(gallery.items), ["c.png", "a.png", "b.png", "d.png"])
    gallery.select(urls[0])
    grouped(undo) { gallery.moveSelection(by: 1) }
    XCTAssertEqual(names(gallery.items), ["c.png", "b.png", "a.png", "d.png"], "] moves past the next one")
    grouped(undo) { gallery.remove([urls[1]]) }
    XCTAssertEqual(names(gallery.items), ["c.png", "a.png", "d.png"])
    XCTAssertEqual(gallery.hidden, [urls[1]])
    XCTAssertTrue(FileManager.default.fileExists(atPath: urls[1].path), "removing only hides it")

    undo.undo()
    XCTAssertEqual(names(gallery.items), ["c.png", "b.png", "a.png", "d.png"])
    XCTAssertTrue(gallery.hidden.isEmpty)
    undo.undo()
    XCTAssertEqual(names(gallery.items), ["c.png", "a.png", "b.png", "d.png"])
    undo.redo()
    XCTAssertEqual(names(gallery.items), ["c.png", "b.png", "a.png", "d.png"])

    let fresh = try pictures(["0.png"])
    gallery.refresh()
    XCTAssertEqual(gallery.items.last, fresh[0], "a new file goes after a hand-made order")

    grouped(undo) { gallery.remove([urls[3]]) }
    grouped(undo) { gallery.add([urls[3], URL(fileURLWithPath: "/elsewhere/x.png")]) }
    XCTAssertTrue(gallery.items.contains(urls[3]), "dropping a removed file back brings it back")
    XCTAssertFalse(gallery.items.contains(URL(fileURLWithPath: "/elsewhere/x.png")), "only a collection takes others")
    XCTAssertNotNil(gallery.status)
  }

  func testShiftArrowsAndEdgesExtendTheSelectionInOrder() throws {
    let urls = try pictures(["a.png", "b.png", "c.png", "d.png", "e.png"])
    let gallery = GalleryModel(folder: folder.appendingPathComponent("shots"), store: store, defaults: suite)
    gallery.set(layout: .grid)
    gallery.resize(by: 1 - gallery.size)
    _ = gallery.layout(width: 310)
    gallery.select(urls[1])
    gallery.moveFocus(.right, extend: true)
    XCTAssertEqual(gallery.selected, Array(urls[1...2]))
    gallery.moveToEdge(end: true, extend: true)
    XCTAssertEqual(gallery.selected, Array(urls[1...4]))
    gallery.moveFocus(.up, extend: false)
    XCTAssertEqual(gallery.selected, [urls[1]], "e is under b in three columns")
    gallery.select(urls[3], toggle: true)
    XCTAssertEqual(gallery.targets(for: urls[3]), [urls[1], urls[3]], "a menu on the selection acts on all of it")
    XCTAssertEqual(gallery.targets(for: urls[0]), [urls[0]])
    XCTAssertEqual(suite.string(forKey: "Gallery.layout"), "grid", "every folder shares the layout")
  }

  func testSavingAFolderAsACollectionKeepsItsOrderAndLeavesOutRemoved() throws {
    let urls = try pictures(["a.png", "b.png", "c.png"])
    let gallery = GalleryModel(folder: folder.appendingPathComponent("shots"), store: store, defaults: suite)
    gallery.move([urls[2]], to: 0)
    gallery.remove([urls[0]])
    gallery.toggleFeatured([urls[1]])
    let name = gallery.saveAsCollection("Shots")
    let saved = try XCTUnwrap(store.collection(named: name))
    XCTAssertEqual(saved.urls, [urls[2], urls[1]])
    XCTAssertEqual(saved.featuredURLs, [urls[1]])
    XCTAssertEqual(saved.layout, .featured, "featuring switches to Featured")
  }

  // MARK: A collection's gallery

  func testACollectionSavesEveryChangeAndOtherWindowsFollow() throws {
    let urls = try pictures(["a.png", "b.png", "c.png"])
    let elsewhere = folder.appendingPathComponent("z.png")
    try picture(at: elsewhere)
    store.create("Trip", urls: [urls[0], urls[1]])
    let gallery = GalleryModel(collection: "trip", store: store, defaults: suite)
    let other = GalleryModel(collection: "Trip", store: store, defaults: suite)
    XCTAssertEqual(gallery.title, "Trip", "found without minding case")

    gallery.add([elsewhere, urls[0], folder.appendingPathComponent("notes.md")])
    XCTAssertEqual(store.collection(named: "Trip")?.urls, [urls[0], urls[1], elsewhere], "from any folder, once each")
    gallery.move([elsewhere], to: 0)
    gallery.remove([urls[0]])
    XCTAssertEqual(store.collection(named: "Trip")?.urls, [elsewhere, urls[1]])
    XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))
    XCTAssertTrue(gallery.hidden.isEmpty, "a collection forgets rather than hides")

    gallery.set(layout: .columns)
    gallery.resize(by: 1)
    gallery.remember(.tiles)
    let saved = try XCTUnwrap(store.collection(named: "Trip"))
    XCTAssertEqual(saved.layout, .columns)
    XCTAssertEqual(saved.size, GalleryGrid.defaultSize + 1)
    XCTAssertEqual(saved.mode, .tiles)
    XCTAssertEqual(other.items, gallery.items, "another window on it follows")
    XCTAssertEqual(other.layout, .columns)
    XCTAssertEqual(GalleryModel(collection: "Trip", store: store, defaults: suite).mode, .tiles,
                   "it opens the way it was last shown")

    gallery.rename(to: "Summer")
    XCTAssertEqual(gallery.title, "Summer")
    XCTAssertNil(store.collection(named: "Trip"))
  }

  func testFavoritesToggleFromAnyGallery() throws {
    let urls = try pictures(["a.png", "b.png"])
    let gallery = GalleryModel(folder: folder.appendingPathComponent("shots"), store: store, defaults: suite)
    gallery.toggleFavorite([urls[0]])
    XCTAssertTrue(gallery.isFavorite([urls[0]]))
    XCTAssertEqual(store.collection(named: CollectionStore.favorites)?.urls, [urls[0]], "made when first used")
    gallery.toggleFavorite([urls[0]])
    XCTAssertFalse(gallery.isFavorite([urls[0]]))
  }

  // MARK: Viewer modes

  func testAGalleryWindowShowsThumbnailsTilesOrOneAndComesBack() throws {
    let urls = try pictures(["a.png", "b.png", "c.png"], size: CGSize(width: 64, height: 48))
    let gallery = GalleryModel(folder: folder.appendingPathComponent("shots"), store: store, defaults: suite)
    gallery.move([urls[2]], to: 0)
    let model = ViewerModel(gallery: gallery)
    XCTAssertEqual(model.mode, .gallery)
    XCTAssertTrue(model.tiles.isEmpty)
    XCTAssertEqual(model.title, "shots")

    model.open([urls[0]])
    XCTAssertEqual(model.mode, .one)
    XCTAssertEqual(model.tiles.map(\.url), [urls[0]])
    XCTAssertEqual(model.media?.position?.index, 2, "← and → follow the gallery's order")
    XCTAssertEqual(model.media?.position?.count, 3)
    model.media?.step(1)
    XCTAssertEqual(model.media?.url, urls[1])
    XCTAssertEqual(gallery.focus, urls[1], "the gallery follows along")

    model.show(.gallery)
    XCTAssertTrue(model.tiles.isEmpty)
    XCTAssertEqual(gallery.selection, [urls[1]])

    gallery.selectAll()
    model.show(.tiles)
    XCTAssertEqual(model.tiles.map(\.url), [urls[2], urls[0], urls[1]], "tiles in the gallery's order")
    model.tiles.forEach(model.remove)
    XCTAssertEqual(model.mode, .gallery, "closing the last tile goes back to the gallery")
  }

  func testTrashingALoneTileStepsAlongTheGallery() {
    let urls = ["a.png", "b.png", "c.png"].map { URL(fileURLWithPath: "/shots/\($0)") }
    XCTAssertEqual(ViewerModel.next(after: urls[0], in: urls, skipping: [urls[0], urls[1]]), urls[2])
    XCTAssertEqual(ViewerModel.next(after: urls[2], in: urls, skipping: [urls[2]]), urls[1], "back from the last")
    XCTAssertNil(ViewerModel.next(after: urls[0], in: [urls[0]], skipping: [urls[0]]))
  }

  // MARK: The collections file

  func testCollectionsRoundTripWithUniqueNamesAndTildePaths() throws {
    let home = URL(fileURLWithPath: NSHomeDirectory() + "/Pictures/x.png")
    XCTAssertEqual(MediaCollection.path(home), "~/Pictures/x.png")
    XCTAssertEqual(MediaCollection.url("~/Pictures/x.png"), home)

    XCTAssertEqual(store.create("Trip", urls: [home, home]), "Trip")
    XCTAssertEqual(store.create("trip"), "trip 2")
    XCTAssertEqual(store.uniqueName("Trip"), "Trip 3")
    XCTAssertEqual(store.add([home, URL(fileURLWithPath: "/y.png")], to: "Trip"), 1, "already in it")
    XCTAssertEqual(store.add([home], to: "New"), 1, "adding to a missing one makes it")
    XCTAssertEqual(store.rename("New", to: "Trip"), "Trip 3")
    store.update("Trip") { $0.featured = [MediaCollection.path(home)] }
    store.remove([home], from: "Trip")
    XCTAssertEqual(store.collection(named: "Trip")?.items, ["/y.png"])
    XCTAssertEqual(store.collection(named: "Trip")?.featured, [], "removing unfeatures")
    store.delete("trip 2")

    let reread = CollectionStore(url: store.url)
    XCTAssertEqual(reread.collections, store.collections)
    XCTAssertEqual(reread.collections.map(\.name), ["Trip", "Trip 3"])
  }

  func testAHandWrittenEntryNeedsOnlyANameAndItems() throws {
    try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"version": 1, "collections": [{"name": "Hand", "items": ["~/a.png"], "size": 99, "layout": "bogus"}]}"#.utf8)
      .write(to: store.url)
    store.refresh()
    let hand = try XCTUnwrap(store.collection(named: "Hand"))
    XCTAssertEqual(hand.layout, .justified)
    XCTAssertEqual(hand.size, GalleryGrid.sizes.count - 1, "sizes clamp")
    XCTAssertEqual(hand.mode, .gallery)
  }

  func testRewritesBackUpTheFileFirstAndKeepTheNewestThree() throws {
    let files = FileManager.default
    let data = store.url.deletingLastPathComponent()
    store.create("First")
    XCTAssertEqual(try backups(in: data), [], "nothing to back up before the first write")
    let first = try Data(contentsOf: store.url)
    for day in ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04"] {
      try first.write(to: URL(fileURLWithPath: store.url.path + ".\(day).bak"))
    }
    store.create("Second")
    let kept = try backups(in: data)
    XCTAssertEqual(kept.count, 3)
    XCTAssertFalse(kept.contains { $0.contains("2026-01-01") || $0.contains("2026-01-02") }, "the oldest go")
    let today = try XCTUnwrap(kept.last)
    XCTAssertEqual(try Data(contentsOf: data.appendingPathComponent(today)), first, "today's copy is the file before")

    try Data("not json".utf8).write(to: store.url)
    store.refresh()
    XCTAssertTrue(store.collections.isEmpty)
    store.create("Third")
    let aside = try files.contentsOfDirectory(atPath: data.path).filter { $0.contains(".unreadable-") }
    XCTAssertEqual(aside.count, 1, "an unreadable file is copied aside before it is replaced")
  }

  // MARK: Helpers

  private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

  /// With `groupsByEvent` off, each edit is its own Undo.
  private func grouped(_ undo: UndoManager, _ edit: () -> Void) {
    undo.beginUndoGrouping()
    edit()
    undo.endUndoGrouping()
  }

  private func backups(in data: URL) throws -> [String] {
    let prefix = store.url.lastPathComponent + "."
    return try FileManager.default.contentsOfDirectory(atPath: data.path)
      .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".bak") && !$0.contains("unreadable") }
      .sorted()
  }

  @discardableResult
  private func pictures(_ names: [String], size: CGSize = CGSize(width: 8, height: 8)) throws -> [URL] {
    try names.map { name in
      let url = folder.appendingPathComponent("shots/\(name)")
      try picture(at: url, size: size)
      return url
    }
  }

  private func picture(at url: URL, size: CGSize = CGSize(width: 8, height: 8)) throws {
    let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(origin: .zero, size: size))
    let image = try XCTUnwrap(context.makeImage())
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }
}
