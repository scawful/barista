import AppKit

/// What a tile draws; `TileIcon` renders each case.
enum TileImage {
  case image(NSImage)
  case symbol(String)
  /// A group's first few member icons, drawn as a small grid.
  case group([TileImage])
  /// An icon with a symbol in its corner, such as a folder shown with the
  /// icon of the app it belongs to.
  case badged(NSImage, symbol: String)

  /// A tile's `icon`: `sf:<symbol>`, an image file, or any path whose
  /// Finder icon to borrow (an app, a folder). Nil when it names nothing.
  static func custom(_ spec: String?) -> TileImage? {
    guard let spec, !spec.isEmpty else { return nil }
    if spec.hasPrefix("sf:") {
      let name = String(spec.dropFirst(3))
      return NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? nil : .symbol(name)
    }
    let path = (spec as NSString).expandingTildeInPath
    guard FileManager.default.fileExists(atPath: path) else { return nil }
    if !path.hasSuffix(".app"), let image = NSImage(contentsOfFile: path) { return .image(image) }
    return .image(NSWorkspace.shared.icon(forFile: path))
  }

  /// A single bitmap `pixels` wide, so magnification never redraws a
  /// workspace icon's many representations. Symbols and grids pass through.
  ///
  /// Draws in pixels: the context's coordinates follow the rep's size when it
  /// is created, so the rep only gets its 2x point size afterwards.
  func rasterized(pixels: Int) -> TileImage {
    guard case .image(let source) = self,
          let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep)
    else { return self }
    let side = CGFloat(pixels)
    let fit = side / max(source.size.width, source.size.height, 1)
    let drawn = NSSize(width: source.size.width * fit, height: source.size.height * fit)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    source.draw(in: NSRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
                           width: drawn.width, height: drawn.height),
                from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    rep.size = NSSize(width: side / 2, height: side / 2)
    let bitmap = NSImage(size: rep.size)
    bitmap.addRepresentation(rep)
    return .image(bitmap)
  }
}

extension DockItem {
  /// A folder or file whose `icon` is an app's would look like that app, so
  /// it carries a folder or document mark.
  var borrowedIconBadge: String? {
    guard let spec = icon, spec.hasSuffix(".app") else { return nil }
    switch kind {
    case .folder: return "folder.fill"
    case .file: return "doc.fill"
    default: return nil
    }
  }
}
