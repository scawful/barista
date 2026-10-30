import AppKit
import SwiftUI

/// Where the icon view puts each icon: rows of cells that share the width
/// inside a fixed margin, so a cell's frame follows from its index whether
/// or not the lazy grid has drawn it. The space around and between icons,
/// and the names' type, grow with the icons.
struct IconLayout: Equatable {
  /// Between the view's edge and the cells, and above the first row.
  static let margin: CGFloat = 8
  let icon: CGFloat
  /// Between cells.
  let spacing: CGFloat
  /// Around the icon, inside its cell.
  let inset: CGFloat
  /// Between the icon and its name.
  let gap: CGFloat
  /// Finder's 10 points for small icons, a point or three more for large ones.
  let fontSize: CGFloat
  let cell: CGSize
  let columns: Int
  /// The block's left edge.
  let left: CGFloat

  /// Room for two lines of name under the icon, and no narrower than a
  /// short name needs at the smallest size; what's left of the width
  /// widens the cells rather than the margins.
  init(width: CGFloat, iconSize: Double) {
    let icon = CGFloat(iconSize)
    self.icon = icon
    spacing = min(16, max(4, (icon * 0.06).rounded()))
    inset = min(12, max(3, (icon * 0.05).rounded()))
    gap = min(8, max(2, (icon * 0.03).rounded()))
    fontSize = icon < 80 ? 10 : icon < 160 ? 11 : icon < 320 ? 12 : 13
    let line = (fontSize * 1.25).rounded(.up)
    let least = max(72, icon + 2 * inset + 8)
    let columns = max(1, Int((width - 2 * Self.margin + spacing) / (least + spacing)))
    let share = ((width - 2 * Self.margin - CGFloat(columns - 1) * spacing) / CGFloat(columns)).rounded(.down)
    cell = CGSize(width: max(least, share), height: icon + 2 * inset + gap + 2 * line + 2)
    self.columns = columns
    left = max(0, (width - (CGFloat(columns) * cell.width + CGFloat(columns - 1) * spacing)) / 2)
  }

  var blockWidth: CGFloat { CGFloat(columns) * cell.width + CGFloat(columns - 1) * spacing }

  func frame(at index: Int) -> CGRect {
    CGRect(x: left + CGFloat(index % columns) * (cell.width + spacing),
           y: Self.margin + CGFloat(index / columns) * (cell.height + spacing),
           width: cell.width, height: cell.height)
  }

  /// The icons a dragged rectangle touches, of `count`.
  func indices(in rect: CGRect, count: Int) -> [Int] {
    let stride = cell.height + spacing
    let first = max(0, Int((rect.minY - Self.margin) / stride))
    let last = min((count - 1) / columns, Int((rect.maxY - Self.margin) / stride))
    guard count > 0, first <= last else { return [] }
    return (first * columns..<min(count, (last + 1) * columns)).filter { frame(at: $0).intersects(rect) }
  }

  /// The next row out of sight above or below the visible `top..<top+height`,
  /// for a drag held past that edge; nil at the first or last row.
  func rowToReveal(top: CGFloat, height: CGFloat, down: Bool, count: Int) -> Int? {
    guard count > 0 else { return nil }
    let stride = cell.height + spacing
    if down {
      let bottom = top + height
      var row = max(0, Int((bottom - Self.margin) / stride))
      if Self.margin + CGFloat(row) * stride + cell.height <= bottom + 1 { row += 1 }
      return row <= (count - 1) / columns ? row : nil
    }
    var row = max(0, Int((top - Self.margin) / stride))
    if Self.margin + CGFloat(row) * stride >= top - 1 { row -= 1 }
    return row >= 0 ? row : nil
  }
}

/// How far the icon view is scrolled, and where a marquee drag is, read by
/// the auto-scroll timer between drag events without redrawing the grid.
private final class MarqueeTrack {
  var top: CGFloat = 0
  var start: CGPoint = .zero
  /// In the visible area's coordinates, so it stays put while the grid scrolls.
  var pointer: CGPoint = .zero
}

private struct ScrollTopKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The icon view: the shown rows as a grid, with Finder's clicks and arrows,
/// and a rectangle dragged across empty space to select.
struct IconGrid: View {
  @ObservedObject var state: BrowserState
  @State private var pinchStart: Double?
  @State private var marquee: CGRect?
  /// What stays selected under a drag: the selection before it, with ⇧ or ⌘.
  @State private var marqueeKeeps: Set<URL> = []
  @State private var track = MarqueeTrack()
  /// Scrolls a row at a time while a marquee is held past the top or bottom.
  @State private var autoscroll: Timer?

  var body: some View {
    GeometryReader { geometry in
      let layout = IconLayout(width: geometry.size.width, iconSize: state.iconSize)
      let columns = layout.columns
      ScrollViewReader { proxy in
        ScrollView {
          LazyVGrid(columns: Array(repeating: GridItem(.fixed(layout.cell.width), spacing: layout.spacing),
                                   count: columns),
                    spacing: layout.spacing) {
            ForEach(state.shown) { entry in
              IconCell(state: state, entry: entry, layout: layout).id(entry.url)
            }
          }
          .frame(width: layout.blockWidth)
          .padding(.vertical, IconLayout.margin)
          .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
          // Behind the icons: a click between them clears the selection,
          // a drag selects what it covers.
          .background {
            Color.clear.contentShape(Rectangle())
              .onTapGesture { state.selection = [] }
              .gesture(select(in: layout, height: geometry.size.height, proxy: proxy))
              .contextMenu { EntryMenu(state: state, urls: []) }
          }
          .background(GeometryReader { content in
            Color.clear.preference(key: ScrollTopKey.self, value: -content.frame(in: .named(Self.space)).minY)
          })
          .overlay(alignment: .topLeading) {
            if let marquee {
              Rectangle().fill(Color.accentColor.opacity(0.15))
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.7)))
                .frame(width: marquee.width, height: marquee.height)
                .offset(x: marquee.minX, y: marquee.minY)
                .allowsHitTesting(false)
            }
          }
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(ScrollTopKey.self) { [track] top in track.top = top }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: state.drop)
        .simultaneousGesture(pinch)
        .onChange(of: state.scrollTarget) { scroll(proxy) }
        .onAppear {
          state.gridColumns = columns
          scroll(proxy)
        }
        .onChange(of: columns) { state.gridColumns = columns }
      }
    }
  }

  private static let space = "IconGrid"

  private func select(in layout: IconLayout, height: CGFloat, proxy: ScrollViewProxy) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        if marquee == nil {
          let adds = !NSEvent.modifierFlags.intersection([.shift, .command]).isEmpty
          marqueeKeeps = adds ? state.selection : []
        }
        track.start = value.startLocation
        track.pointer = CGPoint(x: value.location.x, y: value.location.y - track.top)
        drawMarquee(layout)
        let edge = min(24, height / 4)
        if track.pointer.y < edge || track.pointer.y > height - edge {
          guard autoscroll == nil else { return }
          autoscroll = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            drawMarquee(layout)
            let down = track.pointer.y > height / 2
            guard let row = layout.rowToReveal(top: track.top, height: height, down: down, count: state.shown.count)
            else { return }
            proxy.scrollTo(state.shown[row * layout.columns].url, anchor: down ? .bottom : .top)
          }
        } else {
          stopAutoscroll()
        }
      }
      .onEnded { _ in
        stopAutoscroll()
        marquee = nil
      }
  }

  private func stopAutoscroll() {
    autoscroll?.invalidate()
    autoscroll = nil
  }

  /// The rectangle from where the drag began to the pointer, in the grid's
  /// coordinates, and the icons it touches selected.
  private func drawMarquee(_ layout: IconLayout) {
    let start = track.start
    let end = CGPoint(x: track.pointer.x, y: max(0, track.pointer.y + track.top))
    let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                      width: abs(end.x - start.x), height: abs(end.y - start.y))
    if rect != marquee { marquee = rect }
    let shown = state.shown
    let covered = layout.indices(in: rect, count: shown.count).map { shown[$0].url }
    let selection = marqueeKeeps.union(covered)
    if selection != state.selection { state.selection = selection }
  }

  /// Pinching scales the icons from their size when the pinch began.
  private var pinch: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        let start = pinchStart ?? state.iconSize
        pinchStart = start
        let size = FolderView.iconSize(start * value.magnification)
        if size != state.iconSize { state.iconSize = size }
      }
      .onEnded { _ in pinchStart = nil }
  }

  private func scroll(_ proxy: ScrollViewProxy) {
    guard let target = state.scrollTarget else { return }
    DispatchQueue.main.async { proxy.scrollTo(target) }
  }
}

private struct IconCell: View {
  @ObservedObject var state: BrowserState
  let entry: FileEntry
  let layout: IconLayout

  var body: some View {
    let selected = state.selection.contains(entry.url)
    VStack(spacing: layout.gap) {
      FileIcon(url: entry.url, points: layout.icon, modified: entry.modified)
        .overlay(alignment: .bottomTrailing) {
          if let mark = state.git?.mark(for: entry.url, isFolder: entry.isFolder) {
            Text(mark.letter)
              .font(.caption2.monospaced().weight(.bold))
              .foregroundStyle(mark.color)
              .padding(.horizontal, 3)
              .background(.background, in: RoundedRectangle(cornerRadius: 3))
              .help(mark.help)
          }
        }
        // Finder's highlight: around the icon, with the name's own below.
        .padding(layout.inset)
        .background(selected ? Color.primary.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: layout.inset + 3))
      let font = Font.system(size: layout.fontSize)
      if state.isRenaming(entry.url) {
        RenameField(state: state, entry: entry).multilineTextAlignment(.center).font(font)
      } else {
        Text(entry.name)
          .font(font).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center)
          .padding(.horizontal, 4).padding(.vertical, 1)
          .foregroundStyle(selected ? Color.white : Color.primary)
          .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
      }
    }
    .frame(width: layout.cell.width, height: layout.cell.height, alignment: .top)
    .contentShape(Rectangle())
    .help(entry.match.map { match in entry.line.map { "\(entry.name), line \($0): \(match)" } ?? match } ?? entry.name)
    // Simultaneous, so a single click selects at once instead of waiting
    // to see whether a second click follows.
    .onTapGesture(count: 2) {
      state.selection = [entry.url]
      state.openSelection()
    }
    .simultaneousGesture(TapGesture().onEnded { state.click(entry.url, modifiers: NSEvent.modifierFlags) })
    .onDrag { NSItemProvider(object: entry.url as NSURL) }
    // A right-click on an unselected icon acts on that icon alone, as in Finder.
    .contextMenu { EntryMenu(state: state, urls: selected ? state.selection : [entry.url]) }
  }
}

/// The column view. The shown folder is the live column, so search, file
/// operations, git, and the context panel work as in the list; the folders
/// above it are columns to its left, and a selected folder's contents a
/// column to its right. Clicking in any of those makes it the live one.
struct ColumnBrowser: View {
  @ObservedObject var state: BrowserState
  static let width: CGFloat = 220

  var body: some View {
    let ancestors = BrowserLayout.columnFolders(for: state.location,
                                                home: FileManager.default.homeDirectoryForCurrentUser)
    let preview = state.selectedFolder
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        HStack(spacing: 0) {
          ForEach(Array(ancestors.enumerated()), id: \.element) { index, folder in
            let chosen = index + 1 < ancestors.count ? ancestors[index + 1] : state.location
            FolderColumn(state: state, folder: folder, chosen: chosen) { entry in
              if entry.isFolder { state.go(to: entry.url) } else { state.go(to: folder, selecting: entry.url) }
            }
            Divider()
          }
          LiveColumn(state: state).frame(width: Self.width).id("live")
          if let preview {
            Divider()
            FolderColumn(state: state, folder: preview, chosen: nil) { entry in
              state.go(to: preview, selecting: entry.url)
            }
            .id("preview")
          }
        }
      }
      .onChange(of: state.location) { reveal(proxy) }
      .onChange(of: preview) { reveal(proxy) }
      .onAppear { reveal(proxy) }
    }
  }

  /// Keeps the live column, and a preview beside it, in view.
  private func reveal(_ proxy: ScrollViewProxy) {
    let target = state.selectedFolder == nil ? "live" : "preview"
    DispatchQueue.main.async { proxy.scrollTo(target, anchor: .trailing) }
  }
}

/// The shown folder's rows as a native list: its selection, arrows, ⌘- and
/// ⇧-clicks, and double-click are the table's.
private struct LiveColumn: View {
  @ObservedObject var state: BrowserState
  @FocusState private var focused: Bool

  var body: some View {
    ScrollViewReader { proxy in
      List(selection: $state.selection) {
        ForEach(state.shown) { entry in
          ColumnRow(entry: entry, mark: state.git?.mark(for: entry.url, isFolder: entry.isFolder),
                    rename: state.isRenaming(entry.url) ? RenameField(state: state, entry: entry) : nil)
          .tag(entry.url)
          .itemProvider { NSItemProvider(object: entry.url as NSURL) }
        }
      }
      .listStyle(.plain)
      .focused($focused)
      .contextMenu(forSelectionType: URL.self) { urls in
        EntryMenu(state: state, urls: urls)
      } primaryAction: { urls in
        state.selection = urls
        state.openSelection()
      }
      .onDrop(of: [.fileURL], isTargeted: nil, perform: state.drop)
      .onAppear { focused = true }
      .onChange(of: state.focusList) { focused = true }
      // A click in a side column moves the live column; the keys follow it.
      .onChange(of: state.location) { focused = true }
      .onChange(of: state.scrollTarget) {
        guard let target = state.scrollTarget else { return }
        DispatchQueue.main.async { proxy.scrollTo(target, anchor: .center) }
      }
    }
  }
}

/// A folder beside the live column, read on its own. The row on the path to
/// the live column is marked; clicking a row hands it to `pick`.
private struct FolderColumn: View {
  @ObservedObject var state: BrowserState
  let folder: URL
  let chosen: URL?
  let pick: (FileEntry) -> Void
  @State private var entries: [FileEntry]?

  var body: some View {
    ScrollViewReader { proxy in
      List {
        ForEach(entries ?? []) { entry in
          ColumnRow(entry: entry, mark: state.git?.mark(for: entry.url, isFolder: entry.isFolder))
            .listRowBackground(entry.url.path == chosen?.path
                               ? RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.12)) : nil)
            .contentShape(Rectangle())
            .onTapGesture { pick(entry) }
            .id(entry.url.path)
        }
      }
      .listStyle(.plain)
      .overlay {
        if entries?.isEmpty == true { Text("Empty").foregroundStyle(.tertiary) }
      }
      .task(id: "\(folder.path)\0\(state.hidden)\0\(state.sortKey)\0\(state.ascending)") {
        let (folder, hidden) = (folder, state.hidden)
        if let cached = ListingCache.shared.entries(for: folder, hidden: hidden) {
          entries = FileListing.sorted(cached, by: state.sortKey, ascending: state.ascending)
        }
        let listing = await Task.detached(priority: .userInitiated) { FileListing.load(folder, hidden: hidden) }.value
        if let listing { ListingCache.shared.store(listing, for: folder, hidden: hidden) }
        entries = FileListing.sorted(listing ?? [], by: state.sortKey, ascending: state.ascending)
        if let chosen { DispatchQueue.main.async { proxy.scrollTo(chosen.path, anchor: .center) } }
      }
    }
    .frame(width: ColumnBrowser.width)
  }
}

/// A row in a column: icon, name, git mark, and a chevron on folders.
private struct ColumnRow: View {
  let entry: FileEntry
  let mark: GitMark?
  var rename: RenameField?

  var body: some View {
    HStack(spacing: 6) {
      FileIcon(url: entry.url, points: 16, modified: entry.modified)
      if let rename {
        rename
      } else {
        Text(entry.name).lineLimit(1).truncationMode(.middle)
      }
      Spacer(minLength: 4)
      if let mark {
        Text(mark.letter).font(.caption.monospaced().weight(.bold)).foregroundStyle(mark.color).help(mark.help)
      }
      if entry.isFolder { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
    }
  }
}
