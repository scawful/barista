import AppKit
import SwiftUI

/// Finder icons drawn once into small bitmaps, off the main thread. A
/// workspace icon is cheap to get but costs milliseconds the first time it
/// draws at a size, which a list would otherwise pay on the main thread for
/// every row it shows; on a network mount, getting it is a round trip too.
final class FileIcons: @unchecked Sendable {
  static let shared = FileIcons()

  private let cache = NSCache<NSString, NSImage>()
  private let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 4
    queue.qualityOfService = .userInitiated
    return queue
  }()

  private init() { cache.countLimit = 4000 }

  private static func key(_ url: URL, _ points: CGFloat) -> NSString { "\(Int(points))|\(url.path)" as NSString }

  func cached(_ url: URL, points: CGFloat) -> NSImage? { cache.object(forKey: Self.key(url, points)) }

  /// The icon for `url` at `points`. Rows scrolled past before their turn
  /// are skipped, so a long folder draws only what was on screen.
  func icon(for url: URL, points: CGFloat) async -> NSImage? {
    if let image = cached(url, points: points) { return image }
    let run = SizeRun()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
        queue.addOperation { [cache] in
          guard !run.cancelled else { return continuation.resume(returning: nil) }
          let image = Self.draw(NSWorkspace.shared.icon(forFile: url.path), points: points)
          if let image { cache.setObject(image, forKey: Self.key(url, points)) }
          continuation.resume(returning: image)
        }
      }
    } onCancel: {
      run.cancel()
    }
  }

  private static func draw(_ source: NSImage, points: CGFloat) -> NSImage? {
    guard case .image(let bitmap) = TileImage.image(source).rasterized(pixels: Int(points * 2)) else { return nil }
    return bitmap
  }
}

/// A file's Finder icon, blank until it has been drawn.
struct FileIcon: View {
  let url: URL
  let points: CGFloat
  @State private var image: NSImage?

  init(url: URL, points: CGFloat) {
    self.url = url
    self.points = points
    _image = State(initialValue: FileIcons.shared.cached(url, points: points))
  }

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable()
      } else {
        Color.clear
      }
    }
    .frame(width: points, height: points)
    .task(id: url) {
      if let loaded = await FileIcons.shared.icon(for: url, points: points) { image = loaded }
    }
  }
}
