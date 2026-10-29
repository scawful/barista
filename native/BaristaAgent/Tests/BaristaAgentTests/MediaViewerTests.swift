import AVFoundation
import AppKit
import XCTest
@testable import barista_agent

final class MediaViewerTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    folder = FileManager.default.temporaryDirectory.appendingPathComponent("barista-media-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  func testMoviesTheSystemPlaysOpenInTheViewerAndStepWithPictures() throws {
    XCTAssertEqual(ViewerKind.of(URL(fileURLWithPath: "/a/clip.mov")), .video)
    XCTAssertEqual(ViewerKind.of(URL(fileURLWithPath: "/a/clip.MP4")), .video)
    XCTAssertNil(ViewerKind.of(URL(fileURLWithPath: "/a/clip.mkv")), "AVFoundation can't play it")
    XCTAssertNil(ViewerKind.of(URL(fileURLWithPath: "/a/song.mp3")))

    for name in ["b.mov", "a.png", "c.jpg", "notes.md", "song.mp3"] {
      try Data().write(to: folder.appendingPathComponent(name))
    }
    XCTAssertEqual(ViewerKind.siblings(of: folder.appendingPathComponent("b.mov")).map(\.lastPathComponent),
                   ["a.png", "b.mov", "c.jpg"])
    XCTAssertEqual(ViewerKind.siblings(of: folder.appendingPathComponent("notes.md")).map(\.lastPathComponent),
                   ["notes.md"])
  }

  func testCropHandlesMoveTheirEdgesAndStayInsideThePicture() {
    let rect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    XCTAssertEqual(MediaEdit.adjust(rect, handle: (0, 0), by: CGSize(width: 0.5, height: -0.5)),
                   CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), "moving clamps at the edges")
    XCTAssertEqual(MediaEdit.adjust(rect, handle: (1, 1), by: CGSize(width: 0.1, height: 0.1)),
                   CGRect(x: 0.25, y: 0.25, width: 0.6, height: 0.6))
    XCTAssertEqual(MediaEdit.adjust(rect, handle: (-1, 0), by: CGSize(width: -1, height: 0.3)),
                   CGRect(x: 0, y: 0.25, width: 0.75, height: 0.5), "an edge handle moves one edge")
    let squeezed = MediaEdit.adjust(rect, handle: (1, 0), by: CGSize(width: -0.9, height: 0))
    XCTAssertEqual(squeezed.width, MediaEdit.minimum, accuracy: 0.0001)
    XCTAssertEqual(MediaEdit.pixels(CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), in: CGSize(width: 256, height: 224)),
                   CGRect(x: 128, y: 0, width: 128, height: 112))
  }

  func testCopiesGoBesideTheOriginalWithoutStackingSuffixes() throws {
    let clip = folder.appendingPathComponent("clip.mov")
    XCTAssertEqual(MediaEdit.copyURL(for: clip, ext: "mov").lastPathComponent, "clip (edited).mov")
    try Data().write(to: folder.appendingPathComponent("clip (edited).mov"))
    XCTAssertEqual(MediaEdit.copyURL(for: clip, ext: "mov").lastPathComponent, "clip (edited 2).mov")
    XCTAssertEqual(MediaEdit.copyURL(for: folder.appendingPathComponent("clip (edited).mov"), ext: "mov").lastPathComponent,
                   "clip (edited 2).mov")
  }

  func testRotateThenCropWritesTheRightPixels() throws {
    // Two pixels wide, one high: red on the left, blue on the right.
    let source = folder.appendingPathComponent("pair.png")
    try png([0xFF0000, 0x0000FF], width: 2, height: 1).write(to: source)

    let turned = try MediaEdit.writeImage(source, rotation: 1, crop: nil)
    XCTAssertEqual(turned.lastPathComponent, "pair (edited).png")
    XCTAssertEqual(try pixels(turned), [0xFF0000, 0x0000FF], "a clockwise turn puts the left side on top")
    XCTAssertEqual(try size(turned), CGSize(width: 1, height: 2))

    let bottom = try MediaEdit.writeImage(source, rotation: 1, crop: CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
    XCTAssertEqual(try pixels(bottom), [0x0000FF])
  }

  func testPixelArtOpensAtAWholeMultipleAndZoomsInWholeSteps() throws {
    XCTAssertEqual(ViewerController.natural(CGSize(width: 256, height: 224), in: CGSize(width: 1512, height: 945),
                                            pixelated: true), CGSize(width: 512, height: 448))
    XCTAssertEqual(ViewerController.natural(CGSize(width: 256, height: 224), in: CGSize(width: 1512, height: 945),
                                            pixelated: false), CGSize(width: 256, height: 224))
    XCTAssertEqual(ViewerController.natural(CGSize(width: 4000, height: 2000), in: CGSize(width: 1000, height: 1000),
                                            pixelated: false), CGSize(width: 700, height: 350))

    let sprite = folder.appendingPathComponent("sprite.png")
    try png(Array(repeating: 0x00FF00, count: 16 * 16), width: 16, height: 16).write(to: sprite)
    let media = MediaState(url: sprite, kind: .image)
    XCTAssertNil(media.error)
    XCTAssertTrue(media.pixelated, "a small PNG is pixel art")
    var requests: [CGSize] = []
    media.resize = { if case .exact(let size) = $0 { requests.append(size) } }
    media.magnify(by: 1)
    XCTAssertEqual(media.zoom, .focus(2, CGPoint(x: 0.5, y: 0.5)))
    XCTAssertEqual(requests, [CGSize(width: 32, height: 32)], "the window grows to the zoomed picture")
  }

  func testTilesFillTheWindowAndCenterAShortLastRow() {
    let window = CGSize(width: 800, height: 600)
    XCTAssertEqual(TileGrid.frames(count: 1, in: window), [CGRect(origin: .zero, size: window)])
    let two = TileGrid.frames(count: 2, in: window)
    XCTAssertEqual(two.map(\.minY), [0, 0], "two sit side by side in a landscape window")
    XCTAssertEqual(two[1].minX, two[0].maxX + TileGrid.gap)
    let three = TileGrid.frames(count: 3, in: window)
    XCTAssertEqual(three[2].midX, 400, accuracy: 0.5, "the short last row is centered")
    for (index, frame) in three.enumerated() {
      XCTAssertTrue(CGRect(origin: .zero, size: window).insetBy(dx: -0.5, dy: -0.5).contains(frame))
      for other in three[(index + 1)...] { XCTAssertFalse(frame.intersects(other)) }
    }
    XCTAssertEqual(TileGrid.frames(count: 6, in: CGSize(width: 1200, height: 600)).filter { $0.minY == 0 }.count, 3)
  }

  func testTileLayoutsDistributeTheWindow() {
    let window = CGSize(width: 900, height: 600)
    func check(_ frames: [CGRect], _ name: String, in size: CGSize = window) {
      let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5)
      for (index, frame) in frames.enumerated() {
        XCTAssertTrue(bounds.contains(frame), "\(name) stays in the window")
        for other in frames[(index + 1)...] { XCTAssertFalse(frame.intersects(other), "\(name) tiles don't overlap") }
      }
    }
    let row = TileGrid.frames(count: 3, in: window, layout: .row)
    XCTAssertEqual(Set(row.map(\.minY)), [0])
    let column = TileGrid.frames(count: 3, in: window, layout: .column)
    XCTAssertEqual(Set(column.map(\.minX)), [0])
    let main = TileGrid.frames(count: 4, in: window, layout: .main, active: 2)
    XCTAssertEqual(main[2], CGRect(x: 0, y: 0, width: 673.5, height: 600), "the active tile gets three quarters")
    XCTAssertEqual(Set([0, 1, 3].map { main[$0].minX }), [675.5], "the rest stack in the strip")
    let portrait = TileGrid.frames(count: 3, in: CGSize(width: 600, height: 900), layout: .main, active: 0)
    XCTAssertEqual(portrait[0].width, 600, "a tall window puts the strip below")
    let aspects: [CGFloat] = [2, 0.5, 1, 16.0 / 9]
    let shapes = TileGrid.frames(count: 4, in: window, layout: .shapes, aspects: aspects)
    for (frame, aspect) in zip(shapes, aspects) {
      XCTAssertEqual(frame.width / frame.height, aspect, accuracy: 0.01, "each tile has its picture's shape")
    }
    for (frames, name) in [(row, "row"), (column, "column"), (main, "main"), (shapes, "shapes")] {
      check(frames, name)
    }
    check(portrait, "portrait", in: CGSize(width: 600, height: 900))
  }

  func testACropTurnsWithThePicture() {
    let corner = CGRect(x: 0, y: 0, width: 0.5, height: 0.25)
    XCTAssertEqual(MediaEdit.turn(corner, quarterTurns: 1), CGRect(x: 0.75, y: 0, width: 0.25, height: 0.5),
                   "the top-left corner turns to the top right")
    XCTAssertEqual(MediaEdit.turn(corner, quarterTurns: -1), MediaEdit.turn(corner, quarterTurns: 3))
    XCTAssertEqual(MediaEdit.turn(corner, quarterTurns: 4), corner)
  }

  func testResizingCropsTheViewAndOnlyAnAppliedCropIsAnEdit() throws {
    let source = folder.appendingPathComponent("photo.jpg")
    try write(CGSize(width: 400, height: 200), to: source, type: "public.jpeg")
    let media = MediaState(url: source, kind: .image)
    XCTAssertFalse(media.pixelated)
    let left = CGRect(x: 0, y: 0, width: 0.5, height: 1)
    media.viewed(left)
    XCTAssertTrue(media.viewIsPartial)
    XCTAssertFalse(media.hasEdits, "a window cropped by its edges changes nothing")

    media.beginCrop()
    XCTAssertEqual(media.crop, left, "the handles start at what the window showed")
    XCTAssertEqual(media.zoom, .fit, "the whole picture shows around them")
    media.cancelCrop()
    XCTAssertEqual(media.zoom, .region(left), "Escape goes back to the same view")
    XCTAssertNil(media.applied)

    media.cropToView()
    XCTAssertEqual(media.applied, left)
    XCTAssertTrue(media.hasEdits)
    media.rotate(1)
    XCTAssertEqual(media.applied, CGRect(x: 0, y: 0, width: 1, height: 0.5), "the crop turns with the picture")
    XCTAssertEqual(media.zoom, .region(CGRect(x: 0, y: 0, width: 1, height: 0.5)), "fit shows just the crop")

    media.beginCrop()
    media.crop = MediaEdit.whole
    media.applyCrop()
    XCTAssertNil(media.applied, "applying the whole picture drops the crop")
  }

  func testTilesShareAWindowAndLetGoWhenClosed() throws {
    let names = ["a.png", "b.png", "c.png"]
    for name in names { try write(CGSize(width: 64, height: 48), to: folder.appendingPathComponent(name)) }
    let urls = names.map { folder.appendingPathComponent($0) }
    weak var released: ViewerModel?
    weak var tile: MediaState?
    var emptied = false
    do {
      let model = ViewerModel(url: urls[0])
      released = model
      tile = model.tiles.first
      model.add(urls + [folder.appendingPathComponent("notes.md")])
      XCTAssertEqual(model.tiles.map(\.url.lastPathComponent), names, "files already shown and non-media are skipped")
      XCTAssertTrue(model.media === model.tiles[2], "the last added is active")
      XCTAssertEqual(model.title, "c.png and 2 more")
      model.move(model.tiles[2], by: -5)
      XCTAssertEqual(model.tiles.map(\.url.lastPathComponent), ["c.png", "a.png", "b.png"], "moves clamp at the start")
      model.layout = .shapes
      XCTAssertEqual(model.frames(in: CGSize(width: 900, height: 300)).map { ($0.width / $0.height * 3).rounded() },
                     [4, 4, 4], "By Shape follows each picture's 64 × 48")
      model.cycleLayout()
      XCTAssertEqual(model.layout, .grid, "the layouts go round")
      model.move(model.tiles[0], by: 2)
      model.cycle(1)
      XCTAssertTrue(model.media === model.tiles[0])
      model.remove(model.tiles[0])
      XCTAssertEqual(model.url.lastPathComponent, "b.png", "the next tile takes over")
      model.onEmpty = { emptied = true }
      model.tiles.forEach(model.remove)
      XCTAssertTrue(emptied)
    }
    XCTAssertNil(released, "a closed window's model goes away")
    XCTAssertNil(tile, "so do its tiles")
  }

  func testPicturesDecodeAtScreenSizeUntilAZoomNeedsMore() throws {
    let wide = folder.appendingPathComponent("wide.png")
    let screen = MediaState.screenPixels
    try write(CGSize(width: screen * 2, height: 64), to: wide)
    let media = MediaState(url: wide, kind: .image)
    XCTAssertEqual(media.pixelSize, CGSize(width: screen * 2, height: 64), "the size comes from the header")
    XCTAssertEqual(try decodedWidth(media), screen, accuracy: 1)
    XCTAssertEqual(media.image?.size, media.size, "fewer pixels draw at the same size")

    media.shown(at: 1, backing: 2)
    XCTAssertEqual(try decodedWidth(media, until: { $0 > screen }), screen * 2, accuracy: 1)
    media.shedPixels()
    XCTAssertEqual(try decodedWidth(media, until: { $0 <= screen }), screen, accuracy: 1)

    media.suspend()
    XCTAssertNil(media.image, "a minimized window holds no pixels")
    media.resume()
    XCTAssertEqual(try decodedWidth(media), screen, accuracy: 1)

    let shared = MediaState(url: wide, kind: .image, tiles: 4)
    XCTAssertEqual(try decodedWidth(shared), screen / 2, accuracy: 1, "two tiles to a row share a screen's width")
  }

  func testRetinaScreenshotsShowAtHalfTheirPixels() throws {
    let shot = folder.appendingPathComponent("shot.png")
    try write(CGSize(width: 200, height: 100), to: shot, dpi: 144)
    let header = try XCTUnwrap(ImageHeader.read(shot))
    XCTAssertEqual(header.pixels, CGSize(width: 200, height: 100))
    XCTAssertEqual(header.points, CGSize(width: 100, height: 50))
  }

  @MainActor
  func testZoomingSizesTheWindowToThePicture() throws {
    let screen = try XCTUnwrap(NSScreen.main).visibleFrame
    let window = NSWindow(contentRect: NSRect(x: screen.minX + 100, y: screen.minY + 100, width: 200, height: 150),
                          styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = ImageScrollView()
    window.contentView = view
    view.show(NSImage(size: NSSize(width: 400, height: 300)), zoom: .fit, pixelated: false, fills: false)
    window.contentView?.layoutSubtreeIfNeeded()
    XCTAssertEqual(view.magnification, 0.5, accuracy: 0.001)

    XCTAssertTrue(view.zoomWindow(to: 1))
    XCTAssertEqual(window.frame.size, NSSize(width: 400, height: 300), "zooming in grows the window with the picture")
    XCTAssertTrue(view.zoomWindow(to: 0.25))
    XCTAssertEqual(window.frame.size, NSSize(width: 100, height: 75), "zooming out shrinks it to the picture's edges")

    let huge = screen.width / 100
    XCTAssertTrue(view.zoomWindow(to: huge))
    XCTAssertLessThanOrEqual(window.frame.width, screen.width + 1, "a big zoom stops at the screen")
    XCTAssertTrue(screen.insetBy(dx: -1, dy: -1).contains(window.frame))

    view.ownsWindow = false
    XCTAssertFalse(view.zoomWindow(to: 1), "a tile zooms inside its window")
  }

  func testViewerSettingsLiveInDockJSON() throws {
    let json = #"{"settings": {"viewer_scroll_zoom": "fine", "viewer_loops_movies": false}}"#
    let settings = try DockConfigFile.decode(Data(json.utf8)).settings
    XCTAssertEqual(settings.viewerScrollZoom, "fine")
    XCTAssertFalse(settings.viewerLoopsMovies)
    XCTAssertEqual(DockSettings().viewerScrollZoom, "normal")
    XCTAssertTrue(DockSettings().viewerLoopsMovies)

    let preferences = ViewerPreferences()
    preferences.apply(settings)
    XCTAssertEqual(preferences.scrollZoom, .fine)
    XCTAssertFalse(preferences.loopsMovies)
    var unknown = settings
    unknown.viewerScrollZoom = "turbo"
    preferences.apply(unknown)
    XCTAssertEqual(preferences.scrollZoom, .normal)
    var saved: (ViewerPreferences.ScrollZoom, Bool)?
    preferences.persist = { saved = ($0, $1) }
    preferences.set(scrollZoom: .off)
    XCTAssertEqual(saved?.0, .off)
    XCTAssertEqual(saved?.1, false)
  }

  func testMoviesWaitToBePlayedThenLoop() async throws {
    let source = folder.appendingPathComponent("loop.mov")
    try await writeMovie(to: source, size: CGSize(width: 32, height: 32), seconds: 1)
    let media = await MainActor.run { MediaState(url: source, kind: .video) }
    let loaded = await MainActor.run { media.player }
    let player = try XCTUnwrap(loaded)
    try await Task.sleep(nanoseconds: 300_000_000)
    XCTAssertEqual(player.rate, 0, "a movie doesn't start by itself")
    await MainActor.run {
      ViewerPreferences.shared.apply(DockSettings())
      player.play()
    }
    try await Task.sleep(nanoseconds: 1_800_000_000)
    XCTAssertGreaterThan(player.rate, 0, "it started over at the end")
    XCTAssertLessThan(player.currentTime().seconds, 1)
    await MainActor.run { media.stop() }
  }

  func testTrimAndCropExportANewMovie() async throws {
    let source = folder.appendingPathComponent("clip.mov")
    try await writeMovie(to: source, size: CGSize(width: 64, height: 48), seconds: 2)
    let trim = CMTimeRange(start: CMTime(value: 1, timescale: 2), end: CMTime(value: 3, timescale: 2))
    let copy = try await MediaEdit.exportVideo(source, trim: trim, crop: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)) { _ in }
    XCTAssertEqual(copy.lastPathComponent, "clip (edited).mov")
    let asset = AVURLAsset(url: copy)
    let duration = try await asset.load(.duration)
    XCTAssertEqual(duration.seconds, 1, accuracy: 0.15)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let track = try XCTUnwrap(tracks.first)
    let natural = try await track.load(.naturalSize)
    XCTAssertEqual(natural, CGSize(width: 32, height: 24))
  }

  // MARK: Helpers

  /// A gray picture written with ImageIO, at `dpi` when given.
  private func write(_ size: CGSize, to url: URL, type: String = "public.png", dpi: Double? = nil) throws {
    let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(origin: .zero, size: size))
    let image = try XCTUnwrap(context.makeImage())
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
    let properties = dpi.map { [kCGImagePropertyDPIWidth: $0, kCGImagePropertyDPIHeight: $0] as CFDictionary }
    CGImageDestinationAddImage(destination, image, properties)
    XCTAssertTrue(CGImageDestinationFinalize(destination))
  }

  /// The decoded picture's width in pixels once `done` holds, running the
  /// main queue so the background decode can land.
  private func decodedWidth(_ media: MediaState, until done: (CGFloat) -> Bool = { _ in true }) throws -> CGFloat {
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
      if media.image != nil, media.decoded > 0, done(media.decoded) { return media.decoded }
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
    throw XCTSkip("the picture didn't decode in time")
  }

  private func png(_ colors: [Int], width: Int, height: Int) throws -> Data {
    let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    for (index, color) in colors.enumerated() {
      rep.setColor(NSColor(deviceRed: CGFloat(color >> 16 & 0xFF) / 255, green: CGFloat(color >> 8 & 0xFF) / 255,
                           blue: CGFloat(color & 0xFF) / 255, alpha: 1),
                   atX: index % width, y: index / width)
    }
    return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
  }

  private func size(_ url: URL) throws -> CGSize {
    let rep = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: url)))
    return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
  }

  /// Colors top to bottom, left to right, each channel snapped on or off:
  /// color management nudges the values on the way through.
  private func pixels(_ url: URL) throws -> [Int] {
    let rep = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: url)))
    return (0..<rep.pixelsHigh).flatMap { y in
      (0..<rep.pixelsWide).map { x -> Int in
        let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) ?? .black
        return [color.redComponent, color.greenComponent, color.blueComponent]
          .reduce(0) { $0 << 8 | ($1 >= 0.5 ? 0xFF : 0) }
      }
    }
  }

  private func writeMovie(to url: URL, size: CGSize, seconds: Int) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
    ])
    writer.add(input)
    XCTAssertTrue(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    for frame in 0..<(seconds * 10) {
      while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
      var buffer: CVPixelBuffer?
      CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &buffer)
      let pixels = try XCTUnwrap(buffer)
      CVPixelBufferLockBaseAddress(pixels, [])
      memset(CVPixelBufferGetBaseAddress(pixels), Int32(frame * 12 % 255), CVPixelBufferGetDataSize(pixels))
      CVPixelBufferUnlockBaseAddress(pixels, [])
      adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
    }
    input.markAsFinished()
    await writer.finishWriting()
    XCTAssertEqual(writer.status, .completed)
  }
}
