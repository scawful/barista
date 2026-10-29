import AVFoundation
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// What the viewer shows natively; anything else opens in its default app.
enum ViewerKind: Equatable {
  case markdown, image, video

  var isMedia: Bool { self != .markdown }

  /// Movies AVFoundation can play; an MKV or WebM opens in its own player.
  private static let playable = Set(AVURLAsset.audiovisualTypes().map(\.rawValue))

  static func of(_ url: URL) -> ViewerKind? {
    let ext = url.pathExtension.lowercased()
    if ["md", "markdown", "mdown", "mkd"].contains(ext) { return .markdown }
    guard let type = UTType(filenameExtension: ext) else { return nil }
    if type.conforms(to: .image) { return .image }
    if type.conforms(to: .movie), playable.contains(type.identifier) { return .video }
    return nil
  }

  /// The other files in `url`'s folder the arrow keys step through, in
  /// Finder's name order: Markdown, or pictures and movies together.
  static func siblings(of url: URL) -> [URL] {
    guard let kind = of(url),
          let urls = try? FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else { return [url] }
    let matching = urls.filter { of($0)?.isMedia == kind.isMedia }
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    return matching.isEmpty ? [url] : matching
  }
}

/// Small native windows for Markdown, pictures, and movies, so a file from
/// the dock does not open a whole editor. yabai floats them by title (see
/// `Yabai.ensureViewerRule`); macOS window tabbing is off, so each stays one
/// window to the tiler.
final class ViewerController {
  static let shared = ViewerController()
  static let titleSuffix = " - Barista Viewer"

  private var windows: [NSWindow] = []
  private var models: [ObjectIdentifier: ViewerModel] = [:]
  private var eventMonitor: Any?
  private var observers: [ObjectIdentifier: [NSObjectProtocol]] = [:]
  private var chrome: [ObjectIdentifier: AnyCancellable] = [:]
  private var pressure: DispatchSourceMemoryPressure?

  /// Shows `url` if the viewer handles it; returns false when it doesn't.
  @discardableResult
  func open(_ url: URL) -> Bool { open([url]) }

  /// Shows the files the viewer handles, several pictures and movies as
  /// tiles in one window; returns false when it handles none of them.
  @discardableResult
  func open(_ urls: [URL]) -> Bool {
    let handled = urls.filter {
      $0.isFileURL && ViewerKind.of($0) != nil && FileManager.default.isReadableFile(atPath: $0.path)
    }
    let media = handled.filter { ViewerKind.of($0)?.isMedia == true }
    for url in handled where !media.contains(url) { show([url]) }
    if !media.isEmpty { show(media) }
    return !handled.isEmpty
  }

  private func show(_ urls: [URL]) {
    if urls.count == 1, let window = windows.first(where: { models[ObjectIdentifier($0)]?.shows(urls[0]) == true }) {
      models[ObjectIdentifier(window)]?.focus(urls[0])
      return present(window)
    }
    Yabai.ensureViewerRule()
    let model = ViewerModel(url: urls[0])
    model.add(Array(urls.dropFirst()))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size(for: model)),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    // A picture zoomed out small keeps its window to its edges.
    window.minSize = model.isMedia ? NSSize(width: 96, height: 64) : NSSize(width: 320, height: 220)
    let host = DockHostingView(rootView: ViewerView(model: model))
    window.contentView = host
    model.onTitle = { [weak window] title in window?.title = title + Self.titleSuffix }
    model.onTitle?(model.title)
    if model.isMedia { dressForMedia(window, model: model, host: host) }
    place(window)
    windows.append(window)
    models[ObjectIdentifier(window)] = model
    observe(window, model: model)
    present(window)
  }

  private func present(_ window: NSWindow) {
    installMonitor()
    AgentWindows.bringForward(window)
  }

  /// A minimized window lets go of its pixels and movies; one out of sight
  /// pauses its movies.
  private func observe(_ window: NSWindow, model: ViewerModel) {
    let center = NotificationCenter.default
    let watch = { (name: Notification.Name, action: @escaping (NSWindow, ViewerModel) -> Void) -> NSObjectProtocol in
      center.addObserver(forName: name, object: window, queue: .main) { [weak self] note in
        guard let window = note.object as? NSWindow, let model = self?.models[ObjectIdentifier(window)] else { return }
        action(window, model)
      }
    }
    observers[ObjectIdentifier(window)] = [
      watch(NSWindow.willCloseNotification) { [weak self] window, _ in self?.closed(window) },
      watch(NSWindow.didMiniaturizeNotification) { _, model in model.tiles.forEach { $0.suspend() } },
      watch(NSWindow.didDeminiaturizeNotification) { _, model in model.tiles.forEach { $0.resume() } },
      watch(NSWindow.didChangeOcclusionStateNotification) { window, model in
        if window.occlusionState.contains(.visible) {
          model.tiles.forEach { $0.resume() }
        } else {
          model.tiles.forEach { $0.pause() }
        }
      },
    ]
    watchMemory()
  }

  private func closed(_ window: NSWindow) {
    let id = ObjectIdentifier(window)
    observers.removeValue(forKey: id)?.forEach(NotificationCenter.default.removeObserver)
    chrome[id] = nil
    models.removeValue(forKey: id)?.stop()
    windows.removeAll { $0 === window }
    if windows.isEmpty, let monitor = eventMonitor {
      NSEvent.removeMonitor(monitor)
      eventMonitor = nil
    }
    AgentWindows.closed(window)
  }

  /// Under memory pressure, windows in the background drop to a screen's
  /// worth of pixels, and those out of sight let go of them until they show.
  private func watchMemory() {
    guard pressure == nil else { return }
    let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
    source.setEventHandler { [weak self, weak source] in
      guard let self, let event = source?.data else { return }
      for window in self.windows where !window.isKeyWindow {
        let hidden = !window.occlusionState.contains(.visible)
        for tile in self.models[ObjectIdentifier(window)]?.tiles ?? [] {
          if hidden && event.contains(.critical) { tile.suspend() } else { tile.shedPixels() }
        }
      }
    }
    source.resume()
    pressure = source
  }

  /// Picture and movie windows are only the picture, with the buttons and
  /// bar showing while the pointer is over it. A movie keeps its shape as
  /// the window resizes; a picture is cropped by the window's edges.
  private func dressForMedia(_ window: NSWindow, model: ViewerModel, host: DockHostingView<ViewerView>) {
    window.backgroundColor = .black
    window.titlebarSeparatorStyle = .none
    let buttons = window.standardWindowButton(.closeButton)?.superview
    buttons?.alphaValue = 0
    chrome[ObjectIdentifier(window)] = model.$showsChrome.removeDuplicates().sink { shown in
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        buttons?.animator().alphaValue = shown ? 1 : 0
      }
    }
    host.onPointer = { [weak model] point in model?.pointer(point) }
    model.onResize = { [weak self, weak window] request, locksShape in
      guard let self, let window else { return }
      self.resize(window, request, locksShape: locksShape)
    }
    model.onTilesChanged = { [weak self, weak window, weak model] in
      guard let self, let window, let model else { return }
      self.retile(window, count: model.tiles.count)
    }
    model.onEmpty = { [weak window] in window?.close() }
  }

  /// Escape and ⌘W close, ⌘R reloads, ⌘E opens the file in its editor;
  /// picture and movie windows add `mediaKey`'s, a click picks a tile, and
  /// a right- or Control-click opens its menu.
  private func installMonitor() {
    guard eventMonitor == nil else { return }
    eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) {
      [weak self] event in
      guard let self, let window = event.window, let model = self.models[ObjectIdentifier(window)] else {
        return event
      }
      if event.type == .rightMouseDown || event.type == .leftMouseDown && event.modifierFlags.contains(.control) {
        return Self.showMenu(event, in: window, model: model) ? nil : event
      }
      if event.type == .leftMouseDown {
        Self.pickTile(event, in: window, model: model)
        return event
      }
      if model.isMedia, Self.mediaKey(event, model: model) { return nil }
      let command = event.modifierFlags.contains(.command)
      switch (event.keyCode, command, event.charactersIgnoringModifiers?.lowercased()) {
      case (53, _, _) where model.media?.trimming != true, (_, true, "w"):
        window.performClose(nil)
      case (_, true, "r"):
        model.reload()
      case (_, true, "e"):
        NSWorkspace.shared.open(model.url)
      default:
        return event
      }
      return nil
    }
  }

  /// Clicking a tile makes it the one the bar and keys act on; clicks on
  /// the bar leave the choice alone. False for a click on the bar.
  @discardableResult
  private static func pickTile(_ event: NSEvent, in window: NSWindow, model: ViewerModel) -> Bool {
    guard let content = window.contentView else { return false }
    let point = content.convert(event.locationInWindow, from: nil)
    let fromTop = content.isFlipped ? point.y : content.bounds.height - point.y
    guard !(model.showsChrome && fromTop < 38) else { return false }
    let frames = model.frames(in: content.bounds.size)
    if model.tiles.count > 1, let index = frames.firstIndex(where: { $0.contains(CGPoint(x: point.x, y: fromTop)) }) {
      model.focus(model.tiles[index])
    }
    return true
  }

  /// The tile under the pointer's menu; the player keeps its own while trimming.
  private static func showMenu(_ event: NSEvent, in window: NSWindow, model: ViewerModel) -> Bool {
    guard model.isMedia, pickTile(event, in: window, model: model), let media = model.media, !media.trimming,
          let content = window.contentView
    else { return false }
    let menu = MediaMenu.make(model: model, media: media)
    if !media.cropping {
      menu.addItem(.separator())
      menu.addItem(WindowMenu.item(for: window))
    }
    NSMenu.popUpContextMenu(menu, with: event, for: content)
    return true
  }

  /// ←/→ step through the folder's pictures and movies, Space plays, 0 fits,
  /// 1–9 zoom to that multiple, +/− step the zoom, P sharp pixels, I info,
  /// R/⇧R rotate, C crop, ⇧C crop to the view, T trim, ⌘S save a copy, ⌘C
  /// copy. With tiles, Tab/⇧Tab pick the next, Delete removes it, [ and ]
  /// move it, L changes the layout, F fills tiles or fits them. While
  /// cropping, Return applies and Escape cancels; while trimming the player
  /// has the keys.
  private static func mediaKey(_ event: NSEvent, model: ViewerModel) -> Bool {
    guard let media = model.media, !media.trimming else { return false }
    if media.cropping {
      switch event.keyCode {
      case 53: media.cancelCrop()
      case 36, 76: media.applyCrop()
      default: return false
      }
      return true
    }
    let command = event.modifierFlags.contains(.command)
    let shift = event.modifierFlags.contains(.shift)
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
    switch (event.keyCode, command, key) {
    case (48, false, _): model.cycle(shift ? -1 : 1)
    case (51, false, _) where model.tiles.count > 1: model.remove(media)
    case (_, false, "[") where model.tiles.count > 1: model.move(media, by: -1)
    case (_, false, "]") where model.tiles.count > 1: model.move(media, by: 1)
    case (_, false, "l") where model.tiles.count > 1: model.cycleLayout()
    case (_, false, "f") where model.tiles.count > 1: model.fills.toggle()
    case (123, false, _): media.step(-1)
    case (124, false, _): media.step(1)
    case (49, false, _) where media.isVideo: media.togglePlayback()
    case (_, false, "0"): media.fit()
    case (_, false, _) where Int(key).map((1...9).contains) == true: media.magnify(to: CGFloat(Int(key) ?? 1))
    case (_, _, "="), (_, _, "+"): media.magnify(by: 1)
    case (_, _, "-"): media.magnify(by: -1)
    case (_, false, "p") where !media.isVideo: media.pixelated.toggle()
    case (_, false, "i"): media.showsInfo.toggle()
    case (_, false, "r") where !media.isVideo: media.rotate(shift ? -1 : 1)
    case (_, false, "c") where shift: media.cropToView()
    case (_, false, "c"): media.beginCrop()
    case (_, false, "t") where media.isVideo: media.beginTrimming()
    case (_, true, "s"): media.saveCopy()
    case (_, true, "c"): media.copy()
    default: return false
    }
    return true
  }

  private static func size(for model: ViewerModel) -> NSSize {
    let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
    guard let media = model.media else {
      return NSSize(width: min(760, visible.width * 0.6), height: min(900, visible.height * 0.8))
    }
    if model.tiles.count > 1 { return tiled(model.tiles.count, in: visible) }
    if media.isVideo { return NSSize(width: 640, height: 360) }
    return natural(media.size ?? NSSize(width: 640, height: 480), in: visible, pixelated: media.pixelated)
  }

  /// Room for `count` tiles about 400 by 300 points each, up to most of the screen.
  static func tiled(_ count: Int, in visible: CGSize) -> CGSize {
    let columns = Int(Double(count).squareRoot().rounded(.up))
    let rows = (count + columns - 1) / columns
    return CGSize(width: min(CGFloat(columns) * 400, visible.width * 0.85),
                  height: min(CGFloat(rows) * 300, visible.height * 0.85))
  }

  /// Several tiles share the window: it stops keeping one picture's shape
  /// and grows to fit them.
  private func retile(_ window: NSWindow, count: Int) {
    guard count > 1, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
    window.contentResizeIncrements = NSSize(width: 1, height: 1)
    let content = window.contentLayoutRect.size
    let wanted = Self.tiled(count, in: visible.size)
    guard wanted.width > content.width || wanted.height > content.height else { return }
    let size = CGSize(width: max(content.width, wanted.width), height: max(content.height, wanted.height))
    setContent(window, size, in: visible)
  }

  /// A picture's opening size: its own up to 70% of the screen, shrunk to
  /// fit when bigger. Pixel art grows by the biggest whole multiple that fits.
  static func natural(_ size: CGSize, in visible: CGSize, pixelated: Bool) -> CGSize {
    guard size.width > 0, size.height > 0 else { return CGSize(width: 640, height: 480) }
    let room = min(visible.width * 0.7 / size.width, visible.height * 0.7 / size.height)
    let scale = room >= 1 ? (pixelated ? room.rounded(.down) : 1) : room
    return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
  }

  /// Sizes the window's content for `request` on screen. A movie's window
  /// keeps its shape; a zoom bigger than the screen leaves a picture's
  /// window as big as the screen to pan in.
  private func resize(_ window: NSWindow, _ request: MediaState.Resize, locksShape: Bool) {
    guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
    let shape: CGSize
    var content: CGSize
    switch request {
    case .natural(let size):
      shape = size
      content = Self.natural(size, in: visible.size, pixelated: false)
    case .sameWidth(let size):
      shape = size
      let width = window.contentLayoutRect.width
      content = CGSize(width: width, height: width * size.height / max(size.width, 1))
    case .exact(let size):
      shape = size
      content = size
    }
    let room = min(1, visible.width / content.width, visible.height * 0.95 / content.height)
    if case .exact = request, !locksShape {
      content = CGSize(width: min(content.width, visible.width), height: min(content.height, visible.height * 0.95))
    } else {
      content = CGSize(width: content.width * room, height: content.height * room)
    }
    if locksShape {
      window.contentAspectRatio = shape
    } else {
      window.contentResizeIncrements = NSSize(width: 1, height: 1)
    }
    setContent(window, content, in: visible)
  }

  /// Keeps the window's top edge and center, on screen.
  private func setContent(_ window: NSWindow, _ content: CGSize, in visible: NSRect) {
    var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
    frame.origin = NSPoint(x: window.frame.midX - frame.width / 2, y: window.frame.maxY - frame.height)
    frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
    frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
    window.setFrame(frame, display: true, animate: false)
  }

  /// Centered on the screen under the pointer, each new window a step down
  /// and right of the last so they don't stack exactly.
  private func place(_ window: NSWindow) {
    let pointer = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return window.center() }
    let offset = CGFloat(windows.count % 6) * 24
    let size = window.frame.size
    window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2 + offset,
                                  y: visible.midY - size.height / 2 - offset))
  }
}

/// The viewer's options, kept in dock.json's settings: the agent mirrors
/// them here, and `persist` writes a change back.
final class ViewerPreferences: ObservableObject {
  enum ScrollZoom: String, CaseIterable, Identifiable {
    case off, fine, normal, fast

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Points of trackpad scroll a mouse wheel's notch counts as: at
    /// `normal` a notch zooms about 12%, at `fine` 5%, at `fast` 35%.
    static let notch: CGFloat = 12

    /// Zoom per point scrolled, on a log scale: 100 points of a trackpad
    /// scroll at `normal` zoom in about 2.7 times.
    var rate: CGFloat {
      switch self {
      case .off: return 0
      case .fine: return 0.004
      case .normal: return 0.01
      case .fast: return 0.025
      }
    }
  }

  static let shared = ViewerPreferences()

  @Published private(set) var scrollZoom = ScrollZoom.normal
  @Published private(set) var loopsMovies = true
  var persist: ((ScrollZoom, Bool) -> Void)?

  func apply(_ settings: DockSettings) {
    let zoom = ScrollZoom(rawValue: settings.viewerScrollZoom) ?? .normal
    if zoom != scrollZoom { scrollZoom = zoom }
    if settings.viewerLoopsMovies != loopsMovies { loopsMovies = settings.viewerLoopsMovies }
  }

  func set(scrollZoom: ScrollZoom) {
    self.scrollZoom = scrollZoom
    persist?(scrollZoom, loopsMovies)
  }

  func set(loopsMovies: Bool) {
    self.loopsMovies = loopsMovies
    persist?(scrollZoom, loopsMovies)
  }
}

/// What a viewer window shows: a Markdown file, reloaded when it changes on
/// disk, or pictures and movies as tiles, one unless more were added.
final class ViewerModel: ObservableObject {
  /// The Markdown file, or the picture or movie in the active tile.
  @Published private(set) var url: URL
  let isMedia: Bool
  @Published private(set) var blocks: [MarkdownBlock] = []
  @Published private(set) var error: String?
  @Published private(set) var tiles: [MediaState] = []
  /// The tile the bar and keys act on.
  @Published private(set) var media: MediaState?
  /// The window buttons and bar, shown while the pointer is over the window.
  @Published private(set) var showsChrome = false
  @Published var layout = TileLayout.grid
  /// Tiles show their pictures cut to fill them rather than whole.
  @Published var fills = false
  var onTitle: ((String) -> Void)?
  /// A lone tile's window size; tiles sharing a window leave it alone.
  var onResize: ((MediaState.Resize, _ locksShape: Bool) -> Void)?
  var onTilesChanged: (() -> Void)?
  var onEmpty: (() -> Void)?
  private var watcher: FileWatcher?
  private var hideChrome: DispatchWorkItem?
  /// A tile's shape arriving or turning lays the tiles out again.
  private var shapes: [ObjectIdentifier: AnyCancellable] = [:]

  init(url: URL) {
    self.url = url
    isMedia = ViewerKind.of(url)?.isMedia == true
    if isMedia { add([url]) } else { load() }
  }

  var title: String {
    tiles.count > 1 ? "\(url.lastPathComponent) and \(tiles.count - 1) more" : url.lastPathComponent
  }

  func shows(_ url: URL) -> Bool {
    isMedia ? tiles.contains { $0.url == url } : self.url == url
  }

  func reload() {
    if isMedia { media?.reload() } else { load() }
  }

  /// A Markdown link to another Markdown file opens in place.
  func show(_ next: URL) {
    url = next
    load()
  }

  func stop() {
    tiles.forEach { $0.stop() }
  }

  private func load() {
    onTitle?(title)
    watcher = FileWatcher(url: url) { [weak self] in self?.load() }
    do {
      blocks = Markdown.parse(try String(contentsOf: url, encoding: .utf8))
      error = nil
    } catch {
      self.error = "Can't read \(url.lastPathComponent): \(error.localizedDescription)"
    }
  }

  // MARK: Tiles

  /// Adds the pictures and movies not shown yet; the last becomes active.
  func add(_ urls: [URL]) {
    let fresh = urls.filter { ViewerKind.of($0)?.isMedia == true && !shows($0) }
    guard !fresh.isEmpty else { return urls.first.map(focus) ?? () }
    let count = tiles.count + fresh.count
    tiles += fresh.map { tile($0, sharing: count) }
    focus(tiles[tiles.count - 1])
    onTilesChanged?()
  }

  func remove(_ tile: MediaState) {
    guard let index = tiles.firstIndex(where: { $0 === tile }) else { return }
    tile.stop()
    shapes[ObjectIdentifier(tile)] = nil
    tiles.remove(at: index)
    guard !tiles.isEmpty else {
      media = nil
      return onEmpty?() ?? ()
    }
    if media === tile { focus(tiles[min(index, tiles.count - 1)]) } else { onTitle?(title) }
    onTilesChanged?()
  }

  func focus(_ tile: MediaState) {
    media = tile
    url = tile.url
    onTitle?(title)
  }

  func focus(_ url: URL) {
    if let tile = tiles.first(where: { $0.url == url }) { focus(tile) }
  }

  func cycle(_ offset: Int) {
    guard tiles.count > 1, let index = tiles.firstIndex(where: { $0 === media }) else { return }
    focus(tiles[(index + offset + tiles.count) % tiles.count])
  }

  /// Moves `tile` earlier or later among the tiles, clamped to the ends.
  func move(_ tile: MediaState, by offset: Int) {
    guard let index = tiles.firstIndex(where: { $0 === tile }) else { return }
    let target = min(max(index + offset, 0), tiles.count - 1)
    guard target != index else { return }
    tiles.insert(tiles.remove(at: index), at: target)
  }

  func cycleLayout() {
    let all = TileLayout.allCases
    layout = all[((all.firstIndex(of: layout) ?? 0) + 1) % all.count]
    media?.show(status: layout.title)
  }

  /// Where each tile goes in a window `size` big; drawing and clicks agree.
  func frames(in size: CGSize) -> [CGRect] {
    TileGrid.frames(count: tiles.count, in: size, layout: layout,
                    active: tiles.firstIndex { $0 === media } ?? 0,
                    aspects: tiles.map { tile in tile.size.map { $0.width / max($0.height, 1) } ?? 16 / 9 })
  }

  private func tile(_ url: URL, sharing count: Int) -> MediaState {
    let tile = MediaState(url: url, kind: ViewerKind.of(url) ?? .image, tiles: count)
    tile.onShow = { [weak self, weak tile] url in
      guard let self, let tile, self.media === tile else { return }
      self.url = url
      self.onTitle?(self.title)
    }
    tile.resize = { [weak self, weak tile] request in
      guard let self, let tile, self.tiles.count == 1 else { return }
      self.onResize?(request, tile.isVideo)
    }
    shapes[ObjectIdentifier(tile)] = tile.$size.dropFirst().removeDuplicates()
      .sink { [weak self] _ in self?.objectWillChange.send() }
    return tile
  }

  // MARK: Chrome

  /// The pointer at `point` (top-left origin) over the window, or gone.
  /// The bar shows on any move and hides two seconds after one away from it.
  func pointer(_ point: CGPoint?) {
    hideChrome?.cancel()
    guard let point else { return setChrome(false) }
    setChrome(true)
    guard point.y > 44 else { return }
    let work = DispatchWorkItem { [weak self] in self?.setChrome(false) }
    hideChrome = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
  }

  private func setChrome(_ shown: Bool) {
    guard showsChrome != shown else { return }
    showsChrome = shown
    if shown { media?.loadOpeners() }
  }
}

/// Calls `onChange` when a file is written. Editors often save by replacing
/// the file, so a rename or delete re-attaches to whatever lands at the path.
final class FileWatcher {
  private let url: URL
  private let onChange: () -> Void
  private var source: DispatchSourceFileSystemObject?

  init(url: URL, onChange: @escaping () -> Void) {
    self.url = url
    self.onChange = onChange
    attach()
  }

  deinit { source?.cancel() }

  private func attach() {
    source?.cancel()
    let descriptor = open(url.path, O_EVTONLY)
    guard descriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                                                           eventMask: [.write, .extend, .delete, .rename],
                                                           queue: .main)
    source.setEventHandler { [weak self, weak source] in
      guard let self, let source else { return }
      if source.data.contains(.delete) || source.data.contains(.rename) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
          self?.attach()
          self?.onChange()
        }
      } else {
        self.onChange()
      }
    }
    source.setCancelHandler { close(descriptor) }
    source.resume()
    self.source = source
  }
}

// MARK: Views

struct ViewerView: View {
  @ObservedObject var model: ViewerModel

  var body: some View {
    if model.isMedia {
      MediaView(model: model)
    } else {
      VStack(spacing: 0) {
        header
        Divider()
        if let error = model.error {
          Text(error).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          MarkdownDocumentView(blocks: model.blocks, base: model.url.deletingLastPathComponent(),
                               open: { route in
                                 if case .view(let url) = route, ViewerKind.of(url) == .markdown {
                                   model.show(url)
                                 } else {
                                   route.perform()
                                 }
                               })
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .ignoresSafeArea(edges: .top)
    }
  }

  /// Sits in the transparent title bar, clear of the window buttons.
  private var header: some View {
    HStack(spacing: 10) {
      Text(model.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
      Spacer()
      Button { NSWorkspace.shared.open(model.url) } label: { Image(systemName: "square.and.pencil") }
        .help("Open in Editor (⌘E)")
      Button { NSWorkspace.shared.activateFileViewerSelecting([model.url]) } label: { Image(systemName: "folder") }
        .help("Show in Finder")
      Button { copyText(model.url.path) } label: { Image(systemName: "doc.on.doc") }
        .help("Copy Path")
    }
    .buttonStyle(.borderless)
    .padding(.leading, 78)
    .padding(.trailing, 12)
    .frame(height: 28)
  }
}

/// Block layout for Markdown; inline styles and links come from
/// `AttributedString(markdown:)`.
struct MarkdownDocumentView: View {
  let blocks: [MarkdownBlock]
  let base: URL
  let open: (LinkRoute) -> Void

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 12) {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
          MarkdownBlockView(block: block, base: base)
        }
      }
      .textSelection(.enabled)
      .frame(maxWidth: 720, alignment: .leading)
      .padding(.horizontal, 28)
      .padding(.vertical, 20)
      .frame(maxWidth: .infinity)
    }
    .environment(\.openURL, OpenURLAction { url in
      open(LinkRoute.of(url, base: base))
      return .handled
    })
  }
}

struct MarkdownBlockView: View {
  let block: MarkdownBlock
  let base: URL

  var body: some View {
    switch block {
    case .heading(let level, let text):
      VStack(alignment: .leading, spacing: 4) {
        inline(text).font(Self.headingFont(level)).fontWeight(level <= 2 ? .bold : .semibold)
          .padding(.top, level <= 2 ? 8 : 4)
        if level <= 2 { Divider() }
      }
    case .paragraph(let text):
      inline(text).fixedSize(horizontal: false, vertical: true)
    case .list(let items):
      VStack(alignment: .leading, spacing: 4) {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
              if let checked = item.checked {
                Image(systemName: checked ? "checkmark.square.fill" : "square")
              } else if let number = item.number {
                Text("\(number).").monospacedDigit()
              } else {
                Text(item.depth == 0 ? "•" : "◦")
              }
            }
            .foregroundStyle(.secondary)
            inline(item.text).fixedSize(horizontal: false, vertical: true)
          }
          .padding(.leading, CGFloat(item.depth) * 18)
        }
      }
    case .code(let language, let text):
      VStack(alignment: .leading, spacing: 4) {
        if !language.isEmpty { Text(language).font(.caption2).foregroundStyle(.secondary) }
        ScrollView(.horizontal, showsIndicators: false) {
          Text(text).font(.system(.callout, design: .monospaced)).fixedSize()
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
    case .quote(let blocks):
      HStack(alignment: .top, spacing: 10) {
        Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 3)
        VStack(alignment: .leading, spacing: 8) {
          ForEach(Array(blocks.enumerated()), id: \.offset) { _, inner in
            MarkdownBlockView(block: inner, base: base)
          }
        }
        .foregroundStyle(.secondary)
      }
    case .table(let header, let alignments, let rows):
      Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
        GridRow {
          ForEach(header.indices, id: \.self) { column in
            cell(header[column], alignment: alignments[column]).fontWeight(.semibold)
          }
        }
        .background(Color.primary.opacity(0.06))
        ForEach(rows.indices, id: \.self) { row in
          GridRow {
            ForEach(header.indices, id: \.self) { column in
              cell(rows[row][column], alignment: alignments[column])
            }
          }
          .background(row % 2 == 1 ? Color.primary.opacity(0.03) : .clear)
        }
      }
      .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.12)))
    case .image(let alt, let source):
      MarkdownImage(alt: alt, source: source, base: base)
    case .rule:
      Divider().padding(.vertical, 4)
    }
  }

  private func cell(_ text: String, alignment: MarkdownAlignment) -> some View {
    inline(text)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity, alignment: alignment == .center ? .center
             : alignment == .trailing ? .trailing : .leading)
  }

  private func inline(_ text: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
    let attributed = (try? AttributedString(markdown: text, options: options, baseURL: base))
      ?? AttributedString(text)
    return Text(attributed)
  }

  private static func headingFont(_ level: Int) -> Font {
    switch level {
    case 1: return .title
    case 2: return .title2
    case 3: return .title3
    default: return .headline
    }
  }
}

private struct MarkdownImage: View {
  let alt: String
  let source: String
  let base: URL

  var body: some View {
    if let remote = URL(string: source), ["http", "https"].contains(remote.scheme?.lowercased() ?? "") {
      AsyncImage(url: remote) { image in
        image.resizable().scaledToFit()
      } placeholder: {
        Text(alt).foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      let url = URL(fileURLWithPath: source.removingPercentEncoding ?? source, relativeTo: base).standardizedFileURL
      if let image = Self.image(url) {
        Image(nsImage: image).resizable().scaledToFit()
          .frame(maxWidth: image.size.width, alignment: .leading)
          .onTapGesture { ViewerController.shared.open(url) }
          .help(alt)
      } else {
        Label(alt.isEmpty ? url.lastPathComponent : alt, systemImage: "photo").foregroundStyle(.secondary)
      }
    }
  }

  private static let cache: NSCache<NSString, NSImage> = {
    let cache = NSCache<NSString, NSImage>()
    cache.countLimit = 32
    return cache
  }()

  /// A lazy stack draws a block again each time it scrolls back in; the file
  /// is read once per version, keyed by its modification date.
  private static func image(_ url: URL) -> NSImage? {
    let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    let key = "\(url.path)\u{0}\(modified?.timeIntervalSinceReferenceDate ?? 0)" as NSString
    if let cached = cache.object(forKey: key) { return cached }
    guard let image = NSImage(contentsOf: url) else { return nil }
    cache.setObject(image, forKey: key)
    return image
  }
}
