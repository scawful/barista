import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What the viewer shows natively; anything else opens in its default app.
enum ViewerKind: Equatable {
  case markdown, image

  static func of(_ url: URL) -> ViewerKind? {
    let ext = url.pathExtension.lowercased()
    if ["md", "markdown", "mdown", "mkd"].contains(ext) { return .markdown }
    guard let type = UTType(filenameExtension: ext), type.conforms(to: .image) else { return nil }
    return .image
  }

  /// The other files of this kind in `url`'s folder, in Finder's name order,
  /// for stepping through them with the arrow keys.
  static func siblings(of url: URL) -> [URL] {
    guard let kind = of(url),
          let urls = try? FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    else { return [url] }
    let matching = urls.filter { of($0) == kind }
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
    window.contentView = NSHostingView(rootView: ViewerView(model: model))
    model.onTitle = { [weak window] name in window?.title = name + Self.titleSuffix }
    model.onTitle?(url.lastPathComponent)
    place(window)
    windows.append(window)
    models[ObjectIdentifier(window)] = model
    closeObservers[ObjectIdentifier(window)] = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self] note in
      guard let self, let closing = note.object as? NSWindow else { return }
      self.closeObservers.removeValue(forKey: ObjectIdentifier(closing)).map(NotificationCenter.default.removeObserver)
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

  /// Escape and ⌘W close, ←/→ step through the folder's images, ⌘R reloads,
  /// ⌘E opens the file in its editor.
  private func installKeys() {
    guard keyMonitor == nil else { return }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = event.window, let model = self.models[ObjectIdentifier(window)] else {
        return event
      }
      let command = event.modifierFlags.contains(.command)
      switch (event.keyCode, command, event.charactersIgnoringModifiers?.lowercased()) {
      case (53, _, _), (_, true, "w"):
        window.performClose(nil)
      case (_, true, "r"):
        model.reload()
      case (_, true, "e"):
        NSWorkspace.shared.open(model.url)
      case (123, false, _) where model.kind == .image:
        model.step(-1)
      case (124, false, _) where model.kind == .image:
        model.step(1)
      case (_, false, "0") where model.kind == .image:
        model.zoom = .fit
      case (_, false, "1") where model.kind == .image:
        model.zoom = .actual
      default:
        return event
      }
      return nil
    }
  }

  private static func size(for model: ViewerModel) -> NSSize {
    let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
    switch model.kind {
    case .markdown:
      return NSSize(width: min(760, visible.width * 0.6), height: min(900, visible.height * 0.8))
    case .image:
      let image = model.image?.size ?? NSSize(width: 640, height: 480)
      let scale = min(1, visible.width * 0.7 / max(image.width, 1), visible.height * 0.7 / max(image.height, 1))
      return NSSize(width: max(360, image.width * scale), height: max(240, image.height * scale + 28))
    }
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
  /// `custom` is wherever a pinch left the image.
  enum Zoom { case fit, actual, custom }

  @Published private(set) var url: URL
  @Published private(set) var blocks: [MarkdownBlock] = []
  @Published private(set) var image: NSImage?
  @Published private(set) var error: String?
  @Published var zoom = Zoom.fit
  /// Position among the folder's files of the same kind, for "3 of 12".
  @Published private(set) var position: (index: Int, count: Int)?
  var onTitle: ((String) -> Void)?
  let kind: ViewerKind
  private var watcher: FileWatcher?

  init(url: URL) {
    self.url = url
    kind = ViewerKind.of(url) ?? .markdown
    load()
  }

  func reload() { load() }

  func step(_ offset: Int) {
    let siblings = ViewerKind.siblings(of: url)
    guard siblings.count > 1, let index = siblings.firstIndex(of: url) else { return }
    url = siblings[(index + offset + siblings.count) % siblings.count]
    zoom = .fit
    load()
  }

  func show(_ next: URL) {
    url = next
    load()
  }

  private func load() {
    onTitle?(url.lastPathComponent)
    watcher = FileWatcher(url: url) { [weak self] in self?.load() }
    switch kind {
    case .markdown:
      do {
        blocks = Markdown.parse(try String(contentsOf: url, encoding: .utf8))
        error = nil
      } catch {
        self.error = "Can't read \(url.lastPathComponent): \(error.localizedDescription)"
      }
    case .image:
      image = NSImage(contentsOf: url)
      error = image == nil ? "Can't open \(url.lastPathComponent) as an image." : nil
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
    VStack(spacing: 0) {
      header
      Divider()
      if let error = model.error {
        Text(error).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if model.kind == .markdown {
        MarkdownDocumentView(blocks: model.blocks, base: model.url.deletingLastPathComponent(),
                             open: { route in
                               if case .view(let url) = route, ViewerKind.of(url) == .markdown {
                                 model.show(url)
                               } else {
                                 route.perform()
                               }
                             })
      } else if let image = model.image {
        ZoomableImage(image: image, zoom: $model.zoom)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea(edges: .top)
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
        .help(model.kind == .markdown ? "Open in Editor (⌘E)" : "Open in Default App (⌘E)")
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

/// Pinch to zoom, double-click toggles fit and actual size, and the image
/// stays centered while smaller than the window.
private struct ZoomableImage: NSViewRepresentable {
  let image: NSImage
  @Binding var zoom: ViewerModel.Zoom

  func makeNSView(context: Context) -> ImageScrollView {
    let view = ImageScrollView()
    view.onDoubleClick = { zoom = zoom == .fit ? .actual : .fit }
    view.onPinch = { zoom = .custom }
    return view
  }

  func updateNSView(_ view: ImageScrollView, context: Context) {
    view.show(image, zoom: zoom)
  }
}

final class ImageScrollView: NSScrollView {
  var onDoubleClick: (() -> Void)?
  var onPinch: (() -> Void)?
  private let imageView = NSImageView()
  private var zoom = ViewerModel.Zoom.fit

  init() {
    super.init(frame: .zero)
    contentView = CenteringClipView()
    documentView = imageView
    imageView.imageScaling = .scaleAxesIndependently
    imageView.animates = true
    allowsMagnification = true
    minMagnification = 0.02
    maxMagnification = 16
    hasVerticalScroller = true
    hasHorizontalScroller = true
    autohidesScrollers = true
    drawsBackground = false
    NotificationCenter.default.addObserver(self, selector: #selector(pinched),
                                           name: NSScrollView.didEndLiveMagnifyNotification, object: self)
  }

  @objc private func pinched() {
    zoom = .custom
    onPinch?()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

  func show(_ image: NSImage, zoom: ViewerModel.Zoom) {
    let changed = imageView.image !== image || self.zoom != zoom
    imageView.image = image
    imageView.frame = NSRect(origin: .zero, size: image.size)
    self.zoom = zoom
    if changed { applyZoom() }
  }

  override func layout() {
    super.layout()
    if zoom == .fit { applyZoom() }
  }

  override func mouseDown(with event: NSEvent) {
    if event.clickCount == 2 { onDoubleClick?() } else { super.mouseDown(with: event) }
  }

  private func applyZoom() {
    guard zoom != .custom, let size = imageView.image?.size, size.width > 0, size.height > 0 else { return }
    let bounds = contentView.bounds.size
    let visible = NSSize(width: bounds.width * magnification, height: bounds.height * magnification)
    magnification = zoom == .actual ? 1 : min(1, visible.width / size.width, visible.height / size.height)
  }
}

/// Keeps a document smaller than the view in the middle instead of the corner.
private final class CenteringClipView: NSClipView {
  override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
    var rect = super.constrainBoundsRect(proposedBounds)
    guard let document = documentView else { return rect }
    if rect.width > document.frame.width { rect.origin.x = (document.frame.width - rect.width) / 2 }
    if rect.height > document.frame.height { rect.origin.y = (document.frame.height - rect.height) / 2 }
    return rect
  }
}
