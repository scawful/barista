import CoreGraphics
import Foundation

/// Dock geometry in a top-left canvas. Magnified tiles widen the bar around
/// the pointer like the native Dock. Pure math with no state; `DockScene`
/// animates between the frames it returns.
struct DockLayout {
  enum Slot: Equatable {
    case tile(String)
    case divider(Int)

    var id: String {
      switch self {
      case .tile(let id): return id
      case .divider(let index): return "divider.\(index)"
      }
    }
  }

  struct Frames {
    let bar: CGRect
    let slots: [CGRect]
  }

  /// Hover background around each icon.
  static let inset: CGFloat = 3
  static let padding: CGFloat = 5
  /// Room under the icons for the running-app dot.
  static let indicator: CGFloat = 6
  static let edgeGap: CGFloat = 6
  static let dividerWidth: CGFloat = 9
  /// Transparent room for the bar's shadow and the drag "Remove" label.
  static let margin: CGFloat = 24

  let slots: [Slot]
  let icon: CGFloat
  let magnification: CGFloat
  let spacing: CGFloat
  private(set) var canvas: CGSize = .zero

  /// Shrinks icons when the base bar would be wider than `maxWidth`.
  init(slots: [Slot], icon: CGFloat, magnification: CGFloat, spacing: CGFloat,
       maxWidth: CGFloat = .greatestFiniteMagnitude) {
    self.slots = slots
    self.magnification = max(1, magnification)
    self.spacing = spacing
    let tiles = slots.filter { if case .tile = $0 { return true } else { return false } }.count
    let fixed = Self.padding * 2 + Self.margin * 2
      + Self.dividerWidth * CGFloat(slots.count - tiles)
      + spacing * CGFloat(max(0, slots.count - 1))
      + Self.inset * 2 * CGFloat(tiles)
    let fit = tiles > 0 ? ((maxWidth - fixed) / CGFloat(tiles)).rounded(.down) : icon
    self.icon = max(16, min(icon, fit))

    let key = WidestKey(dividers: slots.map { if case .divider = $0 { return true } else { return false } },
                        icon: self.icon, magnification: self.magnification, spacing: spacing)
    let widest: CGFloat
    if let cached = Self.widestCache[key] {
      widest = cached
    } else {
      widest = widestBar()
      if Self.widestCache.count > 32 { Self.widestCache.removeAll() }
      Self.widestCache[key] = widest
    }
    canvas = CGSize(width: (widest + Self.margin * 2).rounded(.up),
                    height: (Self.margin + headroom + barHeight + Self.edgeGap).rounded(.up))
  }

  private struct WidestKey: Hashable {
    let dividers: [Bool]
    let icon: CGFloat
    let magnification: CGFloat
    let spacing: CGFloat
  }

  /// The scene rebuilds layouts every frame; the widest bar only changes
  /// with the slot sequence and size settings. Main thread only.
  private static var widestCache: [WidestKey: CGFloat] = [:]

  /// The bar at its widest as the pointer sweeps across it.
  private func widestBar() -> CGFloat {
    var widest = barWidth(widths(scales(baseX: nil)))
    guard magnification > 1 else { return widest }
    let base = widest
    var u: CGFloat = 0
    while u <= base {
      widest = max(widest, barWidth(widths(scales(baseX: u))))
      u += 2
    }
    return widest
  }

  static func slots(for sections: [[String]]) -> [Slot] {
    var slots: [Slot] = []
    for (index, section) in sections.filter({ !$0.isEmpty }).enumerated() {
      if index > 0 { slots.append(.divider(index)) }
      slots += section.map(Slot.tile)
    }
    return slots
  }

  var tileBase: CGFloat { icon + Self.inset * 2 }
  var barHeight: CGFloat { tileBase + Self.padding * 2 + Self.indicator }
  /// Extra height a fully magnified tile needs above the bar.
  var headroom: CGFloat { icon * (magnification - 1) }
  var barTop: CGFloat { canvas.height - Self.edgeGap - barHeight }
  /// Distance from the pointer at which magnification fades out.
  private var reach: CGFloat { tileBase * 2.4 }

  /// `amount` scales magnification from none (0) to full (1), so it can ease
  /// in and out while the pointer arrives and leaves.
  func frames(baseX: CGFloat?, amount: CGFloat = 1) -> Frames {
    let widths = self.widths(scales(baseX: baseX, amount: amount))
    let width = barWidth(widths)
    let bar = CGRect(x: (canvas.width - width) / 2, y: barTop, width: width, height: barHeight)
    let bottom = bar.maxY - Self.padding - Self.indicator
    var x = bar.minX + Self.padding
    let rects = zip(slots, widths).map { slot, width -> CGRect in
      defer { x += width + spacing }
      if case .divider = slot {
        let height = tileBase * 0.7
        return CGRect(x: x, y: bottom - (tileBase + height) / 2, width: width, height: height)
      }
      return CGRect(x: x, y: bottom - width, width: width, height: width)
    }
    return Frames(bar: bar, slots: rects)
  }

  /// The unmagnified x that ends up under canvas x `p` once magnified, so
  /// the tile under the pointer stays under it as its neighbours grow.
  func baseX(forCanvasX p: CGFloat, amount: CGFloat = 1) -> CGFloat {
    var low = -canvas.width
    var high = canvas.width * 2
    for _ in 0..<24 {
      let mid = (low + high) / 2
      if canvasX(ofBaseX: mid, amount: amount) < p { low = mid } else { high = mid }
    }
    return (low + high) / 2
  }

  func canvasX(ofBaseX u: CGFloat, amount: CGFloat = 1) -> CGFloat {
    let widths = self.widths(scales(baseX: u, amount: amount))
    var base = Self.padding
    var expanded = (canvas.width - barWidth(widths)) / 2 + Self.padding
    if u <= base { return expanded - (base - u) }
    for (slot, width) in zip(slots, widths) {
      let baseWidth = self.baseWidth(slot)
      if u <= base + baseWidth { return expanded + (u - base) / baseWidth * width }
      if u <= base + baseWidth + spacing { return expanded + width + (u - base - baseWidth) }
      base += baseWidth + spacing
      expanded += width + spacing
    }
    return expanded + (u - base)
  }

  func scales(baseX u: CGFloat?, amount: CGFloat = 1) -> [CGFloat] {
    var x = Self.padding
    return slots.map { slot in
      let width = baseWidth(slot)
      defer { x += width + spacing }
      guard let u, magnification > 1, amount > 0, case .tile = slot else { return 1 }
      let distance = abs(x + width / 2 - u) / reach
      guard distance < 1 else { return 1 }
      return 1 + (magnification - 1) * amount * (1 + cos(.pi * distance)) / 2
    }
  }

  private func baseWidth(_ slot: Slot) -> CGFloat {
    if case .divider = slot { return Self.dividerWidth }
    return tileBase
  }

  private func widths(_ scales: [CGFloat]) -> [CGFloat] {
    zip(slots, scales).map { slot, scale in
      if case .divider = slot { return Self.dividerWidth }
      return icon * scale + Self.inset * 2
    }
  }

  private func barWidth(_ widths: [CGFloat]) -> CGFloat {
    Self.padding * 2 + widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
  }
}
