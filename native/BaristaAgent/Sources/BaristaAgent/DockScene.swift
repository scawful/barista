import AppKit
import QuartzCore

/// The dock's geometry and motion, advanced once per display refresh.
///
/// Every frame the dock draws (the bar, each tile, the dividers) comes from
/// here, and `DockView` draws it with no SwiftUI animations of its own. Mixing
/// SwiftUI springs with per-pointer-move updates made the dock stutter: an
/// unanimated update cancels a running spring, and the AppKit blur behind the
/// bar does not follow SwiftUI animations at all.
///
/// - Magnification follows the pointer directly; only its strength
///   (`amount`) eases in and out as the pointer arrives and leaves.
/// - Order changes (a drag passing a neighbour, a drop, an app launching)
///   animate FLIP-style: a tile starts from where it was drawn and springs to
///   its new frame, so nothing ever jumps.
/// - The reveal raises tiles from the screen edge, middle first; hiding drops
///   them together.
///
/// All rects are in the canvas: a top-left space the size of `Frame.canvas`,
/// pinned to the panel's bottom center. The panel may be taller (see
/// `isLifted`); the canvas never moves within it.
final class DockScene: ObservableObject {
  struct Input: Equatable {
    /// Top-level tile ids, left to right: pins, running apps, others,
    /// minimized windows, and the Trash.
    var pinned: [String] = []
    var running: [String] = []
    var others: [String] = []
    var minimized: [String] = []
    var trash: [String] = []
    /// Groups drawn open, as their members between dividers, by group id.
    var expanded: [String: [String]] = [:]
    /// Tiles that hop after the reveal to ask for a look.
    var attention: Set<String> = []
    var icon: CGFloat = 44
    var magnification: CGFloat = 1.6
    var spacing: CGFloat = 4
    var maxWidth: CGFloat = .greatestFiniteMagnitude

    /// Each list is one section; an open group splits its list around a section of its own.
    var sections: [[String]] {
      func split(_ ids: [String]) -> [[String]] {
        var result: [[String]] = [[]]
        for id in ids {
          if let members = expanded[id] {
            result += [members, []]
          } else {
            result[result.count - 1].append(id)
          }
        }
        return result
      }
      return split(pinned) + [running] + split(others) + [minimized, trash]
    }
  }

  struct Item: Identifiable, Equatable {
    let slot: DockLayout.Slot
    var rect: CGRect
    /// 0 below the screen edge, 1 in place; overshoots slightly while springing.
    var rise: CGFloat
    var opacity: Double
    var id: String { slot.id }
  }

  struct Frame: Equatable {
    var canvas: CGSize = .zero
    var bar: CGRect = .zero
    var barRise: CGFloat = 0
    var barOpacity: Double = 0
    var items: [Item] = []
    /// How far a hidden element sits below its place.
    var slide: CGFloat = 0
    var hoveredID: String?
    var draggedID: String?
    var removing = false
  }

  /// What a drag reorders: a top-level list, or the members of an open group.
  enum Scope: Equatable {
    case list(DockConfig.List)
    case group(String)
  }

  struct Drag: Equatable {
    let id: String
    let scope: Scope
    /// Screen coordinates, which stay put while the panel grows for the drag.
    let startMouse: CGPoint
    /// Where the tile was drawn when grabbed, so it stays under the pointer at that size.
    let origin: CGRect
    var translation: CGSize = .zero
    var target: Int
    var removing = false

    var rect: CGRect { origin.offsetBy(dx: translation.width, dy: translation.height) }
  }

  enum Outcome: Equatable {
    case move(id: String, scope: Scope, index: Int)
    case remove(id: String)
  }

  @Published private(set) var frame = Frame()
  /// The folder or group tile whose popover is open.
  @Published var openPopoverID: String?

  /// Called when a drop changes the dock; the store applies it.
  var onCommit: (Outcome) -> Void = { _ in }
  /// The panel needs room above the bar from the first drag move until the
  /// dropped tile has landed.
  var onLiftChange: (Bool) -> Void = { _ in }
  /// Asks the frame clock for another `step`.
  var requestFrame: () -> Void = {}
  var reduceMotion = false
  /// The display link's timebase; tests substitute their own.
  var currentTime: () -> CFTimeInterval = CACurrentMediaTime

  private(set) var isLifted = false
  var isDragging: Bool { drag != nil || isLifted }

  private var input = Input()
  private var restFrames: [String: CGRect] = [:]
  private var pointer: CGPoint?
  private var drag: Drag?
  private var released: String?

  private var amount: CGFloat = 0
  private var focusX: CGFloat?
  private var springs: [String: RectSpring] = [:]
  private var appear: [String: CGFloat] = [:]
  private var shown: [String: CGRect] = [:]
  private var shownBar: CGRect?
  private var lastSlots: [DockLayout.Slot] = []
  private var lastRise: [String: CGFloat] = [:]
  private var lastTime: CFTimeInterval?
  /// When each attention hop began; each tile hops once per reveal.
  private var hops: [String: CFTimeInterval] = [:]
  private var hopped: Set<String> = []

  private var visible = false
  private var revealed = false
  /// When the current reveal or hide began; set by the first step after it.
  private var phaseStart: CFTimeInterval?

  private static let barKey = "bar"
  private static let springOmega: CGFloat = 2 * .pi / 0.3
  private static let hideDuration: CFTimeInterval = 0.14
  private static let fadeDuration: CFTimeInterval = 0.15
  /// Hops start once the reveal has mostly landed.
  private static let hopDelay: CFTimeInterval = 0.45
  private static let hopDuration: CFTimeInterval = 0.9

  init() {
    apply(input)
  }

  // MARK: Inputs

  func update(_ input: Input) {
    guard input != self.input else { return }
    apply(input)
    if visible { requestFrame() }
  }

  /// The canvas for the current tiles; reordering never changes it.
  private(set) var canvas: CGSize = .zero

  /// Where a tile rests without magnification, in canvas coordinates.
  func restingRect(of id: String) -> CGRect? {
    restFrames[id]
  }

  /// Where a tile's callout points: above the tile as drawn now, or above
  /// the bar under a magnified tile.
  func anchor(of id: String) -> CGPoint? {
    guard let rect = frame.items.first(where: { $0.id == id })?.rect else { return nil }
    return CGPoint(x: rect.midX, y: min(rect.minY, frame.bar.minY) - 2)
  }

  /// The pointer in canvas coordinates, or nil when it left the dock.
  func setPointer(_ point: CGPoint?) {
    guard point != pointer else { return }
    pointer = point
    if visible { requestFrame() }
  }

  /// Starts the reveal from below the screen edge.
  func show() {
    visible = true
    revealed = true
    phaseStart = nil
    amount = 0
    focusX = nil
    pointer = nil
    drag = nil
    released = nil
    springs = [:]
    appear = [:]
    shown = [:]
    shownBar = nil
    lastSlots = []
    lastRise = [:]
    lastTime = nil
    hops = [:]
    hopped = []
    if isLifted {
      isLifted = false
      onLiftChange(false)
    }
    // Publish the hidden first frame now, so a panel moving between screens
    // never shows the last frame from the old one.
    step(now: currentTime())
    requestFrame()
  }

  /// Drops every element from where it is now.
  func hide() {
    guard revealed else { return }
    revealed = false
    phaseStart = nil
    drag = nil
    requestFrame()
  }

  // MARK: Dragging

  /// Drag sideways to reorder within a list or an open group; drag well above
  /// the dock to remove. `mouse` is in screen coordinates; `translation` is the
  /// gesture's, used only to find where the drag began.
  func dragChanged(id: String, scope: Scope?, mouse: CGPoint, translation: CGSize) {
    guard let scope, revealed else { return }
    let start = drag?.startMouse
      ?? CGPoint(x: mouse.x - translation.width, y: mouse.y + translation.height)
    var next = drag ?? Drag(id: id, scope: scope, startMouse: start, origin: shown[id] ?? .zero,
                            target: index(of: id, in: scope))
    next.translation = CGSize(width: mouse.x - start.x, height: start.y - mouse.y)
    next.removing = next.translation.height < -input.icon * 1.1
    if next.removing {
      next.target = index(of: id, in: scope)
    } else {
      let center = next.origin.midX + next.translation.width
      next.target = ids(in: scope).filter { $0 != id && restMidX($0) < center }.count
    }
    drag = next
    if !isLifted {
      isLifted = true
      onLiftChange(true)
    }
    requestFrame()
  }

  /// Ends a drag. A cancelled drag (`commit: false`) springs the tile back.
  func dragEnded(commit: Bool) {
    guard let drag else { return }
    self.drag = nil
    released = drag.id
    shown[drag.id] = drag.rect
    // Each outcome is applied here before the store hears of it, so the next
    // frame does not briefly show the old order.
    if commit, drag.removing {
      var next = input
      next.pinned.removeAll { $0 == drag.id }
      next.others.removeAll { $0 == drag.id }
      next.expanded = next.expanded.mapValues { $0.filter { $0 != drag.id } }
      apply(next)
      onCommit(.remove(id: drag.id))
    } else if commit, drag.target != index(of: drag.id, in: drag.scope) {
      apply(reordered(input, drag: drag))
      onCommit(.move(id: drag.id, scope: drag.scope, index: drag.target))
    }
    requestFrame()
  }

  /// Where a drop at canvas `x` lands in `list`.
  func insertionIndex(in list: DockConfig.List, x: CGFloat) -> Int {
    ids(in: .list(list)).filter { restMidX($0) < x }.count
  }

  // MARK: Frames

  /// Advances one display frame. Returns whether more frames are needed.
  @discardableResult
  func step(now: CFTimeInterval) -> Bool {
    guard visible else { return false }
    let dt = CGFloat(min(max(now - (lastTime ?? now), 0), 1.0 / 30))
    lastTime = now
    if phaseStart == nil { phaseStart = now }
    let phaseTime = now - (phaseStart ?? now)

    let sections = drag.map { reordered(input, drag: $0).sections } ?? input.sections
    let layout = Self.layout(for: sections, input: input)
    updateHops(now: now, phaseTime: phaseTime)

    // Magnification strength eases toward full while the pointer is over the
    // bar and nothing is being dragged.
    let inReach = pointer.map { $0.y >= layout.barTop - layout.headroom } ?? false
    // Hiding keeps whatever magnification there was rather than shrinking mid-drop.
    let goal: CGFloat = revealed ? (inReach && drag == nil ? 1 : 0) : amount
    let tau: CGFloat = goal > amount ? 0.05 : 0.09
    amount += (goal - amount) * (1 - exp(-dt / tau))
    if abs(goal - amount) < 0.002 { amount = goal }
    if inReach, drag == nil, let pointer {
      focusX = layout.baseX(forCanvasX: pointer.x, amount: amount)
    }
    let target = layout.frames(baseX: amount > 0 ? focusX : nil, amount: amount)

    // FLIP: anything whose place changed starts from where it was drawn.
    if layout.slots != lastSlots, !lastSlots.isEmpty {
      for (slot, rect) in zip(layout.slots, target.slots) where slot.id != drag?.id {
        if let old = shown[slot.id] {
          springs[slot.id, default: RectSpring()].retarget(from: old, to: rect)
        } else {
          appear[slot.id] = 0
        }
      }
      if let old = shownBar { springs[Self.barKey, default: RectSpring()].retarget(from: old, to: target.bar) }
    }
    if let id = released, let index = layout.slots.firstIndex(where: { $0.id == id }), let old = shown[id] {
      springs[id, default: RectSpring()].retarget(from: old, to: target.slots[index])
    }
    released = nil
    lastSlots = layout.slots

    let live = Set(layout.slots.map(\.id)).union([Self.barKey])
    springs = springs.filter { live.contains($0.key) }.mapValues { spring in
      var spring = spring
      spring.step(dt, omega: Self.springOmega)
      return spring
    }.filter { !$0.value.settled }
    appear = appear.filter { live.contains($0.key) }.mapValues { min(1, $0 + dt / 0.18) }.filter { $0.value < 1 }

    let count = layout.slots.count
    var items: [Item] = []
    items.reserveCapacity(count)
    for (index, (slot, rect)) in zip(layout.slots, target.slots).enumerated() {
      var drawn = springs[slot.id]?.apply(to: rect) ?? rect
      if slot.id == drag?.id, let drag { drawn = drag.rect }
      shown[slot.id] = drawn
      if let start = hops[slot.id] { drawn.origin.y -= Self.hop(now - start) * input.icon }
      let rise = self.rise(id: slot.id, delay: Self.stagger(index, count: count), phaseTime: phaseTime)
      let fade = Double(appear[slot.id] ?? 1)
      items.append(Item(slot: slot, rect: drawn, rise: reduceMotion ? 1 : rise,
                        opacity: opacity(rise: rise, phaseTime: phaseTime) * fade))
    }
    let bar = springs[Self.barKey]?.apply(to: target.bar) ?? target.bar
    shownBar = bar
    let barRise = rise(id: Self.barKey, delay: 0, phaseTime: phaseTime)

    let hovered = drag == nil ? pointer.flatMap { point in
      items.first { if case .tile = $0.slot { return $0.rect.contains(point) } else { return false } }?.id
    } : nil
    let next = Frame(canvas: layout.canvas, bar: bar, barRise: reduceMotion ? 1 : barRise,
                     barOpacity: opacity(rise: barRise, phaseTime: phaseTime), items: items,
                     slide: layout.barHeight + DockLayout.edgeGap + 8,
                     hoveredID: hovered, draggedID: drag?.id, removing: drag?.removing ?? false)
    if next != frame { frame = next }

    // The drag room goes once the dropped tile has landed.
    if isLifted, drag == nil, springs.isEmpty {
      isLifted = false
      onLiftChange(false)
    }

    let phaseDone = revealed
      ? phaseTime > Double(Self.stagger(0, count: count)) + 1
      : phaseTime > Self.hideDuration
    if !revealed, phaseDone { visible = false }
    return visible && (!phaseDone || amount != goal || !springs.isEmpty || !appear.isEmpty || drag != nil
                       || !hops.isEmpty)
  }

  // MARK: Private

  private func apply(_ input: Input) {
    self.input = input
    let rest = Self.layout(for: input.sections, input: input)
    canvas = rest.canvas
    restFrames = Dictionary(zip(rest.slots, rest.frames(baseX: nil, amount: 0).slots).map { ($0.id, $1) },
                            uniquingKeysWith: { first, _ in first })
  }

  private static func layout(for sections: [[String]], input: Input) -> DockLayout {
    DockLayout(slots: DockLayout.slots(for: sections), icon: input.icon, magnification: input.magnification,
               spacing: input.spacing, maxWidth: input.maxWidth)
  }

  /// Icons rise from the middle outwards.
  private static func stagger(_ index: Int, count: Int) -> CFTimeInterval {
    abs(Double(index) - Double(count - 1) / 2) * 0.016
  }

  private func ids(in scope: Scope) -> [String] {
    switch scope {
    case .list(let list): return list == .pinned ? input.pinned : input.others
    case .group(let id): return input.expanded[id] ?? []
    }
  }

  private func index(of id: String, in scope: Scope) -> Int {
    ids(in: scope).firstIndex(of: id) ?? 0
  }

  /// An open group sits where its members are drawn.
  private func restMidX(_ id: String) -> CGFloat {
    if let rect = restFrames[id] { return rect.midX }
    let members = (input.expanded[id] ?? []).compactMap { restFrames[$0] }
    guard let first = members.first, let last = members.last else { return 0 }
    return (first.minX + last.maxX) / 2
  }

  /// `input` with the dragged tile moved to where it would land.
  private func reordered(_ input: Input, drag: Drag) -> Input {
    guard !drag.removing else { return input }
    var ids = ids(in: drag.scope)
    guard let from = ids.firstIndex(of: drag.id) else { return input }
    ids.remove(at: from)
    ids.insert(drag.id, at: min(drag.target, ids.count))
    var next = input
    switch drag.scope {
    case .list(.pinned): next.pinned = ids
    case .list(.others): next.others = ids
    case .group(let id): next.expanded[id] = ids
    }
    return next
  }

  /// Starts a hop for each tile newly asking for attention, after the reveal
  /// has landed, and drops finished hops.
  private func updateHops(now: CFTimeInterval, phaseTime: CFTimeInterval) {
    hops = hops.filter { input.attention.contains($0.key) && now - $0.value < Self.hopDuration }
    hopped.formIntersection(input.attention)
    guard revealed, !reduceMotion else { return }
    for id in input.attention where !hopped.contains(id) {
      hopped.insert(id)
      hops[id] = now + max(0, Self.hopDelay - phaseTime)
    }
  }

  /// Three shrinking hops, as a fraction of the icon size.
  static func hop(_ t: CFTimeInterval) -> CGFloat {
    guard t > 0, t < hopDuration else { return 0 }
    return CGFloat(0.4 * abs(sin(.pi * t / 0.3)) * exp(-2.2 * t))
  }

  /// A spring step response (response 0.42 s, damping 0.7) delayed per
  /// element while revealing; an ease-in drop from the current rise while hiding.
  private func rise(id: String, delay: CFTimeInterval, phaseTime: CFTimeInterval) -> CGFloat {
    let value: CGFloat
    if revealed {
      let t = phaseTime - delay
      if t <= 0 {
        value = 0
      } else {
        let omega = 2 * Double.pi / 0.42, zeta = 0.7
        let damped = omega * (1 - zeta * zeta).squareRoot()
        let decay = exp(-zeta * omega * t)
        value = CGFloat(1 - decay * (cos(damped * t) + zeta * omega / damped * sin(damped * t)))
      }
      lastRise[id] = value
    } else {
      let progress = min(1, phaseTime / Self.hideDuration)
      value = (lastRise[id] ?? 1) * CGFloat(1 - progress * progress)
    }
    return value
  }

  private func opacity(rise: CGFloat, phaseTime: CFTimeInterval) -> Double {
    guard reduceMotion else { return Double(min(max(rise, 0), 1)) }
    let progress = min(1, phaseTime / Self.fadeDuration)
    return revealed ? progress : 1 - progress
  }
}

/// A critically damped spring per edge, pulling a drawn rect back onto its
/// target. Stored as the offset from the target, so the target can keep
/// moving (magnification) while the offset decays.
struct RectSpring: Equatable {
  private var x = Axis(), y = Axis(), width = Axis(), height = Axis()

  var settled: Bool { x.settled && y.settled && width.settled && height.settled }

  /// Keeps the drawn rect where it is while its target moves to `new`; velocity carries over.
  mutating func retarget(from drawn: CGRect, to new: CGRect) {
    x.offset = drawn.midX - new.midX
    y.offset = drawn.midY - new.midY
    width.offset = drawn.width - new.width
    height.offset = drawn.height - new.height
  }

  mutating func step(_ dt: CGFloat, omega: CGFloat) {
    x.step(dt, omega: omega)
    y.step(dt, omega: omega)
    width.step(dt, omega: omega)
    height.step(dt, omega: omega)
  }

  func apply(to rect: CGRect) -> CGRect {
    let w = rect.width + width.offset, h = rect.height + height.offset
    return CGRect(x: rect.midX + x.offset - w / 2, y: rect.midY + y.offset - h / 2, width: w, height: h)
  }

  private struct Axis: Equatable {
    var offset: CGFloat = 0
    var velocity: CGFloat = 0

    var settled: Bool { abs(offset) < 0.1 && abs(velocity) < 1 }

    /// The exact critically damped solution, stable at any frame time.
    mutating func step(_ dt: CGFloat, omega: CGFloat) {
      let decay = exp(-omega * dt)
      let c = velocity + omega * offset
      offset = (offset + c * dt) * decay
      velocity = (velocity - omega * c * dt) * decay
    }
  }
}

/// Calls `tick` once per refresh of the display showing `view`, and pauses
/// itself whenever `tick` returns false.
final class FrameClock: NSObject {
  private let tick: (CFTimeInterval) -> Bool
  private var link: CADisplayLink?

  init(view: NSView, tick: @escaping (CFTimeInterval) -> Bool) {
    self.tick = tick
    super.init()
    let link = view.displayLink(target: self, selector: #selector(fire(_:)))
    link.isPaused = true
    link.add(to: .main, forMode: .common)
    self.link = link
  }

  func start() {
    link?.isPaused = false
  }

  @objc private func fire(_ link: CADisplayLink) {
    if !tick(link.targetTimestamp) { link.isPaused = true }
  }
}
