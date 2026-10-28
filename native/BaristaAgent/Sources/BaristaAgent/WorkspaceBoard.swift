import QuickLookThumbnailing
import SwiftUI

/// A workspace as halext-org lays one out: tasks by state, then notes and
/// ideas. Typing above captures into the shelf that's shown.
struct WorkspaceBoard: View {
  @ObservedObject var state: BrowserState
  let workspace: Workspace
  @State private var shelf = Workspace.Shelf.tasks
  @State private var draft = ""

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      switch shelf {
      case .tasks: TaskColumns(state: state, workspace: workspace)
      case .notes: NoteList(state: state, pages: workspace.notes)
      case .ideas: IdeaGrid(state: state, pages: workspace.ideas)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Picker("Shelf", selection: $shelf) {
        ForEach(Workspace.Shelf.allCases) { shelf in Text("\(shelf.title) \(count(shelf))").tag(shelf) }
      }
      .pickerStyle(.segmented).labelsHidden().fixedSize()
      TextField(placeholder, text: $draft)
        .textFieldStyle(.roundedBorder)
        .onSubmit(capture)
      Button(action: capture) { Image(systemName: "plus") }
        .buttonStyle(.borderless)
        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        .help(shelf == .tasks ? "Add to \(workspace.tasksFile.lastPathComponent)" : "Start the page in \(shelf.rawValue)")
    }
    .padding(8)
  }

  private var placeholder: String {
    switch shelf {
    case .tasks: return workspace.org ? "New task  (:tag: or #tag)" : "New task  (#tag due:2026-11-01)"
    case .notes: return "New note title"
    case .ideas: return "New idea title"
    }
  }

  private func count(_ shelf: Workspace.Shelf) -> Int {
    switch shelf {
    case .tasks: return workspace.tasks.filter { $0.state != .done }.count
    case .notes: return workspace.notes.count
    case .ideas: return workspace.ideas.count
    }
  }

  private func capture() {
    let text = draft.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    draft = ""
    if shelf == .tasks {
      state.capture(task: text)
    } else {
      state.capture(page: text, in: shelf)
    }
  }
}

private struct TaskColumns: View {
  @ObservedObject var state: BrowserState
  let workspace: Workspace
  /// Done tasks pile up; the newest (last in their files) show.
  private static let doneLimit = 50

  /// Four columns share the width down to this; a narrower board scrolls.
  private static let minimumWidth: CGFloat = 160

  var body: some View {
    GeometryReader { geometry in
      let count = CGFloat(TaskState.allCases.count)
      let width = max(Self.minimumWidth, (geometry.size.width - 8 * (count + 1)) / count)
      ScrollView(.horizontal) {
        columns(width: width).frame(height: geometry.size.height - 16)
      }
    }
  }

  private func columns(width: CGFloat) -> some View {
    HStack(alignment: .top, spacing: 8) {
      ForEach(TaskState.allCases) { column in
        let members = workspace.tasks.filter { $0.state == column }
        let shown = column == .done ? Array(members.suffix(Self.doneLimit).reversed()) : members
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            Text(column.title).font(.headline)
            Text("\(members.count)").foregroundStyle(.secondary)
          }
          ScrollView {
            LazyVStack(spacing: 6) {
              ForEach(shown) { task in TaskCard(state: state, task: task, tasksFile: workspace.tasksFile) }
              if members.count > shown.count {
                Text("\(members.count - shown.count) older").font(.caption).foregroundStyle(.secondary)
              }
            }
          }
        }
        .padding(8)
        .frame(width: width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .dropDestination(for: String.self) { ids, _ in
          let moved = workspace.tasks.filter { ids.contains($0.id) }
          state.move(moved, to: column)
          return !moved.isEmpty
        }
      }
    }
    .padding(8)
  }
}

private struct TaskCard: View {
  @ObservedObject var state: BrowserState
  let task: WorkspaceTask
  let tasksFile: URL

  private static let today: String = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
  }()

  var body: some View {
    let picked = state.picked?.url == task.file && state.picked?.line == task.line + 1
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        if let priority = task.priority {
          Text(priority).font(.caption.bold()).foregroundStyle(priority == "A" ? .red : .orange)
        }
        Text(task.title).lineLimit(3)
          .foregroundStyle(task.state == .done ? .secondary : .primary)
      }
      HStack(spacing: 4) {
        if let keyword = task.keyword { Text(keyword).font(.caption2.bold()).foregroundStyle(.secondary) }
        if let due = task.due {
          Text("due \(due)").font(.caption).fixedSize()
            .foregroundStyle(task.state != .done && due < Self.today ? Color.red : Color.secondary)
        }
        Text(origin).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
      }
      if !task.tags.isEmpty {
        HStack(spacing: 4) {
          ForEach(task.tags, id: \.self) { tag in
            Text(tag).font(.caption2)
              .padding(.horizontal, 5).padding(.vertical, 1)
              .background(Capsule().fill(Color.accentColor.opacity(0.15)))
          }
        }
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 6)
      .fill(picked ? Color.accentColor.opacity(0.22) : Color(nsColor: .controlBackgroundColor)))
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { Editor.edit(task.file, line: task.line + 1) }
    .simultaneousGesture(TapGesture().onEnded { state.pick(task.file, line: task.line + 1) })
    .draggable(task.id)
    .help("Drag to another column, or double-click to edit line \(task.line + 1) of \(task.file.lastPathComponent)")
    .contextMenu {
      ForEach(TaskState.allCases.filter { $0 != task.state }) { target in
        Button("Move to \(target.title)") { state.move([task], to: target) }
      }
      Divider()
      Button("Edit in Editor") { Editor.edit(task.file, line: task.line + 1) }
      Button("Show in Folder") {
        state.showBoard = false
        state.go(to: task.file.deletingLastPathComponent(), selecting: task.file)
      }
      Button("Copy Title") { copyText(task.title) }
    }
  }

  /// The heading it's under, and its file when that isn't the tasks file.
  private var origin: String {
    [task.section, task.file == tasksFile ? nil : task.file.lastPathComponent].compactMap { $0 }.joined(separator: " · ")
  }
}

private struct NoteList: View {
  @ObservedObject var state: BrowserState
  let pages: [WorkspacePage]

  var body: some View {
    if pages.isEmpty {
      Text("No notes yet. Type a title above to start one.").foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      List(pages, selection: Binding(get: { state.picked?.url }, set: { $0.map { state.pick($0) } })) { page in
        VStack(alignment: .leading, spacing: 2) {
          HStack {
            Text(page.title).fontWeight(.medium).lineLimit(1)
            Spacer()
            Text(page.modified, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
          }
          if let excerpt = page.excerpt { Text(excerpt).foregroundStyle(.secondary).lineLimit(2) }
          if !page.tags.isEmpty { Text(page.tags.map { "#\($0)" }.joined(separator: " ")).font(.caption) }
        }
        .padding(.vertical, 2)
      }
      .contextMenu(forSelectionType: URL.self) { urls in
        PageMenu(state: state, urls: urls)
      } primaryAction: { urls in
        urls.forEach { Editor.edit($0) }
      }
    }
  }
}

private struct IdeaGrid: View {
  @ObservedObject var state: BrowserState
  let pages: [WorkspacePage]

  var body: some View {
    if pages.isEmpty {
      Text("No ideas yet. Type a title above, or drop sketches and images into ideas.").foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
          ForEach(pages) { page in IdeaCard(state: state, page: page) }
        }
        .padding(10)
      }
    }
  }
}

private struct IdeaCard: View {
  @ObservedObject var state: BrowserState
  let page: WorkspacePage

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if page.isImage {
        Thumbnail(url: page.url).frame(height: 110).frame(maxWidth: .infinity).clipped()
          .clipShape(RoundedRectangle(cornerRadius: 4))
      }
      Text(page.title).fontWeight(.medium).lineLimit(2)
      if let excerpt = page.excerpt { Text(excerpt).font(.callout).foregroundStyle(.secondary).lineLimit(4) }
      if !page.tags.isEmpty { Text(page.tags.map { "#\($0)" }.joined(separator: " ")).font(.caption) }
    }
    .padding(8)
    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 8)
      .fill(state.picked?.url == page.url ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06)))
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { open() }
    .simultaneousGesture(TapGesture().onEnded { state.pick(page.url) })
    .contextMenu { PageMenu(state: state, urls: [page.url]) }
  }

  private func open() {
    if page.isImage { PopoverController.open(page.url) } else { Editor.edit(page.url) }
  }
}

private struct PageMenu: View {
  @ObservedObject var state: BrowserState
  let urls: Set<URL>

  var body: some View {
    let sorted = urls.sorted { $0.path < $1.path }
    Button("Edit in Editor") { sorted.forEach { Editor.edit($0) } }
    Button("Open") { sorted.forEach(PopoverController.open) }
    Divider()
    if let first = sorted.first {
      Button("Show in Folder") {
        state.showBoard = false
        state.go(to: first.deletingLastPathComponent(), selecting: first)
      }
    }
    Button("Copy Path") { copyText(sorted.map(\.path).joined(separator: "\n")) }
  }
}

private struct Thumbnail: View {
  let url: URL
  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().scaledToFill()
      } else {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(24)
      }
    }
    .task(id: url) {
      let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 340, height: 220), scale: 2,
                                                 representationTypes: .thumbnail)
      image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
  }
}
