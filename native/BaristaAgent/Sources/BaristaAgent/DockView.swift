import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Draws the scene's current frame. Geometry and motion come from
/// `DockScene`; this view only renders them and forwards input, so it never
/// animates on its own.
struct DockView: View {
  @ObservedObject var store: DockStore
  @ObservedObject var scene: DockScene
  let actions: DockActions
  @State private var dropTarget: String?
  @GestureState private var gestureActive = false

  var body: some View {
    let frame = scene.frame
    let tiles = store.tilesByID
    ZStack(alignment: .topLeading) {
      DockBackground(theme: store.theme, cornerRadius: 14)
        .frame(width: frame.bar.width, height: frame.bar.height)
        .modifier(Rise(rise: frame.barRise, opacity: frame.barOpacity, slide: frame.slide, minScale: 1))
        .position(x: frame.bar.midX, y: frame.bar.midY)
      ForEach(frame.items) { item in
        let rise = Rise(rise: item.rise, opacity: item.opacity, slide: frame.slide, minScale: 0.6)
        switch item.slot {
        case .divider:
          Rectangle()
            .fill(store.theme.label.opacity(0.22))
            .frame(width: 1, height: item.rect.height)
            .modifier(rise)
            .position(x: item.rect.midX, y: item.rect.midY)
        case .tile(let id):
          if let tile = tiles[id] {
            tileView(tile, size: item.rect.size, frame: frame)
              .modifier(rise)
              .position(x: item.rect.midX, y: item.rect.midY)
              .zIndex(id == frame.draggedID ? 1 : 0)
          }
        }
      }
    }
    .frame(width: frame.canvas.width, height: frame.canvas.height)
    .transaction { $0.animation = nil }
    .onChange(of: gestureActive) { _, active in
      guard !active else { return }
      // A cancelled drag never reaches onEnded; after a normal end this finds no drag.
      DispatchQueue.main.async { scene.dragEnded(commit: false) }
    }
    .onDrop(of: [.fileURL, .url], isTargeted: nil) { providers, location in
      Self.loadURLs(providers) { urls in
        guard !urls.isEmpty else { return }
        let apps = urls.allSatisfy { $0.isFileURL && $0.pathExtension == "app" }
        let list: DockConfig.List = apps ? .pinned : .others
        store.add(urls, to: list, at: scene.insertionIndex(in: list, x: location.x))
      }
      return true
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
  }

  private func tileView(_ tile: DockTile, size: CGSize, frame: DockScene.Frame) -> some View {
    let dragged = frame.draggedID == tile.id
    let badge = store.badgeText(for: tile)
    let face = TileFace(image: store.image(for: tile), theme: store.theme, size: size,
                        highlighted: frame.hoveredID == tile.id || dropTarget == tile.id
                          || scene.openPopoverID == tile.id,
                        dimmed: tile.isHidden, state: store.actionState(for: tile),
                        badge: badge, badgeColor: badge == nil ? .clear : store.badgeColor(for: tile),
                        finished: badge == nil && store.hasFinished(tile),
                        running: tile.isRunning && !dragged, active: tile.isActive,
                        removing: dragged && frame.removing)
    return DockTileView(tile: tile, face: face, store: store, actions: actions, dropTarget: $dropTarget)
      .equatable()
      // Its state is the dock's, which ends a cancelled drag even if this tile is gone.
      .gesture(reorderGesture(tile))
  }

  /// The gesture's own coordinates move while the panel grows for the drag,
  /// so the scene tracks the pointer on screen instead.
  private func reorderGesture(_ tile: DockTile) -> some Gesture {
    DragGesture(minimumDistance: 6)
      .updating($gestureActive) { _, active, _ in active = true }
      .onChanged { value in
        scene.dragChanged(id: tile.id, scope: tile.dragScope, mouse: NSEvent.mouseLocation,
                          translation: value.translation)
      }
      .onEnded { _ in scene.dragEnded(commit: true) }
  }

  fileprivate static func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    var urls = [URL?](repeating: nil, count: providers.count)
    let lock = NSLock()
    let group = DispatchGroup()
    for (index, provider) in providers.enumerated() where provider.canLoadObject(ofClass: URL.self) {
      group.enter()
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        lock.lock()
        urls[index] = url
        lock.unlock()
        group.leave()
      }
    }
    group.notify(queue: .main) { completion(urls.compactMap { $0 }) }
  }

}

/// A tile and what clicking, dropping on, and right-clicking it do.
/// Equatable on what it draws, so the frames that only move a tile, most of
/// a magnification sweep, skip its body.
private struct DockTileView: View, Equatable {
  let tile: DockTile
  let face: TileFace
  let store: DockStore
  let actions: DockActions
  let dropTarget: Binding<String?>

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.tile == rhs.tile && lhs.face == rhs.face }

  var body: some View {
    face
      .contentShape(Rectangle())
      .onTapGesture { actions.activate(tile) }
      .onDrop(of: Self.dropTypes(for: tile), isTargeted: Binding(
        get: { dropTarget.wrappedValue == tile.id },
        set: { targeted in
          if targeted {
            dropTarget.wrappedValue = tile.id
          } else if dropTarget.wrappedValue == tile.id {
            dropTarget.wrappedValue = nil
          }
        })) { providers in
        DockView.loadURLs(providers) { urls in
          let files = urls.filter(\.isFileURL)
          if !files.isEmpty {
            store.drop(files, on: tile)
          } else if tile.item.kind == .shelf {
            Self.loadText(providers) { store.drop(text: $0, on: tile) }
          }
        }
        return true
      }
      .contextMenu { DockMenu(store: store, tile: tile, actions: actions) }
      .help(tile.name)
  }

  /// The shelf also takes text, such as a selection dragged from a browser.
  private static func dropTypes(for tile: DockTile) -> [UTType] {
    guard tile.acceptsDrops else { return [] }
    return tile.item.kind == .shelf ? [.fileURL, .utf8PlainText] : [.fileURL]
  }

  private static func loadText(_ providers: [NSItemProvider], completion: @escaping (String) -> Void) {
    guard let provider = providers.first(where: { $0.canLoadObject(ofClass: String.self) }) else { return }
    _ = provider.loadObject(ofClass: String.self) { text, _ in
      guard let text else { return }
      DispatchQueue.main.async { completion(text) }
    }
  }
}

/// A tile's picture, badge, and running dot.
private struct TileFace: View, Equatable {
  let image: TileImage
  let theme: DockTheme
  let size: CGSize
  let highlighted: Bool
  let dimmed: Bool
  let state: ActionRunner.State?
  let badge: String?
  let badgeColor: Color
  /// A green dot for a finished agent session; a badge takes its place.
  let finished: Bool
  let running: Bool
  let active: Bool
  let removing: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(highlighted ? theme.hover : .clear)
      TileIcon(image: image, theme: theme)
        .padding(DockLayout.inset)
        .opacity(dimmed ? 0.55 : 1)
      if let state {
        ActionStatus(state: state, theme: theme, side: size.width - DockLayout.inset * 2)
      }
    }
    .overlay(alignment: .topTrailing) {
      if let badge {
        TileBadge(text: badge, color: badgeColor, height: max(14, size.width * 0.3))
          .offset(x: 3, y: -3)
      } else if finished {
        Circle()
          .fill(theme.success)
          .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
          .frame(width: 10, height: 10)
          .offset(x: 2, y: -2)
      }
    }
    .frame(width: size.width, height: size.height)
    .overlay(alignment: .bottom) {
      Circle()
        .fill(active ? theme.accent : theme.label.opacity(0.55))
        .frame(width: 4, height: 4)
        .opacity(running ? 1 : 0)
        .offset(y: DockLayout.indicator - 1)
    }
    .overlay(alignment: .top) {
      if removing {
        Text("Remove")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Capsule().fill(Color.black.opacity(0.65)))
          .fixedSize()
          .offset(y: -24)
      }
    }
    .opacity(removing ? 0.6 : 1)
  }
}

/// A tile's right-click menu.
private struct DockMenu: View {
  @ObservedObject var store: DockStore
  let tile: DockTile
  let actions: DockActions

  var body: some View {
    if let error = store.configError {
      Text(error)
      Divider()
    }
    if tile.section != .trash, tile.item.kind == .app {
      AppMenu(store: store, tile: tile) {
        if case let entries = store.menuEntries(for: tile), !entries.isEmpty {
          MenuEntries(store: store, tile: tile, entries: entries)
          Divider()
        }
        Menu("Add to Group") {
          ForEach(store.groups.filter { $0.id != tile.parentGroup }) { group in
            Button(store.path(of: group)) { store.addToGroup(tile, group: group) }
          }
          if !store.groups.isEmpty { Divider() }
          Button(tile.parentGroup == nil ? "New Group…" : "New Subgroup…") { store.newGroup(with: tile) }
        }
      } options: {
        if let group = tile.parentGroup.flatMap(store.group(id:)) {
          Button("Remove from Group") { store.takeOut(tile, from: group) }
        } else if tile.section == .running {
          Button("Keep in Dock") { store.keepInDock(tile) }
        } else {
          Button("Remove from Dock") { store.remove(tile) }
        }
        Button("Show in Finder") { store.reveal(tile) }
        Divider()
        dockItems
      }
    } else {
      otherMenu
    }
  }

  @ViewBuilder private var dockItems: some View {
    if !store.hasControls { Button("Add Controls to Dock", action: store.addControls) }
    Button("Dock Settings…") { store.editConfig() }
    Button("Use macOS Dock", action: actions.useNativeDock)
  }

  @ViewBuilder private var otherMenu: some View {
    if case let entries = store.menuEntries(for: tile), !entries.isEmpty {
      MenuEntries(store: store, tile: tile, entries: entries)
      Divider()
    }
    switch (tile.section, tile.item.kind) {
    case (.trash, _):
      Button("Open") { store.open(tile) }
      Button("Empty Trash…") { store.emptyTrash() }
    case (_, .app):
      EmptyView()
    case (_, .group):
      Button("Open") { actions.activate(tile) }
      Button("Rename…") { store.rename(tile) }
      Button("Ungroup") { store.ungroup(tile) }
      Divider()
      Button("Remove from Dock") { store.remove(tile) }
    case (_, .folder), (_, .file):
      Button("Open") { store.open(tile) }
      Button("Show in Finder") { store.reveal(tile) }
      Divider()
      Button("Remove from Dock") { store.remove(tile) }
    case (_, .action):
      if store.actions.states[tile.id] == .running {
        Button("Stop") { store.actions.stop(tile.id) }
      } else if store.actions.states[tile.id] == .stopping {
        Button("Stopping…") {}.disabled(true)
      } else {
        Button("Run") { store.actions.run(tile, arguments: []) }
      }
      Button("Show Last Output") { store.actions.showOutput(tile.id) }
      Divider()
      Button("Remove from Dock") { store.remove(tile) }
    case (_, .url):
      Button("Open") { store.open(tile) }
      Divider()
      Button("Remove from Dock") { store.remove(tile) }
    case (_, .shelf):
      Button("Open Shelf") { actions.activate(tile) }
      if !store.shelf.entries.isEmpty { Button("Clear Shelf") { store.shelf.clear() } }
      Divider()
      Button("Remove from Dock") { store.remove(tile) }
    case (_, .controls):
      Button("Open Controls") { actions.activate(tile) }
      Button("System Settings…") {
        if let pane = SettingsPane.named("Settings") { NSWorkspace.shared.open(pane.url) }
      }
      Divider()
      Button("Remove from Dock") { store.remove(tile) }
    }
    Divider()
    dockItems
  }
}

/// A tile's `menu` entries; groups of entries become submenus. A running
/// entry offers Stop, and a failed one shows its output.
struct MenuEntries: View {
  @ObservedObject var store: DockStore
  let tile: DockTile
  let entries: [DockItem]

  var body: some View {
    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
      let title = entry.title ?? entry.command ?? ""
      if entry.kind == .group {
        Menu(title) { MenuEntries(store: store, tile: tile, entries: entry.items ?? []) }
      } else if let reason = entry.disabled, !reason.isEmpty {
        Button("\(title) (\(reason))") {}.disabled(true)
      } else if entry.command?.isEmpty == false {
        let id = store.menuID(entry, of: tile)
        switch store.actions.states[id] {
        case .running?:
          Button("Stop \(title)") { store.actions.stop(id) }
        case .stopping?:
          Button("Stopping \(title)…") {}.disabled(true)
        case .failed?:
          Button("\(title) Failed: Show Output") { store.runMenuEntry(entry, of: tile) }
        default:
          Button(title) { store.runMenuEntry(entry, of: tile) }
        }
      }
    }
  }
}

/// An app's menu in the native Dock's order, shared by dock tiles and group
/// callouts: its windows, then `custom` items and Barista's window controls,
/// then the `options` submenu, then Hide or Show
/// and Quit, which turns into Force Quit while Option is held. Window actions
/// go through Barista's `yabai_control.sh`, so they follow the same rules as
/// the bar's window menu.
struct AppMenu<Custom: View, Options: View>: View {
  @ObservedObject var store: DockStore
  let tile: DockTile
  @ViewBuilder let custom: Custom
  @ViewBuilder let options: Options

  var body: some View {
    let windows = store.windows(of: tile)
    ForEach(windows) { window in
      Button(window.title.isEmpty ? window.app : window.title) { store.focus(window) }
    }
    if !windows.isEmpty { Divider() }
    custom
    windowControls(windows)
    Divider()
    Menu("Options") { options }
    Divider()
    if tile.pid == nil {
      Button("Open") { store.open(tile) }
    } else if tile.isHidden {
      Button("Show") { store.unhide(tile) }
    } else {
      Button("Hide") { store.hide(tile) }
    }
    if tile.canQuit { QuitItem(store: store, tile: tile) }
  }

  @ViewBuilder private func windowControls(_ windows: [YabaiWindow]) -> some View {
    if !windows.isEmpty {
      if let window = store.primaryWindow(of: tile) {
        Menu("Window") {
          Toggle("Float", isOn: toggle(window.isFloating) { store.windowAction("window-toggle-float", on: window) })
          Toggle("Sticky", isOn: toggle(window.isSticky) { store.windowAction("window-toggle-sticky", on: window) })
          Toggle("Zoom to Fill", isOn: toggle(window.hasFullscreenZoom) {
            store.windowAction("window-toggle-fullscreen", on: window)
          })
          Divider()
          Button("Center") { store.windowAction("window-center", on: window) }
          Button("Utility Size") { store.windowAction("window-preset-utility", on: window) }
          Button("Tile Here") { store.windowAction("window-preset-tile-here", on: window) }
          Button("Next Display") { store.windowAction("window-display-next", on: window) }
          Divider()
          Button("Minimize") { store.windowAction("window-minimize", on: window) }
          Button("Close") { store.windowAction("window-close", on: window) }
        }
      }
      if !store.spaces.isEmpty {
        Menu("Move to Space") {
          ForEach(store.spaces) { space in
            Button(space.name + (space.hasFocus ? " (current)" : "")) { store.move(tile, toSpace: space.index) }
          }
        }
      }
      if let here = store.focusedSpace, windows.contains(where: { $0.space != here.index }) {
        Button("Gather Windows Here") { store.gatherWindows(tile) }
      }
    }
    if tile.pid != nil {
      let mode = store.windowDefault(tile)
      Menu("New Windows") {
        Toggle("Float", isOn: toggle(mode == "float") { store.setWindowDefault(tile, mode: "float") })
        Toggle("Tile", isOn: toggle(mode == "tile") { store.setWindowDefault(tile, mode: "tile") })
        Divider()
        Button("Follow yabai Rules") { store.setWindowDefault(tile, mode: "unset") }.disabled(mode == nil)
      }
      let level = store.windowLevel(tile)
      Menu("Window Level") {
        Toggle("Normal", isOn: toggle(level == "normal") { store.setWindowLevel(tile, level: "normal") })
        Toggle("Raised", isOn: toggle(level == "raised") { store.setWindowLevel(tile, level: "raised") })
        Toggle("Always on Top", isOn: toggle(level == "top") { store.setWindowLevel(tile, level: "top") })
        Divider()
        Button("Follow yabai Rules") { store.setWindowLevel(tile, level: "unset") }.disabled(level == nil)
      }
    }
  }

  /// A checkmark item showing `value`; choosing it runs `action`.
  private func toggle(_ value: Bool, _ action: @escaping () -> Void) -> Binding<Bool> {
    Binding(get: { value }, set: { _ in action() })
  }
}

/// Quit, or Force Quit while Option is held. Before macOS 15 menus cannot
/// swap items live, so Option is read when the menu opens.
private struct QuitItem: View {
  @ObservedObject var store: DockStore
  let tile: DockTile

  var body: some View {
    if #available(macOS 15.0, *) {
      Button("Quit") { store.quit(tile) }
        .modifierKeyAlternate(.option) { Button("Force Quit") { store.forceQuit(tile) } }
    } else if NSEvent.modifierFlags.contains(.option) {
      Button("Force Quit") { store.forceQuit(tile) }
    } else {
      Button("Quit") { store.quit(tile) }
    }
  }
}

/// Raises an element from below the screen edge as `rise` goes from 0 to 1.
private struct Rise: ViewModifier {
  let rise: CGFloat
  let opacity: Double
  let slide: CGFloat
  /// Scale at `rise` 0; tiles grow as they rise, the bar does not.
  let minScale: CGFloat

  func body(content: Content) -> some View {
    content
      .scaleEffect(minScale + (1 - minScale) * rise, anchor: .bottom)
      .offset(y: (1 - rise) * slide)
      .opacity(opacity)
  }
}
