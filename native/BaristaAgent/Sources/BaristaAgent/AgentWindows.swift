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

  /// The yabai window menu where the pointer was, once yabai has answered.
  static func showWindowMenu(for window: NSWindow, defaultSizeApp: String? = nil) {
    let number = window.windowNumber
    let point = NSEvent.mouseLocation
    DispatchQueue.global(qos: .userInitiated).async {
      let state = Yabai.state(ofWindow: number)
      DispatchQueue.main.async {
        WindowMenu.make(state, defaultSizeApp: defaultSizeApp).popUp(positioning: nil, at: point, in: nil)
      }
    }
  }

  /// Accessory apps have no visible menu bar until activated, but key equivalents
  /// and standard macOS app menus go through the main menu.
  static func installMainMenu() {
    let main = NSMenu()

    // 1. App Menu ("barista-agent")
    let appMenu = NSMenu(title: "barista-agent")
    appMenu.addItem(withTitle: "About barista-agent", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    let settingsItem = NSMenuItem(title: "Settings…", action: #selector(MenuHandler.openSettings), keyEquivalent: ",")
    settingsItem.target = MenuHandler.shared
    appMenu.addItem(settingsItem)
    appMenu.addItem(.separator())
    let services = NSMenu(title: "Services")
    NSApp.servicesMenu = services
    let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
    servicesItem.submenu = services
    appMenu.addItem(servicesItem)
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide barista-agent", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
    hideOthers.keyEquivalentModifierMask = [.command, .option]
    appMenu.addItem(hideOthers)
    appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Quit barista-agent", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let appMenuItem = NSMenuItem(title: "barista-agent", action: nil, keyEquivalent: "")
    appMenuItem.submenu = appMenu
    main.addItem(appMenuItem)

    // 2. File Menu ("File")
    let fileMenu = NSMenu(title: "File")
    let newWindow = NSMenuItem(title: "New Window", action: #selector(MenuHandler.newWindow), keyEquivalent: "n")
    newWindow.target = MenuHandler.shared
    fileMenu.addItem(newWindow)
    let newTab = NSMenuItem(title: "New Tab", action: #selector(MenuHandler.newTab), keyEquivalent: "t")
    newTab.target = MenuHandler.shared
    fileMenu.addItem(newTab)
    fileMenu.addItem(.separator())
    fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    let closeTab = NSMenuItem(title: "Close Tab", action: #selector(MenuHandler.closeTab), keyEquivalent: "w")
    closeTab.keyEquivalentModifierMask = [.command, .shift]
    closeTab.target = MenuHandler.shared
    fileMenu.addItem(closeTab)
    let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    fileMenuItem.submenu = fileMenu
    main.addItem(fileMenuItem)

    // 3. Edit Menu ("Edit")
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
    main.addItem(editItem)

    // 4. View Menu ("View")
    let viewMenu = NSMenu(title: "View")
    let zoomIn = NSMenuItem(title: "Zoom In", action: #selector(MenuHandler.zoomIn), keyEquivalent: "=")
    zoomIn.target = MenuHandler.shared
    viewMenu.addItem(zoomIn)
    let zoomOut = NSMenuItem(title: "Zoom Out", action: #selector(MenuHandler.zoomOut), keyEquivalent: "-")
    zoomOut.target = MenuHandler.shared
    viewMenu.addItem(zoomOut)
    let actualSize = NSMenuItem(title: "Actual Size", action: #selector(MenuHandler.actualSize), keyEquivalent: "0")
    actualSize.target = MenuHandler.shared
    viewMenu.addItem(actualSize)
    let viewMenuItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
    viewMenuItem.submenu = viewMenu
    main.addItem(viewMenuItem)

    // 5. Window Menu ("Window")
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    windowMenu.addItem(.separator())
    let toggleFloat = NSMenuItem(title: "Toggle Floating", action: #selector(MenuHandler.toggleFloat), keyEquivalent: "f")
    toggleFloat.keyEquivalentModifierMask = [.command, .option]
    toggleFloat.target = MenuHandler.shared
    windowMenu.addItem(toggleFloat)
    let balance = NSMenuItem(title: "Balance Windows", action: #selector(MenuHandler.balanceWindows), keyEquivalent: "b")
    balance.keyEquivalentModifierMask = [.command, .option]
    balance.target = MenuHandler.shared
    windowMenu.addItem(balance)
    windowMenu.addItem(.separator())
    windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
    let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
    windowMenuItem.submenu = windowMenu
    main.addItem(windowMenuItem)
    NSApp.windowsMenu = windowMenu

    // 6. Help Menu ("Help")
    let helpMenu = NSMenu(title: "Help")
    let helpItem = NSMenuItem(title: "barista-agent Help", action: #selector(MenuHandler.openHelp), keyEquivalent: "?")
    helpItem.target = MenuHandler.shared
    helpMenu.addItem(helpItem)
    let helpMenuItem = NSMenuItem(title: "Help", action: nil, keyEquivalent: "")
    helpMenuItem.submenu = helpMenu
    main.addItem(helpMenuItem)
    NSApp.helpMenu = helpMenu

    NSApp.mainMenu = main
    MenuHandler.shared.startObserving()
    MenuHandler.shared.updateAppMenu()
  }

  static func installEditMenu() {
    installMainMenu()
  }
}

final class MenuHandler: NSObject {
  static let shared = MenuHandler()
  private var observing = false

  func startObserving() {
    guard !observing else { return }
    observing = true
    NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
      self?.updateAppMenu()
    }
    NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.updateAppMenu()
    }
  }

  func updateAppMenu() {
    guard let main = NSApp.mainMenu, let appMenuItem = main.items.first, let appMenu = appMenuItem.submenu else { return }
    let title = NSApp.keyWindow?.title ?? ""
    let isViewer = title.hasSuffix(ViewerController.titleSuffix.trimmingCharacters(in: .whitespaces))
    let isBrowser = title.hasSuffix(BrowserController.titleSuffix.trimmingCharacters(in: .whitespaces))
    let name = isViewer ? "Barista View" : (isBrowser ? "Barista Files" : "Barista")
    appMenuItem.title = name
    appMenu.title = name
    if let about = appMenu.items.first { about.title = "About \(name)" }
    for item in appMenu.items {
      if item.action == #selector(NSApplication.hide(_:)) { item.title = "Hide \(name)" }
      else if item.action == #selector(NSApplication.terminate(_:)) { item.title = "Quit \(name)" }
    }
  }

  @objc func openSettings() {
    SettingsWindowController.shared.show()
  }

  @objc func newWindow() {
    BrowserController.shared.open(FileManager.default.homeDirectoryForCurrentUser, newWindow: true)
  }

  @objc func newTab() {
    BrowserController.shared.open(FileManager.default.homeDirectoryForCurrentUser, newWindow: false)
  }

  @objc func closeTab() {
    NSApp.keyWindow?.performClose(nil)
  }

  @objc func zoomIn() { zoom(1) }

  @objc func zoomOut() { zoom(-1) }

  @objc func actualSize() { zoom(0) }

  /// One step bigger or smaller, or back to actual size at 0: the picture or
  /// movie in a viewer, the icons in a browser.
  private func zoom(_ step: Int) {
    guard let window = NSApp.keyWindow else { return }
    if let media = ViewerController.shared.media(in: window) {
      if step == 0 { media.magnify(to: 1) } else { media.magnify(by: step) }
    } else if let state = BrowserController.shared.state(in: window) {
      if step == 0 { state.resetIconSize() } else { state.stepIconSize(step) }
    } else {
      NSSound.beep()
    }
  }

  @objc func toggleFloat() {
    if let window = NSApp.keyWindow {
      let id = String(window.windowNumber)
      DispatchQueue.global(qos: .userInitiated).async {
        if let state = Yabai.state(ofWindow: window.windowNumber) {
          if state.isFloating {
            Yabai.run(["window", id, "--toggle", "float"])
            Yabai.run(["window", id, "--sub-layer", "below"])
            Yabai.run(["space", "--balance"])
          } else {
            Yabai.run(["window", id, "--toggle", "float"])
            Yabai.run(["window", id, "--sub-layer", "below"])
          }
        } else {
          Yabai.run(["window", id, "--toggle", "float"])
        }
      }
    }
  }

  @objc func balanceWindows() {
    DispatchQueue.global(qos: .userInitiated).async {
      Yabai.run(["space", "--balance"])
    }
  }

  @objc func openHelp() {
    let readme = URL(fileURLWithPath: NSHomeDirectory() + "/src/lab/barista/README.md")
    if FileManager.default.fileExists(atPath: readme.path) {
      NSWorkspace.shared.open(readme)
    }
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

  /// Asks yabai when the submenu opens and fills it in while it shows.
  private final class Loader: NSObject, NSMenuDelegate {
    private let number: Int
    private var asked = false

    init(_ window: NSWindow) { number = window.windowNumber }

    func menuNeedsUpdate(_ menu: NSMenu) {
      guard !asked else { return }
      asked = true
      DispatchQueue.global(qos: .userInitiated).async { [number] in
        let state = Yabai.state(ofWindow: number)
        DispatchQueue.main.async { [weak menu] in
          guard let menu else { return }
          let filled = make(state)
          let items = filled.items
          filled.removeAllItems()
          menu.removeAllItems()
          items.forEach(menu.addItem)
        }
      }
    }
  }

  /// `defaultSizeApp` is the app name whose new windows the last section
  /// sizes; nil for windows that size themselves to what they show.
  static func make(_ state: YabaiWindowState?, defaultSizeApp: String? = nil) -> NSMenu {
    let menu = NSMenu(title: "Window")
    menu.autoenablesItems = false
    guard let state else {
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

    add("Float", on: state.isFloating) {
      if state.isFloating {
        run([["window", id, "--toggle", "float"], ["window", id, "--sub-layer", "below"], ["space", "--balance"]])
      } else {
        run([["window", id, "--toggle", "float"], ["window", id, "--sub-layer", "below"]])
      }
    }
    add("Balance Windows") { run([["space", "--balance"]]) }
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
