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

  /// Writes the turned and cropped picture next to `url`, in its format when
  /// ImageIO can write that and as PNG otherwise. Blocking.
  static func writeImage(_ url: URL, rotation: Int, crop: CGRect?) throws -> URL {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          // The thumbnail at full size is the only ImageIO call that applies EXIF orientation.
          let upright = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
          ] as CFDictionary),
          var image = rotate(upright, quarterTurns: rotation)
    else { throw Failure("Can't read \(url.lastPathComponent).") }
    if let crop {
      guard let cropped = image.cropping(to: pixels(crop, in: CGSize(width: image.width, height: image.height)))
      else { throw Failure("The crop is outside the picture.") }
      image = cropped
    }
    let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
    let keepsType = writable.contains(type as String)
    let copy = copyURL(for: url, ext: keepsType ? url.pathExtension : "png")
    guard let destination = CGImageDestinationCreateWithURL(copy as CFURL, keepsType ? type : UTType.png.identifier as CFString,
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

/// The picture or movie in a viewer window: its zoom and turn, the crop
/// and trim being made, and the bar that shows while the pointer is over it.
/// Used on the main thread only; background work hands results back there.
final class MediaState: ObservableObject, @unchecked Sendable {
  enum Zoom: Equatable { case fit, scale(CGFloat) }

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
  @Published var showsInfo = false
  @Published private(set) var showsChrome = false
  @Published private(set) var cropping = false
  @Published var crop = MediaEdit.whole
  @Published fileprivate(set) var trimming = false
  @Published private(set) var trim: CMTimeRange?
  @Published private(set) var status: String?

  var resize: ((Resize) -> Void)?
  var openFile: ((URL) -> Void)?
  fileprivate var beginTrim: (() -> Void)?

  private(set) var url: URL?
  private var original: NSImage?
  private var generation = 0
  private var sized = false
  private var saving = false
  private var hideChrome: DispatchWorkItem?

  var isVideo: Bool { player != nil }
  var hasEdits: Bool { rotation != 0 || trim != nil }

  /// Nil, or why the file can't be shown. `fresh` is another file; otherwise
  /// the same one changed on disk and keeps its zoom and edits.
  func load(_ url: URL, kind: ViewerKind, fresh: Bool) -> String? {
    self.url = url
    generation += 1
    if fresh {
      zoom = .fit
      rotation = 0
      cropping = false
      crop = MediaEdit.whole
      trim = nil
      openers = DefaultApps.choices(for: url)
    }
    if kind == .video {
      // A recording still being written changes on every write.
      guard fresh || player == nil else { return nil }
      player?.pause()
      original = nil
      image = nil
      let player = AVPlayer(url: url)
      self.player = player
      player.play()
      loadVideo(url, generation: generation, fresh: fresh)
      return nil
    }
    player?.pause()
    player = nil
    guard let loaded = NSImage(contentsOf: url) else {
      original = nil
      image = nil
      info = Self.fileRows(url)
      return "Can't open \(url.lastPathComponent) as an image."
    }
    original = loaded
    if fresh { pixelated = Self.looksLikePixelArt(url, loaded) }
    render()
    info = Self.imageInfo(url)
    if fresh, let size { place(size) }
    return nil
  }

  func stop() {
    player?.pause()
  }

  // MARK: Zoom

  func magnify(by direction: Int) {
    guard !isVideo else { return }
    let steps = pixelated ? Self.pixelSteps : Self.steps
    let next = direction > 0 ? steps.first { $0 > scale + 0.01 } : steps.last { $0 < scale - 0.01 }
    if let next { magnify(to: next) }
  }

  /// A multiple of the picture's size; the window grows or shrinks to it.
  func magnify(to scale: CGFloat) {
    guard let size, !cropping else { return }
    if !isVideo { zoom = .scale(scale) }
    resize?(.exact(CGSize(width: size.width * scale, height: size.height * scale)))
  }

  func fit() {
    zoom = .fit
    if let size { resize?(.sameWidth(size)) }
  }

  func toggleActualSize() {
    if zoom == .fit { magnify(to: 1) } else { fit() }
  }

  fileprivate func shown(at scale: CGFloat) {
    if abs(self.scale - scale) > 0.001 { self.scale = scale }
  }

  // MARK: Chrome

  /// The pointer at `point` (top-left origin) over the window, or gone.
  /// The bar shows on any move and hides two seconds after one away from it.
  func pointer(_ point: CGPoint?) {
    hideChrome?.cancel()
    guard let point else { return setChrome(cropping) }
    setChrome(true)
    guard point.y > 44 else { return }
    let work = DispatchWorkItem { [weak self] in self?.setChrome(self?.cropping == true) }
    hideChrome = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
  }

  private func setChrome(_ shown: Bool) {
    if showsChrome != shown { showsChrome = shown }
  }

  // MARK: Edits

  func rotate(_ quarterTurns: Int) {
    guard original != nil, !cropping else { return }
    rotation = (rotation + quarterTurns + 4) % 4
    render()
    zoom = .fit
    if let size { resize?(.sameWidth(size)) }
  }

  func beginCrop() {
    guard size != nil, !trimming else { return }
    zoom = .fit
    crop = MediaEdit.whole
    cropping = true
    setChrome(true)
  }

  func cancelCrop() {
    cropping = false
    crop = MediaEdit.whole
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
    guard let url, !saving else { return }
    let area = cropping && crop != MediaEdit.whole ? crop : nil
    cropping = false
    guard area != nil || hasEdits else { return }
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
      openFile?(copy)
      show(status: "Saved \(copy.lastPathComponent)")
    case .failure(let error):
      show(status: "Couldn't save: \(error.localizedDescription)")
    }
  }

  func copy() {
    NSPasteboard.general.clearContents()
    if !isVideo, let image {
      NSPasteboard.general.writeObjects([image])
      show(status: "Copied image")
    } else if let url {
      NSPasteboard.general.writeObjects([url as NSURL])
      show(status: "Copied file")
    }
  }

  private func show(status: String, clears: Bool = true) {
    self.status = status
    guard clears else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      if self?.status == status { self?.status = nil }
    }
  }

  // MARK: Loading

  private func place(_ size: CGSize) {
    resize?(sized ? .sameWidth(size) : .natural(size))
    sized = true
  }

  private func render() {
    guard let original else { return }
    let turned = rotation % 2 == 0 ? original.size : CGSize(width: original.size.height, height: original.size.width)
    if rotation == 0 {
      image = original
    } else if let source = original.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rotated = MediaEdit.rotate(source, quarterTurns: rotation) {
      image = NSImage(cgImage: rotated, size: turned)
    }
    size = turned
    if let rep = original.representations.first, rep.pixelsWide > 0 {
      let pixels = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
      pixelSize = rotation % 2 == 0 ? pixels : CGSize(width: pixels.height, height: pixels.width)
    } else {
      pixelSize = turned
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
        guard let self, self.generation == generation else { return }
        self.info = rows + file
        guard let shown else { return }
        self.size = shown
        self.pixelSize = shown
        if fresh { self.place(shown) }
      }
    }
  }

  /// Small lossless pictures are sprites, tiles, and emulator captures.
  private static func looksLikePixelArt(_ url: URL, _ image: NSImage) -> Bool {
    guard let rep = image.representations.first, max(rep.pixelsWide, rep.pixelsHigh) <= 1024,
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

// MARK: Views

/// The picture or movie filling the window, with a bar over the top that
/// shows while the pointer is over the window.
struct MediaView: View {
  @ObservedObject var model: ViewerModel
  @ObservedObject var media: MediaState

  var body: some View {
    ZStack {
      Color.black
      if let error = model.error {
        Text(error).foregroundStyle(.secondary)
      } else if let player = media.player {
        VideoView(player: player, media: media)
      } else if let image = media.image {
        ZoomableImage(image: image, zoom: media.zoom, pixelated: media.pixelated, media: media)
      }
      if media.cropping, let size = media.size {
        CropOverlay(rect: $media.crop, size: size, pixels: media.pixelSize ?? size)
      }
    }
    .overlay(alignment: .top) {
      MediaBar(model: model, media: media)
        .opacity(media.showsChrome ? 1 : 0)
        .allowsHitTesting(media.showsChrome)
        .animation(.easeOut(duration: 0.2), value: media.showsChrome)
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
    .ignoresSafeArea()
  }
}

private struct MediaBar: View {
  @ObservedObject var model: ViewerModel
  @ObservedObject var media: MediaState

  var body: some View {
    HStack(spacing: 4) {
      Text(model.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
      if let position = model.position, position.count > 1 {
        Text("\(position.index) of \(position.count)").font(.caption).foregroundStyle(.white.opacity(0.7))
          .fixedSize()
      }
      Spacer(minLength: 8)
      if media.cropping {
        Text("Drag the corners to crop").font(.caption).foregroundStyle(.white.opacity(0.7)).fixedSize()
        Button("Cancel") { media.cancelCrop() }.buttonStyle(.bordered).help("Cancel (Esc)")
        Button("Save Copy") { media.saveCopy() }.buttonStyle(.borderedProminent).help("Save the crop as a new file (Return)")
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
      .help(media.zoom == .fit ? "Actual Size (1)" : "Fit to Window (0)")
      icon("plus.magnifyingglass", "Zoom In (+)") { media.magnify(by: 1) }
      icon("square.grid.3x3", "Sharp Pixels (P)", on: media.pixelated) { media.pixelated.toggle() }
      icon("rotate.left", "Rotate Left (⇧R)") { media.rotate(-1) }
      icon("rotate.right", "Rotate Right (R)") { media.rotate(1) }
    }
    icon("crop", "Crop (C)") { media.beginCrop() }
    if media.hasEdits {
      Button("Save Copy") { media.saveCopy() }.buttonStyle(.borderedProminent).help("Save the edits as a new file (⌘S)")
    }
    icon("info.circle", "Info (I)", on: media.showsInfo) { media.showsInfo.toggle() }
    icon("doc.on.doc", media.isVideo ? "Copy File (⌘C)" : "Copy Image (⌘C)") { media.copy() }
    Image(systemName: "hand.draw")
      .frame(width: 24, height: 24)
      .contentShape(Rectangle())
      .onDrag { NSItemProvider(object: model.url as NSURL) }
      .help("Drag the file out")
    openWith
    icon("folder", "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.url]) }
  }

  private var openWith: some View {
    let url = model.url
    let preferred = NSWorkspace.shared.urlForApplication(toOpen: url)
    return Menu {
      if let preferred {
        Button("\(DefaultApps.name(preferred)) (default)") { open(url, with: preferred) }
        Divider()
      }
      ForEach(media.openers.filter { $0 != preferred }, id: \.self) { app in
        Button(DefaultApps.name(app)) { open(url, with: app) }
      }
    } label: {
      Image(systemName: "arrow.up.forward.app")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("Open With")
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
  }
}

/// Pinch zooms in place; double-click toggles fit and actual size. While
/// the whole picture shows, dragging it moves the window; past that, it pans.
private struct ZoomableImage: NSViewRepresentable {
  let image: NSImage
  let zoom: MediaState.Zoom
  let pixelated: Bool
  let media: MediaState

  func makeNSView(context: Context) -> ImageScrollView {
    let view = ImageScrollView()
    view.onDoubleClick = { [weak media] in media?.toggleActualSize() }
    view.onPinch = { [weak media] scale in media?.zoom = .scale(scale) }
    // Reported from layout, which can run inside a SwiftUI update.
    view.onScale = { [weak media] scale in DispatchQueue.main.async { media?.shown(at: scale) } }
    return view
  }

  func updateNSView(_ view: ImageScrollView, context: Context) {
    view.show(image, zoom: zoom, pixelated: pixelated)
  }
}

final class ImageScrollView: NSScrollView {
  var onDoubleClick: (() -> Void)?
  var onPinch: ((CGFloat) -> Void)?
  var onScale: ((CGFloat) -> Void)?
  private let imageView = PixelImageView()
  private var zoom = MediaState.Zoom.fit
  private var panStart: (point: NSPoint, origin: NSPoint)?

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
    autohidesScrollers = true
    drawsBackground = false
    // The title bar is hidden over the picture, not above it.
    automaticallyAdjustsContentInsets = false
    contentInsets = NSEdgeInsetsZero
    NotificationCenter.default.addObserver(self, selector: #selector(pinched),
                                           name: NSScrollView.didEndLiveMagnifyNotification, object: self)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  @objc private func pinched() {
    zoom = .scale(magnification)
    onPinch?(magnification)
    onScale?(magnification)
  }

  func show(_ image: NSImage, zoom: MediaState.Zoom, pixelated: Bool) {
    let changed = imageView.image !== image || self.zoom != zoom
    imageView.image = image
    imageView.frame = NSRect(origin: .zero, size: image.size)
    imageView.pixelated = pixelated
    self.zoom = zoom
    if changed { applyZoom() }
  }

  override func layout() {
    super.layout()
    if zoom == .fit { applyZoom() }
  }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { return onDoubleClick?() ?? () }
    if fitsInside {
      window?.performDrag(with: event)
    } else {
      panStart = (event.locationInWindow, contentView.bounds.origin)
    }
  }

  override func mouseDragged(with event: NSEvent) {
    guard let start = panStart else { return }
    let target = NSPoint(x: start.origin.x - (event.locationInWindow.x - start.point.x) / magnification,
                         y: start.origin.y - (event.locationInWindow.y - start.point.y) / magnification)
    contentView.scroll(to: contentView.constrainBoundsRect(NSRect(origin: target, size: contentView.bounds.size)).origin)
    reflectScrolledClipView(contentView)
  }

  override func mouseUp(with event: NSEvent) {
    panStart = nil
  }

  private var fitsInside: Bool {
    let shown = imageView.frame.size
    return shown.width * magnification <= contentSize.width + 1 && shown.height * magnification <= contentSize.height + 1
  }

  private func applyZoom() {
    guard let size = imageView.image?.size, size.width > 0, size.height > 0 else { return }
    switch zoom {
    case .fit: magnification = min(contentSize.width / size.width, contentSize.height / size.height)
    case .scale(let scale): magnification = scale
    }
    // Scroll bars only say where you are in a picture bigger than the window.
    let overflows = !fitsInside
    if hasVerticalScroller != overflows {
      hasVerticalScroller = overflows
      hasHorizontalScroller = overflows
    }
    onScale?(magnification)
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
