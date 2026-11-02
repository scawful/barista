import AppKit
import Carbon.HIToolbox

/// One SketchyBar item as `--query` reports it, cut to what keyboard
/// navigation of the bar's menus reads.
struct BarItem: Equatable {
  var name: String
  var position = ""
  var drawing = false
  var popupDrawing = false
  var popupItems: [String] = []
  /// Nil when the item has none (SketchyBar reports `(null)`).
  var clickScript: String?
  var background = false
  var color = ""
  var hoverColor = ""
  /// Left edge and width on the first display the item reports; popup rows
  /// sit off screen while their popup is closed.
  var x = -1.0
  var width = 0.0

  init(name: String) {
    self.name = name
  }

  init?(_ json: [String: Any]) {
    guard let name = json["name"] as? String else { return nil }
    let geometry = json["geometry"] as? [String: Any] ?? [:]
    let background = geometry["background"] as? [String: Any] ?? [:]
    let popup = json["popup"] as? [String: Any] ?? [:]
    let scripting = json["scripting"] as? [String: Any] ?? [:]
    self.name = name
    position = geometry["position"] as? String ?? ""
    drawing = geometry["drawing"] as? String == "on"
    popupDrawing = popup["drawing"] as? String == "on"
    popupItems = popup["items"] as? [String] ?? []
    clickScript = (scripting["click_script"] as? String).flatMap { $0.isEmpty || $0 == "(null)" ? nil : $0 }
    self.background = background["drawing"] as? String == "on"
    color = background["color"] as? String ?? ""
    hoverColor = background["hover_color"] as? String ?? ""
    let rects = json["bounding_rects"] as? [String: Any] ?? [:]
    if let display = rects.keys.sorted().first, let rect = rects[display] as? [String: Any],
       let origin = rect["origin"] as? [Double], let size = rect["size"] as? [Double],
       let left = origin.first, let wide = size.first {
      x = left
      width = wide
    }
  }
}

enum BarMenus {
  /// A row's own background, kept while the keyboard paints it.
  struct Lit: Equatable {
    var name: String
    var drawing: Bool
    var color: String
    var hover: String
  }

  /// `--query a --query b` prints the objects one after another; this cuts
  /// them apart, skipping braces inside strings and any text between objects.
  static func objects(_ data: Data) -> [Data] {
    var objects: [Data] = []
    var depth = 0
    var start = data.startIndex
    var inString = false
    var escaped = false
    for index in data.indices {
      let byte = data[index]
      if inString {
        if escaped {
          escaped = false
        } else if byte == UInt8(ascii: "\\") {
          escaped = true
        } else if byte == UInt8(ascii: "\"") {
          inString = false
        }
        continue
      }
      switch byte {
      case UInt8(ascii: "\"") where depth > 0:
        inString = true
      case UInt8(ascii: "{"):
        if depth == 0 { start = index }
        depth += 1
      case UInt8(ascii: "}") where depth > 0:
        depth -= 1
        if depth == 0 { objects.append(Data(data[start...index])) }
      default:
        break
      }
    }
    return objects
  }

  static func items(_ data: Data) -> [String: BarItem] {
    let items = objects(data).compactMap { object in
      (try? JSONSerialization.jsonObject(with: object) as? [String: Any]).flatMap(BarItem.init)
    }
    return Dictionary(items.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
  }

  /// The bar's own items that open a popup, left to right as drawn.
  static func menus(_ items: [BarItem]) -> [String] {
    items.filter { $0.position != "popup" && $0.drawing && !$0.popupItems.isEmpty && $0.width > 0 && $0.x >= 0 }
      .sorted { $0.x < $1.x }
      .map(\.name)
  }

  /// Rows that do something and light up under the mouse; headers and
  /// separators have neither.
  static func selectable(_ row: BarItem) -> Bool {
    row.drawing && row.clickScript != nil && (color(row.hoverColor) ?? 0) != 0
  }

  /// The next row that can be chosen, one way or the other from `current`,
  /// wrapping at the ends; the first (or last) when nothing is chosen yet.
  static func step(_ rows: [BarItem], from current: String?, by delta: Int) -> String? {
    guard let at = rows.firstIndex(where: { $0.name == current }) else {
      return (delta < 0 ? rows.last(where: selectable) : rows.first(where: selectable))?.name
    }
    for offset in 1...rows.count {
      let index = ((at + delta * offset) % rows.count + rows.count) % rows.count
      if selectable(rows[index]) { return rows[index].name }
    }
    return nil
  }

  static func color(_ text: String) -> UInt32? {
    text.hasPrefix("0x") ? UInt32(text.dropFirst(2), radix: 16) : UInt32(text)
  }

  static func isLit(_ row: BarItem) -> Bool {
    row.background && color(row.color) == color(row.hoverColor)
  }

  /// Paints the row with its hover color, the way the mouse does.
  static func light(_ row: BarItem) -> (lit: Lit, changes: [String]) {
    (Lit(name: row.name, drawing: row.background, color: row.color, hover: row.hoverColor),
     ["--set", row.name, "background.drawing=on", "background.color=\(row.hoverColor)"])
  }

  /// Gives the row its own background back, unless something else
  /// repainted it since.
  static func restore(_ lit: Lit, current: BarItem?) -> [String] {
    guard let current, color(current.color) == color(lit.hover) else { return [] }
    return ["--set", lit.name, "background.drawing=\(lit.drawing ? "on" : "off")", "background.color=\(lit.color)"]
  }
}

/// SketchyBar's command line, as the agent drives the bar's menus. Blocking.
struct SketchyBar {
  var binary = ProcessInfo.processInfo.environment["BARISTA_SKETCHYBAR_BIN"].flatMap { $0.isEmpty ? nil : $0 }
    ?? Tool.find("sketchybar") ?? "/opt/homebrew/bin/sketchybar"

  func names() -> [String] {
    guard let data = run(["--query", "bar"]),
          let bar = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    return bar["items"] as? [String] ?? []
  }

  /// The named items as they are now, in one query; missing ones are left out.
  func items(_ names: [String]) -> [String: BarItem] {
    guard !names.isEmpty, let data = run(names.flatMap { ["--query", $0] }) else { return [:] }
    return BarMenus.items(data)
  }

  func set(_ changes: [String]) {
    if !changes.isEmpty { _ = run(changes) }
  }

  /// Runs the item's click script the way a left click would. Waits up to
  /// five seconds; a script still running after that carries on alone.
  func click(_ item: BarItem) {
    guard let script = item.clickScript else { return set(["--set", item.name, "popup.drawing=toggle"]) }
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
    environment["CONFIG_DIR"] = environment["BARISTA_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : $0 }
      ?? NSHomeDirectory() + "/.config/sketchybar"
    environment["NAME"] = item.name
    environment["SENDER"] = "mouse.clicked"
    environment["BUTTON"] = "left"
    environment["MODIFIER"] = "none"
    // invoke_popup_click.sh's guard against forwarding a click to itself.
    environment["BARISTA_POPUP_CLICK_FORWARDING"] = "1"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", script]
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    let done = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in done.signal() }
    do { try process.run() } catch { return DockStore.log("menus: \(item.name)'s click script didn't start: \(error)") }
    if done.wait(timeout: .now() + 5) == .timedOut { DockStore.log("menus: \(item.name)'s click script is still running") }
  }

  /// Standard output whatever the exit status: a query naming a missing item
  /// still prints the others.
  private func run(_ arguments: [String]) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return data
  }
}

/// The arrow keys, Return, and Esc as hot keys while the menus are being
/// navigated, so the frontmost app doesn't see them until navigation ends.
/// Carbon hot keys need no Accessibility permission. Held arrows repeat.
final class MenuKeys {
  enum Key: UInt32, CaseIterable {
    case left = 123, right = 124, down = 125, up = 126, enter = 36, keypadEnter = 76, escape = 53

    var repeats: Bool { [.left, .right, .down, .up].contains(self) }
  }

  /// Called on the main thread.
  var onKey: (Key) -> Void = { _ in }
  private static let signature: OSType = 0x4252_4D4E // "BRMN"
  private var hotKeys: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?
  private var repeating: Timer?

  func start() {
    guard handler == nil else { return }
    var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                  EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
    let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, me in
      guard let event, let me else { return OSStatus(eventNotHandledErr) }
      var id = EventHotKeyID()
      let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                     nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
      guard status == noErr, id.signature == MenuKeys.signature, let key = Key(rawValue: id.id) else {
        return OSStatus(eventNotHandledErr)
      }
      Unmanaged<MenuKeys>.fromOpaque(me).takeUnretainedValue()
        .hotKey(key, down: GetEventKind(event) == UInt32(kEventHotKeyPressed))
      return noErr
    }, events.count, &events, Unmanaged.passUnretained(self).toOpaque(), &handler)
    guard installed == noErr else { return DockStore.log("menus: no hot key handler (\(installed))") }
    for key in Key.allCases {
      var ref: EventHotKeyRef?
      let status = RegisterEventHotKey(key.rawValue, 0, EventHotKeyID(signature: Self.signature, id: key.rawValue),
                                       GetApplicationEventTarget(), 0, &ref)
      if status == noErr, let ref {
        hotKeys.append(ref)
      } else {
        DockStore.log("menus: key \(key) is taken (\(status))")
      }
    }
  }

  func stop() {
    repeating?.invalidate()
    repeating = nil
    hotKeys.forEach { UnregisterEventHotKey($0) }
    hotKeys = []
    if let handler { RemoveEventHandler(handler) }
    handler = nil
  }

  private func hotKey(_ key: Key, down: Bool) {
    repeating?.invalidate()
    repeating = nil
    guard down else { return }
    onKey(key)
    guard key.repeats else { return }
    repeating = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
      self?.repeating = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in self?.onKey(key) }
    }
  }
}

/// Moves through the bar's popup menus from the keyboard. `barista-agent
/// menus` opens the leftmost menu (or the one already open) and lights its
/// first row. Up and down move between rows; right opens a row's submenu or
/// else the next menu; left closes a submenu or else opens the previous menu;
/// Return clicks the row; Esc or the trigger again closes everything. A click,
/// another app coming forward, a Space change, or 30 idle seconds ends it.
final class BarMenuNavigator {
  private struct Level {
    var owner: String
    var selected: String?
  }

  private let bar = SketchyBar()
  private let keys = MenuKeys()
  private let queue = DispatchQueue(label: "dev.barista.agent.menus")
  // The queue's state.
  private var active = false
  private var session = 0
  private var menus: [String] = []
  /// The open menu, then each submenu opened from it.
  private var stack: [Level] = []
  private var lit: BarMenus.Lit?
  private var idle: DispatchWorkItem?
  // The main thread's.
  private var monitors: [Any] = []
  private var observers: [NSObjectProtocol] = []

  init() {
    keys.onKey = { [weak self] key in self?.queue.async { self?.press(key) } }
  }

  /// Starts navigating, or ends it when it's on.
  func toggle() {
    queue.async { [self] in active ? end(closing: true) : begin() }
  }

  private func begin() {
    let items = bar.items(bar.names())
    menus = BarMenus.menus(Array(items.values))
    guard let menu = menus.first(where: { items[$0]?.popupDrawing == true }) ?? menus.first,
          let item = items[menu] else { return DockStore.log("menus: the bar has no menus") }
    active = true
    session += 1
    let session = self.session
    DispatchQueue.main.async { [self] in
      keys.start()
      watch(session)
    }
    rearm()
    stack = [Level(owner: menu)]
    if !item.popupDrawing { bar.click(item) }
    guard let open = rows() else { return }
    show(nil, in: open.rows)
  }

  private func end(closing: Bool) {
    guard active else { return }
    active = false
    idle?.cancel()
    var changes = unlight(known: [])
    if closing { changes += stack.reversed().flatMap { ["--set", $0.owner, "popup.drawing=off"] } }
    bar.set(changes)
    stack = []
    DispatchQueue.main.async { [self] in
      keys.stop()
      unwatch()
    }
  }

  private func press(_ key: MenuKeys.Key) {
    guard active else { return }
    rearm()
    switch key {
    case .up: move(by: -1)
    case .down: move(by: 1)
    case .right: forward()
    case .left: back()
    case .enter, .keypadEnter: choose()
    case .escape: end(closing: true)
    }
  }

  private func move(by delta: Int) {
    guard let open = rows() else { return }
    show(BarMenus.step(open.rows, from: stack.last?.selected, by: delta), in: open.rows)
  }

  private func forward() {
    guard let open = rows() else { return }
    if let row = selectedRow(in: open.rows), !row.popupItems.isEmpty { enter(row) } else { switchMenu(by: 1) }
  }

  private func back() {
    guard let open = rows() else { return }
    guard stack.count > 1 else { return switchMenu(by: -1) }
    let closing = stack.removeLast()
    bar.set(unlight(known: open.rows) + ["--set", closing.owner, "popup.drawing=off"])
    guard let parent = rows() else { return }
    show(stack.last?.selected, in: parent.rows)
  }

  private func choose() {
    guard let open = rows(), let row = selectedRow(in: open.rows) else { return }
    guard row.popupItems.isEmpty else { return enter(row) }
    bar.click(row)
    guard let after = rows() else { return }
    show(stack.last?.selected, in: after.rows)
  }

  /// Opens the submenu on `row` and lights its first row.
  private func enter(_ row: BarItem) {
    if !row.popupDrawing { bar.click(row) }
    stack.append(Level(owner: row.name))
    guard let open = rows(), open.owner.name == row.name else { return }
    show(nil, in: open.rows)
  }

  /// Closes what's open and opens the menu `delta` places along the bar.
  private func switchMenu(by delta: Int) {
    guard menus.count > 1, let root = stack.first?.owner, let index = menus.firstIndex(of: root) else { return }
    let next = menus[((index + delta) % menus.count + menus.count) % menus.count]
    bar.set(unlight(known: []) + stack.reversed().flatMap { ["--set", $0.owner, "popup.drawing=off"] })
    stack = [Level(owner: next)]
    if let item = bar.items([next])[next], !item.popupDrawing { bar.click(item) }
    guard let open = rows() else { return }
    show(nil, in: open.rows)
  }

  /// The deepest menu still open and its rows, after dropping submenus that
  /// closed on their own; nil, and navigation over, once the menu itself is.
  private func rows() -> (owner: BarItem, rows: [BarItem])? {
    while let level = stack.last {
      if let owner = bar.items([level.owner])[level.owner], owner.popupDrawing {
        let rows = bar.items(owner.popupItems)
        return (owner, owner.popupItems.compactMap { rows[$0] })
      }
      stack.removeLast()
    }
    end(closing: false)
    return nil
  }

  private func selectedRow(in rows: [BarItem]) -> BarItem? {
    stack.last?.selected.flatMap { name in rows.first { $0.name == name } }
  }

  /// Lights `name`, or the first row that can be chosen, in the deepest menu.
  private func show(_ name: String?, in rows: [BarItem]) {
    let row = rows.first { $0.name == name && BarMenus.selectable($0) } ?? rows.first(where: BarMenus.selectable)
    stack[stack.count - 1].selected = row?.name
    if let lit, let row, lit.name == row.name {
      // Still the same row; paint it again if its click repainted it.
      if !BarMenus.isLit(row) { bar.set(BarMenus.light(row).changes) }
      return
    }
    var changes = unlight(known: rows)
    if let row {
      let light = BarMenus.light(row)
      lit = light.lit
      changes += light.changes
    }
    bar.set(changes)
  }

  /// The changes that give the lit row its own background back.
  private func unlight(known rows: [BarItem]) -> [String] {
    guard let lit else { return [] }
    self.lit = nil
    return BarMenus.restore(lit, current: rows.first { $0.name == lit.name } ?? bar.items([lit.name])[lit.name])
  }

  private func rearm() {
    idle?.cancel()
    let session = self.session
    let timeout = DispatchWorkItem { [weak self] in
      guard let self, self.session == session else { return }
      self.end(closing: true)
    }
    idle = timeout
    queue.asyncAfter(deadline: .now() + 30, execute: timeout)
  }

  /// Ends navigation on what takes attention elsewhere. Main thread.
  private func watch(_ session: Int) {
    let interrupt: () -> Void = { [weak self] in
      self?.queue.async {
        guard let self, self.session == session else { return }
        self.end(closing: false)
      }
    }
    let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    monitors = [
      NSEvent.addGlobalMonitorForEvents(matching: clicks) { _ in interrupt() },
      NSEvent.addLocalMonitorForEvents(matching: clicks) { event in
        interrupt()
        return event
      },
    ].compactMap { $0 }
    let center = NSWorkspace.shared.notificationCenter
    observers = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification].map {
      center.addObserver(forName: $0, object: nil, queue: .main) { _ in interrupt() }
    }
  }

  private func unwatch() {
    monitors.forEach(NSEvent.removeMonitor)
    observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    monitors = []
    observers = []
  }
}
