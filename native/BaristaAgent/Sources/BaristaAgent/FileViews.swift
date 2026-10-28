import AppKit
import SwiftUI

/// The icon view: the shown rows as a grid, with Finder's clicks and arrows.
struct IconGrid: View {
  @ObservedObject var state: BrowserState
  private static let cell = CGSize(width: 96, height: 96)
  private static let spacing: CGFloat = 8

  var body: some View {
    GeometryReader { geometry in
      let columns = max(1, Int((geometry.size.width - Self.spacing) / (Self.cell.width + Self.spacing)))
      ScrollViewReader { proxy in
        ScrollView {
          LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cell.width), spacing: Self.spacing), count: columns),
                    spacing: Self.spacing) {
            ForEach(state.shown) { entry in
              IconCell(state: state, entry: entry, size: Self.cell).id(entry.url)
            }
          }
          .padding(Self.spacing)
          .frame(minHeight: geometry.size.height, alignment: .top)
          // Behind the icons: a click between them clears the selection.
          .background {
            Color.clear.contentShape(Rectangle())
              .onTapGesture { state.selection = [] }
              .contextMenu { EntryMenu(state: state, urls: []) }
          }
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: state.drop)
        .onChange(of: state.scrollTarget) { scroll(proxy) }
        .onAppear {
          state.gridColumns = columns
          scroll(proxy)
        }
        .onChange(of: columns) { state.gridColumns = columns }
      }
    }
  }

  private func scroll(_ proxy: ScrollViewProxy) {
    guard let target = state.scrollTarget else { return }
    DispatchQueue.main.async { proxy.scrollTo(target) }
  }
}

private struct IconCell: View {
  @ObservedObject var state: BrowserState
  let entry: FileEntry
  let size: CGSize

  var body: some View {
    let selected = state.selection.contains(entry.url)
    VStack(spacing: 4) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
        .resizable().frame(width: 52, height: 52)
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
      if state.renaming == entry.url {
        RenameField(state: state, entry: entry).multilineTextAlignment(.center).font(.caption)
      } else {
        Text(entry.name)
          .font(.caption).lineLimit(2).truncationMode(.middle).multilineTextAlignment(.center)
          .padding(.horizontal, 4).padding(.vertical, 1)
          .foregroundStyle(selected ? Color.white : Color.primary)
          .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 4))
      }
    }
    .padding(4)
    .frame(width: size.width, height: size.height, alignment: .top)
    .background(selected ? Color.primary.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
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
                    rename: state.renaming == entry.url ? RenameField(state: state, entry: entry) : nil)
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
        let listing = await Task.detached(priority: .userInitiated) { FileListing.load(folder, hidden: hidden) }.value
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
      Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 16, height: 16)
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
