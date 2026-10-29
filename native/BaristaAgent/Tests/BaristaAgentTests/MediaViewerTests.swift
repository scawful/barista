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
    let media = MediaState()
    XCTAssertNil(media.load(sprite, kind: .image, fresh: true))
    XCTAssertTrue(media.pixelated, "a small PNG is pixel art")
    var requests: [CGSize] = []
    media.resize = { if case .exact(let size) = $0 { requests.append(size) } }
    media.magnify(by: 1)
    XCTAssertEqual(media.zoom, .scale(2))
    XCTAssertEqual(requests, [CGSize(width: 32, height: 32)], "the window grows to the zoomed picture")
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
