import AppKit
import ApplicationServices

/// Opens a new window in another app by pressing its own New Window menu
/// item through Accessibility, the way the native Dock's app-provided item
/// does. Apps name the item differently ("New Finder Window", Emacs's "New
/// Frame"), and Terminal keeps it in a submenu of profiles, so the menu bar is
/// searched instead of sending ⌘N, which is New Message or New Document in
/// many apps.
enum NewWindow {
  /// How well a menu item title names a new plain window: lower is better,
  /// nil when it doesn't. Private and incognito windows don't count.
  static func rank(_ title: String) -> Int? {
    let title = title.trimmingCharacters(in: .whitespaces)
    if title == "New Window" { return 0 }
    let lower = title.lowercased()
    if lower.contains("private") || lower.contains("incognito") { return nil }
    if title.hasPrefix("New "), title.hasSuffix(" Window") { return 1 }
    if title == "New Frame" { return 2 }
    return nil
  }

  /// Menus that never hold New Window and can be long.
  private static let skipped: Set<String> = ["Apple", "Help", "History", "Bookmarks"]

  private static let queue = DispatchQueue(label: "dev.barista.agent.new-window")

  /// Brings `app` forward and presses its New Window item. Accessibility
  /// waits on the app, so the search runs off the main thread. Beeps when the
  /// app has no such item, and asks for Accessibility the first time.
  static func open(_ app: NSRunningApplication) {
    guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else {
      DockStore.log("new window: Barista needs Accessibility (System Settings › Privacy & Security)")
      return NSSound.beep()
    }
    app.activate()
    let pid = app.processIdentifier
    let name = app.localizedName ?? String(pid)
    queue.async {
      let pressed = item(in: pid).map { AXUIElementPerformAction($0, kAXPressAction as CFString) == .success } ?? false
      if !pressed {
        DispatchQueue.main.async {
          DockStore.log("new window: \(name) has no New Window menu item")
          NSSound.beep()
        }
      }
    }
  }

  /// The best New Window item in `pid`'s menu bar, or the first item of its
  /// submenu when it has one.
  private static func item(in pid: pid_t) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1)
    guard let bar: AXUIElement = value(app, kAXMenuBarAttribute) else { return nil }
    var best: (rank: Int, item: AXUIElement)?
    for menu in children(bar) where !skipped.contains(value(menu, kAXTitleAttribute) ?? "") {
      for item in children(menu).flatMap(children) {
        guard let rank = NewWindow.rank(value(item, kAXTitleAttribute) ?? ""), rank < best?.rank ?? .max,
              value(item, kAXEnabledAttribute) ?? true else { continue }
        let submenu = children(item).first.map(children) ?? []
        let target = submenu.isEmpty ? item : submenu.first { value($0, kAXEnabledAttribute) ?? true }
        if let target { best = (rank, target) }
        if rank == 0 { return best?.item }
      }
    }
    return best?.item
  }

  private static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value as? T
  }

  private static func children(_ element: AXUIElement) -> [AXUIElement] {
    value(element, kAXChildrenAttribute) ?? []
  }
}
