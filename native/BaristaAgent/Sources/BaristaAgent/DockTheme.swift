import AppKit
import SwiftUI

/// The `barista` theme reuses the bar's colors from Barista's `state.json`, so
/// the dock follows whichever theme the bar has.
struct DockTheme: Equatable {
  var background: Color?
  var border: Color
  var hover: Color
  var label: Color
  var accent: Color
  /// A finished agent session or a passing action.
  var success = Color(red: 0.65, green: 0.89, blue: 0.63)
  var warning = Color(red: 0.98, green: 0.89, blue: 0.69)
  var failure = Color(red: 0.95, green: 0.55, blue: 0.66)

  static let system = DockTheme(background: nil,
                                border: Color.white.opacity(0.12),
                                hover: Color.white.opacity(0.14),
                                label: .white,
                                accent: Color(nsColor: .controlAccentColor))

  static func named(_ name: String, appearance: [String: Any]) -> DockTheme {
    guard name != "system" else { return .system }
    var theme = system
    if let color = color(appearance["bar_color"]) { theme.background = color }
    if let color = color(appearance["popup_border_color"]) { theme.border = color }
    if let color = color(appearance["hover_color"]) { theme.hover = color }
    if let color = color(appearance["menu_label_color"]) { theme.label = color }
    if let color = color(appearance["submenu_hover_color"], opaque: true) { theme.accent = color }
    return theme
  }

  /// SketchyBar colors are `0xAARRGGBB` strings.
  static func color(_ value: Any?, opaque: Bool = false) -> Color? {
    guard var hex = value as? String else { return nil }
    if hex.lowercased().hasPrefix("0x") { hex.removeFirst(2) }
    guard hex.count == 8, let argb = UInt32(hex, radix: 16) else { return nil }
    func channel(_ shift: UInt32) -> Double { Double((argb >> shift) & 0xff) / 255 }
    return Color(.sRGB, red: channel(16), green: channel(8), blue: channel(0),
                 opacity: opaque ? 1 : channel(24))
  }
}

enum BaristaAppearance {
  static let stateURL: URL = {
    let dir = ProcessInfo.processInfo.environment["BARISTA_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
      ?? NSHomeDirectory() + "/.config/sketchybar"
    return URL(fileURLWithPath: dir).appendingPathComponent("state.json")
  }()

  static func load() -> [String: Any] {
    state()["appearance"] as? [String: Any] ?? [:]
  }

  /// Barista's saved float/tile mode for new windows, by app name.
  static func windowDefaults() -> [String: String] {
    let apps = (state()["window_defaults"] as? [String: Any])?["apps"] as? [String: Any] ?? [:]
    return apps.compactMapValues { ($0 as? [String: Any])?["mode"] as? String }
  }

  /// Barista's saved stacking level (`normal`, `raised`, `top`), by app name.
  static func windowLevels() -> [String: String] {
    let apps = state()["window_levels"] as? [String: Any] ?? [:]
    return apps.compactMapValues { ($0 as? [String: Any])?["level"] as? String }
  }

  private static func state() -> [String: Any] {
    guard let data = try? Data(contentsOf: stateURL),
          let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else { return [:] }
    return state
  }
}

/// The dock's and stacks' backdrop: vibrancy tinted with the theme color.
struct DockBackground: View {
  let theme: DockTheme
  let cornerRadius: CGFloat

  var body: some View {
    // Circular corners, to match the blur's mask exactly.
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .circular)
    ZStack {
      shape.fill(Color.black.opacity(0.25))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
      VisualEffectBackground(cornerRadius: cornerRadius)
      if let background = theme.background { shape.fill(background) }
      shape.fill(LinearGradient(colors: [Color.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center))
      shape.strokeBorder(theme.border, lineWidth: 1)
    }
  }
}

/// Behind-window vibrancy. With a corner radius it is rounded by a stretchable
/// mask image, which costs nothing as the view resizes every frame; a
/// SwiftUI clip shape would rebuild a layer mask each time.
struct VisualEffectBackground: NSViewRepresentable {
  var cornerRadius: CGFloat = 0

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .behindWindow
    view.state = .active
    view.maskImage = Self.mask(cornerRadius)
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {}

  private static func mask(_ radius: CGFloat) -> NSImage? {
    guard radius > 0 else { return nil }
    let side = radius * 2 + 1
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
      return true
    }
    image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
    image.resizingMode = .stretch
    return image
  }
}
