import AppKit
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
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
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
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                           queue: .main) { [weak self] note in
      guard let self, let closing = note.object as? NSWindow else { return }
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
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
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
      case (.control, 48, _): state.tabs.selectNeighbor(1); state.reload()
      case ([.control, .shift], 48, _): state.tabs.selectNeighbor(-1); state.reload()
      case (.command, _, _) where Int(key).map({ (1...9).contains($0) }) == true:
        let index = min(Int(key)! - 1, state.tabs.tabs.count - 1)
        state.tabs.select(state.tabs.tabs[index].id)
        state.reload()
      case ([.command, .numericPad, .function], 126, _), (.command, 126, _): state.up()
      case ([.command, .numericPad, .function], 125, _), (.command, 125, _): state.openSelection()
      case ([], 36, _) where !typing, ([], 76, _) where !typing: state.openSelection()
      case ([], 49, _) where !typing: state.showPreview.toggle()
      case (.command, 51, _) where !typing: state.trashSelection()
      case (.command, _, "c") where !typing && !state.selection.isEmpty: state.copySelection()
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
  var places: () -> [(name: String, url: URL)] = { [] }
  var onTitle: ((String) -> Void)?
  var onCloseWindow: (() -> Void)?
  private var watcher: FileWatcher?
  private var generation = 0
  private var pendingSelection: URL?

  init(location: URL, selecting: URL? = nil) {
    tabs = BrowserTabs(location)
    pendingSelection = selecting
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
          self.selection = present.contains(pending) ? [pending] : []
          self.pendingSelection = nil
        } else {
          self.selection = self.selection.intersection(present)
        }
      }
    }
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
  }

  func back() {
    let from = location
    tabs.back()
    pendingSelection = from
    reload()
  }

  func forward() {
    tabs.forward()
    reload()
  }

  /// Up selects the folder you came from, as Finder does.
  func up() {
    guard let parent = tabs.selected.parent else { return }
    let from = location
    go(to: parent)
    pendingSelection = from
  }

  func newTab(at url: URL, selecting: URL? = nil) {
    tabs.open(url)
    pendingSelection = selecting
    query = ""
    reload()
  }

  func select(tab id: UUID) {
    tabs.select(id)
    reload()
  }

  func closeTab(_ id: UUID) {
    if tabs.close(id) { reload() } else { onCloseWindow?() }
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
      TextField("Search", text: $state.query)
        .textFieldStyle(.roundedBorder).frame(width: 180).focused($searchFocused)
      Button { state.hidden.toggle(); state.reload() } label: {
        Image(systemName: state.hidden ? "eye" : "eye.slash")
      }.help("Show Hidden Files (⇧⌘.)")
      Button { state.showPreview.toggle() } label: { Image(systemName: "sidebar.right") }
        .help("Preview (Space)")
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
    }
    .listStyle(.sidebar)
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
          Text(entry.name).lineLimit(1)
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
    if !urls.isEmpty {
      Button("Open") {
        state.selection = urls
        state.openSelection()
      }
      if urls.count == 1, let url = urls.first {
        if ViewerKind.of(url) != nil {
          Button("Open with Default App") { NSWorkspace.shared.open(url) }
        }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
          Button("Open in New Tab") { state.newTab(at: url) }
        }
      }
      Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
      Divider()
      Button("Copy Path") { copyText(urls.map(\.path).sorted().joined(separator: "\n")) }
      Button("Add to Shelf") { NotificationCenter.default.post(name: .browserAddToShelf, object: Array(urls)) }
      Divider()
      Button("Move to Trash") {
        state.selection = urls
        state.trashSelection()
      }
    }
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
