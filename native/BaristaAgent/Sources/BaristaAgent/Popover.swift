import AppKit
import QuickLookThumbnailing
import SwiftUI

struct StackEntry: Identifiable {
  let url: URL
  let name: String
  let icon: NSImage
  /// A folder you can open inside the callout; packages such as apps are not.
  let isFolder: Bool
  var id: URL { url }
}

/// How the open folder is listed. Moving to another folder keeps `hidden`
/// and starts the rest over.
struct FolderBrowsing {
  var hidden = false
  var limit = StackContents.limit
  var query = ""
}

enum StackContents {
  /// Cells shown at first, and how many more each Show More adds.
  static let limit = 60

  /// The whole folder. `added` and `modified` put the newest first, like the
  /// native Dock's Downloads stack; `name` lists folders first. Returns nil
  /// when the folder cannot be read (for example, privacy access was denied).
  static func load(_ folder: URL, sort: DockItem.Sort,
                   hidden: Bool = false) -> [(url: URL, name: String, isFolder: Bool)]? {
    let keys: Set<URLResourceKey> = [.addedToDirectoryDateKey, .contentModificationDateKey, .localizedNameKey,
                                     .isDirectoryKey, .isPackageKey]
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: Array(keys), options: hidden ? [] : [.skipsHiddenFiles])
    else { return nil }
    let entries = urls.map { url -> (url: URL, name: String, isFolder: Bool, date: Date) in
      let values = try? url.resourceValues(forKeys: keys)
      let date = sort == .modified
        ? values?.contentModificationDate
        : values?.addedToDirectoryDate ?? values?.contentModificationDate
      return (url, values?.localizedName ?? url.lastPathComponent,
              values?.isDirectory == true && values?.isPackage != true, date ?? .distantPast)
    }
    let sorted = sort == .name
      ? entries.sorted {
        $0.isFolder != $1.isFolder ? $0.isFolder : $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
      : entries.sorted { $0.date > $1.date }
    return sorted.map { ($0.url, $0.name, $0.isFolder) }
  }

  static func thumbnail(for url: URL) async -> NSImage? {
    let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 56, height: 56),
                                               scale: 2, representationTypes: .thumbnail)
    return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
  }
}

/// A right-click menu item on a folder or shelf cell, or a callout's header.
struct CellAction: Identifiable {
  let title: String
  let perform: () -> Void
  var id: String { title }
}

func copyText(_ text: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(text, forType: .string)
}

/// Pointer position inside a popover. SwiftUI hover is unreliable in windows
/// of an app that is never active, so cells test this against their frames.
final class PopoverPointer: ObservableObject {
  @Published var location: CGPoint?
}

/// One callout at a time above a dock tile: a folder's contents, the shelf,
/// or a group's apps.
final class PopoverController {
  static let shadowRoom: CGFloat = 30

  private var panel = makeOverlayPanel(levelOffset: 1, typing: true)
  /// The open folder's browsing options; a new folder starts over.
  private var browsing = FolderBrowsing()
  private var onClose: (() -> Void)?
  /// Bumped by every show and by `close`. Work that finishes later (a folder
  /// listing, a trash reload, a resize) checks it and drops itself when the
  /// callout has moved on.
  private var generation = 0
  private var placement: (anchor: NSPoint, screen: NSScreen)?

  var frame: NSRect? { panel.isVisible ? panel.frame : nil }
  /// Where the pointer was when the callout last rendered. Navigating can
  /// shrink the callout out from under a still pointer; that is not leaving.
  private(set) var pointerAtPresent: NSPoint?

  func openFolder(_ root: URL, title: String, icon: TileImage? = nil, sort: DockItem.Sort, store: DockStore,
                  anchor: NSPoint, on screen: NSScreen, onClose: @escaping () -> Void) {
    close()
    self.onClose = onClose
    placement = (anchor, screen)
    browsing = FolderBrowsing()
    showFolder([root], rootTitle: title, rootIcon: icon, sort: sort, store: store, animated: true)
  }

  func openShelf(store: DockStore, anchor: NSPoint, on screen: NSScreen, onClose: @escaping () -> Void) {
    close()
    self.onClose = onClose
    placement = (anchor, screen)
    showShelf(store: store, animated: true)
  }

  func openGroup(_ groupID: String, store: DockStore, anchor: NSPoint, on screen: NSScreen,
                 onClose: @escaping () -> Void) {
    close()
    self.onClose = onClose
    placement = (anchor, screen)
    showGroup(groupID, store: store, animated: true)
  }

  private func showGroup(_ groupID: String, store: DockStore, animated: Bool) {
    generation += 1
    let token = generation
    present(animated: animated) { [weak self] arrowX in
      GroupPopover(store: store, groupID: groupID, arrowX: arrowX,
                   onOpen: { tile in
                     if tile.item.kind == .folder, let url = tile.url {
                       self?.browsing = FolderBrowsing()
                       self?.showFolder([url], rootTitle: tile.name, rootIcon: store.image(for: tile),
                                        sort: tile.item.sort ?? .name, store: store,
                                        animated: false, up: { self?.showGroup(groupID, store: store, animated: false) })
                       return
                     }
                     store.open(tile)
                     self?.close()
                   },
                   onSession: { session in
                     store.focus(session)
                     self?.close()
                   },
                   onInfo: { row in
                     guard let group = store.groups.first(where: { $0.id == groupID }),
                           store.activate(row, in: group) else { return }
                     self?.close()
                   },
                   onResize: {
                     guard self?.generation == token else { return }
                     self?.showGroup(groupID, store: store, animated: false)
                   },
                   onDismiss: { self?.close() })
    }
  }

  /// Calls the opener's `onClose` before returning, so the dock controller
  /// sees the callout gone (and may show the attention card) right away.
  func close() {
    generation += 1
    placement = nil
    if panel.isVisible { panel.orderOut(nil) }
    let callback = onClose
    onClose = nil
    callback?()
  }

  // MARK: Folders and the shelf

  /// `path` runs from the dock's folder to the one shown; opening a
  /// subfolder pushes onto it and the back button pops it. `up`, for a
  /// folder opened from a group, is where the back button goes from the root.
  private func showFolder(_ path: [URL], rootTitle: String, rootIcon: TileImage? = nil, sort: DockItem.Sort,
                          store: DockStore, animated: Bool,
                          up: (() -> Void)? = nil) {
    guard let folder = path.last else { return }
    generation += 1
    let token = generation
    let options = browsing
    DispatchQueue.global(qos: .userInitiated).async {
      let listing = StackContents.load(folder, sort: sort, hidden: options.hidden)
      DispatchQueue.main.async { [weak self] in
        guard let self, self.generation == token else { return }
        let entries = listing?.map {
          StackEntry(url: $0.url, name: $0.name, icon: NSWorkspace.shared.icon(forFile: $0.url.path),
                     isFolder: $0.isFolder)
        }
        let refresh = { [weak self] in
          self?.showFolder(path, rootTitle: rootTitle, rootIcon: rootIcon, sort: sort, store: store, animated: false,
                           up: up)
        }
        let show = { [weak self] (next: [URL]) in
          guard let self else { return }
          self.browsing = FolderBrowsing(hidden: self.browsing.hidden)
          self.showFolder(next, rootTitle: rootTitle, rootIcon: rootIcon, sort: sort, store: store, animated: false,
                          up: up)
        }
        let names = [rootTitle] + path.dropFirst().map { FileManager.default.displayName(atPath: $0.path) }
        let crumbs = path.indices.dropLast().map { index in
          Crumb(title: names[index]) { show(Array(path.prefix(index + 1))) }
        }
        let count = entries?.count ?? 0
        let summary = count == 0 ? "Empty"
          : "\(count) item\(count == 1 ? "" : "s")" + (path.count == 1 && sort != .name ? " · newest first" : "")
        let browse = StackPopover.Browse(
          options: options,
          toggleHidden: { [weak self] in
            self?.browsing.hidden.toggle()
            self?.browsing.limit = StackContents.limit
            refresh()
          },
          showMore: { [weak self] in
            self?.browsing.limit += StackContents.limit
            refresh()
          },
          setQuery: { [weak self] in self?.browsing.query = $0 })
        self.present(animated: animated) { [weak self] arrowX in
          StackPopover(
            title: names.last ?? rootTitle,
            subtitle: summary,
            crumbs: crumbs,
            icon: (path.count == 1 ? rootIcon : nil) ?? .image(NSWorkspace.shared.icon(forFile: folder.path)),
            entries: entries,
            emptyText: "Nothing here yet.",
            theme: store.theme, arrowX: arrowX,
            onBack: path.count > 1 ? { show(Array(path.dropLast())) } : up,
            pill: ("Open in Finder", "arrow.up.forward.app", {
              NSWorkspace.shared.open(folder)
              self?.close()
            }),
            headerActions: self?.folderActions(folder, root: path[0]) ?? [],
            browse: browse,
            onOpen: { entry in
              if entry.isFolder {
                show(path + [entry.url])
              } else {
                Self.open(entry.url)
                self?.close()
              }
            },
            actions: { entry in
              self?.fileActions(entry, root: path[0], store: store, reload: {
                if self?.generation == token { refresh() }
              }) ?? []
            })
        }
      }
    }
  }

  /// Installed editors for Open in…, looked up once: menus are built on
  /// every render of every cell.
  static let editors: [(name: String, app: URL)] =
    [("Cursor", "com.todesktop.230313mzl4w4u92"), ("Emacs", "org.gnu.Emacs")].compactMap { name, bundleID in
      NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { (name, $0) }
    }

  /// Open in each installed editor, and a terminal in `directory`.
  private func toolActions(_ url: URL, directory: URL) -> [CellAction] {
    Self.editors.map { name, app in
      CellAction(title: "Open in \(name)") { [weak self] in
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        self?.close()
      }
    } + [
      CellAction(title: "Terminal Here") { [weak self] in
        ActionRunner.openTerminal("cd " + ActionRunner.shellQuote(directory.path), arguments: [])
        self?.close()
      },
    ]
  }

  /// The shown folder's own menu, on the callout's header. Nothing here
  /// changes the folder: trashing it from inside would pull the floor out.
  private func folderActions(_ folder: URL, root: URL) -> [CellAction] {
    [CellAction(title: "Open in Finder") { [weak self] in
      NSWorkspace.shared.open(folder)
      self?.close()
    },
     CellAction(title: "Browse in Barista Files") { [weak self] in
       BrowserController.shared.open(folder)
       self?.close()
     }]
      + toolActions(folder, directory: folder)
      + [CellAction(title: "Copy Path") { Self.copy(folder) }]
      + (folder == root ? [] : [CellAction(title: "Copy Relative Path") {
        copyText(Self.relativePath(folder, from: root))
      }])
  }

  /// A folder cell's right-click menu. `root` is the dock folder the
  /// browsing started from, for relative paths.
  private func fileActions(_ entry: StackEntry, root: URL, store: DockStore,
                           reload: @escaping () -> Void) -> [CellAction] {
    let url = entry.url
    var actions = [
      CellAction(title: "Open") { [weak self] in
        Self.open(url)
        self?.close()
      },
      CellAction(title: "Quick Look") { Self.quickLook(url) },
    ]
    if ViewerKind.of(url) != nil {
      actions.append(CellAction(title: "Open with Default App") { [weak self] in
        NSWorkspace.shared.open(url)
        self?.close()
      })
    }
    actions.append(CellAction(title: "Browse in Barista Files") { [weak self] in
      BrowserController.shared.open(url)
      self?.close()
    })
    actions += toolActions(url, directory: entry.isFolder ? url : url.deletingLastPathComponent())
    actions += [
      CellAction(title: "Show in Finder") { [weak self] in
        NSWorkspace.shared.activateFileViewerSelecting([url])
        self?.close()
      },
      CellAction(title: "Copy Path") { Self.copy(url) },
      CellAction(title: "Copy Relative Path") { copyText(Self.relativePath(url, from: root)) },
      CellAction(title: "Add to Shelf") { store.shelf.add([url]) },
      CellAction(title: "Move to Trash") {
        NSWorkspace.shared.recycle([url]) { _, error in
          if let error { DockStore.log("could not move \(url.path) to the Trash: \(error)") }
          DispatchQueue.main.async { reload() }
        }
      },
    ]
    return actions
  }

  /// `url`'s path under `root`, or its full path when it isn't under it.
  static func relativePath(_ url: URL, from root: URL) -> String {
    let base = root.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(base + "/") else { return path }
    return String(path.dropFirst(base.count + 1))
  }

  /// Markdown and images open in the viewer, everything else in its app.
  static func open(_ url: URL) {
    if !ViewerController.shared.open(url) { NSWorkspace.shared.open(url) }
  }

  private static func quickLook(_ url: URL) {
    launch("/usr/bin/qlmanage", ["-p", url.path], quiet: true)
  }

  private func showShelf(store: DockStore, animated: Bool) {
    generation += 1
    let shelf = store.shelf
    let entries = shelf.urls.map {
      StackEntry(url: $0, name: FileManager.default.displayName(atPath: $0.path),
                 icon: NSWorkspace.shared.icon(forFile: $0.path), isFolder: false)
    }
    let days = store.settings.shelfDays
    let keep = days >= 1 ? "\(Int(days)) day\(Int(days) == 1 ? "" : "s")" : "\(Int(days * 24)) hours"
    present(animated: animated) { [weak self] arrowX in
      StackPopover(
        title: "Shelf",
        subtitle: entries.isEmpty ? "Empty" : "\(entries.count) item\(entries.count == 1 ? "" : "s") · kept \(keep)",
        icon: .symbol("tray.full"),
        entries: entries,
        emptyText: "Drop files or text on the shelf to park them here. Drag them out when you need them.",
        theme: store.theme, arrowX: arrowX,
        onBack: nil,
        pill: entries.isEmpty ? nil : ("Clear Shelf", "xmark.circle", {
          shelf.clear()
          self?.close()
        }),
        headerActions: entries.isEmpty ? [] : [
          CellAction(title: "Copy All Paths") { copyText(entries.map(\.url.path).joined(separator: "\n")) },
          CellAction(title: "Show All in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(entries.map(\.url))
            self?.close()
          },
          CellAction(title: "Clear Shelf") {
            shelf.clear()
            self?.close()
          },
        ],
        onOpen: { entry in
          Self.open(entry.url)
          self?.close()
        },
        actions: { entry in
          [CellAction(title: "Open") {
             Self.open(entry.url)
             self?.close()
           },
           CellAction(title: "Show in Finder") {
             NSWorkspace.shared.activateFileViewerSelecting([entry.url])
             self?.close()
           },
           CellAction(title: "Copy Path") { Self.copy(entry.url) },
           CellAction(title: "Remove from Shelf") {
             shelf.remove(entry.url)
             self?.showShelf(store: store, animated: false)
           }]
        })
    }
  }

  private static func copy(_ url: URL) { copyText(url.path) }

  // MARK: Presenting

  /// Sizes the callout with a centered arrow, clamps it to the screen, then
  /// renders it again with the arrow over the tile. Navigating inside a
  /// callout presents again in place without the entrance animation.
  private func present<Content: View>(animated: Bool, content: @escaping (CGFloat?) -> Content) {
    guard let (anchor, screen) = placement else { return }
    let pointer = PopoverPointer()
    let host = DockHostingView(rootView: AnyView(content(nil).environmentObject(pointer)))
    host.onPointer = { pointer.location = $0 }
    let size = host.fittingSize
    let bounds = screen.frame
    let x = min(max(anchor.x - size.width / 2, bounds.minX), bounds.maxX - size.width).rounded()
    host.rootView = AnyView(content(anchor.x - x - Self.shadowRoom).environmentObject(pointer))
    host.wantsLayer = true
    let frame = NSRect(x: x, y: (anchor.y + 2 - Self.shadowRoom).rounded(), width: size.width, height: size.height)
    show(host, frame: frame)
    if !panel.isOnActiveSpace {
      // The window server can drop the panel from all Spaces (seen after a
      // Space was recreated) while AppKit still reports it visible; setting
      // the collection behavior again does not restore it, a new window does.
      DockStore.log("the callout panel left the active Space; replacing it")
      panel.orderOut(nil)
      panel = makeOverlayPanel(levelOffset: 1, typing: true)
      show(host, frame: frame)
    }
    pointerAtPresent = NSEvent.mouseLocation
    if animated { Self.animateIn(host.layer) }
  }

  private func show(_ host: NSView, frame: NSRect) {
    panel.contentView = host
    panel.setFrame(frame, display: true)
    panel.orderFrontRegardless()
  }

  /// Rises out of the tile and fades in. Core Animation runs this on the
  /// render server, so it stays smooth while SwiftUI lays out the cells.
  private static func animateIn(_ layer: CALayer?) {
    guard let layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    let rise = CASpringAnimation(keyPath: "transform.translation.y")
    rise.fromValue = -8
    rise.toValue = 0
    rise.damping = 22
    rise.stiffness = 300
    rise.duration = rise.settlingDuration
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = 0.16
    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
    layer.add(rise, forKey: "rise")
    layer.add(fade, forKey: "fade")
  }
}

// MARK: Chrome

/// A rounded panel with an arrow on its bottom edge, drawn as one outline so
/// the border runs unbroken around the arrow.
struct CalloutShape: Shape {
  static let arrow = CGSize(width: 22, height: 10)

  var cornerRadius: CGFloat
  /// Arrow tip x in the shape's coordinates; nil centers it.
  var arrowX: CGFloat?

  func path(in rect: CGRect) -> Path {
    let w = Self.arrow.width, h = Self.arrow.height, r = cornerRadius
    let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - h)
    let x = min(max(arrowX ?? body.midX, body.minX + r + w / 2), body.maxX - r - w / 2)
    var path = Path()
    path.move(to: CGPoint(x: body.minX + r, y: body.minY))
    path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
    path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
    path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
    path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
    path.addLine(to: CGPoint(x: x + w / 2, y: body.maxY))
    path.addQuadCurve(to: CGPoint(x: x + 2.5, y: body.maxY + h - 1.6),
                      control: CGPoint(x: x + w / 4, y: body.maxY))
    path.addQuadCurve(to: CGPoint(x: x - 2.5, y: body.maxY + h - 1.6),
                      control: CGPoint(x: x, y: body.maxY + h + 0.6))
    path.addQuadCurve(to: CGPoint(x: x - w / 2, y: body.maxY),
                      control: CGPoint(x: x - w / 4, y: body.maxY))
    path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
    path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
    path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
    path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
    path.closeSubpath()
    return path
  }
}

/// Header, divider, and content inside the callout. `PopoverController`
/// animates it in at the window level.
struct Callout<Header: View, Content: View>: View {
  let theme: DockTheme
  let arrowX: CGFloat?
  @ViewBuilder let header: Header
  @ViewBuilder let content: Content

  var body: some View {
    let shape = CalloutShape(cornerRadius: 18, arrowX: arrowX)
    VStack(alignment: .leading, spacing: 12) {
      header
      CalloutRule(theme: theme)
      content
    }
    .foregroundColor(theme.label)
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 14 + CalloutShape.arrow.height)
    .background(
      ZStack {
        shape.fill(Color.black.opacity(0.3))
          .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
        VisualEffectBackground().clipShape(shape)
        if let background = theme.background { shape.fill(background) }
        shape.fill(LinearGradient(colors: [Color.white.opacity(0.09), .clear],
                                  startPoint: .top, endPoint: .center))
        shape.stroke(theme.border, lineWidth: 1)
      }
    )
    .padding(PopoverController.shadowRoom)
    .fixedSize()
  }
}

private struct CalloutRule: View {
  let theme: DockTheme

  var body: some View {
    Rectangle()
      .fill(LinearGradient(colors: [theme.label.opacity(0), theme.label.opacity(0.14), theme.label.opacity(0)],
                           startPoint: .leading, endPoint: .trailing))
      .frame(height: 1)
  }
}

/// A folder above the open one; clicking it goes back there.
struct Crumb {
  let title: String
  let open: () -> Void
}

struct CalloutTitle<Icon: View>: View {
  let title: String
  let subtitle: String
  var crumbs: [Crumb] = []
  @ViewBuilder let icon: Icon

  var body: some View {
    HStack(spacing: 10) {
      icon.frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
        HStack(spacing: 3) {
          // Folder names repeat along a path (src/…/src); positions don't.
          ForEach(Array(crumbs.enumerated()), id: \.offset) { _, crumb in
            Text(crumb.title).underline().lineLimit(1)
              .contentShape(Rectangle())
              .onTapGesture(perform: crumb.open)
            Text("›")
          }
          Text(subtitle).lineLimit(1).truncationMode(.head)
        }
        .font(.system(size: 11)).opacity(0.6)
      }
    }
  }
}

/// True while the popover pointer is over this view.
struct PointerHover<Content: View>: View {
  @EnvironmentObject private var pointer: PopoverPointer
  @ViewBuilder let content: (Bool) -> Content

  var body: some View {
    GeometryReader { proxy in
      content(pointer.location.map { proxy.frame(in: .global).contains($0) } ?? false)
    }
  }
}

/// An icon with a name under it; lifts and highlights under the pointer, and
/// rises into place a moment after the callout opens.
private struct PopoverCell<Icon: View>: View {
  /// Tall enough for the icon, two lines of name, and the running dot; the grid's scroll view clips.
  static var size: CGSize { CGSize(width: 90, height: 110) }

  let index: Int
  let name: String
  let theme: DockTheme
  var running: Bool? = nil
  var active = false
  @ViewBuilder let icon: Icon
  @State private var appeared = false

  var body: some View {
    PointerHover { hovered in
      VStack(spacing: 6) {
        icon
          .frame(width: 54, height: 54)
          .shadow(color: .black.opacity(hovered ? 0.4 : 0.25), radius: hovered ? 8 : 4, y: hovered ? 5 : 2)
          .scaleEffect(hovered ? 1.1 : 1, anchor: .bottom)
        Text(name)
          .font(.system(size: 11, weight: .medium))
          .lineLimit(2)
          .truncationMode(.middle)
          .multilineTextAlignment(.center)
          .frame(width: Self.size.width - 10, height: 28, alignment: .top)
        if let running {
          Circle()
            .fill(active ? theme.accent : theme.label.opacity(0.6))
            .frame(width: 4, height: 4)
            .opacity(running ? 1 : 0)
        }
      }
      .padding(.top, 8)
      .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(hovered ? theme.hover : Color.clear)
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(hovered ? theme.border : Color.clear, lineWidth: 1))
      )
      .animation(.spring(response: 0.24, dampingFraction: 0.7), value: hovered)
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .contentShape(Rectangle())
    .opacity(appeared ? 1 : 0)
    .offset(y: appeared ? 0 : 10)
    .onAppear {
      // Capped, so the last of a long folder or cells scrolled into view don't wait.
      withAnimation(.spring(response: 0.36, dampingFraction: 0.78).delay(0.04 + Double(min(index, 15)) * 0.018)) {
        appeared = true
      }
    }
  }
}

private struct CellGrid<Cell: View>: View {
  static var gap: CGFloat { 6 }

  let count: Int
  let maxColumns: Int
  let maxRows: Int
  @ViewBuilder let cells: Cell

  static func width(count: Int, maxColumns: Int) -> CGFloat {
    let columns = CGFloat(max(1, min(maxColumns, count)))
    return columns * PopoverCell<EmptyView>.size.width + (columns - 1) * gap
  }

  var body: some View {
    let columns = max(1, min(maxColumns, count))
    let rows = (count + columns - 1) / columns
    let visibleRows = CGFloat(max(1, min(rows, maxRows)))
    let cell = PopoverCell<EmptyView>.size
    ScrollView(.vertical, showsIndicators: rows > maxRows) {
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(cell.width), spacing: Self.gap), count: columns),
                spacing: Self.gap) {
        cells
      }
    }
    .frame(width: Self.width(count: count, maxColumns: maxColumns),
           height: visibleRows * cell.height + (visibleRows - 1) * Self.gap)
  }
}

struct PillButton: View {
  let title: String
  let systemImage: String
  let theme: DockTheme
  let action: () -> Void

  var body: some View {
    PointerHover { hovered in
      Label(title, systemImage: systemImage)
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Capsule().fill(theme.label.opacity(hovered ? 0.2 : 0.1)))
        .overlay(Capsule().strokeBorder(theme.label.opacity(0.12), lineWidth: 1))
        .fixedSize()
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
    .frame(width: 128, height: 24)
    .contentShape(Capsule())
    .onTapGesture(perform: action)
  }
}

private struct BackButton: View {
  let theme: DockTheme
  let action: () -> Void

  var body: some View {
    PointerHover { hovered in
      Image(systemName: "chevron.left")
        .font(.system(size: 12, weight: .semibold))
        .frame(width: 26, height: 26)
        .background(Circle().fill(theme.label.opacity(hovered ? 0.2 : 0.1)))
        .overlay(Circle().strokeBorder(theme.label.opacity(0.12), lineWidth: 1))
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
    .frame(width: 26, height: 26)
    .contentShape(Circle())
    .onTapGesture(perform: action)
  }
}

// MARK: Folders and the shelf

/// A grid of files: a folder stack you can browse into, or the shelf.
struct StackPopover: View {
  /// A folder's filter, hidden-file toggle, and paging; the shelf has none.
  struct Browse {
    let options: FolderBrowsing
    let toggleHidden: () -> Void
    let showMore: () -> Void
    let setQuery: (String) -> Void
  }

  let title: String
  let subtitle: String
  var crumbs: [Crumb] = []
  let icon: TileImage
  let entries: [StackEntry]?
  let emptyText: String
  let theme: DockTheme
  let arrowX: CGFloat?
  let onBack: (() -> Void)?
  let pill: (title: String, systemImage: String, action: () -> Void)?
  /// Right-clicking the header: what to do with the folder or shelf itself.
  var headerActions: [CellAction] = []
  var browse: Browse?
  let onOpen: (StackEntry) -> Void
  let actions: (StackEntry) -> [CellAction]

  @State private var query = ""
  @State private var started = false

  var body: some View {
    Callout(theme: theme, arrowX: arrowX) {
      HStack(alignment: .center, spacing: 12) {
        if let onBack { BackButton(theme: theme, action: onBack) }
        CalloutTitle(title: title, subtitle: subtitle, crumbs: crumbs) { TileIcon(image: icon, theme: theme) }
        Spacer(minLength: 0)
        if let pill { PillButton(title: pill.title, systemImage: pill.systemImage, theme: theme, action: pill.action) }
      }
      .contentShape(Rectangle())
      .contextMenu {
        ForEach(headerActions) { action in Button(action.title, action: action.perform) }
      }
    } content: {
      if let browse, let entries {
        let matches = query.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let shown = Array(matches.prefix(browse.options.limit))
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            FilterField(initial: browse.options.query,
                        onChange: { query = $0 },
                        onSubmit: { if let first = shown.first { onOpen(first) } })
            Toggle("Hidden", isOn: Binding(get: { browse.options.hidden }, set: { _ in browse.toggleHidden() }))
              .toggleStyle(.checkbox)
              .font(.system(size: 11))
          }
          // Sized for the unfiltered folder, so typing never resizes the callout.
          CellGrid(count: max(1, min(entries.count, browse.options.limit)), maxColumns: 5, maxRows: 3) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
              FolderCell(index: index, entry: entry, theme: theme, onOpen: onOpen, actions: actions(entry))
            }
          }
          .overlay {
            if shown.isEmpty {
              Text(entries.isEmpty ? emptyText : "No matches").font(.system(size: 12)).opacity(0.7)
            }
          }
          if matches.count > shown.count {
            Button("Show \(min(StackContents.limit, matches.count - shown.count)) More of \(matches.count)",
                   action: browse.showMore)
              .buttonStyle(.link)
              .font(.system(size: 11))
          }
        }
        .frame(width: CellGrid<EmptyView>.width(count: min(max(entries.count, 3), 5), maxColumns: 5))
        .onAppear {
          guard !started else { return }
          started = true
          query = browse.options.query
        }
        .onChange(of: query) { _, text in browse.setQuery(text) }
      } else if let entries, !entries.isEmpty {
        CellGrid(count: entries.count, maxColumns: 5, maxRows: 3) {
          ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            FolderCell(index: index, entry: entry, theme: theme, onOpen: onOpen, actions: actions(entry))
          }
        }
      } else {
        Text(entries == nil
             ? "Barista can't read this folder. Allow it in System Settings → Privacy & Security → Files and Folders."
             : emptyText)
          .font(.system(size: 12)).opacity(0.7)
          .frame(width: 280, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// A search field that owns its text. SwiftUI's `TextField` writes its
/// binding back into the field on every redraw, and thumbnails redraw the
/// callout while you type, so it could replace newer typing.
private struct FilterField: NSViewRepresentable {
  let initial: String
  let onChange: (String) -> Void
  let onSubmit: () -> Void

  func makeNSView(context: Context) -> NSSearchField {
    let field = NSSearchField()
    field.placeholderString = "Filter"
    field.stringValue = initial
    field.font = .systemFont(ofSize: 12)
    field.controlSize = .small
    field.sendsSearchStringImmediately = true
    field.delegate = context.coordinator
    return field
  }

  func updateNSView(_ field: NSSearchField, context: Context) {
    context.coordinator.parent = self
  }

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  final class Coordinator: NSObject, NSSearchFieldDelegate {
    var parent: FilterField

    init(parent: FilterField) { self.parent = parent }

    func controlTextDidChange(_ note: Notification) {
      guard let field = note.object as? NSSearchField else { return }
      parent.onChange(field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
      parent.onSubmit()
      return true
    }
  }
}

private struct FolderCell: View {
  let index: Int
  let entry: StackEntry
  let theme: DockTheme
  let onOpen: (StackEntry) -> Void
  let actions: [CellAction]
  @State private var thumbnail: NSImage?

  var body: some View {
    PopoverCell(index: index, name: entry.name, theme: theme) {
      Image(nsImage: thumbnail ?? entry.icon)
        .resizable()
        .interpolation(.high)
        .aspectRatio(contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: thumbnail == nil ? 0 : 6, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
          if entry.isFolder {
            Image(systemName: "chevron.right.circle.fill")
              .font(.system(size: 14))
              .foregroundStyle(.white, theme.accent)
              .offset(x: 4, y: 2)
          }
        }
    }
    .onTapGesture { onOpen(entry) }
    .onDrag { NSItemProvider(object: entry.url as NSURL) }
    .contextMenu {
      ForEach(actions) { action in Button(action.title, action: action.perform) }
    }
    .task(id: entry.url) {
      guard !entry.isFolder else { return }
      thumbnail = await StackContents.thumbnail(for: entry.url)
    }
  }
}

// MARK: Group

/// A group's apps with live running state, then its `info_command` rows and
/// the agent sessions in those apps; members keep their dock right-click menu.
struct GroupPopover: View {
  @ObservedObject var store: DockStore
  let groupID: String
  let arrowX: CGFloat?
  let onOpen: (DockTile) -> Void
  let onSession: (AgentSession) -> Void
  let onInfo: (InfoRow) -> Void
  /// The panel is sized once: a change in its members or in the number of
  /// rows sizes it again.
  let onResize: () -> Void
  let onDismiss: () -> Void

  private static let maxSessions = 8

  var body: some View {
    let group = store.groups.first { $0.id == groupID }
    let members = group?.children ?? []
    let running = members.filter(\.isRunning).count
    let sessions = group.map(store.sessions(in:)) ?? []
    let info = group.map(store.info(in:)) ?? []
    let usage = members.compactMap { member in
      member.item.bundleID.flatMap { store.agents.usage[$0] }.map { "\(member.name) \($0)" }
    }
    let waiting = sessions.filter { !$0.needs.isEmpty }.count
    // A session waiting on you takes a taller row.
    let rows = [members.count, info.count, min(sessions.count, Self.maxSessions + 1), waiting, usage.isEmpty ? 0 : 1]
    let noun = members.allSatisfy { $0.item.kind == .app } ? "app" : "item"
    Callout(theme: store.theme, arrowX: arrowX) {
      CalloutTitle(title: group?.name ?? "Group",
                   subtitle: "\(members.count) \(noun)\(members.count == 1 ? "" : "s")"
                     + (running > 0 ? " · \(running) running" : "")
                     + (sessions.isEmpty ? "" : " · \(sessions.count) agent \(sessions.count == 1 ? "session" : "sessions")")
                     + (waiting > 0 ? " · \(waiting) \(waiting == 1 ? "needs" : "need") you" : "")) {
        if let group { GroupGlyph(images: groupImages(group), theme: store.theme) }
      }
      .contentShape(Rectangle())
      .contextMenu { if let group { groupMenu(group) } }
    } content: {
      if members.isEmpty {
        Text("Drop apps on this group, or use Add to Group on any app.")
          .font(.system(size: 12)).opacity(0.7)
          .frame(width: 240, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        let plain = Set(members.filter(store.isPlainFolder).map(\.id))
        let places = members.filter { plain.contains($0.id) }
        let cells = members.filter { !plain.contains($0.id) }
        let width = max(CellGrid<EmptyView>.width(count: cells.count, maxColumns: 4), 300)
        VStack(alignment: .leading, spacing: 10) {
          if !cells.isEmpty {
            CellGrid(count: cells.count, maxColumns: 4, maxRows: 3) {
              ForEach(Array(cells.enumerated()), id: \.element.id) { index, member in
                PopoverCell(index: index, name: member.name, theme: store.theme,
                            running: member.isRunning, active: member.isActive) {
                  TileIcon(image: store.image(for: member), theme: store.theme)
                    .overlay {
                      if let state = store.actionState(for: member) {
                        ActionStatus(state: state, theme: store.theme, side: 54)
                      }
                    }
                    .overlay(alignment: .topTrailing) {
                      if let text = store.badgeText(for: member) {
                        TileBadge(text: text, color: store.badgeColor(for: member), height: 18)
                          .offset(x: 5, y: -5)
                      }
                    }
                }
                .onTapGesture { onOpen(member) }
                .contextMenu { memberMenu(member, group: group) }
              }
            }
          }
          if !places.isEmpty {
            if !cells.isEmpty { CalloutRule(theme: store.theme) }
            ForEach(places) { place in
              PlaceRow(name: place.name, path: place.url.map { ($0.path as NSString).abbreviatingWithTildeInPath },
                       image: store.image(for: place), theme: store.theme, width: width) { onOpen(place) }
                .contextMenu { memberMenu(place, group: group) }
            }
          }
          if !info.isEmpty {
            CalloutRule(theme: store.theme)
            ForEach(info) { row in
              InfoRowView(row: row, state: group.flatMap { store.actionState(for: row, in: $0) },
                          theme: store.theme, width: width) { onInfo(row) }
                .contextMenu { if let group { infoMenu(row, group: group) } }
            }
          }
          if !sessions.isEmpty || !usage.isEmpty {
            CalloutRule(theme: store.theme)
            ForEach(Array(sessions.prefix(Self.maxSessions))) { session in
              SessionRow(session: session, finished: store.attention.finished[session.id] != nil,
                         theme: store.theme, width: width) { onSession(session) }
                .contextMenu { sessionMenu(session, members: members) }
            }
            if sessions.count > Self.maxSessions {
              Text("\(sessions.count - Self.maxSessions) more in the bar's agents menu")
                .font(.system(size: 11)).opacity(0.55)
                .padding(.horizontal, 8)
            }
            if !usage.isEmpty {
              Label("Usage · " + usage.joined(separator: " · "), systemImage: "gauge.with.dots.needle.33percent")
                .font(.system(size: 11)).opacity(0.6)
                .padding(.horizontal, 8)
                .frame(width: width, alignment: .leading)
            }
          }
        }
      }
    }
    .onChange(of: rows) { DispatchQueue.main.async(execute: onResize) }
  }

  @ViewBuilder
  private func groupMenu(_ group: DockTile) -> some View {
    let apps = group.children.filter { $0.item.kind == .app }
    if !apps.isEmpty {
      Button("Open All Apps") {
        apps.forEach(store.open)
        onDismiss()
      }
      if apps.contains(where: \.isRunning) {
        Button("Hide All Apps") { apps.forEach(store.hide) }
      }
      Divider()
    }
    Button("Rename…") { store.rename(group) }
    Button("Ungroup") {
      store.ungroup(group)
      onDismiss()
    }
    Divider()
    Button("Remove from Dock") {
      store.remove(group)
      onDismiss()
    }
  }

  @ViewBuilder
  private func infoMenu(_ row: InfoRow, group: DockTile) -> some View {
    let runID = store.runID(for: row, in: group)
    if let runID, store.actions.states[runID]?.isActive == true {
      Button("Stop") { store.actions.stop(runID) }
        .disabled(store.actions.states[runID] == .stopping)
    } else if row.isClickable {
      Button(verb(for: row, in: group)) { onInfo(row) }
    }
    if let runID, store.actions.hasOutput(runID) {
      Button("Show Last Output") { store.actions.showOutput(runID) }
    }
    if let target = row.open, !target.isEmpty {
      let isLink = target.contains("://")
      let path = (target as NSString).expandingTildeInPath
      if !isLink {
        Button("Show in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
          onDismiss()
        }
      }
      Button(isLink ? "Copy Link" : "Copy Path") { copyText(isLink ? target : path) }
    }
    Divider()
    Button("Copy Row") { copyText(row.detail.map { "\(row.title): \($0)" } ?? row.title) }
  }

  private func verb(for row: InfoRow, in group: DockTile) -> String {
    if let title = row.action, !title.isEmpty {
      let member = group.children.first { $0.name == title }
      return (member?.item.kind == .action ? "Run " : "Open ") + title
    }
    return (row.run ?? "").isEmpty ? "Open" : "Run"
  }

  @ViewBuilder
  private func sessionMenu(_ session: AgentSession, members: [DockTile]) -> some View {
    Button("Go to Session") { onSession(session) }
      .disabled(session.focus.isEmpty)
    if let app = members.first(where: { $0.item.bundleID == session.app }) {
      Button("Open \(app.name)") { onOpen(app) }
    }
    if !session.needs.isEmpty {
      Divider()
      Button("Copy Question") { copyText(session.needs) }
      Button("Hide from Attention Card") { store.setAside(session) }
        .disabled(!store.waitingSessions.contains { $0.id == session.id })
    }
    if store.attention.finished[session.id] != nil {
      Button("Mark as Seen") { store.markSeen(session) }
    }
    Divider()
    Button("Copy Title") { copyText(session.title.isEmpty ? "Session" : session.title) }
  }

  private func groupImages(_ group: DockTile) -> [TileImage] {
    if case .group(let images) = store.image(for: group) { return images }
    return []
  }

  @ViewBuilder
  private func memberMenu(_ member: DockTile, group: DockTile?) -> some View {
    if member.item.kind == .app {
      AppMenu(store: store, tile: member) {
        if case let entries = store.menuEntries(for: member), !entries.isEmpty {
          MenuEntries(store: store, tile: member, entries: entries)
          Divider()
        }
      } options: {
        if let group {
          Button("Remove from Group") {
            store.takeOut(member, from: group)
            onDismiss()
          }
        }
        Button("Show in Finder") { store.reveal(member) }
      }
    } else {
      otherMemberMenu(member, group: group)
    }
  }

  @ViewBuilder
  private func otherMemberMenu(_ member: DockTile, group: DockTile?) -> some View {
    if case let entries = store.menuEntries(for: member), !entries.isEmpty {
      MenuEntries(store: store, tile: member, entries: entries)
      Divider()
    }
    switch member.item.kind {
    case .app:
      EmptyView()
    case .folder, .file:
      Button("Open") { onOpen(member) }
      Button("Show in Finder") { store.reveal(member) }
    case .action, .url, .group, .shelf:
      Button(member.item.kind == .action ? "Run" : "Open") { onOpen(member) }
    }
    if let group {
      Divider()
      Button("Remove from Group") {
        store.takeOut(member, from: group)
        onDismiss()
      }
    }
  }
}

/// A plain folder in a group: a small icon, its name, and where it is.
/// Clicking browses it inside the callout, with a way back to the group.
private struct PlaceRow: View {
  let name: String
  let path: String?
  let image: TileImage
  let theme: DockTheme
  let width: CGFloat
  let action: () -> Void

  var body: some View {
    PointerHover { hovered in
      HStack(spacing: 8) {
        TileIcon(image: image, theme: theme).frame(width: 20, height: 20)
        Text(name)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
        if let path {
          Text(path)
            .font(.system(size: 11)).opacity(0.5)
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(-1)
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .opacity(hovered ? 0.8 : 0.35)
      }
      .padding(.horizontal, 8)
      .frame(width: width, height: 28)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(hovered ? theme.hover : Color.clear))
      .animation(.easeOut(duration: 0.12), value: hovered)
    }
    .frame(width: width, height: 28)
    .contentShape(Rectangle())
    .onTapGesture(perform: action)
  }
}

/// One `info_command` row: a tone dot, its title, and its detail on the
/// right, or the progress of what it runs. Clickable rows highlight.
private struct InfoRowView: View {
  let row: InfoRow
  let state: ActionRunner.State?
  let theme: DockTheme
  let width: CGFloat
  let action: () -> Void

  var body: some View {
    PointerHover { hovered in
      HStack(spacing: 8) {
        Circle().fill(tone).frame(width: 7, height: 7)
        Text(row.title)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 8)
        trailing
      }
      .padding(.horizontal, 8)
      .frame(width: width, height: 26)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(hovered && row.isClickable ? theme.hover : Color.clear))
      .animation(.easeOut(duration: 0.12), value: hovered)
    }
    .frame(width: width, height: 26)
    .contentShape(Rectangle())
    .onTapGesture { if row.isClickable { action() } }
  }

  @ViewBuilder private var trailing: some View {
    switch state {
    case .running?, .stopping?:
      ProgressView().controlSize(.mini)
    case .failed?:
      Label("Failed", systemImage: "xmark.circle.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(theme.failure)
    case .succeeded?:
      Label("Done", systemImage: "checkmark.circle.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(theme.success)
    case nil:
      if let detail = row.detail, !detail.isEmpty {
        Text(detail)
          .font(.system(size: 11)).opacity(0.55)
          .lineLimit(1)
          .layoutPriority(-1)
      }
    }
  }

  private var tone: Color {
    switch row.tone ?? .none {
    case .ok: return theme.success
    case .warn: return theme.warning
    case .error: return theme.failure
    case .none: return theme.label.opacity(0.35)
    }
  }
}

/// One agent session: its tool's color, its title, and whether it waits on
/// you (with its question underneath), is working, finished, or idle.
/// Clicking brings its window or chat forward.
private struct SessionRow: View {
  let session: AgentSession
  let finished: Bool
  let theme: DockTheme
  let width: CGFloat
  let action: () -> Void

  private var height: CGFloat { session.needs.isEmpty ? 26 : 42 }

  var body: some View {
    PointerHover { hovered in
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 8) {
          Circle().fill(session.color ?? theme.accent).frame(width: 7, height: 7)
          Text(session.title.isEmpty ? "Session" : session.title)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 8)
          status
        }
        if !session.needs.isEmpty {
          Text(session.needs)
            .font(.system(size: 11))
            .foregroundColor(theme.failure)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 15)
        }
      }
      .padding(.horizontal, 8)
      .frame(width: width, height: height)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(hovered ? theme.hover : Color.clear))
      .animation(.easeOut(duration: 0.12), value: hovered)
    }
    .frame(width: width, height: height)
    .contentShape(Rectangle())
    .help(session.needs)
    .onTapGesture(perform: action)
  }

  @ViewBuilder private var status: some View {
    if !session.needs.isEmpty {
      Label("Needs you", systemImage: "questionmark.bubble.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(theme.failure)
    } else if finished {
      Label("Done", systemImage: "checkmark.circle.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(theme.success)
    } else if session.working {
      Label("Working", systemImage: "ellipsis.circle")
        .font(.system(size: 11))
        .opacity(0.75)
    } else {
      Text(session.detail).font(.system(size: 11)).opacity(0.55)
    }
  }
}
