import AVFoundation
import AVKit
import AppKit
import CoreImage
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Crops, turns, and the copies they save. Rects are fractions of the
/// picture as shown, origin top left, so one crop fits any pixel size.
enum MediaEdit {
  static let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
  static let minimum: CGFloat = 0.02

  struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }

  /// `rect` after dragging a handle by `delta`. `handle` says which edges
  /// move, -1 for the left or top and 1 for the right or bottom per axis;
  /// (0, 0) moves the whole rect.
  static func adjust(_ rect: CGRect, handle: (x: Int, y: Int), by delta: CGSize) -> CGRect {
    if handle.x == 0 && handle.y == 0 {
      return CGRect(x: min(max(rect.minX + delta.width, 0), 1 - rect.width),
                    y: min(max(rect.minY + delta.height, 0), 1 - rect.height),
                    width: rect.width, height: rect.height)
    }
    var (minX, maxX, minY, maxY) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
    if handle.x < 0 { minX = min(max(minX + delta.width, 0), maxX - minimum) }
    if handle.x > 0 { maxX = max(min(maxX + delta.width, 1), minX + minimum) }
    if handle.y < 0 { minY = min(max(minY + delta.height, 0), maxY - minimum) }
    if handle.y > 0 { maxY = max(min(maxY + delta.height, 1), minY + minimum) }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  /// `rect` on the picture turned clockwise by quarter turns.
  static func turn(_ rect: CGRect, quarterTurns: Int) -> CGRect {
    var rect = rect
    for _ in 0..<((quarterTurns % 4 + 4) % 4) {
      rect = CGRect(x: 1 - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
    }
    return rect
  }

  static func isWhole(_ rect: CGRect) -> Bool { rect.width > 0.999 && rect.height > 0.999 }

  /// `crop` in whole pixels of a picture `size` pixels big.
  static func pixels(_ crop: CGRect, in size: CGSize) -> CGRect {
    CGRect(x: (crop.minX * size.width).rounded(), y: (crop.minY * size.height).rounded(),
           width: (crop.width * size.width).rounded(), height: (crop.height * size.height).rounded())
      .intersection(CGRect(origin: .zero, size: size))
  }

  /// Where a picture `size` big sits when fitted, centered, into `bounds`.
  static func fitted(_ size: CGSize, in bounds: CGSize) -> CGRect {
    guard size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: bounds) }
    let scale = min(bounds.width / size.width, bounds.height / size.height)
    let shown = CGSize(width: size.width * scale, height: size.height * scale)
    return CGRect(x: (bounds.width - shown.width) / 2, y: (bounds.height - shown.height) / 2,
                  width: shown.width, height: shown.height)
  }

  /// "clip (edited).mov" beside `url`, or "clip (edited 2).mov" when that's
  /// taken; editing a copy again doesn't stack the suffix.
  static func copyURL(for url: URL, ext: String) -> URL {
    let folder = url.deletingLastPathComponent()
    let stem = url.deletingPathExtension().lastPathComponent
      .replacingOccurrences(of: #" \(edited( \d+)?\)$"#, with: "", options: .regularExpression)
    var number = 1
    while true {
      let name = number == 1 ? "\(stem) (edited)" : "\(stem) (edited \(number))"
      let candidate = folder.appendingPathComponent(name).appendingPathExtension(ext)
      if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
      number += 1
    }
  }

  /// `image` turned clockwise by quarter turns.
  static func rotate(_ image: CGImage, quarterTurns: Int) -> CGImage? {
    let turns = (quarterTurns % 4 + 4) % 4
    guard turns != 0 else { return image }
    let (width, height) = (image.width, image.height)
    let (outWidth, outHeight) = turns % 2 == 0 ? (width, height) : (height, width)
    let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.interpolationQuality = .none
    // Quartz's y axis points up, so clockwise is a negative angle.
    context.translateBy(x: CGFloat(outWidth) / 2, y: CGFloat(outHeight) / 2)
    context.rotate(by: -CGFloat(turns) * .pi / 2)
    context.draw(image, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2,
                                   width: CGFloat(width), height: CGFloat(height)))
    return context.makeImage()
  }

  /// The picture at `maxPixels` on its longest side at most, upright, or
  /// whole when nil, and the longest side it got. Animations and drawings
  /// load whole so they keep playing and stay sharp. Blocking.
  static func decode(_ url: URL, header: ImageHeader, maxPixels: CGFloat?) -> (image: NSImage, pixels: CGFloat)? {
    if header.frames > 1 || header.drawn {
      return NSImage(contentsOf: url).map { ($0, header.drawn ? .infinity : max(header.pixels.width, header.pixels.height)) }
    }
    return upright(url, header: header, maxPixels: maxPixels)
      .map { (NSImage(cgImage: $0, size: header.points), CGFloat(max($0.width, $0.height))) }
  }

  /// The first frame's pixels, upright, at most `maxPixels` on the longest side. Blocking.
  static func upright(_ url: URL, header: ImageHeader, maxPixels: CGFloat?) -> CGImage? {
    if header.drawn {
      var rect = CGRect(origin: .zero, size: header.pixels)
      return NSImage(contentsOf: url)?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
    let longest = max(header.pixels.width, header.pixels.height)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
    else { return nil }
    // The thumbnail is the only ImageIO call that applies EXIF orientation.
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: Int(min(maxPixels ?? longest, longest)),
    ] as CFDictionary)
  }

  /// The whole picture upright, turned, and cropped. Blocking.
  static func render(_ url: URL, rotation: Int, crop: CGRect?) throws -> CGImage {
    guard let header = ImageHeader.read(url),
          let picture = upright(url, header: header, maxPixels: nil),
          var image = rotate(picture, quarterTurns: rotation)
    else { throw Failure("Can't read \(url.lastPathComponent).") }
    if let crop {
      guard let cropped = image.cropping(to: pixels(crop, in: CGSize(width: image.width, height: image.height)))
      else { throw Failure("The crop is outside the picture.") }
      image = cropped
    }
    return image
  }

  /// Writes the turned and cropped picture next to `url`, in its format when
  /// ImageIO can write that and as PNG otherwise. Blocking.
  static func writeImage(_ url: URL, rotation: Int, crop: CGRect?) throws -> URL {
    let image = try render(url, rotation: rotation, crop: crop)
    let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
    let kept = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(CGImageSourceGetType)
      .map { $0 as String }.flatMap { writable.contains($0) ? $0 : nil }
    let copy = copyURL(for: url, ext: kept == nil ? "png" : url.pathExtension)
    guard let destination = CGImageDestinationCreateWithURL(copy as CFURL, (kept ?? UTType.png.identifier) as CFString,
                                                            1, nil)
    else { throw Failure("Can't write \(copy.lastPathComponent).") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw Failure("Can't write \(copy.lastPathComponent).") }
    return copy
  }

  /// Exports the trimmed and cropped movie next to `url`. A trim alone
  /// copies the samples as they are; a crop re-encodes.
  static func exportVideo(_ url: URL, trim: CMTimeRange?, crop: CGRect?,
                          progress: @escaping (Float) -> Void) async throws -> URL {
    let asset = AVURLAsset(url: url)
    var composition: AVVideoComposition?
    if let crop {
      guard let track = try await asset.loadTracks(withMediaType: .video).first
      else { throw Failure("\(url.lastPathComponent) has no video.") }
      let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
      let turned = natural.applying(transform)
      let size = CGSize(width: abs(turned.width), height: abs(turned.height))
      var area = pixels(crop, in: size)
      // Encoders want even dimensions.
      area.size = CGSize(width: max(2, floor(area.width / 2) * 2), height: max(2, floor(area.height / 2) * 2))
      let flipped = CGRect(x: area.minX, y: size.height - area.maxY, width: area.width, height: area.height)
      let video = try await AVMutableVideoComposition.videoComposition(with: asset) { request in
        let image = request.sourceImage.cropped(to: flipped)
          .transformed(by: CGAffineTransform(translationX: -flipped.minX, y: -flipped.minY))
        request.finish(with: image, context: nil)
      }
      video.renderSize = area.size
      composition = video
    }
    let preset = composition == nil ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
    guard let session = AVAssetExportSession(asset: asset, presetName: preset)
    else { throw Failure("Can't export \(url.lastPathComponent).") }
    let ext = url.pathExtension.lowercased()
    let fileType: AVFileType = ["mp4", "m4v"].contains(ext) ? .mp4 : .mov
    let copy = copyURL(for: url, ext: fileType == .mp4 ? ext : "mov")
    session.outputURL = copy
    session.outputFileType = fileType
    session.videoComposition = composition
    if let trim { session.timeRange = trim }
    // `progress` is safe to read from any thread.
    nonisolated(unsafe) let watched = session
    let timer = Timer(timeInterval: 0.25, repeats: true) { _ in progress(watched.progress) }
    RunLoop.main.add(timer, forMode: .common)
    await session.export()
    timer.invalidate()
    if let error = session.error { throw error }
    guard session.status == .completed else { throw Failure("The export stopped.") }
    return copy
  }
}

/// What a picture file says about itself before its pixels are decoded.
struct ImageHeader: Equatable {
  /// Upright, after the EXIF orientation.
  let pixels: CGSize
  /// The size AppKit draws it at: Retina screenshots at half their pixels.
  let points: CGSize
  let frames: Int
  /// A format only AppKit draws, like SVG; it has no pixels to downsample.
  var drawn = false

  static func read(_ url: URL) -> ImageHeader? {
    if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
       let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
       let width = properties[kCGImagePropertyPixelWidth] as? Int,
       let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 {
      let sideways = (5...8).contains(properties[kCGImagePropertyOrientation] as? Int ?? 1)
      let pixels = sideways ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
      let dpi = properties[kCGImagePropertyDPIWidth] as? Double ?? 72
      let scale = (72...288).contains(dpi) ? 72 / dpi : 1
      return ImageHeader(pixels: pixels,
                         points: CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded()),
                         frames: CGImageSourceGetCount(source))
    }
    guard let drawing = NSImage(contentsOf: url), drawing.size.width > 0, drawing.size.height > 0 else { return nil }
    return ImageHeader(pixels: drawing.size, points: drawing.size, frames: 1, drawn: true)
  }
}

/// How tiles share a window.
enum TileLayout: String, CaseIterable, Identifiable {
  /// Rows and columns, however many fit 4:3 pictures biggest.
  case grid
  case row
  case column
  /// The active tile big, the others in a strip beside or below it.
  case main
  /// Rows of tiles as wide as their pictures' shapes, without bars.
  case shapes

  var id: String { rawValue }

  var title: String {
    switch self {
    case .grid: return "Grid"
    case .row: return "Side by Side"
    case .column: return "Stacked"
    case .main: return "Main and Strip"
    case .shapes: return "By Shape"
    }
  }
}

/// Where tiles go in a window. A short last row is centered.
enum TileGrid {
  static let gap: CGFloat = 2

  /// `active` is the main tile's index; `aspects` are the pictures' widths
  /// over their heights, for `shapes`.
  static func frames(count: Int, in size: CGSize, layout: TileLayout = .grid, active: Int = 0,
                     aspects: [CGFloat] = []) -> [CGRect] {
    guard count > 1 else { return count == 1 ? [CGRect(origin: .zero, size: size)] : [] }
    switch layout {
    case .grid:
      return grid(count, in: size, columns: (1...count).max { a, b in
        let (one, other) = (cell(count, in: size, columns: a), cell(count, in: size, columns: b))
        return min(one.width, one.height * 4 / 3) < min(other.width, other.height * 4 / 3)
      } ?? 1)
    case .row:
      return grid(count, in: size, columns: count)
    case .column:
      return grid(count, in: size, columns: 1)
    case .main:
      return main(count, in: size, active: min(max(active, 0), count - 1))
    case .shapes:
      return shapes((0..<count).map { $0 < aspects.count && aspects[$0] > 0 ? aspects[$0] : 4.0 / 3 }, in: size)
    }
  }

  private static func cell(_ count: Int, in size: CGSize, columns: Int) -> CGSize {
    let rows = (count + columns - 1) / columns
    return CGSize(width: max((size.width - gap * CGFloat(columns - 1)) / CGFloat(columns), 1),
                  height: max((size.height - gap * CGFloat(rows - 1)) / CGFloat(rows), 1))
  }

  /// A quarter of the window's longer side holds the others.
  private static func main(_ count: Int, in size: CGSize, active: Int) -> [CGRect] {
    let wide = size.width >= size.height
    let strip = ((wide ? size.width : size.height) - gap) / 4
    let others = wide
      ? grid(count - 1, in: CGSize(width: strip, height: size.height), columns: 1)
        .map { $0.offsetBy(dx: size.width - strip, dy: 0) }
      : grid(count - 1, in: CGSize(width: size.width, height: strip), columns: count - 1)
        .map { $0.offsetBy(dx: 0, dy: size.height - strip) }
    var frames = others
    frames.insert(CGRect(x: 0, y: 0, width: wide ? size.width - strip - gap : size.width,
                         height: wide ? size.height : size.height - strip - gap), at: active)
    return frames
  }

  /// Rows in order, each tile as wide as its shape at its row's height and
  /// each row as wide as the window, scaled down to fit the height. Tries
  /// every count of rows and keeps the one that shows the most picture.
  private static func shapes(_ aspects: [CGFloat], in size: CGSize) -> [CGRect] {
    var best: (area: CGFloat, frames: [CGRect]) = (-1, [])
    for rows in 1...aspects.count {
      let groups = split(aspects, into: rows)
      let heights = groups.map { max(size.width - gap * CGFloat($0.count - 1), 1) / $0.reduce(0, +) }
      let gaps = gap * CGFloat(groups.count - 1)
      let scale = min(1, max(size.height - gaps, 1) / heights.reduce(0, +))
      var y = (size.height - heights.reduce(0, +) * scale - gaps) / 2
      var frames: [CGRect] = []
      for (group, height) in zip(groups, heights) {
        let tall = height * scale
        var x = (size.width - group.reduce(0) { $0 + $1 * tall } - gap * CGFloat(group.count - 1)) / 2
        for aspect in group {
          frames.append(CGRect(x: x, y: y, width: aspect * tall, height: tall))
          x += aspect * tall + gap
        }
        y += tall + gap
      }
      let area = frames.reduce(0) { $0 + $1.width * $1.height }
      if area > best.area { best = (area, frames) }
    }
    return best.frames
  }

  /// Splits in order into up to `rows` runs whose shapes add up about evenly.
  private static func split(_ aspects: [CGFloat], into rows: Int) -> [[CGFloat]] {
    let target = aspects.reduce(0, +) / CGFloat(rows)
    var groups: [[CGFloat]] = [[]]
    var sum: CGFloat = 0
    for (index, aspect) in aspects.enumerated() {
      let rowsLeft = rows - groups.count
      if !groups[groups.count - 1].isEmpty, rowsLeft > 0,
         sum + aspect / 2 > target || aspects.count - index == rowsLeft {
        groups.append([])
        sum = 0
      }
      groups[groups.count - 1].append(aspect)
      sum += aspect
    }
    return groups
  }

  private static func grid(_ count: Int, in size: CGSize, columns: Int) -> [CGRect] {
    let rows = (count + columns - 1) / columns
    let tile = cell(count, in: size, columns: columns)
    return (0..<count).map { index in
      let (row, column) = (index / columns, index % columns)
      let inRow = row == rows - 1 ? count - row * columns : columns
      let inset = (size.width - CGFloat(inRow) * tile.width - gap * CGFloat(inRow - 1)) / 2
      return CGRect(x: inset + CGFloat(column) * (tile.width + gap), y: CGFloat(row) * (tile.height + gap),
                    width: tile.width, height: tile.height)
    }
  }
}

/// One picture or movie in a viewer window: its file, zoom and turn, the
/// crop and trim being made, and what part of it the window shows. Used on
/// the main thread only; background work hands results back there.
final class MediaState: ObservableObject, Identifiable, @unchecked Sendable {
  enum Zoom: Equatable {
    /// This part of the picture, in fractions with the origin top left, as big as fits.
    case region(CGRect)
    /// This multiple, centered on a point of the picture in fractions.
    case focus(CGFloat, CGPoint)
    /// This multiple wherever the picture is scrolled: after a pinch, a
    /// scroll, a pan, or a resize.
    case scale(CGFloat)

    static let fit = Zoom.region(MediaEdit.whole)
  }

  /// A content size for the window; the controller fits it to the screen.
  enum Resize {
    /// A newly opened file, at its own size up to most of the screen.
    case natural(CGSize)
    /// Stepping to another file: its shape at about the window's width.
    case sameWidth(CGSize)
    /// A zoom: exactly this big, or the screen when that's smaller.
    case exact(CGSize)
  }

  struct InfoRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
    init(_ label: String, _ value: String) {
      self.label = label
      self.value = value
    }
  }

  static let steps: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8, 12, 16]
  /// Whole multiples keep every pixel the same size.
  static let pixelSteps: [CGFloat] = [0.25, 0.5, 1, 2, 3, 4, 5, 6, 8, 10, 12, 16]

  /// The longest side, in pixels, pictures decode at until a zoom needs more.
  static var screenPixels: CGFloat {
    NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 3024
  }

  @Published private(set) var url: URL
  @Published private(set) var kind: ViewerKind
  @Published private(set) var error: String?
  /// Position among the folder's files the arrow keys reach, for "3 of 12".
  @Published private(set) var position: (index: Int, count: Int)?
  @Published var zoom = Zoom.fit
  /// What the picture is drawn at now, fitted or not, for the readout.
  @Published private(set) var scale: CGFloat = 1
  @Published var pixelated = false
  /// Quarter turns clockwise.
  @Published private(set) var rotation = 0
  @Published private(set) var image: NSImage?
  @Published private(set) var player: AVPlayer?
  /// The picture or frame as shown, in points, and in pixels.
  @Published private(set) var size: CGSize?
  @Published private(set) var pixelSize: CGSize?
  @Published private(set) var info: [InfoRow] = []
  @Published private(set) var openers: [URL] = []
  @Published var showsInfo = false {
    didSet { if showsInfo { loadInfo() } }
  }
  @Published private(set) var cropping = false
  @Published var crop = MediaEdit.whole
  /// A crop waiting for Save Copy, from Crop to View or the crop handles.
  @Published private(set) var applied: CGRect?
  /// Some of the picture is outside the window: zoomed in, or cut off by a resize.
  @Published private(set) var viewIsPartial = false
  @Published fileprivate(set) var trimming = false
  @Published private(set) var trim: CMTimeRange?
  @Published private(set) var status: String?

  var resize: ((Resize) -> Void)?
  /// Zooms the shown picture and sizes its window around it; false when
  /// the picture shares its window.
  var zoomWindow: ((CGFloat) -> Bool)?
  /// The tile shows another file: stepped to, or a saved copy.
  var onShow: ((URL) -> Void)?
  fileprivate var beginTrim: (() -> Void)?

  /// The part of the picture in the window, in fractions, origin top left.
  private(set) var view = MediaEdit.whole
  private var header: ImageHeader?
  private var original: NSImage?
  /// The longest side the picture is decoded at; 0 while it isn't.
  private(set) var decoded: CGFloat = 0
  /// The longest side a picture decodes at until a zoom needs more: a
  /// screen's worth, shared among the tiles in a row.
  private let baseLimit: CGFloat
  /// The longest side last asked of the decoder.
  private var requested: CGFloat = 0
  private var generation = 0
  private var sized = false
  private var saving = false
  private var suspended = false
  private var resumeAt: CMTime?
  private var beforeCrop: Zoom?
  private var watcher: FileWatcher?
  private var endObserver: NSObjectProtocol?

  var isVideo: Bool { kind == .video }
  var hasEdits: Bool { rotation != 0 || trim != nil || applied != nil }
  var isFitted: Bool {
    if case .region = zoom { return true }
    return false
  }

  /// `tiles` is how many share the window as it opens.
  init(url: URL, kind: ViewerKind, tiles: Int = 1) {
    self.url = url
    self.kind = kind
    baseLimit = Self.screenPixels / Double(max(tiles, 1)).squareRoot().rounded(.up)
    load(fresh: true)
  }

  deinit {
    endObserver.map(NotificationCenter.default.removeObserver)
  }

  /// The same file changed on disk; zoom and edits stay.
  func reload() { load(fresh: false) }

  func step(_ offset: Int) {
    let siblings = ViewerKind.siblings(of: url)
    guard siblings.count > 1, let index = siblings.firstIndex(of: url) else { return }
    show(siblings[(index + offset + siblings.count) % siblings.count])
  }

  func show(_ next: URL) {
    guard let kind = ViewerKind.of(next), kind.isMedia else { return }
    url = next
    self.kind = kind
    load(fresh: true)
    onShow?(next)
  }

  private func load(fresh: Bool) {
    guard fresh || !suspended else { return }
    generation += 1
    if fresh {
      zoom = .fit
      rotation = 0
      cropping = false
      crop = MediaEdit.whole
      applied = nil
      trim = nil
      openers = []
      info = []
      view = MediaEdit.whole
      viewIsPartial = false
      decoded = 0
      watcher = FileWatcher(url: url) { [weak self] in self?.reload() }
      let siblings = ViewerKind.siblings(of: url)
      position = siblings.firstIndex(of: url).map { ($0 + 1, siblings.count) }
    }
    if isVideo { loadMovie(fresh: fresh) } else { loadPicture(fresh: fresh) }
    if showsInfo { loadInfo() }
  }

  private func loadMovie(fresh: Bool) {
    // A recording still being written changes on every write.
    guard fresh || player == nil else { return }
    header = nil
    original = nil
    image = nil
    error = nil
    player?.pause()
    let player = AVPlayer(url: url)
    player.actionAtItemEnd = .pause
    self.player = player
    watchEnd(of: player.currentItem)
    loadVideo(url, generation: generation, fresh: fresh)
  }

  private func loadPicture(fresh: Bool) {
    player?.pause()
    player = nil
    watchEnd(of: nil)
    guard let header = ImageHeader.read(url) else {
      self.header = nil
      original = nil
      image = nil
      error = "Can't open \(url.lastPathComponent) as an image."
      return
    }
    error = nil
    self.header = header
    info = []
    if fresh {
      pixelated = Self.looksLikePixelArt(url, header)
      // The last file's picture would show at this one's shape until it decodes.
      original = nil
      image = nil
    }
    geometry()
    decode(limit: fresh ? baseLimit : max(requested, baseLimit))
    if fresh, let size { place(size) }
  }

  /// Pauses and releases the player, for a closed window or tile.
  func stop() {
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    watchEnd(of: nil)
    watcher = nil
  }

  func pause() {
    player?.pause()
  }

  /// Lets go of the pixels and the movie's decoder until `resume`, for a
  /// minimized window or one out of sight under memory pressure.
  func suspend() {
    guard !suspended else { return }
    suspended = true
    generation += 1
    if let player {
      resumeAt = player.currentTime()
      player.pause()
      player.replaceCurrentItem(with: nil)
      watchEnd(of: nil)
    }
    original = nil
    image = nil
    decoded = 0
    requested = 0
  }

  func resume() {
    guard suspended else { return }
    suspended = false
    guard let player else { return decode(limit: baseLimit) }
    let item = AVPlayerItem(url: url)
    if let trim {
      item.reversePlaybackEndTime = trim.start
      item.forwardPlaybackEndTime = trim.end
    }
    player.replaceCurrentItem(with: item)
    watchEnd(of: item)
    if let resumeAt { player.seek(to: resumeAt, toleranceBefore: .zero, toleranceAfter: .zero) }
  }

  /// Under memory pressure: back to the pixels it opened with.
  func shedPixels() {
    guard !isVideo, !suspended, requested > baseLimit else { return }
    decode(limit: baseLimit)
  }

  // MARK: Zoom

  func magnify(by direction: Int) {
    guard !isVideo else { return }
    let steps = pixelated ? Self.pixelSteps : Self.steps
    let next = direction > 0 ? steps.first { $0 > scale + 0.01 } : steps.last { $0 < scale - 0.01 }
    if let next { magnify(to: next) }
  }

  /// A multiple of the picture's size about the middle of what shows; the
  /// window grows or shrinks with it.
  func magnify(to scale: CGFloat) {
    guard let size, !cropping else { return }
    guard !isVideo else { return resize?(.exact(CGSize(width: size.width * scale, height: size.height * scale))) ?? () }
    if zoomWindow?(scale) == true { return }
    zoom = .focus(scale, CGPoint(x: view.midX, y: view.midY))
    resize?(.exact(CGSize(width: size.width * view.width * scale, height: size.height * view.height * scale)))
  }

  /// The whole picture, or the crop waiting to be saved, and the window takes its shape.
  func fit() {
    guard let size else { return }
    let region = isVideo ? MediaEdit.whole : applied ?? MediaEdit.whole
    zoom = .region(region)
    resize?(.sameWidth(CGSize(width: size.width * region.width, height: size.height * region.height)))
  }

  func toggleActualSize() {
    if isFitted { magnify(to: 1) } else { fit() }
  }

  /// The picture is drawn at `scale` on a screen with `backing` pixels per
  /// point; past the decoded pixels, it decodes again with room to zoom.
  func shown(at scale: CGFloat, backing: CGFloat) {
    if abs(self.scale - scale) > 0.001 { self.scale = scale }
    guard let header, let size, decoded > 0 else { return }
    let longest = max(header.pixels.width, header.pixels.height)
    let needed = scale * backing * max(size.width, size.height)
    guard requested < longest, needed > requested * 1.05 else { return }
    decode(limit: min(longest, max(needed * 1.25, baseLimit)))
  }

  /// The window shows `rect` of the picture.
  func viewed(_ rect: CGRect) {
    view = rect
    let partial = !MediaEdit.isWhole(rect)
    if partial != viewIsPartial { viewIsPartial = partial }
  }

  // MARK: Edits

  func rotate(_ quarterTurns: Int) {
    guard !isVideo, header != nil, !cropping else { return }
    rotation = (rotation + quarterTurns + 4) % 4
    applied = applied.map { MediaEdit.turn($0, quarterTurns: quarterTurns) }
    geometry()
    render()
    fit()
  }

  /// Shows the handles over the whole picture, starting from the crop
  /// waiting to be saved or else the part the window showed.
  func beginCrop() {
    guard size != nil, !trimming, !cropping else { return }
    beforeCrop = isVideo ? nil : .region(view)
    crop = applied ?? (viewIsPartial && !isVideo ? view : MediaEdit.whole)
    zoom = .fit
    cropping = true
  }

  func cancelCrop() {
    guard cropping else { return }
    cropping = false
    if let beforeCrop { zoom = beforeCrop }
  }

  /// Keeps the handles' crop for Save Copy and shows just that part.
  func applyCrop() {
    guard cropping else { return }
    cropping = false
    applied = MediaEdit.isWhole(crop) ? nil : crop
    fit()
  }

  /// Keeps the part of the picture in the window as the crop for Save Copy.
  func cropToView() {
    guard !isVideo, !cropping, viewIsPartial else { return }
    applied = view
    let area = MediaEdit.pixels(view, in: pixelSize ?? .zero)
    show(status: "Crop \(Int(area.width)) × \(Int(area.height)): Save Copy keeps it")
  }

  func clearCrop() {
    applied = nil
  }

  func beginTrimming() {
    guard isVideo, !cropping else { return }
    beginTrim?()
  }

  fileprivate func trimmed(_ range: CMTimeRange?) {
    trimming = false
    if let range { trim = range }
  }

  func togglePlayback() {
    guard let player else { return }
    if player.timeControlStatus == .playing { player.pause() } else { player.play() }
  }

  /// Writes the turn, crop, and trim to a new file beside this one, then
  /// shows that file.
  func saveCopy() {
    if cropping { applyCrop() }
    guard hasEdits, !saving else { return }
    let (url, area) = (url, applied)
    saving = true
    show(status: "Saving…", clears: false)
    if isVideo {
      let trim = trim
      Task { [weak self] in
        let result: Result<URL, Error>
        do {
          result = .success(try await MediaEdit.exportVideo(url, trim: trim, crop: area) { fraction in
            self?.show(status: "Saving… \(Int(fraction * 100))%", clears: false)
          })
        } catch {
          result = .failure(error)
        }
        DispatchQueue.main.async { self?.saved(result) }
      }
    } else {
      let rotation = rotation
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let result = Result { try MediaEdit.writeImage(url, rotation: rotation, crop: area) }
        DispatchQueue.main.async { self?.saved(result) }
      }
    }
  }

  private func saved(_ result: Result<URL, Error>) {
    saving = false
    switch result {
    case .success(let copy):
      show(copy)
      show(status: "Saved \(copy.lastPathComponent)")
    case .failure(let error):
      show(status: "Couldn't save: \(error.localizedDescription)")
    }
  }

  /// The picture with its edits at full size, or the movie file.
  func copy() {
    NSPasteboard.general.clearContents()
    if !isVideo, let image = try? MediaEdit.render(url, rotation: rotation, crop: applied) {
      NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
      show(status: "Copied image")
    } else {
      NSPasteboard.general.writeObjects([url as NSURL])
      show(status: "Copied file")
    }
  }

  func show(status: String, clears: Bool = true) {
    self.status = status
    guard clears else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      if self?.status == status { self?.status = nil }
    }
  }

  /// Apps for the Open With menu, looked up when the bar first shows.
  func loadOpeners() {
    if openers.isEmpty { openers = DefaultApps.choices(for: url) }
  }

  // MARK: Loading

  private func place(_ size: CGSize) {
    resize?(sized ? .sameWidth(size) : .natural(size))
    sized = true
  }

  private func geometry() {
    guard let header else { return }
    let turned = { (size: CGSize) in self.rotation % 2 == 0 ? size : CGSize(width: size.height, height: size.width) }
    size = turned(header.points)
    pixelSize = turned(header.pixels)
  }

  private func decode(limit: CGFloat) {
    guard let header else { return }
    requested = limit
    generation += 1
    let (url, generation) = (url, generation)
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let picture = MediaEdit.decode(url, header: header, maxPixels: limit)
      DispatchQueue.main.async {
        guard let self, self.generation == generation else { return }
        guard let picture else {
          self.error = "Can't open \(url.lastPathComponent) as an image."
          return
        }
        self.decoded = picture.pixels
        self.original = picture.image
        self.render()
      }
    }
  }

  private func render() {
    guard let original, let size else { return }
    if rotation == 0 {
      image = original
    } else if let source = original.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rotated = MediaEdit.rotate(source, quarterTurns: rotation) {
      image = NSImage(cgImage: rotated, size: size)
    }
  }

  private func watchEnd(of item: AVPlayerItem?) {
    endObserver.map(NotificationCenter.default.removeObserver)
    endObserver = item.map { item in
      NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item,
                                             queue: .main) { [weak self] _ in self?.ended() }
    }
  }

  /// Starts over from the trim's start, when movies loop.
  private func ended() {
    guard ViewerPreferences.shared.loopsMovies, let player, let item = player.currentItem else { return }
    let start = item.reversePlaybackEndTime.isNumeric ? item.reversePlaybackEndTime : .zero
    player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero) { [weak player] finished in
      guard finished else { return }
      DispatchQueue.main.async { player?.play() }
    }
  }

  private func loadVideo(_ url: URL, generation: Int, fresh: Bool) {
    Task { [weak self] in
      let asset = AVURLAsset(url: url)
      var rows: [InfoRow] = []
      var shown: CGSize?
      if let track = try? await asset.loadTracks(withMediaType: .video).first,
         let loaded = try? await track.load(.naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions) {
        let turned = loaded.0.applying(loaded.1)
        let size = CGSize(width: abs(turned.width), height: abs(turned.height))
        shown = size
        rows.append(InfoRow("Size", "\(Int(size.width)) × \(Int(size.height)) px"))
        if loaded.2 > 0 { rows.append(InfoRow("Frame Rate", String(format: "%.3g fps", loaded.2))) }
        if let format = loaded.3.first { rows.append(InfoRow("Video", Self.codec(CMFormatDescriptionGetMediaSubType(format)))) }
      }
      if let duration = try? await asset.load(.duration), duration.isNumeric {
        rows.append(InfoRow("Duration", Self.clock(duration.seconds)))
      }
      if let audio = try? await asset.loadTracks(withMediaType: .audio).first,
         let format = try? await audio.load(.formatDescriptions).first {
        rows.append(InfoRow("Audio", Self.codec(CMFormatDescriptionGetMediaSubType(format))))
      }
      let file = Self.fileRows(url)
      DispatchQueue.main.async {
        guard let self, self.url == url else { return }
        self.info = rows + file
        guard let shown, self.generation == generation else { return }
        self.size = shown
        self.pixelSize = shown
        if fresh { self.place(shown) }
      }
    }
  }

  /// Picture info is read when the panel opens; a movie's comes with its size.
  private func loadInfo() {
    guard !isVideo, info.isEmpty else { return }
    info = Self.imageInfo(url)
  }

  /// Small lossless pictures are sprites, tiles, and emulator captures.
  private static func looksLikePixelArt(_ url: URL, _ header: ImageHeader) -> Bool {
    guard !header.drawn, max(header.pixels.width, header.pixels.height) <= 1024,
          let type = UTType(filenameExtension: url.pathExtension) else { return false }
    return type.conforms(to: .png) || type.conforms(to: .gif) || type.conforms(to: .bmp)
  }

  private static func imageInfo(_ url: URL) -> [InfoRow] {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return fileRows(url) }
    var rows: [InfoRow] = []
    if let width = properties[kCGImagePropertyPixelWidth] as? Int,
       let height = properties[kCGImagePropertyPixelHeight] as? Int {
      rows.append(InfoRow("Size", "\(width) × \(height) px"))
    }
    let frames = CGImageSourceGetCount(source)
    if frames > 1 { rows.append(InfoRow("Frames", "\(frames)")) }
    var color = [properties[kCGImagePropertyColorModel] as? String, properties[kCGImagePropertyProfileName] as? String]
      .compactMap { $0 }
    if let depth = properties[kCGImagePropertyDepth] as? Int { color.append("\(depth)-bit") }
    if properties[kCGImagePropertyHasAlpha] as? Bool == true { color.append("alpha") }
    if !color.isEmpty { rows.append(InfoRow("Color", color.joined(separator: ", "))) }
    if let dpi = properties[kCGImagePropertyDPIWidth] as? Double { rows.append(InfoRow("Resolution", "\(Int(dpi.rounded())) dpi")) }
    return rows + fileRows(url)
  }

  private static func fileRows(_ url: URL) -> [InfoRow] {
    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .localizedTypeDescriptionKey, .contentModificationDateKey])
    var rows: [InfoRow] = []
    if let kind = values?.localizedTypeDescription { rows.append(InfoRow("Kind", kind)) }
    if let bytes = values?.fileSize { rows.append(InfoRow("File", ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))) }
    if let modified = values?.contentModificationDate {
      rows.append(InfoRow("Modified", modified.formatted(date: .abbreviated, time: .shortened)))
    }
    return rows
  }

  static func codec(_ code: FourCharCode) -> String {
    let known: [FourCharCode: String] = [
      kCMVideoCodecType_H264: "H.264", kCMVideoCodecType_HEVC: "HEVC",
      kCMVideoCodecType_AppleProRes422: "ProRes 422", kCMVideoCodecType_AppleProRes4444: "ProRes 4444",
      kAudioFormatMPEG4AAC: "AAC", kAudioFormatLinearPCM: "PCM",
    ]
    if let name = known[code] { return name }
    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
    return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
  }

  static func clock(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    return total >= 3600
      ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
      : String(format: "%d:%02d", total / 60, total % 60)
  }
}

/// The right-click menu for a tile: what its bar and keys do, and with
/// several tiles, how they share the window. Shortcuts show as hints.
enum MediaMenu {
  static func make(model: ViewerModel, media: MediaState) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    func add(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [], on: Bool = false,
             to target: NSMenu? = nil, _ perform: @escaping () -> Void) {
      let item = MenuChoice.item(title, perform: perform)
      item.keyEquivalent = key
      item.keyEquivalentModifierMask = modifiers
      item.state = on ? .on : .off
      (target ?? menu).addItem(item)
    }
    func submenu(_ title: String) -> NSMenu {
      let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      holder.submenu = NSMenu(title: title)
      menu.addItem(holder)
      return holder.submenu!
    }

    if media.cropping {
      add("Apply Crop", "\r") { media.applyCrop() }
      add("Cancel Crop", "\u{1b}") { media.cancelCrop() }
      return menu
    }
    let preferences = ViewerPreferences.shared
    if media.isVideo {
      add(media.player?.timeControlStatus == .playing ? "Pause" : "Play", " ") { media.togglePlayback() }
      add("Loop Movies", on: preferences.loopsMovies) { preferences.set(loopsMovies: !preferences.loopsMovies) }
      menu.addItem(.separator())
      add("Trim…", "t") { media.beginTrimming() }
    } else {
      add("Zoom to Fit", "0") { media.fit() }
      add("Actual Size", "1") { media.magnify(to: 1) }
      add("Zoom In", "+") { media.magnify(by: 1) }
      add("Zoom Out", "-") { media.magnify(by: -1) }
      add("Sharp Pixels", "p", on: media.pixelated) { media.pixelated.toggle() }
      let scroll = submenu("Scroll to Zoom")
      for choice in ViewerPreferences.ScrollZoom.allCases {
        add(choice.title, on: preferences.scrollZoom == choice, to: scroll) { preferences.set(scrollZoom: choice) }
      }
      menu.addItem(.separator())
      add("Rotate Left", "r", .shift) { media.rotate(-1) }
      add("Rotate Right", "r") { media.rotate(1) }
    }
    add("Crop…", "c") { media.beginCrop() }
    if !media.isVideo, media.viewIsPartial { add("Crop to View", "c", .shift) { media.cropToView() } }
    if media.applied != nil { add("Remove Crop") { media.clearCrop() } }
    if media.hasEdits { add("Save Copy", "s", .command) { media.saveCopy() } }
    menu.addItem(.separator())
    add(media.isVideo ? "Copy File" : "Copy Image", "c", .command) { media.copy() }
    add("Show Info", "i", on: media.showsInfo) { media.showsInfo.toggle() }
    add("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([media.url]) }
    media.loadOpeners()
    let openWith = submenu("Open With")
    for app in media.openers {
      add(DefaultApps.name(app), to: openWith) {
        NSWorkspace.shared.open([media.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
      }
    }
    menu.addItem(.separator())
    add("Add Pictures or Movies…") { model.add(chooseFiles(near: media.url)) }
    guard model.tiles.count > 1 else { return menu }
    let layout = submenu("Layout")
    for choice in TileLayout.allCases {
      add(choice.title, on: model.layout == choice, to: layout) { model.layout = choice }
    }
    layout.addItem(.separator())
    add("Next Layout", "l", to: layout) { model.cycleLayout() }
    let fit = submenu("Fit")
    add("Whole Pictures", on: !model.fills, to: fit) { model.fills = false }
    add("Fill the Tiles", "f", on: model.fills, to: fit) { model.fills = true }
    let index = model.tiles.firstIndex { $0 === media } ?? 0
    if index > 0 {
      add("Move Earlier", "[") { model.move(media, by: -1) }
      add("Move to Start") { model.move(media, by: -index) }
    }
    if index < model.tiles.count - 1 { add("Move Later", "]") { model.move(media, by: 1) } }
    add("Remove Tile", "\u{8}") { model.remove(media) }
    return menu
  }

  static func chooseFiles(near url: URL) -> [URL] {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.allowedContentTypes = [.image, .movie]
    panel.directoryURL = url.deletingLastPathComponent()
    return panel.runModal() == .OK ? panel.urls : []
  }
}

// MARK: Views

/// The window's tiles, one filling it unless more were added, with the bar
/// over the top while the pointer is over the window. Dropping pictures or
/// movies on it adds tiles.
struct MediaView: View {
  @ObservedObject var model: ViewerModel

  var body: some View {
    GeometryReader { geometry in
      let frames = model.frames(in: geometry.size)
      let tiled = model.tiles.count > 1
      ZStack(alignment: .topLeading) {
        Color.black
        ForEach(Array(model.tiles.enumerated()), id: \.element.id) { index, tile in
          if index < frames.count {
            MediaTileView(media: tile, tiled: tiled, active: tiled && tile === model.media,
                          fills: tiled && model.fills)
              .frame(width: frames[index].width, height: frames[index].height)
              .offset(x: frames[index].minX, y: frames[index].minY)
          }
        }
      }
    }
    .overlay {
      if let media = model.media { MediaChrome(model: model, media: media) }
    }
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
      for provider in providers {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          guard let url else { return }
          DispatchQueue.main.async { model.add([url]) }
        }
      }
      return true
    }
    .ignoresSafeArea()
  }
}

/// The bar, info panel, and status line for the active tile.
private struct MediaChrome: View {
  @ObservedObject var model: ViewerModel
  @ObservedObject var media: MediaState

  var body: some View {
    let shown = model.showsChrome || media.cropping
    Color.clear
      .allowsHitTesting(false)
      .overlay(alignment: .top) {
        MediaBar(model: model, media: media)
          .opacity(shown ? 1 : 0)
          .allowsHitTesting(shown)
          .animation(.easeOut(duration: 0.2), value: shown)
      }
      .overlay(alignment: .topTrailing) {
        if media.showsInfo, !media.info.isEmpty {
          InfoPanel(rows: media.info).padding(.top, 44).padding(.trailing, 10)
        }
      }
      .overlay(alignment: .bottom) {
        if let status = media.status {
          Text(status)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
            .padding(.bottom, media.isVideo ? 70 : 14)
        }
      }
  }
}

private struct MediaTileView: View {
  @ObservedObject var media: MediaState
  let tiled: Bool
  let active: Bool
  let fills: Bool

  var body: some View {
    ZStack {
      Color.black
      if let error = media.error {
        Text(error).foregroundStyle(.secondary).padding()
      } else if let player = media.player {
        VideoView(player: player, media: media, fills: fills && !media.cropping)
      } else if let image = media.image {
        ZoomableImage(image: image, zoom: media.zoom, pixelated: media.pixelated, ownsWindow: !tiled,
                      frozen: media.cropping, fills: fills && !media.cropping, media: media)
      } else if !media.isVideo {
        ProgressView().controlSize(.small)
      }
      if media.cropping, let size = media.size {
        CropOverlay(rect: $media.crop, size: size, pixels: media.pixelSize ?? size)
      }
    }
    .overlay {
      if active { Rectangle().strokeBorder(Color.accentColor, lineWidth: 2).allowsHitTesting(false) }
    }
    .clipped()
  }
}

private struct MediaBar: View {
  @ObservedObject var model: ViewerModel
  @ObservedObject var media: MediaState
  @ObservedObject private var preferences = ViewerPreferences.shared

  var body: some View {
    HStack(spacing: 4) {
      Text(media.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
      if let position = media.position, position.count > 1 {
        Text("\(position.index) of \(position.count)").font(.caption).foregroundStyle(.white.opacity(0.7))
          .fixedSize()
      }
      Spacer(minLength: 8)
      if media.cropping {
        Text("Drag the edges to crop").font(.caption).foregroundStyle(.white.opacity(0.7)).fixedSize()
        Button("Cancel") { media.cancelCrop() }.buttonStyle(.bordered).help("Cancel (Esc)")
        Button("Apply") { media.applyCrop() }.buttonStyle(.borderedProminent)
          .help("Keep this crop; Save Copy writes it (Return)")
      } else {
        controls
      }
    }
    .controlSize(.small)
    .foregroundStyle(.white)
    .buttonStyle(.borderless)
    .padding(.leading, 78)
    .padding(.trailing, 10)
    .frame(height: 38)
    .background {
      ZStack {
        LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
        WindowDragArea()
      }
    }
  }

  @ViewBuilder private var controls: some View {
    if media.isVideo {
      icon("scissors", "Trim (T)") { media.beginTrimming() }
    } else {
      icon("minus.magnifyingglass", "Zoom Out (−)") { media.magnify(by: -1) }
      Button { media.toggleActualSize() } label: {
        Text("\(Int((media.scale * 100).rounded()))%").monospacedDigit().frame(minWidth: 40)
      }
      .help(media.isFitted ? "Actual Size (1)" : "Fit to Window (0)")
      icon("plus.magnifyingglass", "Zoom In (+)") { media.magnify(by: 1) }
      icon("square.grid.3x3", "Sharp Pixels (P)", on: media.pixelated) { media.pixelated.toggle() }
      icon("rotate.left", "Rotate Left (⇧R)") { media.rotate(-1) }
      icon("rotate.right", "Rotate Right (R)") { media.rotate(1) }
    }
    icon("crop", "Crop (C)") { media.beginCrop() }
    if !media.isVideo, media.viewIsPartial, media.applied != media.view {
      Button("Crop to View") { media.cropToView() }.buttonStyle(.bordered)
        .help("Keep the part in the window as the crop (⇧C)")
    }
    if let applied = media.applied {
      let area = MediaEdit.pixels(applied, in: media.pixelSize ?? .zero)
      HStack(spacing: 2) {
        Text("\(Int(area.width)) × \(Int(area.height))").font(.caption.monospacedDigit())
        Button { media.clearCrop() } label: { Image(systemName: "xmark.circle.fill") }.help("Remove the crop")
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.white.opacity(0.18), in: Capsule())
      .fixedSize()
    }
    if media.hasEdits {
      Button("Save Copy") { media.saveCopy() }.buttonStyle(.borderedProminent).help("Save the edits as a new file (⌘S)")
    }
    icon("info.circle", "Info (I)", on: media.showsInfo) { media.showsInfo.toggle() }
    Image(systemName: "hand.draw")
      .frame(width: 24, height: 24)
      .contentShape(Rectangle())
      .onDrag { NSItemProvider(object: media.url as NSURL) }
      .help("Drag the file out")
    more
  }

  private var more: some View {
    let url = media.url
    let preferred = NSWorkspace.shared.urlForApplication(toOpen: url)
    return Menu {
      Button(media.isVideo ? "Copy File" : "Copy Image") { media.copy() }
      Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
      Menu("Open With") {
        if let preferred {
          Button("\(DefaultApps.name(preferred)) (default)") { open(url, with: preferred) }
          Divider()
        }
        ForEach(media.openers.filter { $0 != preferred }, id: \.self) { app in
          Button(DefaultApps.name(app)) { open(url, with: app) }
        }
      }
      Divider()
      Button("Add Pictures or Movies…") { model.add(MediaMenu.chooseFiles(near: media.url)) }
      if model.tiles.count > 1 {
        Picker("Layout", selection: $model.layout) {
          ForEach(TileLayout.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.menu)
        Picker("Fit", selection: $model.fills) {
          Text("Whole Pictures").tag(false)
          Text("Fill the Tiles").tag(true)
        }
        .pickerStyle(.menu)
        Button("Remove This Tile") { model.remove(media) }
      }
      Divider()
      Picker("Scroll to Zoom", selection: Binding(get: { preferences.scrollZoom },
                                                  set: { preferences.set(scrollZoom: $0) })) {
        ForEach(ViewerPreferences.ScrollZoom.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.menu)
      Toggle("Loop Movies", isOn: Binding(get: { preferences.loopsMovies },
                                          set: { preferences.set(loopsMovies: $0) }))
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("More")
  }

  private func open(_ url: URL, with app: URL) {
    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
  }

  private func icon(_ symbol: String, _ help: String, on: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .frame(width: 24, height: 24)
        .background(on ? Color.white.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }
    .help(help)
  }
}

/// Dragging the bar's background moves the window; its title bar is hidden.
private struct WindowDragArea: NSViewRepresentable {
  final class DragView: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
  }

  func makeNSView(context: Context) -> DragView { DragView() }
  func updateNSView(_ view: DragView, context: Context) {}
}

private struct InfoPanel: View {
  let rows: [MediaState.InfoRow]

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
      ForEach(rows) { row in
        GridRow {
          Text(row.label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
          Text(row.value).textSelection(.enabled)
        }
      }
    }
    .font(.caption)
    .padding(10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    .environment(\.colorScheme, .dark)
  }
}

/// A crop rect with eight handles over the fitted picture; outside it dims.
private struct CropOverlay: View {
  @Binding var rect: CGRect
  let size: CGSize
  let pixels: CGSize
  @State private var start: CGRect?

  private struct Handle: Identifiable {
    let x: Int
    let y: Int
    var id: Int { (x + 1) * 3 + y + 1 }
  }

  private static let handles = (-1...1).flatMap { x in (-1...1).map { Handle(x: x, y: $0) } }
    .filter { $0.x != 0 || $0.y != 0 }

  var body: some View {
    GeometryReader { geometry in
      let frame = MediaEdit.fitted(size, in: geometry.size)
      let shown = CGRect(x: frame.minX + rect.minX * frame.width, y: frame.minY + rect.minY * frame.height,
                         width: rect.width * frame.width, height: rect.height * frame.height)
      let area = MediaEdit.pixels(rect, in: pixels)
      ZStack(alignment: .topLeading) {
        Path { path in
          path.addRect(CGRect(origin: .zero, size: geometry.size))
          path.addRect(shown)
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
        Rectangle()
          .fill(Color.white.opacity(0.001))
          .overlay(thirds)
          .border(Color.white, width: 1)
          .frame(width: shown.width, height: shown.height)
          .offset(x: shown.minX, y: shown.minY)
          .gesture(drag(x: 0, y: 0, in: frame))
        ForEach(Self.handles) { handle in
          RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: handle.x == 0 || handle.y == 0 ? 14 : 10, height: handle.x == 0 || handle.y == 0 ? 14 : 10)
            .shadow(radius: 1)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .position(x: shown.minX + CGFloat(handle.x + 1) / 2 * shown.width,
                      y: shown.minY + CGFloat(handle.y + 1) / 2 * shown.height)
            .gesture(drag(x: handle.x, y: handle.y, in: frame))
        }
        Text("\(Int(area.width)) × \(Int(area.height))")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.black.opacity(0.6), in: Capsule())
          .position(x: shown.midX, y: min(shown.maxY + 14, geometry.size.height - 12))
          .allowsHitTesting(false)
      }
    }
  }

  private var thirds: some View {
    GeometryReader { geometry in
      Path { path in
        for third in [1.0 / 3, 2.0 / 3] {
          path.move(to: CGPoint(x: geometry.size.width * third, y: 0))
          path.addLine(to: CGPoint(x: geometry.size.width * third, y: geometry.size.height))
          path.move(to: CGPoint(x: 0, y: geometry.size.height * third))
          path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height * third))
        }
      }
      .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
    }
    .allowsHitTesting(false)
  }

  private func drag(x: Int, y: Int, in frame: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let from = start ?? rect
        if start == nil { start = rect }
        rect = MediaEdit.adjust(from, handle: (x, y),
                                by: CGSize(width: value.translation.width / max(frame.width, 1),
                                           height: value.translation.height / max(frame.height, 1)))
      }
      .onEnded { _ in start = nil }
  }
}

private struct VideoView: NSViewRepresentable {
  let player: AVPlayer
  let media: MediaState
  let fills: Bool

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .floating
    view.showsFullScreenToggleButton = true
    view.player = player
    media.beginTrim = { [weak view, weak media] in
      guard let view, let media, view.canBeginTrimming else { return }
      media.trimming = true
      view.beginTrimming { result in
        guard result == .okButton, let item = view.player?.currentItem else { return media.trimmed(nil) }
        let start = item.reversePlaybackEndTime.isNumeric ? item.reversePlaybackEndTime : .zero
        let end = item.forwardPlaybackEndTime.isNumeric ? item.forwardPlaybackEndTime : item.duration
        media.trimmed(end.isNumeric ? CMTimeRange(start: start, end: end) : nil)
      }
    }
    return view
  }

  func updateNSView(_ view: AVPlayerView, context: Context) {
    if view.player !== player { view.player = player }
    let gravity: AVLayerVideoGravity = fills ? .resizeAspectFill : .resizeAspect
    if view.videoGravity != gravity { view.videoGravity = gravity }
  }
}

/// Pinch and scroll zoom at the pointer; double-click toggles fit and
/// actual size. While the whole picture shows, dragging it moves the
/// window; past that, it pans. Resizing the window crops the view.
private struct ZoomableImage: NSViewRepresentable {
  let image: NSImage
  let zoom: MediaState.Zoom
  let pixelated: Bool
  let ownsWindow: Bool
  let frozen: Bool
  let fills: Bool
  let media: MediaState

  func makeNSView(context: Context) -> ImageScrollView {
    let view = ImageScrollView()
    media.zoomWindow = { [weak view] scale in view?.zoomWindow(to: scale) ?? false }
    view.onDoubleClick = { [weak media] in media?.toggleActualSize() }
    view.onZoom = { [weak media] zoom in media?.zoom = zoom }
    // Reported from layout, which can run inside a SwiftUI update.
    view.onScale = { [weak media] scale, backing in DispatchQueue.main.async { media?.shown(at: scale, backing: backing) } }
    view.onView = { [weak media] rect in DispatchQueue.main.async { media?.viewed(rect) } }
    return view
  }

  func updateNSView(_ view: ImageScrollView, context: Context) {
    view.ownsWindow = ownsWindow
    view.frozen = frozen
    view.show(image, zoom: zoom, pixelated: pixelated, fills: fills)
  }
}

final class ImageScrollView: NSScrollView {
  var onDoubleClick: (() -> Void)?
  /// A zoom the view made itself: a pinch, a scroll, a pan, or a resize.
  var onZoom: ((MediaState.Zoom) -> Void)?
  var onScale: ((CGFloat, CGFloat) -> Void)?
  /// The part of the picture in view, in fractions, origin top left.
  var onView: ((CGRect) -> Void)?
  /// The picture is alone in its window: zooms size the window around it,
  /// and a live resize keeps it still and moves the window's edges over it.
  var ownsWindow = true
  /// Cropping: the picture stays fitted under the handles.
  var frozen = false
  private let imageView = PixelImageView()
  private var zoom = MediaState.Zoom.fit
  /// A fitted region covers the view, cut at its edges, instead of showing whole.
  private var fills = false
  private var panStart: (point: NSPoint, origin: NSPoint)?
  private var resizeStart: (frame: NSRect, origin: NSPoint)?
  /// Scrolling adds up to the next whole multiple for sharp pixels.
  private var scrolled: CGFloat = 0
  private var shown: CGRect?

  /// Scroll bars float over the picture and fade, whatever the system's setting.
  override var scrollerStyle: NSScroller.Style {
    get { .overlay }
    set { super.scrollerStyle = .overlay }
  }

  init() {
    super.init(frame: .zero)
    contentView = CenteringClipView()
    documentView = imageView
    imageView.wantsLayer = true
    imageView.imageScaling = .scaleAxesIndependently
    imageView.animates = true
    allowsMagnification = true
    minMagnification = 0.02
    maxMagnification = 32
    hasVerticalScroller = true
    hasHorizontalScroller = true
    autohidesScrollers = true
    scrollerKnobStyle = .light
    super.scrollerStyle = .overlay
    drawsBackground = false
    // The title bar is hidden over the picture, not above it.
    automaticallyAdjustsContentInsets = false
    contentInsets = NSEdgeInsetsZero
    contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(self, selector: #selector(pinched),
                                           name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    NotificationCenter.default.addObserver(self, selector: #selector(scrolledClip),
                                           name: NSView.boundsDidChangeNotification, object: contentView)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  @objc private func pinched() {
    zoomed(.scale(magnification))
  }

  @objc private func scrolledClip() {
    report()
  }

  func show(_ image: NSImage, zoom: MediaState.Zoom, pixelated: Bool, fills: Bool) {
    let resized = imageView.image?.size != image.size
    imageView.image = image
    imageView.frame = NSRect(origin: .zero, size: image.size)
    imageView.pixelated = pixelated
    let changed = self.zoom != zoom || self.fills != fills
    self.zoom = zoom
    self.fills = fills
    if changed || resized { applyZoom() }
  }

  override func layout() {
    super.layout()
    if let start = resizeStart, let window {
      // The window's left and bottom edges moved; the picture stays put under them.
      scroll(to: NSPoint(x: start.origin.x + (window.frame.minX - start.frame.minX) / magnification,
                         y: start.origin.y + (window.frame.minY - start.frame.minY) / magnification))
    } else if case .scale = zoom {
      report()
    } else {
      applyZoom()
    }
  }

  /// The window's edges stop at the picture's, so a resize shows no black;
  /// with ⌥ the part in view scales with the window and keeps its shape.
  override func viewWillStartLiveResize() {
    super.viewWillStartLiveResize()
    guard ownsWindow, !frozen, let window, let size = imageView.image?.size else { return }
    if NSEvent.modifierFlags.contains(.option) {
      if let shown { zoomed(.region(shown)) }
      window.aspectRatio = window.frame.size
      return
    }
    zoomed(.scale(magnification))
    resizeStart = (window.frame, contentView.bounds.origin)
    window.maxSize = NSSize(width: size.width * magnification, height: size.height * magnification)
  }

  override func viewDidEndLiveResize() {
    super.viewDidEndLiveResize()
    resizeStart = nil
    guard ownsWindow, let window else { return }
    window.resizeIncrements = NSSize(width: 1, height: 1)
    window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
  }

  override func magnify(with event: NSEvent) {
    guard ownsWindow, !frozen else { return frozen ? () : super.magnify(with: event) }
    zoomWindow(to: magnification * (1 + event.magnification), around: event.locationInWindow)
  }

  override func scrollWheel(with event: NSEvent) {
    let rate = ViewerPreferences.shared.scrollZoom.rate
    guard rate > 0, !frozen, !event.modifierFlags.contains(.command), imageView.image != nil else {
      return super.scrollWheel(with: event)
    }
    // Momentum would keep zooming after the fingers lift.
    guard event.momentumPhase.isEmpty else { return }
    // Pulling toward you zooms in, with natural scrolling or without.
    let toward = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
    guard toward != 0 else { return }
    // A wheel zooms one step per notch however fast it spins, as PictureView
    // does: the system's wheel acceleration would jump several at once.
    let precise = event.hasPreciseScrollingDeltas
    let amount = precise ? toward * rate : (toward > 0 ? 1 : -1) * rate * ViewerPreferences.ScrollZoom.notch
    var target = magnification * exp(amount)
    if imageView.pixelated {
      scrolled += precise ? amount : (amount > 0 ? 0.2 : -0.2)
      guard abs(scrolled) >= 0.2 else { return }
      let steps = MediaState.pixelSteps
      target = (scrolled > 0 ? steps.first { $0 > magnification + 0.01 } : steps.last { $0 < magnification - 0.01 })
        ?? magnification
      scrolled = 0
    }
    if zoomWindow(to: target, around: event.locationInWindow) { return }
    setMagnification(min(max(target, minMagnification), maxMagnification),
                     centeredAt: imageView.convert(event.locationInWindow, from: nil))
    zoomed(.scale(magnification))
  }

  /// Zooms to `scale` and sizes the window to the picture at that size,
  /// keeping the point under `anchor` (in the window; its middle when nil)
  /// still. Zooming in grows the window around it up to the screen; zooming
  /// out shows more of the picture, then shrinks the window to its edges,
  /// so no black shows. False when the picture shares its window.
  @discardableResult
  func zoomWindow(to scale: CGFloat, around anchor: NSPoint? = nil) -> Bool {
    guard ownsWindow, !frozen, let window, let size = imageView.image?.size, size.width > 0, size.height > 0,
          var screen = (window.screen ?? NSScreen.main)?.visibleFrame
    else { return false }
    let scale = min(max(scale, minMagnification), maxMagnification)
    let old = magnification
    let view = window.convertToScreen(convert(bounds, to: nil))
    let pointer = anchor.map { window.convertToScreen(NSRect(origin: $0, size: .zero)).origin }
      ?? NSPoint(x: view.midX, y: view.midY)
    let held = NSPoint(x: contentView.bounds.minX + (pointer.x - view.minX) / old,
                       y: contentView.bounds.minY + (pointer.y - view.minY) / old)
    let ratio = scale / old
    var frame = ratio > 1
      ? NSRect(x: pointer.x + (view.minX - pointer.x) * ratio, y: pointer.y + (view.minY - pointer.y) * ratio,
               width: view.width * ratio, height: view.height * ratio)
      : view
    var visible = NSRect(x: held.x - (pointer.x - frame.minX) / scale, y: held.y - (pointer.y - frame.minY) / scale,
                         width: frame.width / scale, height: frame.height / scale)
    let picture = visible.intersection(NSRect(origin: .zero, size: size))
    guard !picture.isNull, picture.width > 0, picture.height > 0 else { return false }
    frame = NSRect(x: frame.minX + (picture.minX - visible.minX) * scale,
                   y: frame.minY + (picture.minY - visible.minY) * scale,
                   width: picture.width * scale, height: picture.height * scale)
    visible = picture
    // The window may sit inset from the view's edges; the screen shrinks by as much.
    let (left, bottom) = (view.minX - window.frame.minX, view.minY - window.frame.minY)
    let (right, top) = (window.frame.maxX - view.maxX, window.frame.maxY - view.maxY)
    screen = NSRect(x: screen.minX + left, y: screen.minY + bottom,
                    width: screen.width - left - right, height: screen.height - bottom - top)
    // Small enough to fit moves onto the screen; bigger is cut to it.
    if frame.width <= screen.width {
      frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
    } else {
      visible.origin.x += (screen.minX - frame.minX) / scale
      visible.size.width = screen.width / scale
      frame.origin.x = screen.minX
      frame.size.width = screen.width
    }
    if frame.height <= screen.height {
      frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
    } else {
      visible.origin.y += (screen.minY - frame.minY) / scale
      visible.size.height = screen.height / scale
      frame.origin.y = screen.minY
      frame.size.height = screen.height
    }
    zoom = .scale(scale)
    magnification = scale
    window.setFrame(NSRect(x: frame.minX - left, y: frame.minY - bottom,
                           width: frame.width + left + right, height: frame.height + bottom + top),
                    display: true)
    window.contentView?.layoutSubtreeIfNeeded()
    scroll(to: visible.origin)
    zoomed(.scale(scale))
    return true
  }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { return onDoubleClick?() ?? () }
    if fitsInside {
      window?.performDrag(with: event)
    } else {
      if case .scale = zoom {} else { zoomed(.scale(magnification)) }
      panStart = (event.locationInWindow, contentView.bounds.origin)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start = panStart else { return }
    scroll(to: NSPoint(x: start.origin.x - (event.locationInWindow.x - start.point.x) / magnification,
                       y: start.origin.y - (event.locationInWindow.y - start.point.y) / magnification))
  }

  override func mouseUp(with event: NSEvent) {
    panStart = nil
  }

  private var fitsInside: Bool {
    let size = imageView.frame.size
    return size.width * magnification <= contentSize.width + 1 && size.height * magnification <= contentSize.height + 1
  }

  private func zoomed(_ zoom: MediaState.Zoom) {
    self.zoom = zoom
    onZoom?(zoom)
    report()
  }

  private func applyZoom() {
    guard let size = imageView.image?.size, size.width > 0, size.height > 0,
          contentSize.width > 0, contentSize.height > 0 else { return }
    switch zoom {
    case .region(let region):
      let across = contentSize.width / (size.width * region.width)
      let down = contentSize.height / (size.height * region.height)
      magnification = fills ? max(across, down) : min(across, down)
      center(on: CGPoint(x: region.midX, y: region.midY), in: size)
    case .focus(let scale, let point):
      magnification = scale
      center(on: point, in: size)
    case .scale(let scale):
      magnification = scale
    }
    report()
  }

  /// Scrolls `point` of the picture, in fractions from the top left, to the middle.
  private func center(on point: CGPoint, in size: CGSize) {
    let visible = contentView.bounds.size
    scroll(to: NSPoint(x: point.x * size.width - visible.width / 2,
                       y: (1 - point.y) * size.height - visible.height / 2))
  }

  private func scroll(to origin: NSPoint) {
    contentView.scroll(to: contentView.constrainBoundsRect(NSRect(origin: origin, size: contentView.bounds.size)).origin)
    reflectScrolledClipView(contentView)
  }

  private func report() {
    onScale?(magnification, window?.backingScaleFactor ?? 2)
    guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return }
    let visible = contentView.documentVisibleRect.intersection(NSRect(origin: .zero, size: size))
    guard !visible.isNull, visible.width > 0, visible.height > 0 else { return }
    let rect = CGRect(x: visible.minX / size.width, y: (size.height - visible.maxY) / size.height,
                      width: visible.width / size.width, height: visible.height / size.height)
    guard rect != shown else { return }
    shown = rect
    onView?(rect)
  }
}

/// Draws scaled-up pixels as hard squares when `pixelated`, whether AppKit
/// scales the layer or redraws the view at the zoomed size.
private final class PixelImageView: NSImageView {
  var pixelated = false {
    didSet {
      guard pixelated != oldValue else { return }
      layer?.magnificationFilter = pixelated ? .nearest : .linear
      needsDisplay = true
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    NSGraphicsContext.current?.imageInterpolation = pixelated ? .none : .high
    super.draw(dirtyRect)
  }

  override func mouseDown(with event: NSEvent) { nextResponder?.mouseDown(with: event) }
  override func mouseDragged(with event: NSEvent) { nextResponder?.mouseDragged(with: event) }
  override func mouseUp(with event: NSEvent) { nextResponder?.mouseUp(with: event) }
}

/// Keeps a document smaller than the view in the middle instead of the corner.
private final class CenteringClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var rect = super.constrainBoundsRect(proposedBounds)
    guard let document = documentView else { return rect }
    if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
    if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
    return rect
  }
}
