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

/// Small native windows for Markdown and images, so a file from the dock
/// does not open a whole editor. yabai floats them by title (see
/// `Yabai.ensureViewerRule`); macOS window tabbing is off, so each stays one
/// window to the tiler.
final class ViewerController {
  static let shared = ViewerController()
  static let titleSuffix = " - Barista Viewer"

  private var windows: [NSWindow] = []
  private var models: [ObjectIdentifier: ViewerModel] = [:]
  private var keyMonitor: Any?
  private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
  private var chrome: [ObjectIdentifier: AnyCancellable] = [:]

  /// Shows `url` if the viewer handles it; returns false when it doesn't.
  @discardableResult
  func open(_ url: URL) -> Bool {
    guard url.isFileURL, ViewerKind.of(url) != nil, FileManager.default.isReadableFile(atPath: url.path) else {
      return false
    }
    if let window = windows.first(where: { models[ObjectIdentifier($0)]?.url == url }) {
      present(window)
      return true
    }
    Yabai.ensureViewerRule()
    let model = ViewerModel(url: url)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size(for: model)),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.minSize = NSSize(width: 320, height: 220)
    let host = DockHostingView(rootView: ViewerView(model: model))
    window.contentView = host
    model.onTitle = { [weak window] name in window?.title = name + Self.titleSuffix }
    model.onTitle?(url.lastPathComponent)
    if model.kind.isMedia { dressForMedia(window, model: model, host: host) }
    place(window)
    windows.append(window)
    models[ObjectIdentifier(window)] = model
    closeObservers[ObjectIdentifier(window)] = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] note in
      guard let self, let closing = note.object as? NSWindow else { return }
      self.closeObservers.removeValue(forKey: ObjectIdentifier(closing)).map(NotificationCenter.default.removeObserver)
      self.chrome[ObjectIdentifier(closing)] = nil
      self.models[ObjectIdentifier(closing)]?.media.stop()
      self.windows.removeAll { $0 === closing }
      self.models[ObjectIdentifier(closing)] = nil
      if self.windows.isEmpty, let monitor = self.keyMonitor {
        NSEvent.removeMonitor(monitor)
        self.keyMonitor = nil
      }
      AgentWindows.closed(closing)
    }
    present(window)
    return true
  }

  private func present(_ window: NSWindow) {
    installKeys()
    AgentWindows.bringForward(window)
  }

  /// Picture and movie windows are only the picture: the window keeps its
  /// shape as it resizes, and the buttons and bar show while the pointer is
  /// over it.
  private func dressForMedia(_ window: NSWindow, model: ViewerModel, host: DockHostingView<ViewerView>) {
    window.backgroundColor = .black
    window.titlebarSeparatorStyle = .none
    if let size = model.media.size { window.contentAspectRatio = size }
    let buttons = window.standardWindowButton(.closeButton)?.superview
    buttons?.alphaValue = 0
    chrome[ObjectIdentifier(window)] = model.media.$showsChrome.removeDuplicates().sink { shown in
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.2
        buttons?.animator().alphaValue = shown ? 1 : 0
      }
    }
    host.onPointer = { [weak media = model.media] point in media?.pointer(point) }
    model.media.resize = { [weak self, weak window, weak media = model.media] request in
      guard let self, let window, let media else { return }
      self.resize(window, request, keepShape: media.isVideo)
    }
  }

  /// Escape and ⌘W close, ⌘R reloads, ⌘E opens the file in its editor;
  /// picture and movie windows add `mediaKey`'s.
  private func installKeys() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = event.window, let model = self.models[ObjectIdentifier(window)] else {
        return event
      }
      if model.kind.isMedia, Self.mediaKey(event, model: model) { return nil }
      let command = event.modifierFlags.contains(.command)
      switch (event.keyCode, command, event.charactersIgnoringModifiers?.lowercased()) {
      case (53, _, _) where !model.media.trimming, (_, true, "w"):
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

  /// ←/→ step through the folder's pictures and movies, Space plays, 0 fits,
  /// 1–9 zoom to that multiple, +/− step the zoom, P sharp pixels, I info,
  /// R/⇧R rotate, C crop, T trim, ⌘S save a copy, ⌘C copy. While cropping,
  /// Return saves and Escape cancels; while trimming the player has the keys.
  private static func mediaKey(_ event: NSEvent, model: ViewerModel) -> Bool {
    let media = model.media
    if media.trimming { return false }
    if media.cropping {
      switch event.keyCode {
      case 53: media.cancelCrop()
      case 36, 76: media.saveCopy()
      default: return false
      }
      return true
    }
    let command = event.modifierFlags.contains(.command)
    let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
    switch (event.keyCode, command, key) {
    case (123, false, _): model.step(-1)
    case (124, false, _): model.step(1)
    case (49, false, _) where media.isVideo: media.togglePlayback()
    case (_, false, "0"): media.fit()
    case (_, false, _) where Int(key).map((1...9).contains) == true: media.magnify(to: CGFloat(Int(key) ?? 1))
    case (_, _, "="), (_, _, "+"): media.magnify(by: 1)
    case (_, _, "-"): media.magnify(by: -1)
    case (_, false, "p") where !media.isVideo: media.pixelated.toggle()
    case (_, false, "i"): media.showsInfo.toggle()
    case (_, false, "r") where !media.isVideo: media.rotate(event.modifierFlags.contains(.shift) ? -1 : 1)
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
    switch model.kind {
    case .markdown:
      return NSSize(width: min(760, visible.width * 0.6), height: min(900, visible.height * 0.8))
    case .image:
      let image = model.media.size ?? NSSize(width: 640, height: 480)
      return natural(image, in: visible, pixelated: model.media.pixelated)
    case .video:
      return NSSize(width: 640, height: 360)
    }
  }

  /// A picture's opening size: its own up to 70% of the screen, shrunk to
  /// fit when bigger. Pixel art grows by the biggest whole multiple that fits.
  static func natural(_ size: CGSize, in visible: CGSize, pixelated: Bool) -> CGSize {
    guard size.width > 0, size.height > 0 else { return CGSize(width: 640, height: 480) }
    let room = min(visible.width * 0.7 / size.width, visible.height * 0.7 / size.height)
    let scale = room >= 1 ? (pixelated ? room.rounded(.down) : 1) : room
    return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
  }

  /// Sizes the window's content for `request`, keeping its top edge and
  /// center, on screen. The window keeps the picture's shape unless a zoom
  /// is bigger than the screen, which leaves it free to pan.
  private func resize(_ window: NSWindow, _ request: MediaState.Resize, keepShape: Bool) {
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
    let clipped = room < 1
    if case .exact = request, clipped, !keepShape {
      content = CGSize(width: min(content.width, visible.width), height: min(content.height, visible.height * 0.95))
      window.contentResizeIncrements = NSSize(width: 1, height: 1)
    } else {
      content = CGSize(width: content.width * room, height: content.height * room)
      window.contentAspectRatio = shape
    }
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

/// The file a viewer window shows, reloaded when it changes on disk.
final class ViewerModel: ObservableObject {
  @Published private(set) var url: URL
  /// Changes as the arrow keys step between pictures and movies.
  @Published private(set) var kind: ViewerKind
  @Published private(set) var blocks: [MarkdownBlock] = []
  @Published private(set) var error: String?
  /// Position among the folder's files the arrow keys reach, for "3 of 12".
  @Published private(set) var position: (index: Int, count: Int)?
  let media = MediaState()
  var onTitle: ((String) -> Void)?
  private var watcher: FileWatcher?

  init(url: URL) {
    self.url = url
    kind = ViewerKind.of(url) ?? .markdown
    media.openFile = { [weak self] in self?.show($0) }
    load(fresh: true)
  }

  func reload() { load(fresh: false) }

  func step(_ offset: Int) {
    let siblings = ViewerKind.siblings(of: url)
    guard siblings.count > 1, let index = siblings.firstIndex(of: url) else { return }
    show(siblings[(index + offset + siblings.count) % siblings.count])
  }

  func show(_ next: URL) {
    url = next
    kind = ViewerKind.of(next) ?? kind
    load(fresh: true)
  }

  private func load(fresh: Bool) {
    onTitle?(url.lastPathComponent)
    watcher = FileWatcher(url: url) { [weak self] in self?.load(fresh: false) }
    switch kind {
    case .markdown:
      do {
        blocks = Markdown.parse(try String(contentsOf: url, encoding: .utf8))
        error = nil
      } catch {
        self.error = "Can't read \(url.lastPathComponent): \(error.localizedDescription)"
      }
    case .image, .video:
      error = media.load(url, kind: kind, fresh: fresh)
      let siblings = ViewerKind.siblings(of: url)
      position = siblings.firstIndex(of: url).map { ($0 + 1, siblings.count) }
    }
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
    if model.kind.isMedia {
      MediaView(model: model, media: model.media)
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
      if let position = model.position, position.count > 1 {
        Text("\(position.index) of \(position.count)").font(.caption).foregroundStyle(.secondary)
      }
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

  private static let cache = NSCache<NSString, NSImage>()

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
