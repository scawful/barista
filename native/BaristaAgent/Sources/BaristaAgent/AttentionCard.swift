import AppKit
import SwiftUI

/// A card above the dock for the first agent session that waits on you, so a
/// question does not hide behind a badge. It points at the tile holding the
/// session's app and offers Open (bring the chat forward) and Later (set the
/// question aside until the session asks something else); right-clicking it
/// also opens the app or copies the question.
final class AttentionCardController {
  private struct Shown: Equatable {
    let session: AgentSession
    let more: Int
    let anchor: NSPoint
    let theme: DockTheme
  }

  private var panel: NSPanel?
  private var shown: Shown?

  var frame: NSRect? { panel.map(\.frame) }

  func show(_ session: AgentSession, more: Int, store: DockStore, anchor: NSPoint, on screen: NSScreen) {
    let next = Shown(session: session, more: more, anchor: anchor, theme: store.theme)
    guard next != shown else { return }
    let pointer = PopoverPointer()
    let view = { [weak self, weak store] (arrowX: CGFloat?) -> AnyView in
      AnyView(AttentionCard(session: session, more: more, theme: next.theme, arrowX: arrowX,
                            onOpen: {
                              store?.setAside(session)
                              store?.focus(session)
                              self?.hide()
                            },
                            onLater: {
                              store?.setAside(session)
                              self?.hide()
                            },
                            onOpenApp: NSWorkspace.shared.urlForApplication(withBundleIdentifier: session.app)
                              .map { app in {
                                store?.setAside(session)
                                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
                                self?.hide()
                              } })
        .environment(\.popoverPointer, pointer))
    }
    let host = DockHostingView(rootView: view(nil))
    host.onPointer = { pointer.location = $0 }
    let size = host.fittingSize
    let bounds = screen.frame
    let x = min(max(anchor.x - size.width / 2, bounds.minX), bounds.maxX - size.width).rounded()
    host.rootView = view(anchor.x - x - PopoverController.shadowRoom)
    // A new window each time also joins every Space, which a long-lived
    // panel can stop doing (see PopoverController.present).
    let card = makeOverlayPanel(levelOffset: 1)
    card.contentView = host
    card.setFrame(NSRect(x: x, y: (anchor.y + 2 - PopoverController.shadowRoom).rounded(),
                         width: size.width, height: size.height), display: true)
    card.orderFrontRegardless()
    panel?.orderOut(nil)
    panel = card
    shown = next
  }

  func hide() {
    panel?.orderOut(nil)
    panel = nil
    shown = nil
  }
}

private struct AttentionCard: View {
  let session: AgentSession
  let more: Int
  let theme: DockTheme
  let arrowX: CGFloat?
  let onOpen: () -> Void
  let onLater: () -> Void
  /// Nil when the session's app is not installed where Launch Services sees it.
  let onOpenApp: (() -> Void)?

  var body: some View {
    Callout(theme: theme, arrowX: arrowX) {
      CalloutTitle(title: session.title.isEmpty ? "Session" : session.title,
                   subtitle: "Needs you" + (more > 0 ? " · \(more) more waiting" : "")) {
        Image(systemName: "questionmark.bubble.fill")
          .font(.system(size: 20))
          .foregroundColor(session.color ?? theme.failure)
      }
    } content: {
      VStack(alignment: .leading, spacing: 12) {
        Text(session.needs)
          .font(.system(size: 13))
          .lineLimit(4)
          .fixedSize(horizontal: false, vertical: true)
          .frame(width: 300, alignment: .leading)
        HStack(spacing: 8) {
          PillButton(title: "Open", systemImage: "arrow.up.forward.app", theme: theme, action: onOpen)
          PillButton(title: "Later", systemImage: "clock", theme: theme, action: onLater)
        }
      }
    }
    .contextMenu {
      Button("Go to Session", action: onOpen)
      if let onOpenApp { Button("Open App", action: onOpenApp) }
      Button("Later", action: onLater)
      Divider()
      Button("Copy Question") { copyText(session.needs) }
      Button("Copy Title") { copyText(session.title.isEmpty ? "Session" : session.title) }
    }
  }
}
