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
  private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

  /// Opens `url` in a new tab of the front browser, or a new browser when
  /// there is none or `newWindow`. A file opens its folder with it selected.
  func open(_ url: URL, newWindow: Bool = false) {
    var isFolder: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
    let folder = exists && isFolder.boolValue ? url : url.deletingLastPathComponent()
    let select = exists && !isFolder.boolValue ? url : nil
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
      switch (flags, event.keyCode, key) {
      case (.command, _, "t"): state.newTab(at: state.tabs.selected.location)
      case (.command, _, "w"): state.closeTab(state.tabs.selectedID)
      case (.command, _, "n"): self.open(state.tabs.selected.location, newWindow: true)
      case (.command, _, "["): state.back()
      case (.command, _, "]"): state.forward()
      case (.command, _, "f"): state.focusSearch += 1
      case ([.command, .shift], _, "."), ([.command, .shift], _, ">"): state.hidden.toggle(); state.reload()
      case (.control, 48, _): state.selectNeighborTab(1)
      case ([.control, .shift], 48, _): state.selectNeighborTab(-1)
      case (.command, _, _) where Int(key).map({ (1...9).contains($0) }) == true:
        state.select(tab: state.tabs.tabs[min(Int(key)! - 1, state.tabs.tabs.count - 1)].id)
      case (.command, 126, _): state.up()
      case (.command, 125, _): state.openSelection()
      case ([], 36, _) where !typing, ([], 76, _) where !typing: state.openSelection()
      case ([], 49, _) where !typing: state.onQuickLook?()
      case ([.command, .shift], _, "p"), ([.command, .shift], _, "P"): state.showPreview.toggle()
      case ([.command, .shift], _, "n"), ([.command, .shift], _, "N"): state.newFolder()
      case (.command, _, "k"), ([.command, .shift], _, "g"), ([.command, .shift], _, "G"): state.jumping = true
      case (.command, 51, _) where !typing: state.trashSelection()
      case (.command, _, "c") where !typing && !state.selection.isEmpty: state.copySelection()
      case (.command, _, "d") where !typing && !state.selection.isEmpty: state.duplicateSelection()
      case (.command, _, "v") where !typing: state.paste(move: false)
      case ([.command, .option], _, "v") where !typing: state.paste(move: true)
      default: return event
      }
      return nil
    }
  }
}

/// One browser window's tabs, listing, and selection.
final class BrowserState: ObservableObject {
  @Published var tabs: BrowserTabs
  @Published private(set) var entries: [FileEntry]?
  @Published var selection: Set<URL> = []
  @Published var sortKey = FileSortKey.name { didSet { refreshShown() } }
  @Published var ascending = true { didSet { refreshShown() } }
  @Published var query = "" { didSet { refreshShown() } }
  @Published var hidden = false
  @Published var showPreview = true
  @Published private(set) var shown: [FileEntry] = []
  /// Bumped to move focus to the search field.
  @Published var focusSearch = 0
  /// The entry whose name is being edited in place.
  @Published var renaming: URL?
  /// A failed file operation, shown as an alert.
  @Published var problem: String?
  /// The repo holding the shown folder, and its worktrees.
  @Published private(set) var git: GitStatus?
  @Published private(set) var worktrees: [GitWorktree] = []
  @Published var jumping = false
  var places: () -> [(name: String, url: URL)] = { [] }
  var onTitle: ((String) -> Void)?
  var onCloseWindow: (() -> Void)?
  var onQuickLook: (() -> Void)?
  private var watcher: FileWatcher?
  private var generation = 0
  /// Selected by the next listing; nil keeps whatever is still there.
  private var pendingSelection: Set<URL>?

  init(location: URL, selecting: URL? = nil) {
    tabs = BrowserTabs(location)
    pendingSelection = selecting.map { [$0] }
  }

  var location: URL { tabs.selected.location }

  func reload() {
    generation += 1
    let token = generation
    let folder = location
    let hidden = self.hidden
    onTitle?(FileManager.default.displayName(atPath: folder.path))
    watcher = FileWatcher(url: folder) { [weak self] in self?.reload() }
    DispatchQueue.global(qos: .userInitiated).async {
      let listing = FileListing.load(folder, hidden: hidden)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == token else { return }
        self.entries = listing
        self.refreshShown()
        let present = Set(self.shown.map(\.url))
        if let pending = self.pendingSelection {
          self.selection = pending.intersection(present)
          self.pendingSelection = nil
        } else {
          self.selection = self.selection.intersection(present)
        }
      }
      // After the listing is shown: git should never hold it up.
      let inspected = Git.inspect(folder)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == token else { return }
        if self.git != inspected?.status { self.git = inspected?.status }
        if self.worktrees != inspected?.worktrees ?? [] { self.worktrees = inspected?.worktrees ?? [] }
      }
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
    shown = FileListing.filtered(FileListing.sorted(entries ?? [], by: sortKey, ascending: ascending),
                                 query: query)
  }

  func go(to url: URL) {
    tabs.go(to: url)
    query = ""
    selection = []
    reload()
    JumpIndex.remember(url)
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
    query = ""
    reload()
  }

  /// Up selects the folder you came from, as Finder does.
  func up() {
    guard let parent = tabs.selected.parent else { return }
    let from = location
    go(to: parent)
    pendingSelection = [from]
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
    query = ""
    reload()
  }

  func selectNeighborTab(_ offset: Int) {
    tabs.selectNeighbor(offset)
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
    } else {
      chosen.filter { !$0.isFolder }.forEach(open)
    }
  }

  func trashSelection() {
    let urls = Array(selection)
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.recycle(urls) { _, error in
      if let error { DockStore.log("could not move files to the Trash: \(error)") }
    }
  }

  /// Copies the files themselves, so ⌘V in Finder or an editor pastes them.
  func copySelection() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(Array(selection) as [NSURL])
  }

  /// The selection in list order.
  var selectedURLs: [URL] { shown.map(\.url).filter { selection.contains($0) } }

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

  func beginRename(_ url: URL) {
    selection = [url]
    renaming = url
  }

  /// Ends the edit for `url` once: Return and losing focus both commit.
  func commitRename(_ url: URL, to name: String) {
    guard renaming == url else { return }
    renaming = nil
    do {
      pendingSelection = [try FileOperations.rename(url, to: name)]
      reload()
    } catch {
      problem = error.localizedDescription
    }
  }

  func duplicateSelection() {
    perform(selectedURLs) { try FileOperations.duplicate($0) }
  }

  static let fileURLsOnly: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

  var canPaste: Bool {
    NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: Self.fileURLsOnly)
  }

  /// Files on the clipboard (copied here or in Finder) copy into this
  /// folder, or move with `move` (⌥⌘V). Copying this folder's own files
  /// duplicates them.
  func paste(move: Bool) {
    let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: Self.fileURLsOnly) as? [URL] ?? []
    let target = location
    perform(urls) { url in
      if url.deletingLastPathComponent().standardizedFileURL == target.standardizedFileURL {
        return move ? url : try FileOperations.duplicate(url)
      }
      return try FileOperations.place(url, in: target, move: move)
    }
  }

  /// Runs `operation` on each URL off the main thread, then selects what it
  /// made and reports what failed.
  private func perform(_ urls: [URL], _ operation: @escaping (URL) throws -> URL) {
    guard !urls.isEmpty else { return }
    DispatchQueue.global(qos: .userInitiated).async {
      var made: [URL] = []
      var failures: [String] = []
      for url in urls {
        do { made.append(try operation(url)) } catch { failures.append(error.localizedDescription) }
      }
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if !failures.isEmpty { self.problem = failures.joined(separator: "\n") }
        if !made.isEmpty { self.pendingSelection = Set(made) }
        self.reload()
      }
    }
  }

  /// Dropped files move within a volume and copy across volumes, as in Finder.
  func receive(_ urls: [URL]) {
    let target = location
    func volume(_ url: URL) -> AnyHashable? {
      (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? AnyHashable
    }
    let incoming = urls.filter { $0.deletingLastPathComponent().standardizedFileURL != target.standardizedFileURL }
    let moves = incoming.filter { volume($0) != nil && volume($0) == volume(target) }
    let copies = incoming.filter { !moves.contains($0) }
    DispatchQueue.global(qos: .userInitiated).async {
      if !moves.isEmpty { DockStore.transfer(moves, into: target, move: true) }
      if !copies.isEmpty { DockStore.transfer(copies, into: target, move: false) }
    }
  }

  static let standardPlaces: [(name: String, url: URL)] = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates: [(String, URL)] = [
      ("Home", home),
      ("Desktop", home.appendingPathComponent("Desktop")),
      ("Documents", home.appendingPathComponent("Documents")),
      ("Downloads", home.appendingPathComponent("Downloads")),
      ("src", home.appendingPathComponent("src")),
      ("Applications", URL(fileURLWithPath: "/Applications")),
    ]
    return candidates.filter { FileManager.default.fileExists(atPath: $0.1.path) }
  }()
}

// MARK: Views

struct BrowserView: View {
  @ObservedObject var state: BrowserState
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      if state.tabs.tabs.count > 1 { tabStrip }
      Divider()
      HSplitView {
        sidebar.frame(minWidth: 140, idealWidth: 170, maxWidth: 260)
        listing.frame(minWidth: 320)
        if state.showPreview {
          BrowserPreview(entry: selectedEntry).frame(minWidth: 220, idealWidth: 300)
        }
      }
      Divider()
      statusBar
    }
    .ignoresSafeArea(edges: .top)
    .onChange(of: state.focusSearch) { searchFocused = true }
    .sheet(isPresented: $state.jumping) { JumpView(state: state) }
    .alert("Barista Files", isPresented: Binding(get: { state.problem != nil },
                                                 set: { if !$0 { state.problem = nil } })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(state.problem ?? "")
    }
  }

  private var selectedEntry: FileEntry? {
    state.selection.count == 1 ? state.shown.first { state.selection.contains($0.url) } : nil
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      Button(action: state.back) { Image(systemName: "chevron.left") }
        .disabled(!state.tabs.selected.canGoBack).help("Back (⌘[)")
      Button(action: state.forward) { Image(systemName: "chevron.right") }
        .disabled(!state.tabs.selected.canGoForward).help("Forward (⌘])")
      Button(action: state.up) { Image(systemName: "arrow.up") }
        .disabled(state.tabs.selected.parent == nil).help("Enclosing Folder (⌘↑)")
      PathBar(location: state.location, go: state.go(to:))
      Spacer(minLength: 8)
      Button { state.jumping = true } label: { Image(systemName: "arrow.up.forward.square") }
        .help("Jump to a Folder (⌘K)")
      TextField("Search", text: $state.query)
        .textFieldStyle(.roundedBorder).frame(width: 180).focused($searchFocused)
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

  private var tabStrip: some View {
    HStack(spacing: 1) {
      ForEach(state.tabs.tabs) { tab in
        let selected = tab.id == state.tabs.selectedID
        HStack(spacing: 4) {
          Text(FileManager.default.displayName(atPath: tab.location.path)).lineLimit(1)
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
      Section("Places") {
        ForEach(BrowserState.standardPlaces, id: \.url) { place in placeRow(place) }
      }
      let dock = state.places()
      if !dock.isEmpty {
        Section("Dock") {
          ForEach(dock, id: \.url) { place in placeRow(place) }
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
                .fontWeight(worktree.path == git.root ? .semibold : .regular)
                .help("\(worktree.branch ?? "Detached HEAD") at "
                      + "\((worktree.path.path as NSString).abbreviatingWithTildeInPath); "
                      + "opens the same folder there")
                .contentShape(Rectangle())
                .onTapGesture { state.switchTo(worktree) }
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
        .fontWeight(state.location == git.root ? .semibold : .regular)
      Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    .help((git.root.path as NSString).abbreviatingWithTildeInPath)
    .contentShape(Rectangle())
    .onTapGesture { state.go(to: git.root) }
  }

  private func placeRow(_ place: (name: String, url: URL)) -> some View {
    Label {
      Text(place.name)
    } icon: {
      Image(nsImage: NSWorkspace.shared.icon(forFile: place.url.path)).resizable().frame(width: 16, height: 16)
    }
    .fontWeight(state.location == place.url.standardizedFileURL ? .semibold : .regular)
    .contentShape(Rectangle())
    .onTapGesture { state.go(to: place.url) }
  }

  @ViewBuilder
  private var listing: some View {
    if state.entries == nil {
      Text("Barista can't read this folder. Allow it in System Settings → Privacy & Security → Files and Folders.")
        .foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      FileTable(state: state)
    }
  }

  private var statusBar: some View {
    HStack {
      let count = state.shown.count
      Text("\(count) item\(count == 1 ? "" : "s")"
           + (state.selection.isEmpty ? "" : ", \(state.selection.count) selected"))
      if state.hidden { Text("· hidden files shown") }
      Spacer()
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
        Button(FileManager.default.displayName(atPath: url.path)) { go(url) }
          .fontWeight(url == location ? .semibold : .regular)
          .lineLimit(1)
      }
    }
    .buttonStyle(.borderless)
  }
}

private struct FileTable: View {
  @ObservedObject var state: BrowserState
  @State private var order = [KeyPathComparator(\FileEntry.name)]

  var body: some View {
    Table(of: FileEntry.self, selection: $state.selection, sortOrder: $order) {
      TableColumn("Name", value: \.name) { entry in
        HStack(spacing: 6) {
          Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 16, height: 16)
          if state.renaming == entry.url {
            // The on-disk name: a localized name can hide the extension.
            RenameField(text: entry.url.lastPathComponent,
                        commit: { state.commitRename(entry.url, to: $0) },
                        cancel: { state.renaming = nil })
          } else {
            Text(entry.name).lineLimit(1)
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
      TableColumn("Date Modified", value: \.modified) { entry in
        Text(entry.modified, format: .dateTime.year().month().day().hour().minute()).foregroundStyle(.secondary)
      }
      .width(min: 110, ideal: 150)
      TableColumn("Size", value: \.sortableSize) { entry in
        Text(entry.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "--")
          .foregroundStyle(.secondary)
      }
      .width(min: 60, ideal: 80)
      TableColumn("Kind", value: \.kind) { entry in
        Text(entry.kind).foregroundStyle(.secondary).lineLimit(1)
      }
      .width(min: 80, ideal: 120)
    } rows: {
      ForEach(state.shown) { entry in
        TableRow(entry).itemProvider { NSItemProvider(object: entry.url as NSURL) }
      }
    }
    .contextMenu(forSelectionType: URL.self) { urls in
      menu(for: urls)
    } primaryAction: { urls in
      state.selection = urls
      state.openSelection()
    }
    .onChange(of: order) {
      guard let first = order.first else { return }
      state.ascending = first.order == .forward
      switch first.keyPath {
      case \FileEntry.modified: state.sortKey = .modified
      case \FileEntry.sortableSize: state.sortKey = .size
      case \FileEntry.kind: state.sortKey = .kind
      default: state.sortKey = .name
      }
    }
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
      var urls: [URL] = []
      let group = DispatchGroup()
      for provider in providers {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          if let url { DispatchQueue.main.async { urls.append(url) } }
          group.leave()
        }
      }
      group.notify(queue: .main) { state.receive(urls) }
      return true
    }
  }

  @ViewBuilder
  private func menu(for urls: Set<URL>) -> some View {
    if urls.isEmpty {
      folderMenu
    } else {
      let sorted = urls.sorted { $0.path < $1.path }
      let single = urls.count == 1 ? urls.first : nil
      let singleFolder = single.flatMap { url in
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true ? url : nil
      }
      Button("Open") {
        state.selection = urls
        state.openSelection()
      }
      if let singleFolder {
        Button("Open in New Tab") { state.newTab(at: singleFolder) }
      } else if let single {
        OpenWithMenu(url: single)
      }
      Button("Quick Look") {
        state.selection = urls
        state.onQuickLook?()
      }
      Divider()
      if let single {
        Button("Rename") { state.beginRename(single) }
      }
      Button("Duplicate") {
        state.selection = urls
        state.duplicateSelection()
      }
      Divider()
      ToolButtons(urls: sorted, directory: singleFolder ?? state.location)
      Divider()
      Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(sorted) }
      Button("Copy Path") { copyText(sorted.map(\.path).joined(separator: "\n")) }
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
    }
  }

  /// Right-click on the list's empty space: the shown folder itself.
  @ViewBuilder
  private var folderMenu: some View {
    Button("New Folder") { state.newFolder() }
    Button("Paste") { state.paste(move: false) }.disabled(!state.canPaste)
    Button("Move Items Here") { state.paste(move: true) }.disabled(!state.canPaste)
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
private struct RenameField: View {
  @State var text: String
  let commit: (String) -> Void
  let cancel: () -> Void
  @FocusState private var focused: Bool

  var body: some View {
    TextField("Name", text: $text)
      .textFieldStyle(.plain)
      .focused($focused)
      .onSubmit { commit(text) }
      .onExitCommand(perform: cancel)
      .onChange(of: focused) { if !focused { commit(text) } }
      // The table is still settling the row when the field appears.
      .onAppear { DispatchQueue.main.async { focused = true } }
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

private extension GitMark {
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

/// The selected file: Markdown and images render, anything else shows its
/// icon and details.
private struct BrowserPreview: View {
  let entry: FileEntry?

  var body: some View {
    Group {
      if let entry {
        switch entry.isFolder ? nil : ViewerKind.of(entry.url) {
        case .markdown:
          let text = (try? String(contentsOf: entry.url, encoding: .utf8)) ?? ""
          MarkdownDocumentView(blocks: Markdown.parse(String(text.prefix(200_000))),
                               base: entry.url.deletingLastPathComponent(),
                               open: { $0.perform() })
        case .image:
          if let image = NSImage(contentsOf: entry.url) {
            Image(nsImage: image).resizable().scaledToFit().padding(12)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            details(entry)
          }
        case nil:
          details(entry)
        }
      } else {
        Text("Select a file to preview it.").foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color.primary.opacity(0.02))
  }

  private func details(_ entry: FileEntry) -> some View {
    VStack(spacing: 8) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 96, height: 96)
      Text(entry.name).font(.headline).multilineTextAlignment(.center)
      Text(entry.kind).foregroundStyle(.secondary)
      if let size = entry.size {
        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).foregroundStyle(.secondary)
      }
      Text(entry.modified, format: .dateTime).foregroundStyle(.secondary)
    }
    .font(.callout)
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
