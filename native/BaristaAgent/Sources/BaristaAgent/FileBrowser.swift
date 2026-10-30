import AppKit
import Combine
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

/// Barista Files: a file browser built to tile. Each browser is one ordinary
/// window that yabai manages; its tabs are drawn inside it, and macOS window
/// tabbing is off, so tabs never turn into extra windows for the tiler.
final class BrowserController {
  static let shared = BrowserController()
  static let titleSuffix = " - Barista Files"
  private static let frameName = "Barista Files"

  /// Folders the dock shows, added under the standard places.
  var dockPlaces: () -> [(name: String, url: URL)] = { [] }

  private var windows: [NSWindow] = []
  private var states: [ObjectIdentifier: BrowserState] = [:]
  private var keyMonitor: Any?
  private var menuActions: [MenuAction] = []
  private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

  /// The browser `window` shows, if it is one.
  func state(in window: NSWindow) -> BrowserState? { states[ObjectIdentifier(window)] }

  /// Opens `url` in a new tab of the front browser, or a new browser when
  /// there is none or `newWindow`. A file or package (an app) opens its folder
  /// with it selected.
  func open(_ url: URL, newWindow: Bool = false) {
    var isFolder: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
    let browses = exists && isFolder.boolValue && !NSWorkspace.shared.isFilePackage(atPath: url.path)
    let folder = browses ? url : url.deletingLastPathComponent()
    let select = exists && !browses ? url : nil
    if !newWindow, let window = windows.last(where: { $0.isVisible }) ?? windows.last,
       let state = states[ObjectIdentifier(window)] {
      state.newTab(at: folder, selecting: select)
      present(window)
      return
    }
    let state = BrowserState(location: folder, selecting: select)
    state.places = { [weak self] in self?.dockPlaces() ?? [] }
    let window = BrowserWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                               styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
    window.watch(state)
    state.onQuickLook = { [weak window] in window?.toggleQuickLook() }
    state.undoManager = window.undoManager
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    // An empty toolbar only makes the title bar 40 points, centering the
    // window buttons on the browser's own toolbar; clicks still reach it.
    let toolbar = NSToolbar(identifier: "BaristaFiles")
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    window.toolbarStyle = .unifiedCompact
    window.titlebarSeparatorStyle = .none
    window.backgroundColor = .controlBackgroundColor
    window.acceptsMouseMovedEvents = true
    window.minSize = NSSize(width: 600, height: 300)
    let host = NSHostingView(rootView: BrowserView(state: state))
    // Otherwise SwiftUI lays the whole window out again on every change to
    // work out its smallest size, a third of a folder change's main-thread time.
    host.sizingOptions = []
    window.contentView = host
    state.onTitle = { [weak window] name in window?.title = name + Self.titleSuffix }
    state.onCloseWindow = { [weak window] in window?.performClose(nil) }
    state.onWindowMenu = { [weak window] in
      window.map { AgentWindows.showWindowMenu(for: $0, defaultSizeApp: "barista-agent") }
    }
    state.reload()
    if !window.setFrameUsingName(Self.frameName) { window.center() }
    // The first browser keeps its frame across launches; one opened beside it cascades.
    if !window.setFrameAutosaveName(Self.frameName), let last = windows.last {
      window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
    }
    windows.append(window)
    states[ObjectIdentifier(window)] = state
    closeObservers[ObjectIdentifier(window)] = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] note in
      guard let self, let closing = note.object as? NSWindow else { return }
      self.closeObservers.removeValue(forKey: ObjectIdentifier(closing)).map(NotificationCenter.default.removeObserver)
      self.windows.removeAll { $0 === closing }
      self.states[ObjectIdentifier(closing)] = nil
      if self.windows.isEmpty, let monitor = self.keyMonitor {
        NSEvent.removeMonitor(monitor)
        self.keyMonitor = nil
      }
      AgentWindows.closed(closing)
    }
    present(window)
  }

  /// The front browser as it was left, or a new one at Home.
  func show() {
    guard let window = windows.last(where: { $0.isVisible }) ?? windows.last else {
      open(FileManager.default.homeDirectoryForCurrentUser)
      return
    }
    if window.isMiniaturized { window.deminiaturize(nil) }
    present(window)
  }

  private func present(_ window: NSWindow) {
    installKeys()
    AgentWindows.bringForward(window)
  }

  /// Finder's shortcuts for tabs and navigation. Keys that edit text pass
  /// through while the search field has focus.
  private func installKeys() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = event.window, let state = self.states[ObjectIdentifier(window)] else {
        return event
      }
      // Caps Lock, keypad, and fn bits would make every pattern below miss.
      let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
      let typing = window.firstResponder is NSText
      let key = event.charactersIgnoringModifiers ?? ""
      if let place = BrowserState.goPlaces.first(where: { flags == [.command, $0.modifiers] && key.lowercased() == $0.key }) {
        self.go(state, to: place.url)
        return nil
      }
      switch (flags, event.keyCode, key) {
      // The board has no file selection for these to act on.
      case _ where state.boardShown && !typing
        && (flags.isEmpty && [36, 49, 76, 123, 124, 125, 126].contains(event.keyCode)
            || flags == .command && ([51, 125].contains(event.keyCode) || ["a", "c", "d", "o", "r"].contains(key))):
        return event
      case ([.command, .option], _, "4") where state.workspace != nil: state.showBoard.toggle()
      case (.command, _, "t"): state.newTab(at: state.tabs.selected.location)
      case (.command, _, "w"): state.closeTab(state.tabs.selectedID)
      case (.command, _, "n"): self.open(state.tabs.selected.location, newWindow: true)
      case (.command, _, "["): state.back()
      case (.command, _, "]"): state.forward()
      case (.command, _, "f"): state.focusSearch += 1
      case ([.command, .shift], _, "f"), ([.command, .shift], _, "F"):
        state.scope = .contents
        state.focusSearch += 1
      case (.command, _, "r") where !typing: state.revealSelection()
      case ([.command, .shift], _, "."), ([.command, .shift], _, ">"): state.hidden.toggle(); state.reload()
      case (.control, 48, _): state.selectNeighborTab(1)
      case ([.control, .shift], 48, _): state.selectNeighborTab(-1)
      case (.command, _, _) where Int(key).map({ (1...9).contains($0) }) == true:
        state.select(tab: state.tabs.tabs[min(Int(key)! - 1, state.tabs.tabs.count - 1)].id)
      // Finder's ⌘1–⌘3, moved under ⌥ because ⌘1–⌘9 pick tabs here.
      case ([.command, .option], _, _) where Int(key).map({ (1...3).contains($0) }) == true:
        state.layout = BrowserLayout.allCases[Int(key)! - 1]
      case (.command, 126, _): state.up()
      case (.command, 125, _), (.command, _, "o"): state.openSelection()
      case ([], 36, _) where !typing, ([], 76, _) where !typing: state.renameSelection()
      case ([], 123...126, _) where !typing && state.layout == .icons: state.moveSelection(keyCode: event.keyCode)
      // A list that has focus moves (and ⇧-extends) on its own; until one
      // is clicked, as in a new window, the arrows still move the selection.
      case ([], 125...126, _) where !typing && !(window.firstResponder is NSTableView):
        state.moveSelection(keyCode: event.keyCode)
      case ([], 124, _) where !typing && state.layout == .columns && state.selectedFolder != nil:
        state.enterSelectedFolder()
      case ([], 123, _) where !typing && state.layout == .columns: state.up()
      case ([], 49, _) where !typing: state.onQuickLook?()
      case ([.command, .shift], _, "p"), ([.command, .shift], _, "P"): state.showPreview.toggle()
      case ([.command, .shift], _, "n"), ([.command, .shift], _, "N"): state.newFolder()
      case (.command, _, "k"), ([.command, .shift], _, "g"), ([.command, .shift], _, "G"): state.jumping = true
      case (.command, _, "i") where !typing: state.getInfo()
      case (.command, 51, _) where !typing: state.trashSelection()
      case (.command, _, "a") where !typing: state.selection = Set(state.shown.map(\.url))
      case (.command, _, "c") where !typing && !state.selection.isEmpty: state.copySelection()
      case (.command, _, "d") where !typing && !state.selection.isEmpty: state.duplicateSelection()
      case (.command, _, "v") where !typing: state.paste(move: false)
      case ([.command, .option], _, "v") where !typing: state.paste(move: true)
      case (.command, _, "y") where !typing: state.onQuickLook?()
      case ([.command, .option], _, "s"): state.showSidebar.toggle()
      case ([.command, .option], _, "c") where !typing: state.copyPathnames()
      case ([.command, .control], _, "n") where !typing: state.newFolderWithSelection()
      case (.command, _, "e") where !typing: state.ejectSelectionOrShown()
      case (.command, _, "="), ([.command, .shift], _, "+"): state.stepIconSize(1)
      case (.command, _, "-"): state.stepIconSize(-1)
      case (.command, _, "0"): state.resetIconSize()
      case ([], 115, _) where !typing: state.selectFirst()
      case ([], 119, _) where !typing: state.selectLast()
      case ([], 116, _) where !typing: state.pageSelection(up: true)
      case ([], 121, _) where !typing: state.pageSelection(up: false)
      case ([.command, .shift], 51, _) where !typing: self.emptyTrash(from: window)
      case ([], _, _) where !typing && !state.boardShown && Self.typesToSelect(key),
           ([.shift], _, _) where !typing && !state.boardShown && Self.typesToSelect(key):
        state.typeSelect(key)
      default: return event
      }
      return nil
    }
    installMenus()
  }

  /// A printable character, which type-to-select takes; Space stays Quick Look.
  private static func typesToSelect(_ key: String) -> Bool {
    guard key.count == 1, key != " ", let scalar = key.unicodeScalars.first else { return false }
    return !CharacterSet.controlCharacters.contains(scalar) && !(0xF700...0xF8FF).contains(scalar.value)
  }

  private func go(_ state: BrowserState, to url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return NSSound.beep() }
    state.go(to: url)
  }

  private func emptyTrash(from window: NSWindow) {
    let alert = NSAlert()
    alert.messageText = "Empty the Trash?"
    alert.informativeText = "Items in the Trash are deleted immediately. You can't undo this."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Empty Trash")
    alert.addButton(withTitle: "Cancel")
    alert.beginSheetModal(for: window) { response in
      guard response == .alertFirstButtonReturn else { return }
      let finder = Process()
      finder.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      finder.arguments = ["-e", "tell application \"Finder\" to empty trash"]
      try? finder.run()
    }
  }

  /// The key window's browser, for menu commands.
  private var frontState: BrowserState? {
    NSApp.keyWindow.flatMap { states[ObjectIdentifier($0)] }
  }

  /// Go and View menus in the menu bar, where a browser's shortcuts can be
  /// looked up. The key monitor answers them first; these are for the mouse.
  /// Shortcuts that also edit text (⌘⌫, ⌘E, ⌘I) are left to the monitor,
  /// which knows when a field has focus.
  private func installMenus() {
    guard let main = NSApp.mainMenu, main.item(withTitle: "Go") == nil else { return }
    func item(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
              _ run: @escaping (BrowserState) -> Void) -> NSMenuItem {
      let action = MenuAction { [weak self] in if let state = self?.frontState { run(state) } }
      menuActions.append(action)
      let item = NSMenuItem(title: title, action: #selector(MenuAction.invoke), keyEquivalent: key)
      item.keyEquivalentModifierMask = modifiers
      item.target = action
      return item
    }
    let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    let view = NSMenu(title: "View")
    for (index, layout) in BrowserLayout.allCases.enumerated() {
      view.addItem(item(layout.title, "\(index + 1)", [.command, .option]) { $0.layout = layout })
    }
    view.addItem(.separator())
    let sort = NSMenu(title: "Sort By")
    for key in FileSortKey.allCases {
      sort.addItem(item(key.title) { state in
        if state.sortKey == key { state.ascending.toggle() } else { state.sortKey = key; state.ascending = key.ascendsByDefault }
      })
    }
    let sortHolder = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
    sortHolder.submenu = sort
    view.addItem(sortHolder)
    view.addItem(item("Use as Defaults") { $0.useAsDefaults() })
    view.addItem(.separator())
    view.addItem(item("Show or Hide Sidebar", "s", [.command, .option]) { $0.showSidebar.toggle() })
    view.addItem(item("Show or Hide Preview", "p", [.command, .shift]) { $0.showPreview.toggle() })
    view.addItem(item("Show or Hide Hidden Files", ".", [.command, .shift]) { $0.hidden.toggle(); $0.reload() })
    view.addItem(item("Calculate All Sizes") { $0.measuringSizes.toggle() })
    let go = NSMenu(title: "Go")
    go.addItem(item("Back", "[") { $0.back() })
    go.addItem(item("Forward", "]") { $0.forward() })
    go.addItem(item("Enclosing Folder", up) { $0.up() })
    go.addItem(.separator())
    for place in BrowserState.goPlaces {
      go.addItem(item(place.title, place.key, [.command, place.modifiers]) { [weak self] in self?.go($0, to: place.url) })
    }
    go.addItem(.separator())
    go.addItem(item("Go to Folder…", "g", [.command, .shift]) { $0.jumping = true })
    go.addItem(item("New Tab", "t") { $0.newTab(at: $0.location) })
    go.addItem(item("New Folder with Selection", "n", [.command, .control]) { $0.newFolderWithSelection() })
    // The shared View menu keeps its Zoom items, which size icons here.
    if let existingView = main.item(withTitle: "View")?.submenu {
      existingView.addItem(.separator())
      for entry in view.items {
        view.removeItem(entry)
        existingView.addItem(entry)
      }
    } else {
      let holder = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
      holder.submenu = view
      main.addItem(holder)
    }
    let goHolder = NSMenuItem(title: "Go", action: nil, keyEquivalent: "")
    goHolder.submenu = go
    if let windowIndex = main.items.firstIndex(where: { $0.title == "Window" }) {
      main.insertItem(goHolder, at: windowIndex)
    } else {
      main.addItem(goHolder)
    }
  }
}

/// A menu item's action, run on the front browser.
private final class MenuAction: NSObject, NSMenuItemValidation {
  let run: () -> Void
  init(_ run: @escaping () -> Void) { self.run = run }
  @objc func invoke() { run() }
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    NSApp.keyWindow.map { $0.title.hasSuffix(BrowserController.titleSuffix) } ?? false
  }
}

/// One browser window's tabs, listing, and selection.
final class BrowserState: ObservableObject {
  @Published var tabs: BrowserTabs
  @Published private(set) var entries: [FileEntry]?
  /// The folder's first listing is taking a while.
  @Published private(set) var loading = false
  @Published var selection: Set<URL> = []
  @Published var sortKey = FileSortKey.name { didSet { sortChanged { $0.sortKey = sortKey } } }
  @Published var ascending = true { didSet { sortChanged { $0.ascending = ascending } } }
  /// Points per icon in the icon view, one of `FolderView.iconSizes`.
  @Published var iconSize = FolderView.fallback.iconSize ?? 64 { didSet { remember { $0.iconSize = iconSize } } }
  /// Going to a folder clears it; only a change re-sorts the rows.
  @Published var query = "" { didSet { if query != oldValue { search() } } }
  @Published var scope = SearchScope.folder { didSet { if scope != oldValue { search() } } }
  /// fd or rg is running for the query.
  @Published private(set) var searching = false
  /// Why a deep search's results are partial or missing.
  @Published private(set) var searchNote: String?
  @Published var hidden = false
  @Published var showSidebar = UserDefaults.standard.object(forKey: "BaristaFilesShowSidebar") as? Bool ?? true {
    didSet { UserDefaults.standard.set(showSidebar, forKey: "BaristaFilesShowSidebar") }
  }
  @Published var showPreview = UserDefaults.standard.object(forKey: "BaristaFilesShowPreview") as? Bool ?? true {
    didSet { UserDefaults.standard.set(showPreview, forKey: "BaristaFilesShowPreview") }
  }
  /// Picking one in a folder makes the folder always open that way.
  @Published var layout = BrowserLayout.list {
    didSet {
      guard !applyingView else { return }
      showBoard = false
      remember { $0.layout = layout }
    }
  }
  /// The shown folder as a board, when it has a tasks file at its top.
  @Published private(set) var workspace: Workspace?
  /// The board in place of the listing; on again in each workspace you enter.
  @Published var showBoard = true
  /// The task or page the board's preview shows.
  @Published private(set) var picked: FileEntry?
  /// Finder's Calculate All Sizes: folders get their size, so sorting by
  /// size ranks what's taking the space.
  @Published var measuringSizes = false { didSet { if measuringSizes != oldValue { measureSizes() } } }
  /// Folders still being measured.
  @Published private(set) var sizesPending = 0
  /// The biggest shown size, which the size bars are drawn against.
  @Published private(set) var largestSize: Int64 = 0
  /// Free space on the shown folder's volume.
  @Published private(set) var available: Int64?
  /// Icons per row in the icon view, for the up and down arrows.
  var gridColumns = 1
  @Published private(set) var shown: [FileEntry] = []
  /// Bumped to move focus to the search field.
  @Published var focusSearch = 0
  /// The entry whose name is being edited in place.
  @Published var renaming: URL?
  /// Bumped to give the list keyboard focus, as after Return ends a rename.
  @Published var focusList = 0
  /// A failed file operation, shown as an alert.
  @Published var problem: String?
  /// The repo holding the shown folder, and its worktrees.
  @Published private(set) var git: GitStatus?
  @Published private(set) var worktrees: [GitWorktree] = []
  /// The nearest AFS `.context` folder, shown when nothing is selected.
  @Published private(set) var contextRoot: URL?
  @Published var jumping = false
  /// A row selected for you (going up, back, or revealing), scrolled into view.
  @Published private(set) var scrollTarget: URL?
  /// What Get Info is showing; empty when it's closed.
  @Published var inspecting: [URL] = []
  var places: () -> [(name: String, url: URL)] = { [] }
  var onTitle: ((String) -> Void)?
  var onCloseWindow: (() -> Void)?
  var onWindowMenu: (() -> Void)?
  var onQuickLook: (() -> Void)?
  /// The window's, where Move to Trash leaves its Undo.
  weak var undoManager: UndoManager?
  private var watcher: FileWatcher?
  /// The folder whose view is applied, and the layout the window had
  /// before it, which the folder keeps unless it has its own.
  private var viewedFolder: String?
  private var inheritedLayout: BrowserLayout?
  /// Set while a folder's view is applied, so applying it isn't saved as a choice.
  private var applyingView = false
  /// What Finder recorded, by folder, as last read. Every visit reads it
  /// again off the main thread; this answers until then.
  private static var finderViews: [String: FolderView.Finder] = [:]
  /// The folder (and hidden setting) the rows list, which trails `location`
  /// while a listing loads.
  private var listedFolder: String?
  private var generation = 0
  private var reloadScheduled = false
  /// Selected by the next listing; nil keeps whatever is still there.
  private var pendingSelection: Set<URL>?
  /// A deep search's rows; nil while the folder filter applies.
  private var results: [FileEntry]?
  private var searchRun: ToolRun?
  private var searchWork: DispatchWorkItem?
  /// Where a shift-click's range starts in the icon view.
  private var anchor: URL?
  /// What type-to-select has heard so far, and when it last heard a key.
  private var typed = ""
  private var typedAt = Date.distantPast
  /// Folder sizes by path, for the folder they were measured in.
  private var measured: [String: Int64] = [:]
  private var measuredIn: String?
  private var measuring: Set<String> = []
  private var sizeRuns: [SizeRun] = []

  private let views: FolderViews

  init(location: URL, selecting: URL? = nil, views: FolderViews = .shared) {
    tabs = BrowserTabs(location)
    pendingSelection = selecting.map { [$0] }
    self.views = views
    layout = views.defaults.layout ?? .list
  }

  var location: URL { tabs.selected.location }

  func reload() {
    reloadScheduled = false
    generation += 1
    let token = generation
    let folder = location
    let hidden = self.hidden
    applyView(for: folder)
    onTitle?(DisplayNames.name(of: folder))
    // Until git and the context are read again, the old ones must not show
    // against a folder outside them.
    if let root = git?.root, !folder.isWithin(root) {
      git = nil
      worktrees = []
    }
    if let context = contextRoot, !folder.isWithin(context.deletingLastPathComponent()) { contextRoot = nil }
    if measuredIn != folder.path {
      stopMeasuring()
      measured = [:]
      measuredIn = folder.path
    }
    VolumeMonitor.shared.refresh()
    PlacesMonitor.shared.refresh()
    CollectionStore.shared.refresh()
    watcher = FileWatcher(url: folder) { [weak self] in self?.scheduleReload() }
    if isDeepSearch { search() }
    let listed = "\(hidden)|\(folder.path)"
    if listed != listedFolder {
      if let cached = ListingCache.shared.entries(for: folder, hidden: hidden) {
        show(cached, listed: listed, final: false)
      } else {
        // A quick listing replaces the last folder's rows at once; a slow
        // one (a big folder, a network mount) must not leave them up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
          guard let self, self.generation == token, self.listedFolder != listed else { return }
          self.loading = true
          self.show([], listed: nil, final: false)
        }
      }
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let listing = FileListing.load(folder, hidden: hidden)
      let workspace = Workspace.load(folder)
      let finder = FolderView.Finder.read(folder)
      // With the listing, so a folder change draws once, not twice; a
      // network mount's free space waits until after it.
      let local = (try? folder.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal != false
      let context = AFSContext.find(from: folder)
      var available = local ? Volume.available(at: folder) : nil
      DispatchQueue.main.async { [weak self, available] in
        guard let self, self.generation == token else { return }
        if let listing { ListingCache.shared.store(listing, for: folder, hidden: hidden) }
        self.finderRead(finder, for: folder)
        self.loading = false
        self.show(listing, listed: listed, final: true)
        self.show(workspace)
        if self.available != available { self.available = available }
        if self.contextRoot != context { self.contextRoot = context }
        if self.measuringSizes { self.measureSizes() }
      }
      // After the listing is shown: git should never hold it up, and on a
      // network mount it would read the whole tree over the wire.
      let inspected = local ? Git.inspect(folder) : nil
      if !local { available = Volume.available(at: folder) }
      DispatchQueue.main.async { [weak self, available] in
        guard let self, self.generation == token else { return }
        if self.available != available { self.available = available }
        if self.git != inspected?.status { self.git = inspected?.status }
        if self.worktrees != inspected?.worktrees ?? [] { self.worktrees = inspected?.worktrees ?? [] }
      }
    }
  }

  /// A build or an agent can write hundreds of files in a burst; each would
  /// start a listing and a git status. At most one reload per 0.2 s follows,
  /// and a steady stream of writes can't hold it off.
  private func scheduleReload() {
    guard !reloadScheduled else { return }
    reloadScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      guard let self, self.reloadScheduled else { return }
      self.reload()
    }
  }

  var isDeepSearch: Bool { scope != .folder && !query.trimmingCharacters(in: .whitespaces).isEmpty }

  /// The folder filter applies at once; fd and rg start after a pause in
  /// typing, and each keystroke stops the run before it.
  private func search() {
    searchRun?.cancel()
    searchRun = nil
    searchWork?.cancel()
    guard isDeepSearch else {
      results = nil
      searching = false
      searchNote = nil
      refreshShown()
      return
    }
    guard let command = FileSearch.command(scope, query: query, in: location, everything: hidden) else {
      results = []
      searching = false
      searchNote = "\(scope.tool ?? "") isn't installed"
      refreshShown()
      return
    }
    let run = ToolRun()
    let root = location
    searchRun = run
    searching = true
    let work = DispatchWorkItem {
      guard let output = run.lines(command.tool, command.arguments, limit: FileSearch.limit) else { return }
      let found = FileSearch.entries(output.lines, root: root)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.searchRun === run else { return }
        self.results = found
        self.searching = false
        self.searchNote = output.complete ? nil : "Showing the first \(FileSearch.limit)"
        self.refreshShown()
        self.settleSelection()
      }
    }
    searchWork = work
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.2, execute: work)
  }

  /// `listing` as the rows: a remembered one (`final` false) until the
  /// folder's own arrives.
  private func show(_ listing: [FileEntry]?, listed: String?, final: Bool) {
    entries = listing.map { $0.map(withMeasuredSize) }
    listedFolder = listed
    refreshShown()
    // Search results are the rows then; their own run settles the selection.
    if !isDeepSearch { settleSelection(final: final) }
  }

  /// Once new rows are shown: select what an action asked for (a renamed or
  /// made file, the folder you came up from), else keep what's still there.
  /// Remembered rows can lack a file just made, so until the real listing
  /// they only take a request they can meet in full.
  private func settleSelection(final: Bool = true) {
    if let pending = pendingSelection {
      // By path: the folder you came up from is a tab's standardized
      // location, without the trailing `/` its row's URL has.
      let wanted = Set(pending.map(\.standardizedFileURL.path))
      let found = shown.map(\.url).filter { wanted.contains($0.standardizedFileURL.path) }
      guard final || found.count == wanted.count else {
        selection = selection.intersection(shown.map(\.url))
        return
      }
      selection = Set(found)
      pendingSelection = nil
      scrollTarget = selectedURLs.first
    } else {
      selection = selection.intersection(shown.map(\.url))
    }
  }

  /// Goes to the same place in another worktree, or its top when that
  /// folder isn't there.
  func switchTo(_ worktree: GitWorktree) {
    guard let root = git?.root else { return go(to: worktree.path) }
    let relative = PopoverController.relativePath(location, from: root)
    let same = relative.hasPrefix("/") ? worktree.path : worktree.path.appendingPathComponent(relative)
    var isFolder: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: same.path, isDirectory: &isFolder) && isFolder.boolValue
    go(to: exists ? same : worktree.path)
  }

  private func refreshShown() {
    shown = FileListing.sorted(results ?? FileListing.filtered(entries ?? [], query: query),
                               by: sortKey, ascending: ascending)
    largestSize = shown.compactMap(\.size).max() ?? 0
  }

  /// The shown folder's view, when the shown folder changes (or `again`,
  /// when what Finder recorded for it did).
  private func applyView(for folder: URL, again: Bool = false) {
    if !again {
      guard folder.path != viewedFolder else { return }
      inheritedLayout = viewedFolder == nil ? nil : layout
      viewedFolder = folder.path
    }
    let view = views.view(for: folder, current: inheritedLayout, finder: Self.finderViews[folder.path])
    let resorts = (view.sortKey ?? sortKey) != sortKey || (view.ascending ?? ascending) != ascending
    applyingView = true
    if let new = view.layout, new != layout { layout = new }
    if let new = view.sortKey, new != sortKey { sortKey = new }
    if let new = view.ascending, new != ascending { ascending = new }
    if let new = view.iconSize, new != iconSize { iconSize = new }
    applyingView = false
    if resorts { refreshShown() }
  }

  private func finderRead(_ finder: FolderView.Finder, for folder: URL) {
    let known = Self.finderViews[folder.path]
    Self.finderViews[folder.path] = finder
    if known != finder && viewedFolder == folder.path { applyView(for: folder, again: true) }
  }

  private func sortChanged(_ change: (inout FolderView) -> Void) {
    guard !applyingView else { return }
    refreshShown()
    remember(change)
  }

  /// A view choice made in the shown folder, kept for it.
  private func remember(_ change: (inout FolderView) -> Void) {
    guard !applyingView else { return }
    views.update(location, change)
  }

  /// `steps` of `FolderView.iconSizes` bigger, or smaller when negative; icons only.
  func stepIconSize(_ steps: Int) {
    guard layout == .icons, !boardShown else { return NSSound.beep() }
    let size = FolderView.iconSize(iconSize, steppedBy: steps)
    if size != iconSize { iconSize = size }
  }

  /// Back to the default icon size.
  func resetIconSize() {
    iconSize = FolderView.fallback.iconSize ?? 64
  }

  /// Finder's View → Use as Defaults: folders without a choice of their
  /// own, and new windows, look like this one.
  func useAsDefaults() {
    views.defaults = FolderView(layout: layout, sortKey: sortKey, ascending: ascending, iconSize: iconSize)
  }

  private func withMeasuredSize(_ entry: FileEntry) -> FileEntry {
    guard entry.isFolder else { return entry }
    var sized = entry
    sized.size = measured[entry.url.path]
    return sized
  }

  /// Measures the shown folders not yet measured, one after another; a
  /// reload while that runs adds only what's new.
  private func measureSizes() {
    guard measuringSizes else {
      stopMeasuring()
      entries = entries?.map { entry in
        var unsized = entry
        if entry.isFolder { unsized.size = nil }
        return unsized
      }
      refreshShown()
      return
    }
    let folders = (entries ?? []).filter(\.isFolder).map(\.url.path)
      .filter { measured[$0] == nil && !measuring.contains($0) }
    guard !folders.isEmpty else { return }
    measuring.formUnion(folders)
    sizesPending = measuring.count
    let run = SizeRun()
    sizeRuns.append(run)
    DispatchQueue.global(qos: .utility).async {
      for path in folders {
        guard let size = FolderSize.measure([URL(fileURLWithPath: path)], cancelled: { run.cancelled }) else { return }
        DispatchQueue.main.async { [weak self] in self?.record(path, bytes: size.bytes) }
      }
    }
  }

  private func record(_ path: String, bytes: Int64) {
    guard measuring.remove(path) != nil else { return }
    measured[path] = bytes
    sizesPending = measuring.count
    entries = entries?.map(withMeasuredSize)
    refreshShown()
  }

  private func stopMeasuring() {
    sizeRuns.forEach { $0.cancel() }
    sizeRuns = []
    measuring = []
    sizesPending = 0
  }

  /// The biggest folders first, as a disk-usage tool shows them. Not kept
  /// as the folder's sort: it's a one-off look.
  func showLargest(in folder: URL) {
    go(to: folder)
    applyingView = true
    sortKey = .size
    ascending = false
    applyingView = false
    refreshShown()
    measuringSizes = true
  }

  func go(to url: URL, selecting: URL? = nil) {
    tabs.go(to: url)
    query = ""
    selection = []
    pendingSelection = selecting.map { [$0] }
    reload()
    JumpIndex.remember(url)
  }

  /// A search result shown in its own folder, as Finder's ⌘R does.
  func revealSelection() {
    guard let url = selectedURLs.first, selection.count == 1 else { return }
    go(to: url.deletingLastPathComponent(), selecting: url)
  }

  func back() {
    let from = location
    tabs.back()
    pendingSelection = [from]
    query = ""
    reload()
  }

  func forward() {
    tabs.forward()
    pendingSelection = nil
    query = ""
    reload()
  }

  /// Up selects the folder you came from, as Finder does.
  func up() {
    guard let parent = tabs.selected.parent else { return }
    go(to: parent, selecting: location)
  }

  func newTab(at url: URL, selecting: URL? = nil) {
    tabs.open(url)
    pendingSelection = selecting.map { [$0] }
    query = ""
    reload()
  }

  /// The search filters one folder's listing, so it ends whenever the shown
  /// folder changes.
  func select(tab id: UUID) {
    tabs.select(id)
    pendingSelection = nil
    query = ""
    reload()
  }

  func selectNeighborTab(_ offset: Int) {
    tabs.selectNeighbor(offset)
    pendingSelection = nil
    query = ""
    reload()
  }

  func closeTab(_ id: UUID) {
    let shown = tabs.selectedID
    guard tabs.close(id) else {
      onCloseWindow?()
      return
    }
    if tabs.selectedID != shown { query = "" }
    reload()
  }

  /// A folder browses; a file opens with Barista's app for it, else in the
  /// viewer when it can show it, else with the system's default.
  func open(_ entry: FileEntry) {
    if entry.isFolder {
      go(to: entry.url)
    } else if let app = OpenRules.app(for: entry.url) {
      NSWorkspace.shared.open([entry.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    } else if !ViewerController.shared.open(entry.url) {
      NSWorkspace.shared.open(entry.url)
    }
  }

  func openSelection() {
    let chosen = shown.filter { selection.contains($0.url) }
    if chosen.count == 1, let entry = chosen.first {
      open(entry)
      return
    }
    // Each opens after the selected tab, so the last goes in first.
    for folder in chosen.filter(\.isFolder).reversed() { tabs.open(folder.url, select: false) }
    let files = chosen.filter { !$0.isFolder }
    // Several pictures and movies share one viewer window as tiles.
    let tiled = files.filter { OpenRules.app(for: $0.url) == nil && ViewerKind.of($0.url)?.isMedia == true }
      .map(\.url)
    if tiled.count > 1, ViewerController.shared.open(tiled) {
      files.filter { !tiled.contains($0.url) }.forEach(open)
    } else {
      files.forEach(open)
    }
  }

  /// ⌘Z puts the files back where they were, selected.
  func trashSelection() {
    let urls = Array(selection)
    guard !urls.isEmpty else { return }
    FileOperations.trash(urls, undo: undoManager, target: self) { [weak self] _, restored, problem in
      guard let self else { return }
      if let problem { self.problem = problem }
      if !restored.isEmpty { self.pendingSelection = Set(restored) }
      // The watcher sees the shown folder only; search results can be deeper.
      self.scheduleReload()
    }
  }

  /// Copies the files themselves, so ⌘V in Finder or an editor pastes them.
  func copySelection() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(Array(selection) as [NSURL])
  }

  /// The selection in list order.
  var selectedURLs: [URL] { shown.map(\.url).filter { selection.contains($0) } }

  /// The selection's info, or the shown folder's when nothing is selected.
  func getInfo() {
    let urls = selectedURLs
    inspecting = urls.isEmpty ? [location] : urls
  }

  /// Makes an untitled folder and starts naming it.
  func newFolder() {
    do {
      let folder = try FileOperations.makeFolder(in: location)
      query = ""
      pendingSelection = [folder]
      renaming = folder
      reload()
    } catch {
      problem = error.localizedDescription
    }
  }

  var boardShown: Bool { workspace != nil && showBoard }

  private func show(_ loaded: Workspace?) {
    if loaded?.root != workspace?.root {
      showBoard = true
      picked = nil
    }
    workspace = loaded
    // Read again, so a file changed under the preview shows the change.
    if let picked, FileManager.default.fileExists(atPath: picked.url.path) {
      pick(picked.url, line: picked.line)
    } else {
      picked = nil
    }
  }

  /// 1-based `line`, which a text preview scrolls to.
  func pick(_ url: URL, line: Int? = nil) {
    var entry = FileListing.entry(url)
    entry.line = line
    picked = entry
  }

  func move(_ tasks: [WorkspaceTask], to target: TaskState) {
    do {
      for task in tasks where task.state != target { try TaskFile.set(task, to: target) }
    } catch {
      problem = error.localizedDescription
    }
    reload()
  }

  func capture(task title: String) {
    do {
      try workspace?.capture(task: title)
    } catch {
      problem = error.localizedDescription
    }
    reload()
  }

  /// Starts a page and opens it for writing below its title.
  func capture(page title: String, in shelf: Workspace.Shelf) {
    guard let workspace else { return }
    do {
      let url = try workspace.capture(page: title, in: shelf)
      pick(url)
      Editor.edit(url, line: 3)
    } catch {
      problem = error.localizedDescription
    }
    reload()
  }

  func makeWorkspace() {
    do {
      try Workspace.make(in: location)
      showBoard = true
    } catch {
      problem = error.localizedDescription
    }
    reload()
  }

  func beginRename(_ url: URL) {
    selection = [url]
    renaming = url
  }

  /// Return renames the one selected item, as in Finder; ⌘O opens it.
  func renameSelection() {
    guard selection.count == 1, let url = selection.first else { return }
    beginRename(url)
  }

  /// A click in the icon view: ⌘ toggles, ⇧ extends from the last click.
  func click(_ url: URL, modifiers: NSEvent.ModifierFlags) {
    let urls = shown.map(\.url)
    if modifiers.contains(.command) {
      selection.formSymmetricDifference([url])
      anchor = url
    } else if modifiers.contains(.shift), let anchor, let from = urls.firstIndex(of: anchor),
              let to = urls.firstIndex(of: url) {
      selection = Set(urls[min(from, to)...max(from, to)])
    } else {
      selection = [url]
      anchor = url
    }
  }

  /// An arrow key: across the icon grid, or along a list.
  func moveSelection(keyCode: UInt16) {
    let urls = shown.map(\.url)
    let current = selectedURLs.last.flatMap { urls.firstIndex(of: $0) }
    guard let index = BrowserLayout.step(from: current, count: urls.count,
                                         columns: layout == .icons ? gridColumns : 1, keyCode: keyCode)
    else { return }
    selection = [urls[index]]
    anchor = urls[index]
    scrollTarget = urls[index]
  }

  func selectFirst() {
    guard let first = shown.first?.url else { return }
    selection = [first]
    anchor = first
    scrollTarget = first
  }

  func selectLast() {
    guard let last = shown.last?.url else { return }
    selection = [last]
    anchor = last
    scrollTarget = last
  }

  func pageSelection(up: Bool) {
    let urls = shown.map(\.url)
    guard !urls.isEmpty else { return }
    let step = max(1, (layout == .icons ? gridColumns : 1) * 4)
    let current = selectedURLs.last.flatMap { urls.firstIndex(of: $0) } ?? (up ? urls.count - 1 : 0)
    let next = up ? max(0, current - step) : min(urls.count - 1, current + step)
    selection = [urls[next]]
    anchor = urls[next]
    scrollTarget = urls[next]
  }

  /// The one selected folder, which the column view previews and → enters.
  var selectedFolder: URL? {
    guard selection.count == 1 else { return nil }
    return shown.first { selection.contains($0.url) && $0.isFolder }?.url
  }

  func enterSelectedFolder() {
    if let folder = selectedFolder { go(to: folder) }
  }

  /// By path: a folder's row ends in `/`, and the URL a new folder was made
  /// at doesn't.
  func isRenaming(_ url: URL) -> Bool {
    renaming.map { $0.standardizedFileURL.path == url.standardizedFileURL.path } ?? false
  }

  /// Ends the edit for `url` once: Return and losing focus both commit.
  func commitRename(_ url: URL, to name: String) {
    guard isRenaming(url) else { return }
    renaming = nil
    do {
      pendingSelection = [try FileOperations.rename(url, to: name)]
      reload()
    } catch {
      problem = error.localizedDescription
    }
  }

  func duplicateSelection() {
    perform(selectedURLs, operation: FileOperations.duplicate)
  }

  /// Zips the selection beside it and selects the archive.
  func compressSelection() {
    let urls = selectedURLs
    // One archive holds them all, so the operation runs once.
    perform(Array(urls.prefix(1)), operation: { _ in try FileOperations.compress(urls) })
  }

  static let fileURLsOnly: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

  var canPaste: Bool {
    NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: Self.fileURLsOnly)
  }

  /// Files on the clipboard (copied here or in Finder) copy into this
  /// folder, or move with `move` (⌥⌘V). Copying this folder's own files
  /// duplicates them.
  func paste(move: Bool) {
    let pasteboard = NSPasteboard.general
    let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: Self.fileURLsOnly) as? [URL] ?? []
    let copied = pasteboard.changeCount
    let target = location
    perform(urls, operation: { url in
      if url.deletingLastPathComponent().standardizedFileURL.path == target.path {
        return move ? url : try FileOperations.duplicate(url)
      }
      return try FileOperations.place(url, in: target, move: move)
    }, then: {
      // Moved files are gone from where the clipboard says, as after Finder's move.
      if move && pasteboard.changeCount == copied { pasteboard.clearContents() }
    })
  }

  /// Runs `operation` on each URL off the main thread, then selects what it
  /// made (or `selecting`) and reports what failed; `then` runs when nothing did.
  private func perform(_ urls: [URL], selecting: URL? = nil, operation: @escaping (URL) throws -> URL,
                       then: (() -> Void)? = nil) {
    guard !urls.isEmpty else { return }
    DispatchQueue.global(qos: .userInitiated).async {
      var made: [URL] = []
      var failures: [String] = []
      for url in urls {
        do { made.append(try operation(url)) } catch { failures.append(error.localizedDescription) }
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if failures.isEmpty { then?() } else { self.problem = failures.joined(separator: "\n") }
        if let selecting { self.pendingSelection = [selecting] } else if !made.isEmpty { self.pendingSelection = Set(made) }
        self.reload()
      }
    }
  }

  /// Search results come from many folders, so a drop on them has no one
  /// place to go; a row dragged a little and let go would move out of its own.
  var acceptsDrops: Bool { !isDeepSearch }

  /// Files dropped on any of the views; false when they take no drops.
  func drop(_ providers: [NSItemProvider]) -> Bool {
    guard acceptsDrops else { return false }
    var urls: [URL] = []
    let group = DispatchGroup()
    for provider in providers {
      group.enter()
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        if let url { DispatchQueue.main.async { urls.append(url) } }
        group.leave()
      }
    }
    group.notify(queue: .main) { [weak self] in self?.receive(urls) }
    return true
  }

  /// Dropped files move within a volume and copy across volumes, as in Finder.
  func receive(_ urls: [URL]) {
    guard acceptsDrops else { return }
    let target = location
    func volume(_ url: URL) -> AnyHashable? {
      (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? AnyHashable
    }
    let here = volume(target)
    let incoming = urls.filter { $0.deletingLastPathComponent().standardizedFileURL.path != target.path }
    perform(incoming, operation: { url in
      try FileOperations.place(url, in: target, move: here != nil && volume(url) == here)
    })
  }

  /// Ejects `volume`, leaving it first when it's shown, as Finder does.
  func eject(_ volume: Volume) {
    VolumeMonitor.eject(volume, done: { [weak self] in
      guard let self, self.location.isWithin(volume.url) else { return }
      self.go(to: FileManager.default.homeDirectoryForCurrentUser)
    }, failed: { [weak self] in self?.problem = $0 })
  }

  /// Mounts a remote, or remounts one whose server stopped answering, and
  /// opens it.
  func connect(_ remote: RemoteMount) {
    VolumeMonitor.shared.connect(remote, done: { [weak self] in self?.go(to: remote.url) },
                                 failed: { [weak self] in self?.problem = $0 })
  }

  /// ⌘E: the selected volumes, else the one the shown folder is on.
  func ejectSelectionOrShown() {
    let volumes = VolumeMonitor.shared.volumes
    let picked = volumes.filter { volume in selection.contains { $0.standardizedFileURL.path == volume.url.path } }
    let targets = picked.isEmpty ? Volume.holding(location, in: volumes).map { [$0] } ?? [] : picked
    targets.filter(\.canEject).forEach(eject)
  }

  /// Finder's Copy as Pathname (⌥⌘C): the selection, or the shown folder.
  func copyPathnames() {
    let urls = selectedURLs.isEmpty ? [location] : selectedURLs
    copyText(urls.map(\.path).joined(separator: "\n"))
  }

  /// Finder's New Folder with Selection (⌃⌘N): the selected items go into a
  /// new folder, which is then named.
  func newFolderWithSelection() {
    let urls = selectedURLs
    guard !urls.isEmpty, !isDeepSearch else { return }
    do {
      let folder = try FileOperations.makeFolder(in: location, named: "New Folder With Items")
      perform(urls, selecting: folder, operation: { try FileOperations.place($0, in: folder, move: true) },
              then: { [weak self] in self?.renaming = folder })
    } catch {
      problem = error.localizedDescription
    }
  }

  /// Typing a name selects the first row it starts, as in Finder; a pause
  /// of a second starts a new name.
  func typeSelect(_ characters: String) {
    let now = Date()
    typed = now.timeIntervalSince(typedAt) > 1 ? characters : typed + characters
    typedAt = now
    guard let match = shown.first(where: { $0.name.lowercased().hasPrefix(typed.lowercased()) }) else { return }
    selection = [match.url]
    anchor = match.url
    scrollTarget = match.url
  }

  /// Finder's Go menu: shortcut, title, and place. ⌘ is implied.
  static let goPlaces: [(key: String, modifiers: NSEvent.ModifierFlags, title: String, url: URL)] = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
      ("c", .shift, "Computer", URL(fileURLWithPath: "/Volumes")),
      ("h", .shift, "Home", home),
      ("d", .shift, "Desktop", home.appendingPathComponent("Desktop")),
      ("o", .shift, "Documents", home.appendingPathComponent("Documents")),
      ("l", .option, "Downloads", home.appendingPathComponent("Downloads")),
      ("a", .shift, "Applications", URL(fileURLWithPath: "/Applications")),
      ("u", .shift, "Utilities", URL(fileURLWithPath: "/Applications/Utilities")),
      ("l", .shift, "Library", home.appendingPathComponent("Library")),
      ("i", .shift, "iCloud Drive", home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")),
    ]
  }()
}

// MARK: Views

struct BrowserView: View {
  @ObservedObject var state: BrowserState
  @ObservedObject private var volumes = VolumeMonitor.shared
  @ObservedObject private var places = PlacesMonitor.shared
  @ObservedObject private var sidebarPrefs = SidebarPreferences.shared
  @ObservedObject private var collections = CollectionStore.shared
  /// The collection row files are being dragged over.
  @State private var collectionTarget: String?
  @FocusState private var searchFocused: Bool
  @AppStorage("BaristaFilesSidebarWidth") private var sidebarWidth = 180.0
  @AppStorage("BaristaFilesPreviewWidth") private var previewWidth = 320.0
  /// Sidebar sections closed by their header's chevron, one per line.
  @AppStorage("BaristaFilesCollapsedSections") private var collapsedSections = ""
  @State private var width: CGFloat = 1000
  static let surface = Color(nsColor: .controlBackgroundColor)
  private static let sidebarWidths: ClosedRange<Double> = 140...360
  private static let previewWidths: ClosedRange<Double> = 200...720

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      if state.tabs.tabs.count > 1 { tabStrip }
      if !state.query.isEmpty { scopeBar }
      Divider()
      GeometryReader { geometry in
        // A tiled window can be narrow: the panes give way so the list keeps room.
        let total = geometry.size.width
        let side = state.showSidebar ? min(sidebarWidth, total * 0.35) : 0
        let preview = state.showPreview ? min(previewWidth, max(160, total - side - 320)) : 0
        HStack(spacing: 0) {
          if state.showSidebar {
            sidebar.frame(width: side)
            PaneHandle(width: $sidebarWidth, range: Self.sidebarWidths, direction: 1)
          }
          listing.frame(maxWidth: .infinity)
          if state.showPreview {
            PaneHandle(width: $previewWidth, range: Self.previewWidths, direction: -1)
            BrowserPreview(entry: selectedEntry, state: state).frame(width: preview)
          }
        }
      }
      Divider()
      statusBar
    }
    .ignoresSafeArea(edges: .top)
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    // One surface under the sidebar, list, and preview.
    .scrollContentBackground(.hidden)
    .background(Self.surface)
    .onChange(of: state.focusSearch) { searchFocused = true }
    .sheet(isPresented: $state.jumping) { JumpView(state: state) }
    .sheet(isPresented: Binding(get: { !state.inspecting.isEmpty }, set: { if !$0 { state.inspecting = [] } })) {
      GetInfoView(urls: state.inspecting, repo: state.git?.root) { state.inspecting = [] }
    }
    .alert("Barista Files", isPresented: Binding(get: { state.problem != nil },
                                                 set: { if !$0 { state.problem = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(state.problem ?? "")
    }
  }

  private var selectedEntry: FileEntry? {
    if state.boardShown { return state.picked }
    return state.selection.count == 1 ? state.shown.first { state.selection.contains($0.url) } : nil
  }

  /// A narrow window keeps the buttons that have no key of their own.
  private var toolbar: some View {
    let compact = width < 820
    return HStack(spacing: 10) {
      HStack(spacing: 2) {
        Button { state.showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }.help("Sidebar (⌥⌘S)")
        Button(action: state.back) { Image(systemName: "chevron.left") }
          .disabled(!state.tabs.selected.canGoBack).help("Back (⌘[)")
        Button(action: state.forward) { Image(systemName: "chevron.right") }
          .disabled(!state.tabs.selected.canGoForward).help("Forward (⌘])")
        Button(action: state.up) { Image(systemName: "arrow.up") }
          .disabled(state.tabs.selected.parent == nil).help("Enclosing Folder (⌘↑)")
      }
      FolderTitle(location: state.location) { state.go(to: $0) }
      Spacer(minLength: 6)
      // Nil is the board, so while it shows any layout leaves it.
      let shown = Binding<BrowserLayout?> {
        state.boardShown ? nil : state.layout
      } set: { layout in
        if let layout { state.layout = layout } else { state.showBoard = true }
      }
      Picker("View", selection: shown) {
        if state.workspace != nil {
          Image(systemName: "checklist").accessibilityLabel("Board").help("View as Board").tag(BrowserLayout?.none)
        }
        ForEach(BrowserLayout.allCases) {
          Image(systemName: $0.symbol).help("View \($0.title)").tag(BrowserLayout?.some($0))
        }
      }
      .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.large)
      .help(state.workspace == nil ? "List, icons, or columns (⌥⌘1, ⌥⌘2, ⌥⌘3)"
            : "Board, list, icons, or columns (⌥⌘4, ⌥⌘1, ⌥⌘2, ⌥⌘3)")
      if state.layout == .icons && !state.boardShown && !compact {
        HStack(spacing: 0) {
          Button { state.stepIconSize(-1) } label: { Image(systemName: "minus") }
            .disabled(state.iconSize <= FolderView.iconSizes.first ?? 32)
            .help("Smaller Icons (⌘-)")
          Button { state.stepIconSize(1) } label: { Image(systemName: "plus") }
            .disabled(state.iconSize >= FolderView.iconSizes.last ?? 128)
            .help("Larger Icons (⌘+)")
        }
      }
      HStack(spacing: 2) {
        if !compact {
          Button { state.jumping = true } label: { Image(systemName: "arrow.up.forward.square") }
            .help("Jump to a Folder (⌘K)")
        }
        TextField("Search", text: $state.query)
          .textFieldStyle(.roundedBorder).controlSize(.large).frame(width: compact ? 110 : 180)
          .focused($searchFocused).padding(.horizontal, 4)
          .onExitCommand { state.query = "" }
          .help("Search (⌘F); ⇧⌘F searches file contents; Escape clears")
        if !compact {
          Button { state.hidden.toggle(); state.reload() } label: {
            Image(systemName: state.hidden ? "eye" : "eye.slash")
          }.help("Show Hidden Files (⇧⌘.)")
          Button(action: state.newFolder) { Image(systemName: "folder.badge.plus") }.help("New Folder (⇧⌘N)")
        }
      }
      HStack(spacing: 2) {
        Button { state.showPreview.toggle() } label: { Image(systemName: "sidebar.right") }
          .help("Preview Pane (⇧⌘P); Space opens Quick Look")
        if !compact {
          Button { state.newTab(at: state.location) } label: { Image(systemName: "plus") }.help("New Tab (⌘T)")
        }
        Button { state.onWindowMenu?() } label: { Image(systemName: "macwindow") }
          .help("Window: float or tile, level, size, and how new windows open (yabai)")
      }
    }
    .buttonStyle(ChromeButtonStyle())
    // Clear of the window buttons, which a compact toolbar centers in 40 points.
    .padding(.leading, 82)
    .padding(.trailing, 10)
    .frame(height: 40)
  }

  private var scopeBar: some View {
    HStack(spacing: 8) {
      Text("Search").foregroundStyle(.secondary)
      Picker("Search", selection: $state.scope) {
        ForEach(SearchScope.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.segmented).labelsHidden().fixedSize()
      .help("Subfolders matches names with fd; Contents matches text with rg. Both skip what .gitignore "
            + "ignores unless hidden files are shown.")
      if state.searching { ProgressView().controlSize(.small) }
      Spacer()
      if let note = state.searchNote { Text(note).foregroundStyle(.secondary) }
    }
    .font(.callout)
    .padding(.horizontal, 10)
    .frame(height: 26)
  }

  private var tabStrip: some View {
    HStack(spacing: 1) {
      ForEach(state.tabs.tabs) { tab in
        let selected = tab.id == state.tabs.selectedID
        HStack(spacing: 4) {
          Text(DisplayNames.name(of: tab.location)).lineLimit(1)
          Button { state.closeTab(tab.id) } label: { Image(systemName: "xmark").font(.caption2) }
            .buttonStyle(.borderless).opacity(selected ? 1 : 0.5)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 22)
        .background(selected ? Color.primary.opacity(0.1) : Color.primary.opacity(0.03))
        .contentShape(Rectangle())
        .onTapGesture { state.select(tab: tab.id) }
      }
    }
    .font(.callout)
  }

  /// Whether a sidebar section is open; the closed ones are remembered.
  private func expanded(_ section: String) -> Binding<Bool> {
    Binding {
      !collapsedSections.split(separator: "\n").contains(Substring(section))
    } set: { open in
      var closed = Set(collapsedSections.split(separator: "\n").map(String.init))
      if open { closed.remove(section) } else { closed.insert(section) }
      collapsedSections = closed.sorted().joined(separator: "\n")
    }
  }

  private var sidebar: some View {
    List {
      Section(isExpanded: expanded("Favorites")) {
        ForEach(places.favorites, id: \.url) { place in placeRow(place) }
      } header: {
        sectionHeader("Favorites", symbol: "star.fill", divided: false)
      }
      // Finder's favorites already list most of what the dock pins.
      let favorites = Set(places.favorites.map(\.url.path))
      let dock = state.places().filter { !favorites.contains($0.url.standardizedFileURL.path) }
      if !dock.isEmpty {
        Section(isExpanded: expanded("Dock")) {
          ForEach(dock, id: \.url) { place in
            placeRow(Place(name: place.name, url: place.url, symbol: sidebarPrefs.symbol(for: place.url)))
          }
        } header: {
          sectionHeader("Dock", symbol: "dock.rectangle")
        }
      }
      if !volumes.volumes.isEmpty || !volumes.offline.isEmpty {
        Section(isExpanded: expanded("Locations")) {
          ForEach(volumes.volumes) { volume in volumeRow(volume) }
          ForEach(volumes.offline) { remote in remoteRow(remote) }
        } header: {
          sectionHeader("Locations", symbol: "internaldrive")
        }
      }
      Section(isExpanded: expanded("Collections")) {
        ForEach(CollectionPlace.list(collections), id: \.name) { place in collectionRow(place) }
      } header: {
        sectionHeader("Collections", symbol: "photo.on.rectangle.angled")
      }
      // Last, so entering or leaving a repo never moves the places above.
      if let git = state.git {
        Section(isExpanded: expanded("Repository")) {
          repoRow(git)
          if state.worktrees.count > 1 {
            ForEach(state.worktrees, id: \.path) { worktree in
              // Agent branches share prefixes (`claude/`, `codex/`); the
              // rest is what tells them apart in a narrow sidebar.
              let name = worktree.branch.map { ($0 as NSString).lastPathComponent } ?? worktree.path.lastPathComponent
              let isCurrent = worktree.path.path == git.root.path
              Label(name, systemImage: isCurrent ? "arrow.triangle.branch" : "arrow.triangle.turn.up.right.diamond")
                .lineLimit(1)
                .fontWeight(isCurrent ? .semibold : .regular)
                .help("\(worktree.branch ?? "Detached HEAD") at "
                      + "\((worktree.path.path as NSString).abbreviatingWithTildeInPath); "
                      + "opens the same folder there")
                .contentShape(Rectangle())
                .onTapGesture { state.switchTo(worktree) }
                .contextMenu { RepoMenu(root: worktree.path, branch: worktree.branch) }
            }
          }
        } header: {
          sectionHeader("Repository", symbol: "shippingbox")
        }
      }
    }
    .listStyle(.sidebar)
    .font(.system(size: sidebarPrefs.fontSize))
    .environment(\.sidebarRowSize, sidebarPrefs.fontSize < 12 ? .small : (sidebarPrefs.fontSize > 14 ? .large : .medium))
    .contextMenu { fontSizeMenu }
  }

  /// A sidebar section's title, with a line above it to set the section
  /// apart from the one before.
  private func sectionHeader(_ title: String, symbol: String, divided: Bool = true) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if divided { Divider().padding(.top, 2) }
      Label(title, systemImage: symbol)
    }
  }

  /// Behind the sidebar row for the shown folder.
  private func currentMark(_ url: URL) -> some View {
    rowMark(state.location.path == url.standardizedFileURL.path)
  }

  private func rowMark(_ marked: Bool) -> some View {
    RoundedRectangle(cornerRadius: 5)
      .fill(marked ? Color.accentColor.opacity(0.22) : Color.clear)
      .padding(.horizontal, 8)
  }

  private func repoRow(_ git: GitStatus) -> some View {
    let count = git.changeCount
    let parts = [git.branch ?? "detached",
                 count == 0 ? "clean" : "\(count) changed",
                 git.ahead > 0 ? "↑\(git.ahead)" : nil,
                 git.behind > 0 ? "↓\(git.behind)" : nil].compactMap { $0 }
    return VStack(alignment: .leading, spacing: 1) {
      Label(git.root.lastPathComponent, systemImage: "shippingbox")
        .fontWeight(state.location.path == git.root.path ? .semibold : .regular)
      Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    .help((git.root.path as NSString).abbreviatingWithTildeInPath)
    .contentShape(Rectangle())
    .listRowBackground(currentMark(git.root))
    .onTapGesture { state.go(to: git.root) }
    .contextMenu {
      RepoMenu(root: git.root, branch: git.branch)
      Divider()
      fontSizeMenu
    }
  }

  private func volumeRow(_ volume: Volume) -> some View {
    let home = FileManager.default.homeDirectoryForCurrentUser
    // The startup volume's own folders are mostly the system's; Home is where yours are.
    let largest = volume.isStartup ? home : volume.url
    // A dead SSHFS mount the `mounts` tool made can be made again.
    let remote = volume.responding ? nil : volumes.remote(for: volume)
    let reconnecting = remote.map { volumes.connecting.contains($0.name) } ?? false
    let detail = reconnecting ? "Reconnecting…"
      : remote != nil ? "Not responding; click to reconnect"
      : !volume.responding ? "Not responding"
      : volume.total > 0 ? "\(Self.bytes(volume.available)) free" : "Network"
    return VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Label(volume.name, systemImage: volume.symbol)
          .fontWeight(state.location.path == volume.url.standardizedFileURL.path ? .semibold : .regular)
          .lineLimit(1)
        Spacer(minLength: 2)
        if reconnecting {
          ProgressView().controlSize(.mini)
        } else if let remote {
          Button { state.connect(remote) } label: { Image(systemName: "arrow.clockwise").font(.caption2) }
            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Reconnect to \(remote.source)")
        }
        if volume.canEject {
          Button { state.eject(volume) } label: { Image(systemName: "eject.fill").font(.caption2) }
            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Eject \(volume.name) (⌘E)")
        }
      }
      if volume.total > 0 {
        ProgressView(value: volume.fraction)
          .controlSize(.small)
          .tint(volume.fraction > 0.9 ? .red : volume.fraction > 0.75 ? .orange : .accentColor)
      }
      Text(detail).font(.caption).foregroundStyle(volume.responding ? .secondary : Color.orange).lineLimit(1)
    }
    .help(volume.total > 0 ? "\(Self.bytes(volume.used)) of \(Self.bytes(volume.total)) used; right-click to find the largest folders"
          : (volume.url.path as NSString).abbreviatingWithTildeInPath)
    .contentShape(Rectangle())
    .listRowBackground(currentMark(volume.url))
    .onTapGesture {
      if let remote { state.connect(remote) } else { state.go(to: volume.url) }
    }
    .contextMenu {
      if let remote {
        Button("Reconnect") { state.connect(remote) }.disabled(reconnecting)
        Divider()
      }
      if volume.total > 0 && volume.responding {
        Button(volume.isStartup ? "Show Largest Folders in Home" : "Show Largest Folders") {
          state.showLargest(in: largest)
        }
      }
      Button("Get Info") { state.inspecting = [volume.url] }
      Button("Copy Path") { copyText(volume.url.path) }
      if volume.canEject {
        Divider()
        Button(volume.isLocal ? "Eject" : "Disconnect") { state.eject(volume) }
      }
      Divider()
      fontSizeMenu
    }
  }

  /// A remote the `mounts` tool knows that isn't mounted: a click connects.
  private func remoteRow(_ remote: RemoteMount) -> some View {
    let busy = volumes.connecting.contains(remote.name)
    return VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Label(remote.title, systemImage: "network").lineLimit(1)
        Spacer(minLength: 2)
        if busy {
          ProgressView().controlSize(.mini)
        } else {
          Button { state.connect(remote) } label: { Image(systemName: "link").font(.caption2) }
            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Connect to \(remote.source)")
        }
      }
      Text(busy ? "Connecting…" : remote.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    .opacity(busy ? 1 : 0.7)
    .help("\(remote.source) isn't connected; click to connect")
    .contentShape(Rectangle())
    .onTapGesture { state.connect(remote) }
    .contextMenu {
      Button("Connect") { state.connect(remote) }.disabled(busy)
      Button("Copy Address") { copyText(remote.source) }
      Divider()
      fontSizeMenu
    }
  }

  static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }

  /// A click opens the collection's gallery, or brings its window forward.
  private func collectionRow(_ place: CollectionPlace) -> some View {
    let targeted = Binding<Bool> {
      collectionTarget == place.name
    } set: { over in
      if over { collectionTarget = place.name } else if collectionTarget == place.name { collectionTarget = nil }
    }
    return HStack(spacing: 4) {
      Label(place.name, systemImage: place.symbol).lineLimit(1)
      Spacer(minLength: 2)
      if place.made { Text("\(place.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary) }
    }
    .help(place.made ? "\(place.count) item\(place.count == 1 ? "" : "s"); drop pictures or movies here to add them"
          : "Made when the first picture or movie is added; drop one here")
    .contentShape(Rectangle())
    .listRowBackground(rowMark(collectionTarget == place.name))
    .onTapGesture { ViewerController.shared.openCollection(place.name) }
    .onDrop(of: [.fileURL], isTargeted: targeted) { drop($0, on: place.name) }
    .contextMenu {
      Button("Open") { ViewerController.shared.openCollection(place.name) }
      Divider()
      Button("Rename Collection…") {
        if let name = CollectionPrompt.name("Rename Collection", value: place.name) {
          ViewerController.shared.renameCollection(place.name, to: name)
        }
      }.disabled(!place.made)
      Button("Delete Collection…") {
        if CollectionPrompt.confirmDelete(place.name) { ViewerController.shared.deleteCollection(place.name) }
      }.disabled(!place.made)
      Divider()
      fontSizeMenu
    }
  }

  /// The pictures and movies dropped on a collection's row join it; a drop
  /// with none beeps.
  private func drop(_ providers: [NSItemProvider], on name: String) -> Bool {
    var found: [Int: URL] = [:]
    let group = DispatchGroup()
    for (index, provider) in providers.enumerated() {
      group.enter()
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        if let url { DispatchQueue.main.async { found[index] = url } }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      let media = CollectionPlace.media(found.keys.sorted().compactMap { found[$0] })
      if media.isEmpty { NSSound.beep() } else { collections.add(media, to: name) }
    }
    return true
  }

  private func placeRow(_ place: Place) -> some View {
    let symbol = sidebarPrefs.symbol(for: place.url)
    return Label(place.name, systemImage: symbol)
      .lineLimit(1)
      .fontWeight(state.location.path == place.url.path ? .semibold : .regular)
      .help((place.url.path as NSString).abbreviatingWithTildeInPath)
      .contentShape(Rectangle())
      .listRowBackground(currentMark(place.url))
      .onTapGesture { state.go(to: place.url) }
      .contextMenu {
        Button("Open in New Tab") { state.newTab(at: place.url) }
        Button("Get Info") { state.inspecting = [place.url] }
        Button("Copy Path") { copyText(place.url.path) }
        Divider()
        iconCustomizationMenu(for: place.url, current: symbol)
        fontSizeMenu
      }
  }

  @ViewBuilder
  private func iconCustomizationMenu(for url: URL, current: String) -> some View {
    Menu {
      ForEach(SidebarPreferences.presetIcons, id: \.category) { section in
        Menu(section.category) {
          ForEach(section.icons, id: \.self) { icon in
            Button {
              sidebarPrefs.setIcon(icon, for: url)
            } label: {
              Label(icon, systemImage: icon)
            }
          }
        }
      }
      Divider()
      Button("Custom Symbol Name…") {
        SidebarPreferences.promptForCustomIcon(for: url, current: current) { chosen in
          if let chosen { sidebarPrefs.setIcon(chosen, for: url) }
        }
      }
      let path = url.standardizedFileURL.path
      let tilde = (path as NSString).abbreviatingWithTildeInPath
      if sidebarPrefs.customIcons[path] != nil || sidebarPrefs.customIcons[tilde] != nil || sidebarPrefs.customIcons[url.lastPathComponent] != nil {
        Divider()
        Button("Reset Icon to Default") {
          sidebarPrefs.setIcon(nil, for: url)
        }
      }
    } label: {
      Label("Change Icon", systemImage: "paintbrush")
    }
  }

  private var fontSizeMenu: some View {
    Menu {
      Button("Small (11 pt)") { sidebarPrefs.fontSize = 11 }
      Button("Medium (13 pt)") { sidebarPrefs.fontSize = 13 }
      Button("Large (15 pt)") { sidebarPrefs.fontSize = 15 }
      Divider()
      Button("Increase Text Size") { sidebarPrefs.stepFontSize(by: 1) }
      Button("Decrease Text Size") { sidebarPrefs.stepFontSize(by: -1) }
      Button("Reset Text Size (12 pt)") { sidebarPrefs.fontSize = 12 }
    } label: {
      Label("Sidebar Text Size (\(Int(sidebarPrefs.fontSize)) pt)", systemImage: "textformat.size")
    }
  }

  @ViewBuilder
  private var listing: some View {
    if state.entries == nil {
      Text(FileManager.default.fileExists(atPath: state.location.path)
           ? "Barista can't read this folder. Allow it in System Settings → Privacy & Security → Files and Folders."
           : "This folder was moved or deleted.")
        .foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if state.boardShown, let workspace = state.workspace {
      WorkspaceBoard(state: state, workspace: workspace)
    } else {
      switch state.layout {
      case .list: FileTable(state: state).overlay { emptyNote }
      case .icons: IconGrid(state: state).overlay { emptyNote }
      case .columns: ColumnBrowser(state: state)
      }
    }
  }

  @ViewBuilder
  private var emptyNote: some View {
    if state.shown.isEmpty && !state.loading && !state.searching {
      VStack(spacing: 6) {
        Image(systemName: state.query.isEmpty ? "folder" : "magnifyingglass")
          .font(.system(size: 28, weight: .light))
        Text(state.query.isEmpty ? "Empty Folder" : "No Matches").font(.headline)
        if !state.query.isEmpty {
          Text(state.scope == .contents ? "Nothing here contains “\(state.query)”."
               : "No names here match “\(state.query)”.")
            .font(.callout)
        }
      }
      .foregroundStyle(.tertiary)
      .allowsHitTesting(false)
    }
  }

  /// The path on the left, counts and sizes on the right. A narrow window
  /// drops the slider, then the free space, before the path loses folders.
  private var statusBar: some View {
    HStack(spacing: 6) {
      PathBar(location: state.location) { state.go(to: $0) }
        .layoutPriority(-1)
      Spacer(minLength: 8)
      ViewThatFits(in: .horizontal) {
        statusDetails(slider: true, available: true)
        statusDetails(slider: false, available: true)
        statusDetails(slider: false, available: false)
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .padding(.horizontal, 8)
    .frame(height: 26)
  }

  private func statusDetails(slider: Bool, available: Bool) -> some View {
    HStack(spacing: 6) {
      if state.boardShown, let workspace = state.workspace {
        let open = workspace.tasks.filter { $0.state != .done }.count
        Text("\(open) open task\(open == 1 ? "" : "s") · \(workspace.notes.count) notes · \(workspace.ideas.count) ideas")
      } else if state.loading {
        ProgressView().controlSize(.mini)
        Text("Loading…")
      } else {
        Text(statusSummary(available: available))
      }
      if state.sizesPending > 0 {
        ProgressView().controlSize(.mini)
        Text("measuring \(state.sizesPending)")
          .help("Measuring \(state.sizesPending) folder\(state.sizesPending == 1 ? "" : "s")")
      }
      if slider && !state.boardShown && state.layout == .icons {
        HStack(spacing: 2) {
          Button { state.stepIconSize(-1) } label: { Image(systemName: "minus") }
          .buttonStyle(ChromeButtonStyle.small)
          .disabled(state.iconSize <= FolderView.iconSizes.first ?? 32)
          .help("Smaller Icons (⌘-)")

          Slider(value: Binding(get: { Double(FolderView.iconStep(of: state.iconSize)) },
                                set: { state.iconSize = FolderView.iconSizes[Int($0.rounded())] }),
                 in: 0...Double(FolderView.iconSizes.count - 1), step: 1)
            .controlSize(.mini)

          Button { state.stepIconSize(1) } label: { Image(systemName: "plus") }
          .buttonStyle(ChromeButtonStyle.small)
          .disabled(state.iconSize >= FolderView.iconSizes.last ?? 128)
          .help("Larger Icons (⌘+ or ⌘=)")
        }
        .frame(width: 160)
        .help("Icon size: \(Int(state.iconSize)) pt (⌘- and ⌘+, or pinch)")
      }
      if !state.boardShown {
        Button { state.measuringSizes.toggle() } label: {
          Image(systemName: state.measuringSizes ? "scalemass.fill" : "scalemass")
        }
        .buttonStyle(ChromeButtonStyle(size: CGSize(width: 24, height: 22), symbol: 12))
        .help(state.measuringSizes ? "Hide Folder Sizes"
              : "Calculate Sizes: measures every folder shown, so sorting by Size ranks what takes the space")
      }
    }
    .fixedSize()
  }

  /// Finder's one line: "9 items, 2 selected, 41.99 GB available".
  private func statusSummary(available: Bool) -> String {
    let count = state.shown.count
    let noun = state.isDeepSearch ? "result" : "item"
    var parts = ["\(count) \(noun)\(count == 1 ? "" : "s")"]
    if !state.selection.isEmpty { parts.append("\(state.selection.count) selected") }
    if state.measuringSizes && state.sizesPending == 0 {
      parts.append("\(Self.bytes(state.shown.compactMap(\.size).reduce(0, +))) in all")
    }
    if state.hidden { parts.append("hidden shown") }
    if available, let free = state.available { parts.append("\(Self.bytes(free)) available") }
    return parts.joined(separator: ", ")
  }
}

/// The line between two panes, dragged to resize the pane on one side;
/// `direction` is 1 when that pane is to its left, -1 when to its right.
private struct PaneHandle: View {
  @Binding var width: Double
  let range: ClosedRange<Double>
  let direction: Double
  @State private var start: Double?

  var body: some View {
    Rectangle()
      .fill(Color(nsColor: .separatorColor))
      .frame(width: 1)
      .overlay {
        // Wider than the line, so it's easy to grab.
        Color.clear.frame(width: 8).contentShape(Rectangle())
          .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
          .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { drag in
              let base = start ?? width
              start = base
              width = min(max(base + direction * drag.translation.width, range.lowerBound), range.upperBound)
              NSCursor.resizeLeftRight.set()
            }
            .onEnded { _ in start = nil })
      }
      .zIndex(1)
  }
}

/// The shown folder and those around it, from the top of the disk down.
private func enclosingFolders(of location: URL) -> [URL] {
  let components = location.pathComponents
  return components.indices.map { index in
    URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(index + 1))))
  }
}

/// Finder's path bar, along the bottom: each enclosing folder as a button,
/// so any of them is one click away.
private struct PathBar: View {
  let location: URL
  let go: (URL) -> Void

  var body: some View {
    let urls = enclosingFolders(of: location)
    // A narrow window drops folders from the top, never breaks a name; the
    // dropped ones wait behind a … menu.
    ViewThatFits(in: .horizontal) {
      bar(urls, showing: urls.count)
      bar(urls, showing: 4)
      bar(urls, showing: 2)
      bar(urls, showing: 1)
    }
    .buttonStyle(.borderless)
  }

  private func bar(_ urls: [URL], showing count: Int) -> some View {
    let dropped = urls.dropLast(count)
    return HStack(spacing: 3) {
      if !dropped.isEmpty {
        Menu {
          ForEach(dropped.reversed(), id: \.self) { url in
            Button(DisplayNames.name(of: url)) { go(url) }
          }
        } label: {
          Text("…")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Enclosing folders")
        Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
      }
      ForEach(Array(urls.suffix(count).enumerated()), id: \.offset) { offset, url in
        if offset > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
        Button { go(url) } label: {
          HStack(spacing: 3) {
            FileIcon(url: url, points: 14)
            Text(DisplayNames.name(of: url)).lineLimit(1).fixedSize()
          }
        }
        .foregroundStyle(url == location ? .primary : .secondary)
        .fontWeight(url == location ? .medium : .regular)
        .help((url.path as NSString).abbreviatingWithTildeInPath)
      }
    }
  }
}

/// The shown folder's name in the toolbar; clicking it lists the folders
/// above, as Finder's title does.
/// A toolbar or status bar button: a bigger target than a borderless
/// button's symbol, lit while the pointer is over it.
private struct ChromeButtonStyle: ButtonStyle {
  var size = CGSize(width: 30, height: 28)
  var symbol: CGFloat = 15
  var weight = Font.Weight.regular

  /// The status bar's icon-size steps: small symbols, a whole-button target.
  static let small = ChromeButtonStyle(size: CGSize(width: 22, height: 22), symbol: 10, weight: .bold)

  func makeBody(configuration: Configuration) -> some View {
    Chrome(configuration: configuration, size: size, symbol: symbol, weight: weight)
  }

  private struct Chrome: View {
    let configuration: ButtonStyleConfiguration
    let size: CGSize
    let symbol: CGFloat
    let weight: Font.Weight
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
      let lit = configuration.isPressed ? 0.16 : hovering && enabled ? 0.08 : 0
      configuration.label
        .font(.system(size: symbol, weight: weight))
        .foregroundStyle(enabled ? .secondary : .tertiary)
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(lit)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
  }
}

private struct FolderTitle: View {
  let location: URL
  let go: (URL) -> Void

  var body: some View {
    Menu {
      ForEach(enclosingFolders(of: location).dropLast().reversed(), id: \.self) { url in
        Button { go(url) } label: { Text(DisplayNames.name(of: url)) }
      }
    } label: {
      HStack(spacing: 5) {
        FileIcon(url: location, points: 16)
        Text(DisplayNames.name(of: location)).fontWeight(.semibold).lineLimit(1)
      }
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help((location.path as NSString).abbreviatingWithTildeInPath)
  }
}

private struct FileTable: View {
  @ObservedObject var state: BrowserState
  @FocusState private var focused: Bool
  /// Which columns show, in what order and how wide, for every list.
  @AppStorage("BaristaFilesColumns") private var savedColumns = Data()
  @State private var columns = TableColumnCustomization<FileEntry>()

  /// Read from the state, so a table made again (after an unreadable folder)
  /// shows the sort the list still has.
  private var order: Binding<[KeyPathComparator<FileEntry>]> {
    Binding {
      let order: SortOrder = state.ascending ? .forward : .reverse
      switch state.sortKey {
      case .name: return [KeyPathComparator(\FileEntry.name, order: order)]
      case .modified: return [KeyPathComparator(\FileEntry.modified, order: order)]
      case .created: return [KeyPathComparator(\FileEntry.created, order: order)]
      case .added: return [KeyPathComparator(\FileEntry.added, order: order)]
      case .size: return [KeyPathComparator(\FileEntry.sortableSize, order: order)]
      case .kind: return [KeyPathComparator(\FileEntry.kind, order: order)]
      }
    } set: { comparators in
      guard let first = comparators.first else { return }
      let ascending = first.order == .forward
      let key: FileSortKey
      switch first.keyPath {
      case \FileEntry.modified: key = .modified
      case \FileEntry.created: key = .created
      case \FileEntry.added: key = .added
      case \FileEntry.sortableSize: key = .size
      case \FileEntry.kind: key = .kind
      default: key = .name
      }
      // The table calls this from its sort delegate, where re-sorting its rows
      // is reentrant. Each assignment re-sorts, so only a change is assigned.
      DispatchQueue.main.async {
        if state.ascending != ascending { state.ascending = ascending }
        if state.sortKey != key { state.sortKey = key }
      }
    }
  }

  var body: some View {
    ScrollViewReader { proxy in
      table
        .focused($focused)
        .onChange(of: state.scrollTarget) { scroll(proxy) }
        .onChange(of: state.focusList) { focused = true }
        // A new window's listing can land before the table is shown. The
        // list takes the keys, so arrows work without a click first.
        .onAppear {
          if let saved = try? JSONDecoder().decode(TableColumnCustomization<FileEntry>.self, from: savedColumns) {
            columns = saved
          }
          scroll(proxy)
          focused = true
        }
        .onChange(of: columns) { savedColumns = (try? JSONEncoder().encode(columns)) ?? savedColumns }
    }
  }

  private func scroll(_ proxy: ScrollViewProxy) {
    guard let target = state.scrollTarget else { return }
    // The target arrives with the listing; its row isn't laid out yet.
    DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
  }

  private var table: some View {
    Table(of: FileEntry.self, selection: $state.selection, sortOrder: order, columnCustomization: $columns) {
      TableColumn("Name", value: \.name) { entry in
        HStack(spacing: 6) {
          FileIcon(url: entry.url, points: 16, modified: entry.modified)
          if state.isRenaming(entry.url) {
            // The on-disk name: a localized name can hide the extension.
            RenameField(state: state, entry: entry)
          } else {
            Text(entry.name).lineLimit(1).truncationMode(.middle).layoutPriority(1)
            if let match = entry.match {
              Text(match).foregroundStyle(.secondary).lineLimit(1)
                .help(entry.line.map { "Line \($0): \(match)" } ?? match)
            }
          }
          if let mark = state.git?.mark(for: entry.url, isFolder: entry.isFolder) {
            Spacer(minLength: 4)
            Text(mark.letter)
              .font(.caption.monospaced().weight(.bold))
              .foregroundStyle(mark.color)
              .help(mark.help)
          }
        }
      }
      // Without its own minimum, Name is the column that gives way in a
      // narrow window; these minimums add up to about the list's.
      .width(min: 150, ideal: 280)
      .customizationID("name")
      .disabledCustomizationBehavior(.visibility)
      TableColumn("Date Modified", value: \.modified) { entry in dateText(entry.modified) }
        .width(min: 90, ideal: 150)
        .customizationID("modified")
      TableColumn("Date Created", value: \.created) { entry in dateText(entry.created) }
        .width(min: 90, ideal: 150)
        .customizationID("created")
        .defaultVisibility(.hidden)
      TableColumn("Date Added", value: \.added) { entry in dateText(entry.added) }
        .width(min: 90, ideal: 150)
        .customizationID("added")
        .defaultVisibility(.hidden)
      TableColumn("Size", value: \.sortableSize) { entry in
        Text(entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(alignment: .leading) {
            if state.measuringSizes, let size = entry.size, state.largestSize > 0 {
              GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.25))
                  .frame(width: geometry.size.width * CGFloat(size) / CGFloat(state.largestSize))
              }
            }
          }
      }
      .width(min: 50, ideal: 70)
      .customizationID("size")
      TableColumn("Kind", value: \.kind) { entry in
        Text(entry.kind).foregroundStyle(.secondary).lineLimit(1)
      }
      .width(min: 60, ideal: 120)
      .customizationID("kind")
    } rows: {
      ForEach(state.shown) { entry in
        TableRow(entry).itemProvider { NSItemProvider(object: entry.url as NSURL) }
      }
    }
    .contextMenu(forSelectionType: URL.self) { urls in
      EntryMenu(state: state, urls: urls)
    } primaryAction: { urls in
      state.selection = urls
      state.openSelection()
    }
    .alternatingRowBackgrounds(.disabled)
    .onDrop(of: [.fileURL], isTargeted: nil, perform: state.drop)
  }

  private static let dateStyle = Date.FormatStyle.dateTime.year().month().day().hour().minute()

  /// A volume that keeps no creation or added date answers nothing.
  private func dateText(_ date: Date) -> some View {
    Text(date == .distantPast ? "--" : date.formatted(Self.dateStyle)).foregroundStyle(.secondary)
  }
}

/// The right-click menu for `urls`, or for the shown folder when the click
/// was on empty space.
struct EntryMenu: View {
  @ObservedObject var state: BrowserState
  let urls: Set<URL>

  var body: some View {
    if urls.isEmpty {
      folderMenu
    } else {
      let sorted = urls.sorted { $0.path < $1.path }
      let single = urls.count == 1 ? urls.first : nil
      // As the listing decided: an app or other package opens, it isn't browsed.
      let singleFolder = single.flatMap { url in state.shown.first { $0.url == url }?.isFolder == true ? url : nil }
      Button("Open") {
        state.selection = urls
        state.openSelection()
      }
      .keyboardShortcut("o")
      if let singleFolder {
        Button("Open in New Tab") { state.newTab(at: singleFolder) }
      } else if let single {
        OpenWithMenu(state: state, url: single)
      }
      if let single, single.deletingLastPathComponent().standardizedFileURL.path != state.location.path {
        Button("Show in Enclosing Folder") {
          state.selection = [single]
          state.revealSelection()
        }
      }
      Button("Quick Look") {
        state.selection = urls
        state.onQuickLook?()
      }
      .keyboardShortcut("y")
      Button("Get Info") { state.inspecting = sorted }.keyboardShortcut("i")
      Divider()
      if let single {
        Button("Rename") { state.beginRename(single) }.keyboardShortcut(.return, modifiers: [])
      }
      Button("Duplicate") {
        state.selection = urls
        state.duplicateSelection()
      }
      .keyboardShortcut("d")
      if !state.isDeepSearch {
        Button("New Folder with Selection") {
          state.selection = urls
          state.newFolderWithSelection()
        }
        .keyboardShortcut("n", modifiers: [.command, .control])
        Button(single.map { "Compress “\($0.lastPathComponent)”" } ?? "Compress \(urls.count) Items") {
          state.selection = urls
          state.compressSelection()
        }
      }
      Divider()
      ToolButtons(urls: sorted, directory: singleFolder ?? state.location)
      Divider()
      Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(sorted) }
      Button("Copy Path") { copyText(sorted.map(\.path).joined(separator: "\n")) }
        .keyboardShortcut("c", modifiers: [.command, .option])
      Button("Copy Relative Path") {
        let root = FileOperations.repoRoot(of: state.location) ?? state.location
        copyText(sorted.map { PopoverController.relativePath($0, from: root) }.joined(separator: "\n"))
      }
      Button("Add to Shelf") { NotificationCenter.default.post(name: .browserAddToShelf, object: sorted) }
      Divider()
      Button("Move to Trash") {
        state.selection = urls
        state.trashSelection()
      }
      .keyboardShortcut(.delete)
    }
  }

  /// Right-click on the list's empty space: the shown folder itself.
  @ViewBuilder
  private var folderMenu: some View {
    Button("New Folder") { state.newFolder() }.keyboardShortcut("n", modifiers: [.command, .shift])
    Button("Paste") { state.paste(move: false) }.disabled(!state.canPaste)
    Button("Move Items Here") { state.paste(move: true) }.disabled(!state.canPaste)
    Button("Get Info") { state.inspecting = [state.location] }
    if state.workspace == nil {
      Button("Make Workspace Here") { state.makeWorkspace() }
        .help("Adds tasks.org and notes and ideas folders, and shows them as a board")
    }
    Divider()
    Picker("View", selection: $state.layout) {
      ForEach(BrowserLayout.allCases) { Text($0.title).tag($0) }
    }
    Picker("Sort By", selection: $state.sortKey) {
      ForEach(FileSortKey.allCases) { Text($0.title).tag($0) }
    }
    Toggle("Calculate All Sizes", isOn: $state.measuringSizes)
    Button("Use as Defaults") { state.useAsDefaults() }
      .help("Folders you haven't set a view for, and new windows, look like this one")
    Divider()
    ToolButtons(urls: [state.location], directory: state.location)
    Divider()
    Button("Copy Path") { copyText(state.location.path) }
  }
}

/// Open in each installed editor, and a terminal in `directory`.
private struct ToolButtons: View {
  let urls: [URL]
  let directory: URL

  var body: some View {
    ForEach(PopoverController.editors, id: \.app) { editor in
      Button("Open in \(editor.name)") {
        NSWorkspace.shared.open(urls, withApplicationAt: editor.app, configuration: NSWorkspace.OpenConfiguration())
      }
    }
    Button("Terminal Here") {
      ActionRunner.openTerminal("cd " + ActionRunner.shellQuote(directory.path), arguments: [])
    }
    if urls.count == 1, let rom = urls.first, ROMApp.isROM(rom) {
      ForEach(ROMApp.installed, id: \.title) { app in
        Button(app.title) { app.open(rom) }
      }
    }
  }
}

/// A repository or worktree in the sidebar: its editors, a terminal, and
/// lazygit at its top, and its branch to paste into a prompt.
private struct RepoMenu: View {
  let root: URL
  let branch: String?

  var body: some View {
    ToolButtons(urls: [root], directory: root)
    if let lazygit = Tool.find("lazygit") {
      Button("lazygit") {
        ActionRunner.openTerminal("cd " + ActionRunner.shellQuote(root.path) + " && "
                                  + ActionRunner.shellQuote(lazygit), arguments: [])
      }
    }
    Divider()
    if let branch { Button("Copy Branch Name") { copyText(branch) } }
    Button("Copy Path") { copyText(root.path) }
  }
}

/// SNES tools that declare no document types, so Open With never lists them.
struct ROMApp {
  let title: String
  let bundleID: String
  let arguments: (URL) -> [String]

  static let all = [
    ROMApp(title: "Open in yaze", bundleID: "com.scawful.yaze") { ["--rom_file", $0.path] },
    ROMApp(title: "Play in Mesen2 OOS", bundleID: "ca.mesen.oos") { [$0.path] },
  ]

  static var installed: [ROMApp] { all.filter { $0.app != nil } }

  static func isROM(_ url: URL) -> Bool { ["sfc", "smc"].contains(url.pathExtension.lowercased()) }

  var app: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

  /// A new instance with the ROM as its argument: a running one would ignore
  /// launch arguments.
  func open(_ rom: URL) {
    guard let app else { return }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = arguments(rom)
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
      if let error { DockStore.log("could not open \(rom.path) with \(app.path): \(error)") }
    }
  }
}

/// The name being edited in place: Return renames, Escape keeps the old
/// name, and clicking away renames, as in Finder.
struct RenameField: View {
  let state: BrowserState
  let entry: FileEntry
  @State private var text: String
  @FocusState private var focused: Bool

  init(state: BrowserState, entry: FileEntry) {
    self.state = state
    self.entry = entry
    // The on-disk name: a localized name can hide the extension.
    _text = State(initialValue: entry.url.lastPathComponent)
  }

  var body: some View {
    TextField("Name", text: $text)
      .textFieldStyle(.plain)
      .focused($focused)
      // Return and Escape hand the keys back to the list; a click elsewhere
      // keeps focus where it went.
      .onSubmit {
        state.commitRename(entry.url, to: text)
        state.focusList += 1
      }
      .onExitCommand {
        state.renaming = nil
        state.focusList += 1
      }
      // Focus leaves while the table is changing its selection; reloading the
      // rows inside that delegate call is reentrant, so the commit waits a turn.
      .onChange(of: focused) {
        guard !focused else { return }
        let url = entry.url, name = text
        DispatchQueue.main.async { state.commitRename(url, to: name) }
      }
      // The row is still being laid out when the field appears, and focus
      // selects the whole name before the stem can be selected.
      .onAppear {
        DispatchQueue.main.async {
          focused = true
          DispatchQueue.main.async {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.string == text else { return }
            editor.setSelectedRange(FileOperations.stem(text, isFolder: entry.isFolder))
          }
        }
      }
  }
}

/// A browser window is the Quick Look panel's controller while it shows the
/// window's selection, and keeps the panel on the selection as it changes.
/// Barista's scroll bars float over what they scroll and fade, whatever the
/// system's Show Scroll Bars setting; folder views show them on hover.
enum OverlayScrollers {
  static func install() {
    guard let method = class_getClassMethod(NSScroller.self, #selector(getter: NSScroller.preferredScrollerStyle))
    else { return }
    let overlay: @convention(block) (AnyObject) -> Int = { _ in NSScroller.Style.overlay.rawValue }
    method_setImplementation(method, imp_implementationWithBlock(overlay))
  }
}

final class BrowserWindow: NSWindow, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  private weak var state: BrowserState?
  private var selectionWatch: AnyCancellable?
  private weak var hovered: NSScrollView?
  private var hoverFlashedAt = Date.distantPast

  private var previewed: [URL] { state?.selectedURLs ?? [] }

  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .mouseMoved:
      showScrollers(at: event.locationInWindow)
    case .leftMouseDown:
      // A drag up or down the list selects rows, as in Finder; sideways
      // it still carries the files out.
      var view = contentView?.hitTest(event.locationInWindow)
      while let current = view, !(current is NSTableView) { view = current.superview }
      (view as? NSTableView)?.verticalMotionCanBeginDrag = false
    default:
      break
    }
    super.sendEvent(event)
  }

  /// Overlay scroll bars only show while scrolling; these show while the
  /// pointer moves over what scrolls.
  private func showScrollers(at point: NSPoint) {
    guard let scroll = contentView?.hitTest(point)?.enclosingScrollView else { return }
    let now = Date()
    guard scroll !== hovered || now.timeIntervalSince(hoverFlashedAt) > 0.6 else { return }
    hovered = scroll
    hoverFlashedAt = now
    scroll.flashScrollers()
  }

  func watch(_ state: BrowserState) {
    self.state = state
    // $selection fires before the value changes; read it on the next turn.
    selectionWatch = state.$selection.receive(on: DispatchQueue.main).sink { [weak self] _ in
      guard let self, QLPreviewPanel.sharedPreviewPanelExists(),
            let panel = QLPreviewPanel.shared(), panel.isVisible, panel.dataSource === self else { return }
      panel.reloadData()
    }
  }

  func toggleQuickLook() {
    guard let panel = QLPreviewPanel.shared() else { return }
    if panel.isVisible {
      panel.orderOut(nil)
    } else if !previewed.isEmpty {
      panel.makeKeyAndOrderFront(nil)
    }
  }

  override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

  override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    panel.dataSource = self
    panel.delegate = self
  }

  override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    panel.dataSource = nil
    panel.delegate = nil
  }

  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewed.count }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
    let urls = previewed
    return urls.indices.contains(index) ? urls[index] as NSURL : nil
  }

  /// Space closes the panel and arrows move the list's selection, as in Finder.
  func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
    guard event.type == .keyDown else { return false }
    if event.keyCode == 49 {
      panel.orderOut(nil)
      return true
    }
    guard (123...126).contains(event.keyCode), let responder = firstResponder, responder !== self else { return false }
    responder.keyDown(with: event)
    return true
  }
}

extension Notification.Name {
  /// The browser has no store; the agent delegate adds these URLs to the shelf.
  static let browserAddToShelf = Notification.Name("BrowserAddToShelf")
}

extension FileEntry {
  /// Folders sort below every file when sorting by size.
  var sortableSize: Int64 { size ?? -1 }
}

extension GitMark {
  var color: Color {
    switch self {
    case .modified, .renamed: return .orange
    case .added, .untracked: return .green
    case .deleted, .conflicted: return .red
    case .inside: return .secondary
    }
  }

  var help: String {
    switch self {
    case .modified: return "Modified"
    case .added: return "Added"
    case .deleted: return "Deleted"
    case .renamed: return "Renamed"
    case .untracked: return "Untracked"
    case .conflicted: return "Conflicted"
    case .inside: return "Has changes inside"
    }
  }
}

extension FileOperations {
  /// Moves `urls` to the Trash, then registers Undo on `undo` to put them
  /// back where they were, and Redo to trash them again. `changed` runs on
  /// the main thread with what each step moved, by the paths they left.
  static func trash(_ urls: [URL], undo: UndoManager?, target: AnyObject,
                    changed: @escaping (_ trashed: [URL], _ restored: [URL], _ problem: String?) -> Void) {
    NSWorkspace.shared.recycle(urls) { moved, error in
      DispatchQueue.main.async {
        if let error { DockStore.log("could not move files to the Trash: \(error)") }
        changed(Array(moved.keys), [], error?.localizedDescription)
        guard let undo, !moved.isEmpty else { return }
        // The manager keeps its actions; holding it from them would keep it.
        undo.registerUndo(withTarget: target) { [weak undo] target in
          var restored: [URL] = []
          var failures: [String] = []
          for (original, trashed) in moved {
            do { restored.append(try restore(trashed, to: original)) } catch { failures.append(error.localizedDescription) }
          }
          changed([], restored, failures.isEmpty ? nil : failures.joined(separator: "\n"))
          undo?.registerUndo(withTarget: target) { [weak undo] target in
            trash(restored, undo: undo, target: target, changed: changed)
          }
          undo?.setActionName("Move to Trash")
        }
        undo.setActionName("Move to Trash")
      }
    }
  }
}
