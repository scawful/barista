import AppKit
import Combine
import SwiftUI

final class DockActions {
  var activate: (DockTile, CGPoint) -> Void = { _, _ in }
  var useNativeDock: () -> Void = {}
}

/// A menu item that runs a closure; the item keeps its target alive.
final class MenuChoice: NSObject {
  private let perform: () -> Void

  private init(_ perform: @escaping () -> Void) { self.perform = perform }

  static func item(_ title: String, perform: @escaping () -> Void) -> NSMenuItem {
    let choice = MenuChoice(perform)
    let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
    item.target = choice
    item.representedObject = choice
    return item
  }

  @objc private func run() { perform() }
}

/// Starts a helper without waiting for it. Its stdout is discarded, and its
/// stderr too when `quiet`; otherwise errors reach the agent's log.
/// `onExit` runs on the main queue.
func launch(_ executable: String, _ arguments: [String], quiet: Bool = false, onExit: (() -> Void)? = nil) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  process.standardInput = FileHandle.nullDevice
  process.standardOutput = FileHandle.nullDevice
  if quiet { process.standardError = FileHandle.nullDevice }
  if let onExit {
    process.terminationHandler = { _ in DispatchQueue.main.async(execute: onExit) }
  }
  do {
    try process.run()
  } catch {
    DockStore.log("could not run \(executable): \(error)")
  }
}

/// Takes typing only after a click in one of its text fields, without
/// activating the agent or taking focus otherwise.
private final class TypingPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

func makeOverlayPanel(levelOffset: Int = 0, typing: Bool = false) -> NSPanel {
  let panel = (typing ? TypingPanel.self : NSPanel.self).init(contentRect: .zero,
                                                             styleMask: [.borderless, .nonactivatingPanel],
                                                             backing: .buffered,
                                                             defer: false)
  panel.becomesKeyOnlyIfNeeded = true
  panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + levelOffset)
  panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
  panel.isOpaque = false
  panel.backgroundColor = .clear
  panel.hasShadow = false
  panel.hidesOnDeactivate = false
  panel.isMovable = false
  panel.acceptsMouseMovedEvents = true
  return panel
}

/// The agent is never the active app, so the first click must reach SwiftUI
/// instead of activating the window, and pointer tracking must stay on while
/// another app is frontmost.
final class DockHostingView<Content: View>: NSHostingView<Content> {
  var onPointer: ((CGPoint?) -> Void)?
  private var tracking: NSTrackingArea?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero,
                              options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                              owner: self, userInfo: nil)
    addTrackingArea(area)
    tracking = area
  }

  override func mouseMoved(with event: NSEvent) {
    super.mouseMoved(with: event)
    report(event)
  }

  /// The first move after the panel appears under the pointer arrives only as an enter.
  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    report(event)
  }

  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    onPointer?(nil)
  }

  private func report(_ event: NSEvent) {
    var point = convert(event.locationInWindow, from: nil)
    if !isFlipped { point.y = bounds.height - point.y }
    onPointer?(point)
  }
}

/// Hidden until the pointer touches a screen's bottom edge, then shown on
/// that screen until the pointer leaves it, like the native auto-hiding Dock.
///
/// The panel is the scene's canvas, centered on the screen's bottom edge. It
/// grows upward by `dragLift` while a tile is dragged so the tile can leave
/// the bar; the canvas stays pinned to the bottom, so nothing on screen moves.
final class DockController {
  private static let hoverSlack: CGFloat = 8
  private static let dragLift: CGFloat = 160

  private let store: DockStore
  private let scene = DockScene()
  private let panel = makeOverlayPanel()
  private let host: DockHostingView<DockView>
  private var clock: FrameClock?
  private let popover = PopoverController()
  private let card = AttentionCardController()
  private var screen: NSScreen?
  private var maxWidth: CGFloat = .greatestFiniteMagnitude
  private var monitors: [Any] = []
  private var observers: [NSObjectProtocol] = []
  private var pointerTimer: Timer?
  private var outsideSince: Date?
  private var edgeTrigger = EdgeTrigger()
  private var edgeScreen: NSScreen?
  private var menuOpen = false
  private var syncPending = false
  private var cancellables: Set<AnyCancellable> = []

  init(store: DockStore, onUseNativeDock: @escaping () -> Void) {
    self.store = store
    let actions = DockActions()
    host = DockHostingView(rootView: DockView(store: store, scene: scene, actions: actions))
    host.sizingOptions = []
    panel.contentView = host
    clock = FrameClock(view: host) { [weak self] now in self?.scene.step(now: now) ?? false }

    actions.useNativeDock = onUseNativeDock
    actions.activate = { [weak self] tile, anchor in self?.activate(tile, anchor: anchor) }
    host.onPointer = { [weak self] point in self?.pointerChanged(point) }
    scene.requestFrame = { [weak self] in self?.clock?.start() }
    scene.onLiftChange = { [weak self] _ in
      self?.relayout()
      self?.syncCard()
    }
    scene.onCommit = { [weak self] outcome in self?.commit(outcome) }

    // One refresh sets several published values; they settle into one sync.
    store.objectWillChange
      .sink { [weak self] _ in
        guard let self, !self.syncPending else { return }
        self.syncPending = true
        DispatchQueue.main.async {
          self.syncPending = false
          self.syncScene()
        }
      }
      .store(in: &cancellables)
    let menus = NotificationCenter.default
    observers = [
      menus.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
        self?.menuOpen = true
      },
      menus.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
        self?.menuOpen = false
        self?.outsideSince = nil
      },
    ]
    syncScene()
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
    monitors.forEach(NSEvent.removeMonitor)
  }

  func start() {
    monitors = [
      NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
        self?.pointerMoved(event)
      },
      // Global monitors only see clicks in other apps, so this closes a popover on outside clicks.
      NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        self?.popover.close()
      },
    ].compactMap { $0 }
  }

  func hide() {
    guard screen != nil else { return }
    screen = nil
    pointerTimer?.invalidate()
    pointerTimer = nil
    outsideSince = nil
    popover.close()
    card.hide()
    scene.hide()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self, self.screen == nil else { return }
      self.panel.orderOut(nil)
    }
  }

  /// Mouse deltas keep coming while the pointer is pinned at the screen edge,
  /// so pushing past the edge can be measured even though the pointer stays put.
  private func pointerMoved(_ event: NSEvent) {
    let edge = Self.bottomEdgeScreen(at: NSEvent.mouseLocation)
    if edge !== edgeScreen {
      edgeScreen = edge
      edgeTrigger.reset()
    }
    guard let edge, edge !== screen else { return }
    let settings = store.settings
    let arming = !edgeTrigger.isArmed
    if edgeTrigger.update(deltaY: event.deltaY, now: ProcessInfo.processInfo.systemUptime,
                          push: settings.revealPush, delay: settings.revealDelay) {
      show(on: edge)
    } else if arming {
      // Resting sends no events, so check again once the delay has passed.
      DispatchQueue.main.asyncAfter(deadline: .now() + settings.revealDelay + 0.01) { [weak self] in
        guard let self, self.edgeScreen === edge, edge !== self.screen,
              Self.bottomEdgeScreen(at: NSEvent.mouseLocation) === edge,
              self.edgeTrigger.update(deltaY: 0, now: ProcessInfo.processInfo.systemUptime,
                                      push: self.store.settings.revealPush,
                                      delay: self.store.settings.revealDelay)
        else { return }
        self.show(on: edge)
      }
    }
  }

  private func show(on target: NSScreen) {
    screen = target
    edgeTrigger.reset()
    outsideSince = nil
    popover.close()
    store.reload()
    store.refreshWindows()
    maxWidth = target.frame.width - 24
    scene.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    syncScene()
    scene.show()
    panel.setFrame(frame(on: target), display: false)
    panel.orderFrontRegardless()
    syncCard()
    if pointerTimer == nil {
      pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        self?.checkPointer()
      }
    }
  }

  /// Panel points to canvas points; the canvas sits at the panel's bottom center.
  private func pointerChanged(_ point: CGPoint?) {
    guard screen != nil else { return }
    let canvas = scene.canvas
    let bounds = host.bounds
    scene.setPointer(point.map {
      CGPoint(x: $0.x - (bounds.width - canvas.width) / 2, y: $0.y - (bounds.height - canvas.height))
    })
  }

  private func activate(_ tile: DockTile, anchor: CGPoint) {
    let opensPopover = [.group, .shelf, .controls].contains(tile.item.kind)
      || (tile.item.kind == .folder && tile.section != .trash)
    guard opensPopover else {
      popover.close()
      store.open(tile)
      return
    }
    let wasOpen = scene.openPopoverID == tile.id
    popover.close()
    guard !wasOpen, let screen else { return }
    let frame = panel.frame
    let canvas = scene.canvas
    let point = NSPoint(x: frame.midX - canvas.width / 2 + anchor.x, y: frame.minY + canvas.height - anchor.y)
    let onClose: () -> Void = { [weak self] in
      self?.scene.openPopoverID = nil
      self?.syncCard()
    }
    card.hide()
    switch tile.item.kind {
    case .group:
      popover.openGroup(tile.id, store: store, anchor: point, on: screen, onClose: onClose)
    case .shelf:
      popover.openShelf(store: store, anchor: point, on: screen, onClose: onClose)
    case .controls:
      popover.openControls(store: store, anchor: point, on: screen, onClose: onClose)
    default:
      guard let url = tile.url else { return }
      popover.openFolder(url, title: tile.name, icon: store.image(for: tile), sort: tile.item.sort ?? .added,
                         store: store,
                         anchor: point, on: screen, onClose: onClose)
    }
    scene.openPopoverID = tile.id
  }

  private func commit(_ outcome: DockScene.Outcome) {
    let tiles = store.sections.joined()
    switch outcome {
    case .move(let id, _, let index):
      if let tile = tiles.first(where: { $0.id == id }) { store.move(tile, to: index) }
    case .remove(let id):
      if let tile = tiles.first(where: { $0.id == id }) { store.remove(tile) }
    }
  }

  private func syncScene() {
    let settings = store.settings
    let tiles = store.sections.joined()
    var expanded: [String: [String]] = [:]
    for group in tiles where store.expanded.contains(group.id) {
      expanded[group.id] = group.children.map(\.id)
    }
    let attention = Set(tiles.flatMap { tile -> [DockTile] in
      expanded[tile.id] != nil ? tile.children : [tile]
    }.filter { store.hasFinished($0) || store.waiting(on: $0) > 0 }.map(\.id))
    scene.update(DockScene.Input(pinned: store.pinned.map(\.id),
                                 running: store.running.map(\.id),
                                 others: store.others.map(\.id),
                                 trash: store.trash.map { [$0.id] } ?? [],
                                 expanded: expanded,
                                 attention: attention,
                                 icon: CGFloat(settings.iconSize),
                                 magnification: CGFloat(settings.magnification),
                                 spacing: CGFloat(settings.spacing),
                                 maxWidth: maxWidth))
    relayout()
    syncCard()
  }

  /// Shows the attention card while the dock is out, nothing is dragged, and
  /// no callout is open.
  private func syncCard() {
    guard let screen, popover.frame == nil, !scene.isLifted,
          let session = store.waitingSessions.first
    else {
      card.hide()
      return
    }
    let frame = panel.frame
    let canvas = scene.canvas
    let tileX = cardTile(for: session.app).flatMap(scene.restingRect(of:))?.midX ?? canvas.width / 2
    // Just above the tallest a magnified tile gets.
    let anchor = NSPoint(x: frame.midX - canvas.width / 2 + tileX,
                         y: frame.minY + canvas.height - DockLayout.margin)
    card.show(session, more: store.waitingSessions.count - 1, store: store, anchor: anchor, on: screen)
  }

  /// The tile showing an app: its own, or its group's while the group is closed.
  private func cardTile(for app: String) -> String? {
    for tile in store.sections.joined() {
      if tile.item.bundleID == app { return tile.id }
      if let member = tile.children.first(where: { $0.item.bundleID == app }) {
        return store.expanded.contains(tile.id) ? member.id : tile.id
      }
    }
    return nil
  }

  private func relayout() {
    guard let screen else { return }
    let frame = frame(on: screen)
    if frame != panel.frame { panel.setFrame(frame, display: false) }
  }

  private func checkPointer() {
    guard let screen else { return }
    if menuOpen || scene.isDragging {
      outsideSince = nil
      return
    }
    let point = NSEvent.mouseLocation
    let dock = panel.frame
    let slack = Self.hoverSlack
    let zone = NSRect(x: dock.minX + DockLayout.margin - slack,
                      y: screen.frame.minY,
                      width: dock.width - DockLayout.margin * 2 + slack * 2,
                      height: dock.height - DockLayout.margin + slack)
    let inPopover = [popover.frame, card.frame].contains { $0?.insetBy(dx: -slack, dy: -slack).contains(point) ?? false }
    let stillSinceNavigating = popover.frame != nil && popover.pointerAtPresent == point
    if zone.contains(point) || inPopover || stillSinceNavigating {
      outsideSince = nil
    } else if let since = outsideSince {
      if Date().timeIntervalSince(since) >= store.settings.hideDelay { hide() }
    } else {
      outsideSince = Date()
    }
  }

  private func frame(on screen: NSScreen) -> NSRect {
    let canvas = scene.canvas
    let height = canvas.height + (scene.isLifted ? Self.dragLift : 0)
    return NSRect(x: (screen.frame.midX - canvas.width / 2).rounded(),
                  y: screen.frame.minY,
                  width: canvas.width,
                  height: height)
  }

  /// A screen whose bottom row of points is under the pointer and has no
  /// other screen directly below it to continue onto.
  private static func bottomEdgeScreen(at point: NSPoint) -> NSScreen? {
    let screens = NSScreen.screens
    return screens.first { screen in
      let frame = screen.frame
      guard point.x >= frame.minX, point.x < frame.maxX,
            point.y >= frame.minY - 0.5, point.y < frame.minY + 1
      else { return false }
      let below = NSPoint(x: point.x, y: frame.minY - 1)
      return !screens.contains { $0 !== screen && $0.frame.contains(below) }
    }
  }
}

/// Reveals the dock once the pointer, pinned at a bottom edge, has pushed
/// `push` points further down or rested there for `delay` seconds, so
/// brushing the edge on the way somewhere else does nothing.
struct EdgeTrigger {
  private var since: TimeInterval?
  private var pushed: CGFloat = 0

  var isArmed: Bool { since != nil }

  /// Records one pointer event at the edge (`deltaY` is positive downward);
  /// returns whether the dock should reveal.
  mutating func update(deltaY: CGFloat, now: TimeInterval, push: Double, delay: Double) -> Bool {
    if since == nil {
      since = now
      pushed = 0
    } else {
      pushed += max(0, deltaY)
    }
    return pushed >= CGFloat(push) || now - (since ?? now) >= delay
  }

  mutating func reset() {
    since = nil
    pushed = 0
  }
}
