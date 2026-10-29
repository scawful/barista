import AppKit

/// Focus for the agent's own titled windows (viewer, file browser). The agent
/// is an accessory app until one opens: then it becomes a regular app, so
/// ⌘Tab reaches it, and activates to take typing. When the last one closes it
/// goes back to accessory and hands focus to the app you were in.
enum AgentWindows {
  private static var previousApp: NSRunningApplication?

  static func bringForward(_ window: NSWindow) {
    if !NSApp.isActive, let front = NSWorkspace.shared.frontmostApplication,
       front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
      previousApp = front
    }
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
      // A bare executable has no icon of its own for the app switcher.
      NSApp.applicationIconImage = NSWorkspace.shared.icon(for: .folder)
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    // A menu item's action runs before its menu has finished closing, and
    // the close makes the window the menu came from key again, over this one.
    RunLoop.main.perform(inModes: [.default]) {
      if window.isVisible { window.makeKeyAndOrderFront(nil) }
    }
  }

  /// Call from a window's will-close; `closing` is still listed then.
  static func closed(_ closing: NSWindow) {
    let others = NSApp.windows.contains {
      $0 !== closing && ($0.isVisible || $0.isMiniaturized) && $0.styleMask.contains(.titled)
    }
    guard !others else { return }
    defer { previousApp = nil }
    let wasActive = NSApp.isActive
    NSApp.setActivationPolicy(.accessory)
    // A close button clicked from another app doesn't activate the agent;
    // focus is already where the user wants it.
    guard wasActive else { return }
    previousApp?.activate()
  }

  /// The yabai window menu at the pointer.
  static func showWindowMenu(for window: NSWindow, defaultSizeApp: String? = nil) {
    WindowMenu.make(for: window, defaultSizeApp: defaultSizeApp)
      .popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
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

/// yabai's controls for one of Barista's own windows: float or tile, where
/// it stacks, its size, and how new windows of its kind open.
enum WindowMenu {
  /// `DockSettings.windowSizes`, read and written through the dock's store.
  static var sizes: () -> [String: String] = { [:] }
  static var setSize: (String, WindowSize?) -> Void = { _, _ in }

  /// A "Window" item for a context menu; it asks yabai only when opened.
  static func item(for window: NSWindow) -> NSMenuItem {
    let holder = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
    let loader = Loader(window)
    let submenu = NSMenu(title: "Window")
    submenu.addItem(NSMenuItem(title: "Asking yabai…", action: nil, keyEquivalent: ""))
    submenu.delegate = loader
    holder.submenu = submenu
    holder.representedObject = loader
    return holder
  }

  private final class Loader: NSObject, NSMenuDelegate {
    private weak var window: NSWindow?

    init(_ window: NSWindow) { self.window = window }

    func menuNeedsUpdate(_ menu: NSMenu) {
      guard let window else { return }
      let filled = make(for: window)
      let items = filled.items
      filled.removeAllItems()
      menu.removeAllItems()
      items.forEach(menu.addItem)
    }
  }

  /// `defaultSizeApp` is the app name whose new windows the last section
  /// sizes; nil for windows that size themselves to what they show.
  static func make(for window: NSWindow, defaultSizeApp: String? = nil) -> NSMenu {
    let menu = NSMenu(title: "Window")
    menu.autoenablesItems = false
    guard let state = Yabai.state(of: window) else {
      let item = NSMenuItem(title: "yabai isn't answering", action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
      return menu
    }
    let id = String(state.id)
    func add(_ title: String, on: Bool = false, to target: NSMenu? = nil, _ perform: @escaping () -> Void) {
      let item = MenuChoice.item(title, perform: perform)
      item.state = on ? .on : .off
      (target ?? menu).addItem(item)
    }
    func submenu(_ title: String) -> NSMenu {
      let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
      holder.submenu = NSMenu(title: title)
      menu.addItem(holder)
      return holder.submenu!
    }
    /// In order, off the main thread; a grid only sizes a floating window.
    func run(_ commands: [[String]]) {
      DispatchQueue.global(qos: .userInitiated).async { commands.forEach { Yabai.run($0) } }
    }

    add("Float", on: state.isFloating) { run([["window", id, "--toggle", "float"]]) }
    let level = submenu("Level")
    for choice in WindowLevel.allCases {
      add(choice.title, on: state.level == choice, to: level) { run([["window", id, "--sub-layer", choice.subLayer]]) }
    }
    let size = submenu("Size")
    for choice in WindowSize.allCases {
      add(choice.title, to: size) {
        run((state.isFloating ? [] : [["window", id, "--toggle", "float"]]) + [["window", id, "--grid", choice.grid]])
      }
    }
    add("Next Display") { run([["window", id, "--display", "next"], ["window", id, "--focus"]]) }

    guard let app = defaultSizeApp else { return menu }
    menu.addItem(.separator())
    let current = sizes()[app].flatMap(WindowSize.init(rawValue:))
    let opens = submenu("New Windows Open")
    add("Tiled", on: current == nil, to: opens) { setSize(app, nil) }
    for choice in WindowSize.allCases {
      add("Floating, \(choice.title)", on: current == choice, to: opens) { setSize(app, choice) }
    }
    return menu
  }
}
