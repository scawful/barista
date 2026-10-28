import AppKit

/// Focus for the agent's own titled windows (viewer, file browser). The agent
/// is an accessory app: it activates to take typing when one opens, and hands
/// focus back to the app you were in when the last one closes.
enum AgentWindows {
  private static var previousApp: NSRunningApplication?

  static func bringForward(_ window: NSWindow) {
    if !NSApp.isActive, let front = NSWorkspace.shared.frontmostApplication,
       front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
      previousApp = front
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  /// Call from a window's will-close; `closing` is still listed then.
  static func closed(_ closing: NSWindow) {
    let others = NSApp.windows.contains {
      $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled)
    }
    guard !others else { return }
    previousApp?.activate()
    previousApp = nil
  }

  /// Accessory apps have no visible menu bar, but key equivalents still go
  /// through the main menu; without Edit, ⌘C does nothing in text.
  static func installEditMenu() {
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    editItem.submenu = edit
    let main = NSMenu()
    main.addItem(NSMenuItem(title: "barista-agent", action: nil, keyEquivalent: ""))
    main.addItem(editItem)
    NSApp.mainMenu = main
  }
}
