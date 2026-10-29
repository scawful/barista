import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Finder icons drawn once into small bitmaps, off the main thread. A
/// workspace icon is cheap to get but costs milliseconds the first time it
/// draws at a size, which a list would otherwise pay on the main thread for
/// every row it shows; on a network mount, getting it is a round trip too.
/// Images and videos get a Quick Look thumbnail instead, as Finder shows them.
final class FileIcons: @unchecked Sendable {
  static let shared = FileIcons()

  private let cache = NSCache<NSString, NSImage>()
  private let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 4
    queue.qualityOfService = .userInitiated
    return queue
  }()

  /// Big icon-view sizes are 256 px a side, so bytes bound it as well as count.
  private init() {
    cache.countLimit = 4000
    cache.totalCostLimit = 128 << 20
  }

  /// A thumbnail shows the file's contents, so its modification date is part
  /// of the key; a type icon does not change when the file does.
  private static func key(_ url: URL, _ points: CGFloat, _ modified: Date?) -> NSString {
    "\(Int(points))|\(Int(modified?.timeIntervalSince1970 ?? 0))|\(url.path)" as NSString
  }

  static func hasThumbnail(_ url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
    return type.conforms(to: .image) || type.conforms(to: .movie)
  }

  func cached(_ url: URL, points: CGFloat, modified: Date? = nil) -> NSImage? {
    cache.object(forKey: Self.key(url, points, modified))
  }

  /// The icon for `url` at `points`. Rows scrolled past before their turn
  /// are skipped, so a long folder draws only what was on screen.
  func icon(for url: URL, points: CGFloat, modified: Date? = nil) async -> NSImage? {
    let key = Self.key(url, points, modified)
    if let image = cache.object(forKey: key) { return image }
    let cost = Int(points * points) * 16
    if Self.hasThumbnail(url), let image = await thumbnail(url, points: points) {
      cache.setObject(image, forKey: key, cost: cost)
      return image
    }
    guard !Task.isCancelled else { return nil }
    let run = SizeRun()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
        queue.addOperation { [self] in
          guard !run.cancelled else { return continuation.resume(returning: nil) }
          let image = Self.draw(NSWorkspace.shared.icon(forFile: url.path), points: points)
          if let image { self.cache.setObject(image, forKey: key, cost: cost) }
          continuation.resume(returning: image)
        }
      }
    } onCancel: {
      run.cancel()
    }
  }

  /// Nil when Quick Look cannot draw the file, which then keeps its type icon.
  private func thumbnail(_ url: URL, points: CGFloat) async -> NSImage? {
    let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: points, height: points),
                                               scale: 2, representationTypes: .thumbnail)
    return await withTaskCancellationHandler {
      try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    } onCancel: {
      QLThumbnailGenerator.shared.cancel(request)
    }
  }

  private static func draw(_ source: NSImage, points: CGFloat) -> NSImage? {
    guard case .image(let bitmap) = TileImage.image(source).rasterized(pixels: Int(points * 2)) else { return nil }
    return bitmap
  }
}

/// A file's Finder icon, or its thumbnail for an image or video; blank until
/// it has been drawn. Pass `modified` so an edited file's thumbnail redraws.
struct FileIcon: View {
  let url: URL
  let points: CGFloat
  let modified: Date?
  @State private var image: NSImage?

  init(url: URL, points: CGFloat, modified: Date? = nil) {
    self.url = url
    self.points = points
    self.modified = modified
    _image = State(initialValue: FileIcons.shared.cached(url, points: points, modified: modified))
  }

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().scaledToFit()
      } else {
        Color.clear
      }
    }
    .frame(width: points, height: points)
    // The icon at the old size stays, scaled, until the new one is drawn.
    .task(id: "\(Int(points))|\(modified?.timeIntervalSince1970 ?? 0)|\(url.path)") {
      if let loaded = await FileIcons.shared.icon(for: url, points: points, modified: modified) { image = loaded }
    }
  }
}
