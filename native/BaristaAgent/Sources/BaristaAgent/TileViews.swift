import AppKit
import SwiftUI

/// A tile's picture: an app or file icon, an SF Symbol on an accent square,
/// or a group's member grid.
struct TileIcon: View {
  let image: TileImage
  let theme: DockTheme

  var body: some View {
    switch image {
    case .image(let image):
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
    case .group(let images):
      GroupGlyph(images: images, theme: theme)
    case .badged(let image, let symbol):
      GeometryReader { proxy in
        let side = min(proxy.size.width, proxy.size.height)
        let mark = side * 0.42
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .overlay(alignment: .bottomTrailing) {
            Circle()
              .fill(theme.accent)
              .overlay(Image(systemName: symbol)
                .font(.system(size: mark * 0.5, weight: .semibold))
                .foregroundColor(.white))
              .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: max(1, side / 48)))
              .shadow(color: .black.opacity(0.3), radius: side / 40, y: side / 80)
              .frame(width: mark, height: mark)
          }
          .frame(width: side, height: side)
      }
    case .symbol(let name):
      GeometryReader { proxy in
        let side = min(proxy.size.width, proxy.size.height)
        RoundedRectangle(cornerRadius: side * 0.23, style: .continuous)
          .fill(LinearGradient(colors: [theme.accent, theme.accent.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom))
          .overlay(
            Image(systemName: name)
              .font(.system(size: side * 0.44, weight: .semibold))
              .foregroundColor(.white)
          )
          .frame(width: side, height: side)
      }
      .scaleEffect(0.86)
    }
  }
}

/// A short label in an icon's corner, like an app badge: a session count,
/// a shelf count, or a badge command's output.
struct TileBadge: View {
  let text: String
  let color: Color
  let height: CGFloat

  var body: some View {
    Text(Int(text).map { $0 > 99 ? "99+" : "\($0)" } ?? text)
      .font(.system(size: height * 0.62, weight: .bold, design: .rounded))
      .foregroundColor(.white)
      .lineLimit(1)
      .padding(.horizontal, height * 0.26)
      .frame(minWidth: height, minHeight: height)
      .background(Capsule().fill(color))
      .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
      .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
      .fixedSize()
  }
}

/// An action's last result over its icon: a spinning ring while it runs,
/// then a check or a cross in the corner.
struct ActionStatus: View {
  let state: ActionRunner.State
  let theme: DockTheme
  let side: CGFloat

  var body: some View {
    switch state {
    case .running, .stopping:
      TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
        let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
        Circle()
          .trim(from: 0, to: 0.28)
          .stroke(state == .stopping ? theme.warning : theme.label.opacity(0.9),
                  style: StrokeStyle(lineWidth: max(2, side * 0.06), lineCap: .round))
          .rotationEffect(.degrees(turn * 360))
          .frame(width: side * 0.86, height: side * 0.86)
      }
    case .succeeded:
      corner("checkmark.circle.fill", color: theme.success)
    case .failed:
      corner("xmark.circle.fill", color: theme.failure)
    }
  }

  private func corner(_ symbol: String, color: Color) -> some View {
    Image(systemName: symbol)
      .font(.system(size: max(12, side * 0.32), weight: .bold))
      .foregroundStyle(.white, color)
      .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
      .frame(width: side, height: side, alignment: .bottomTrailing)
      .offset(x: 3, y: 3)
  }
}

/// A tinted rounded square holding up to four member icons, like an iOS
/// folder. It sits on the dock's or callout's blur, so it needs none of its own.
struct GroupGlyph: View {
  let images: [TileImage]
  let theme: DockTheme

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let gap = side * 0.07
      let cell = (side - gap * 3) / 2
      let shape = RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
      ZStack {
        shape
          .fill(LinearGradient(colors: [theme.label.opacity(0.22), theme.label.opacity(0.1)],
                               startPoint: .top, endPoint: .bottom))
          .overlay(shape.strokeBorder(theme.label.opacity(0.18), lineWidth: max(0.5, side / 80)))
        VStack(spacing: gap) {
          ForEach(0..<2, id: \.self) { row in
            HStack(spacing: gap) {
              ForEach(0..<2, id: \.self) { column in
                let index = row * 2 + column
                if index < images.count {
                  TileIcon(image: images[index], theme: theme).frame(width: cell, height: cell)
                } else {
                  Color.clear.frame(width: cell, height: cell)
                }
              }
            }
          }
        }
      }
      .frame(width: side, height: side)
    }
    .scaleEffect(0.9)
  }
}
