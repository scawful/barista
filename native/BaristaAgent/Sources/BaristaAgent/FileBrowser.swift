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

  /// Folders the dock shows, added under the standard places.
  var dockPlaces: () -> [(name: String, url: URL)] = { [] }

  private var windows: [NSWindow] = []
  private var states: [ObjectIdentifier: BrowserState] = [:]
  private var keyMonitor: Any?
  private var menuActions: [MenuAction] = []
  private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

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
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.minSize = NSSize(width: 480, height: 300)
    window.contentView = NSHostingView(rootView: BrowserView(state: state))
    state.onTitle = { [weak window] name in window?.title = name + Self.titleSuffix }
    state.onCloseWindow = { [weak window] in window?.performClose(nil) }
    state.reload()
    window.center()
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
    for menu in [view, go] {
      let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
      holder.submenu = menu
      main.addItem(holder)
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
  @Published var sortKey = FileSortKey.name { didSet { refreshShown() } }
  @Published var ascending = true { didSet { refreshShown() } }
  @Published var query = "" { didSet { search() } }
  @Published var scope = SearchScope.folder { didSet { if scope != oldValue { search() } } }
  /// fd or rg is running for the query.
  @Published private(set) var searching = false
  /// Why a deep search's results are partial or missing.
  @Published private(set) var searchNote: String?
  @Published var hidden = false
  @Published var showSidebar = true
  @Published var showPreview = true
  @Published var layout = BrowserLayout.remembered {
    didSet {
      UserDefaults.standard.set(layout.rawValue, forKey: BrowserLayout.defaultsKey)
      showBoard = false
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
  var onQuickLook: (() -> Void)?
  private var watcher: FileWatcher?
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

  init(location: URL, selecting: URL? = nil) {
    tabs = BrowserTabs(location)
    pendingSelection = selecting.map { [$0] }
  }

  var location: URL { tabs.selected.location }

  func reload() {
    reloadScheduled = false
    generation += 1
    let token = generation
    let folder = location
    let hidden = self.hidden
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
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == token else { return }
        if let listing { ListingCache.shared.store(listing, for: folder, hidden: hidden) }
        self.loading = false
        self.show(listing, listed: listed, final: true)
        self.show(workspace)
        if self.measuringSizes { self.measureSizes() }
      }
      // After the listing is shown: git should never hold it up, and on a
      // network mount it would read the whole tree over the wire.
      let local = (try? folder.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal != false
      let inspected = local ? Git.inspect(folder) : nil
      let context = AFSContext.find(from: folder)
      let available = Volume.available(at: folder)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == token else { return }
        if self.available != available { self.available = available }
        if self.contextRoot != context { self.contextRoot = context }
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

  /// The biggest folders first, as a disk-usage tool shows them.
  func showLargest(in folder: URL) {
    go(to: folder)
    sortKey = .size
    ascending = false
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

  func open(_ entry: FileEntry) {
    if entry.isFolder {
      go(to: entry.url)
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
    chosen.filter { !$0.isFolder }.forEach(open)
  }

  func trashSelection() {
    let urls = Array(selection)
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.recycle(urls) { _, error in
      if let error { DockStore.log("could not move files to the Trash: \(error)") }
      // The watcher sees the shown folder only; search results can be deeper.
      DispatchQueue.main.async { [weak self] in self?.scheduleReload() }
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
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      if state.tabs.tabs.count > 1 { tabStrip }
      if !state.query.isEmpty { scopeBar }
      Divider()
      HSplitView {
        if state.showSidebar { sidebar.frame(minWidth: 140, idealWidth: 170, maxWidth: 260) }
        listing.frame(minWidth: 360)
        if state.showPreview {
          // Capped, so a wider window widens the list rather than the preview.
          BrowserPreview(entry: selectedEntry, state: state).frame(minWidth: 220, idealWidth: 320, maxWidth: 560)
        }
      }
      Divider()
      statusBar
    }
    .ignoresSafeArea(edges: .top)
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

  private var toolbar: some View {
    HStack(spacing: 8) {
      Button { state.showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }.help("Sidebar (⌥⌘S)")
      Button(action: state.back) { Image(systemName: "chevron.left") }
        .disabled(!state.tabs.selected.canGoBack).help("Back (⌘[)")
      Button(action: state.forward) { Image(systemName: "chevron.right") }
        .disabled(!state.tabs.selected.canGoForward).help("Forward (⌘])")
      Button(action: state.up) { Image(systemName: "arrow.up") }
        .disabled(state.tabs.selected.parent == nil).help("Enclosing Folder (⌘↑)")
      PathBar(location: state.location) { state.go(to: $0) }
      Spacer(minLength: 8)
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
      .pickerStyle(.segmented).labelsHidden().fixedSize()
      .help(state.workspace == nil ? "List, icons, or columns (⌥⌘1, ⌥⌘2, ⌥⌘3)"
            : "Board, list, icons, or columns (⌥⌘4, ⌥⌘1, ⌥⌘2, ⌥⌘3)")
      Button { state.jumping = true } label: { Image(systemName: "arrow.up.forward.square") }
        .help("Jump to a Folder (⌘K)")
      TextField("Search", text: $state.query)
        .textFieldStyle(.roundedBorder).frame(width: 180).focused($searchFocused)
        .onExitCommand { state.query = "" }
        .help("Search (⌘F); ⇧⌘F searches file contents; Escape clears")
      Button { state.hidden.toggle(); state.reload() } label: {
        Image(systemName: state.hidden ? "eye" : "eye.slash")
      }.help("Show Hidden Files (⇧⌘.)")
      Button(action: state.newFolder) { Image(systemName: "folder.badge.plus") }.help("New Folder (⇧⌘N)")
      Button { state.showPreview.toggle() } label: { Image(systemName: "sidebar.right") }
        .help("Preview Pane (⇧⌘P); Space opens Quick Look")
      Button { state.newTab(at: state.location) } label: { Image(systemName: "plus") }.help("New Tab (⌘T)")
    }
    .buttonStyle(.borderless)
    .padding(.leading, 78)
    .padding(.trailing, 12)
    .frame(height: 38)
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
    .padding(.horizontal, 12)
    .frame(height: 28)
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
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 24)
        .background(selected ? Color.primary.opacity(0.1) : Color.primary.opacity(0.03))
        .contentShape(Rectangle())
        .onTapGesture { state.select(tab: tab.id) }
      }
    }
    .font(.callout)
  }

  private var sidebar: some View {
    List {
      Section("Favorites") {
        ForEach(places.favorites, id: \.url) { place in placeRow(place) }
      }
      // Finder's favorites already list most of what the dock pins.
      let favorites = Set(places.favorites.map(\.url.path))
      let dock = state.places().filter { !favorites.contains($0.url.standardizedFileURL.path) }
      if !dock.isEmpty {
        Section("Dock") {
          ForEach(dock, id: \.url) { place in
            placeRow(Place(name: place.name, url: place.url, symbol: FinderFavorites.place(place.url).symbol))
          }
        }
      }
      if !volumes.volumes.isEmpty {
        Section("Locations") {
          ForEach(volumes.volumes) { volume in volumeRow(volume) }
        }
      }
      // Last, so entering or leaving a repo never moves the places above.
      if let git = state.git {
        Section("Repository") {
          repoRow(git)
          if state.worktrees.count > 1 {
            ForEach(state.worktrees, id: \.path) { worktree in
              // Agent branches share prefixes (`claude/`, `codex/`); the
              // rest is what tells them apart in a narrow sidebar.
              let name = worktree.branch.map { ($0 as NSString).lastPathComponent } ?? worktree.path.lastPathComponent
              Label(name, systemImage: "arrow.triangle.branch")
                .lineLimit(1)
                .fontWeight(worktree.path.path == git.root.path ? .semibold : .regular)
                .help("\(worktree.branch ?? "Detached HEAD") at "
                      + "\((worktree.path.path as NSString).abbreviatingWithTildeInPath); "
                      + "opens the same folder there")
                .contentShape(Rectangle())
                .onTapGesture { state.switchTo(worktree) }
                .contextMenu { RepoMenu(root: worktree.path, branch: worktree.branch) }
            }
          }
        }
      }
    }
    .listStyle(.sidebar)
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
    .onTapGesture { state.go(to: git.root) }
    .contextMenu { RepoMenu(root: git.root, branch: git.branch) }
  }

  private func volumeRow(_ volume: Volume) -> some View {
    let home = FileManager.default.homeDirectoryForCurrentUser
    // The startup volume's own folders are mostly the system's; Home is where yours are.
    let largest = volume.isStartup ? home : volume.url
    let detail = !volume.responding ? "Not responding"
      : volume.total > 0 ? "\(Self.bytes(volume.available)) free" : "Network"
    return VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 4) {
        Label(volume.name, systemImage: volume.symbol)
          .fontWeight(state.location.path == volume.url.standardizedFileURL.path ? .semibold : .regular)
          .lineLimit(1)
        Spacer(minLength: 2)
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
    .onTapGesture { state.go(to: volume.url) }
    .contextMenu {
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
    }
  }

  static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }

  private func placeRow(_ place: Place) -> some View {
    Label(place.name, systemImage: place.symbol)
      .lineLimit(1)
      .fontWeight(state.location.path == place.url.path ? .semibold : .regular)
      .help((place.url.path as NSString).abbreviatingWithTildeInPath)
      .contentShape(Rectangle())
      .onTapGesture { state.go(to: place.url) }
      .contextMenu {
        Button("Open in New Tab") { state.newTab(at: place.url) }
        Button("Get Info") { state.inspecting = [place.url] }
        Button("Copy Path") { copyText(place.url.path) }
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
      case .list: FileTable(state: state)
      case .icons: IconGrid(state: state)
      case .columns: ColumnBrowser(state: state)
      }
    }
  }

  private var statusBar: some View {
    HStack {
      if state.boardShown, let workspace = state.workspace {
        let open = workspace.tasks.filter { $0.state != .done }.count
        Text("\(open) open task\(open == 1 ? "" : "s") · \(workspace.notes.count) notes · \(workspace.ideas.count) ideas")
      } else if state.loading {
        ProgressView().controlSize(.mini)
        Text("Loading…")
      } else {
        let count = state.shown.count
        let noun = state.isDeepSearch ? "result" : "item"
        Text("\(count) \(noun)\(count == 1 ? "" : "s")"
             + (state.selection.isEmpty ? "" : ", \(state.selection.count) selected"))
        if state.measuringSizes && state.sizesPending == 0 {
          Text("· \(Self.bytes(state.shown.compactMap(\.size).reduce(0, +))) in all")
        }
      }
      if state.hidden { Text("· hidden files shown") }
      Spacer()
      if state.sizesPending > 0 {
        ProgressView().controlSize(.mini)
        Text("measuring \(state.sizesPending) folder\(state.sizesPending == 1 ? "" : "s")")
      }
      if !state.boardShown {
        Button(state.measuringSizes ? "Hide Folder Sizes" : "Calculate Sizes") { state.measuringSizes.toggle() }
          .buttonStyle(.borderless).font(.caption)
          .help("Measures every folder shown, so sorting by Size ranks what takes the space")
      }
      if let available = state.available { Text("\(Self.bytes(available)) available") }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 12)
    .frame(height: 22)
  }
}

/// Each enclosing folder as a button, so any of them is one click away.
private struct PathBar: View {
  let location: URL
  let go: (URL) -> Void

  var body: some View {
    let components = location.pathComponents
    let urls = components.indices.map { index in
      URL(fileURLWithPath: NSString.path(withComponents: Array(components.prefix(index + 1))))
    }
    HStack(spacing: 2) {
      ForEach(Array(urls.suffix(4).enumerated()), id: \.offset) { offset, url in
        if offset > 0 { Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary) }
        Button(DisplayNames.name(of: url)) { go(url) }
          .fontWeight(url == location ? .semibold : .regular)
          .lineLimit(1)
      }
    }
    .buttonStyle(.borderless)
  }
}

private struct FileTable: View {
  @ObservedObject var state: BrowserState
  @FocusState private var focused: Bool

  /// Read from the state, so a table made again (after an unreadable folder)
  /// shows the sort the list still has.
  private var order: Binding<[KeyPathComparator<FileEntry>]> {
    Binding {
      let order: SortOrder = state.ascending ? .forward : .reverse
      switch state.sortKey {
      case .name: return [KeyPathComparator(\FileEntry.name, order: order)]
      case .modified: return [KeyPathComparator(\FileEntry.modified, order: order)]
      case .size: return [KeyPathComparator(\FileEntry.sortableSize, order: order)]
      case .kind: return [KeyPathComparator(\FileEntry.kind, order: order)]
      }
    } set: { comparators in
      guard let first = comparators.first else { return }
      state.ascending = first.order == .forward
      switch first.keyPath {
      case \FileEntry.modified: state.sortKey = .modified
      case \FileEntry.sortableSize: state.sortKey = .size
      case \FileEntry.kind: state.sortKey = .kind
      default: state.sortKey = .name
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
          scroll(proxy)
          focused = true
        }
    }
  }

  private func scroll(_ proxy: ScrollViewProxy) {
    guard let target = state.scrollTarget else { return }
    // The target arrives with the listing; its row isn't laid out yet.
    DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
  }

  private var table: some View {
    Table(of: FileEntry.self, selection: $state.selection, sortOrder: order) {
      TableColumn("Name", value: \.name) { entry in
        HStack(spacing: 6) {
          FileIcon(url: entry.url, points: 16)
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
      TableColumn("Date Modified", value: \.modified) { entry in
        Text(entry.modified, format: .dateTime.year().month().day().hour().minute()).foregroundStyle(.secondary)
      }
      .width(min: 90, ideal: 150)
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
      TableColumn("Kind", value: \.kind) { entry in
        Text(entry.kind).foregroundStyle(.secondary).lineLimit(1)
      }
      .width(min: 60, ideal: 120)
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
    .onDrop(of: [.fileURL], isTargeted: nil, perform: state.drop)
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
        OpenWithMenu(url: single)
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

/// The apps that open `url`, its default first, as in Finder's Open With.
private struct OpenWithMenu: View {
  let url: URL

  var body: some View {
    let preferred = NSWorkspace.shared.urlForApplication(toOpen: url)
    let others = NSWorkspace.shared.urlsForApplications(toOpen: url).filter { $0 != preferred }.prefix(20)
    Menu("Open With") {
      if let preferred {
        Button("\(Self.name(preferred)) (default)") { open(with: preferred) }
        if !others.isEmpty { Divider() }
      }
      ForEach(Array(others), id: \.self) { app in
        Button(Self.name(app)) { open(with: app) }
      }
    }
  }

  private func open(with app: URL) {
    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
  }

  private static func name(_ app: URL) -> String {
    FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
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
      .onChange(of: focused) { if !focused { state.commitRename(entry.url, to: text) } }
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
final class BrowserWindow: NSWindow, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
  private weak var state: BrowserState?
  private var selectionWatch: AnyCancellable?

  private var previewed: [URL] { state?.selectedURLs ?? [] }

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
