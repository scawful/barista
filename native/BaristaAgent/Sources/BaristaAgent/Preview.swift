import AppKit
import SwiftUI

/// What the browser's preview pane shows for a file.
enum PreviewContent: Equatable {
  /// Markdown, and org translated to Markdown.
  case document([MarkdownBlock])
  /// Code and other text; minified JSON is indented. `note` says what was
  /// changed or cut; `spans` color code the preview knows.
  case text(String, note: String?, spans: [SyntaxSpan] = [])
  case rom(SNESHeader)
  /// Read here, off the main thread; drawing it in the view would read the
  /// file again on every update.
  case image(NSImage)
  case details
}

enum Preview {
  static let textLimit = 256 * 1024
  static let documentLimit = 200_000
  static let jsonLimit = 4 * 1024 * 1024
  static let romLimit = 16 * 1024 * 1024

  /// Blocking; call it off the main thread.
  static func load(_ url: URL) -> PreviewContent {
    let ext = url.pathExtension.lowercased()
    switch ViewerKind.of(url) {
    case .markdown?: return .document(Markdown.parse(read(url, limit: documentLimit)))
    case .image?: return NSImage(contentsOf: url).map { .image($0) } ?? .details
    case nil: break
    }
    if ext == "org" { return .document(Markdown.parse(Org.markdown(read(url, limit: documentLimit)))) }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    if ["sfc", "smc"].contains(ext), size <= romLimit,
       let data = try? Data(contentsOf: url), let header = SNESHeader.parse(data) {
      return .rom(header)
    }
    guard let head = head(url, limit: textLimit), let text = decodeText(head), !text.isEmpty else { return .details }
    let syntax = Syntax.of(url)
    func code(_ text: String, note: String?) -> PreviewContent {
      .text(text, note: note, spans: syntax?.spans(text) ?? [])
    }
    if ext == "json", size <= jsonLimit, let whole = try? Data(contentsOf: url) {
      do {
        let object = try JSONSerialization.jsonObject(with: whole, options: .fragmentsAllowed)
        // Files written by hand or by tools that indent stay as they are.
        if !text.prefix(4096).contains("\n"),
           let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes,
                                                              .fragmentsAllowed]),
           let indented = String(data: pretty, encoding: .utf8) {
          return code(String(indented.prefix(textLimit)), note: "Minified JSON, shown indented with keys sorted")
        }
      } catch {
        let reason = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
        return code(text, note: "Not valid JSON: \(reason)")
      }
    }
    let cut = size > head.count
      ? "Showing the first \(byteCount(head.count)) of \(byteCount(size))" : nil
    return code(text, note: cut)
  }

  /// Text, or nil for binary: a NUL early on, or bytes that aren't UTF-8.
  static func decodeText(_ data: Data) -> String? {
    guard !data.prefix(8192).contains(0) else { return nil }
    // A cut can land inside a multi-byte character.
    for trim in 0...min(3, data.count) {
      if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
    }
    return nil
  }

  private static func head(_ url: URL, limit: Int) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    return try? handle.read(upToCount: limit) ?? Data()
  }

  private static func read(_ url: URL, limit: Int) -> String {
    head(url, limit: limit).flatMap(decodeText) ?? ""
  }

  static func byteCount(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
  }

  /// Line `line` (1-based, as rg counts) of `text`, without its line break;
  /// nil past the end, which a cut preview can be.
  static func range(ofLine line: Int, in text: String) -> NSRange? {
    let text = text as NSString
    var current = 1
    var found: NSRange?
    text.enumerateSubstrings(in: NSRange(location: 0, length: text.length),
                             options: [.byLines, .substringNotRequired]) { _, range, _, stop in
      if current == line {
        found = range
        stop.pointee = true
      }
      current += 1
    }
    return found
  }
}

/// Org as Markdown, close enough to read notes: headings, lists, source and
/// example blocks, quotes, tables, links, bold, and verbatim. Drawers, comments,
/// and `#+` settings other than the title are left out.
enum Org {
  static func markdown(_ source: String) -> String {
    var out: [String] = []
    var fenceEnd: String?
    var quoting = false
    var inDrawer = false
    var tableColumns = 0
    var tableHasDelimiter = false
    for raw in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
      let trimmed = raw.trimmingCharacters(in: .whitespaces)
      let lower = trimmed.lowercased()
      if let end = fenceEnd {
        if lower.hasPrefix(end) {
          out.append("```")
          fenceEnd = nil
        } else {
          out.append(raw)
        }
        continue
      }
      if inDrawer {
        if lower == ":end:" { inDrawer = false }
        continue
      }
      if !trimmed.hasPrefix("|") {
        tableColumns = 0
        tableHasDelimiter = false
      }
      if lower.hasPrefix("#+begin_src") || lower.hasPrefix("#+begin_example") {
        let isSource = lower.hasPrefix("#+begin_src")
        let words = trimmed.split(separator: " ")
        out.append("```" + (isSource && words.count > 1 ? String(words[1]) : ""))
        fenceEnd = isSource ? "#+end_src" : "#+end_example"
        continue
      }
      if lower.hasPrefix("#+begin_quote") { quoting = true; continue }
      if lower.hasPrefix("#+end_quote") { quoting = false; out.append(""); continue }
      if lower.hasPrefix("#+title:") {
        out.append("# " + inline(String(trimmed.dropFirst("#+title:".count)).trimmingCharacters(in: .whitespaces)))
        continue
      }
      if trimmed.hasPrefix("#+") || trimmed == "#" || trimmed.hasPrefix("# ") { continue }
      if lower != ":end:", trimmed.range(of: #"^:[A-Za-z_-]+:$"#, options: .regularExpression) != nil {
        inDrawer = true
        continue
      }
      let line: String
      if let match = raw.range(of: #"^\*+ "#, options: .regularExpression) {
        let level = raw.distance(from: match.lowerBound, to: match.upperBound) - 1
        let title = String(raw[match.upperBound...])
          .replacingOccurrences(of: #"\s+:[\w@#%:]+:\s*$"#, with: "", options: .regularExpression)
        line = String(repeating: "#", count: min(level, 6)) + " " + inline(title)
      } else if trimmed.hasPrefix("|") {
        if trimmed.hasPrefix("|-") {
          // Only the rule under the first row is a header delimiter; borders drop.
          guard tableColumns > 0, !tableHasDelimiter else { continue }
          tableHasDelimiter = true
          line = "|" + String(repeating: "---|", count: tableColumns)
        } else {
          if tableColumns == 0 { tableColumns = max(trimmed.split(separator: "|").count, 1) }
          line = inline(trimmed)
        }
      } else {
        line = inline(raw)
      }
      out.append(quoting ? "> " + line : line)
    }
    if fenceEnd != nil { out.append("```") }
    return out.joined(separator: "\n")
  }

  /// Links to headings in the same file (`[[*Heading]]`, `[[#id]]`, or a bare
  /// `[[Heading]]`) become their text; the preview has nowhere to jump.
  private static let rules: [(NSRegularExpression, String)] = [
    (#"\[\[[*#][^\]]+\]\[([^\]]+)\]\]"#, "$1"),
    (#"\[\[(?:file:)?([^\]]+)\]\[([^\]]+)\]\]"#, "[$2](<$1>)"),
    (#"\[\[[*#]?([^\]/.:]+)\]\]"#, "$1"),
    (#"\[\[(?:file:)?([^\]]+)\]\]"#, "[$1](<$1>)"),
    (#"(^|[\s(])[=~]([^\s=~](?:[^=~]*[^\s=~])?)[=~](?=$|[\s.,;:!?)])"#, "$1`$2`"),
    (#"(^|[\s(])\*([^\s*](?:[^*]*[^\s*])?)\*(?=$|[\s.,;:!?)])"#, "$1**$2**"),
  ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

  static func inline(_ text: String) -> String {
    rules.reduce(text) { text, rule in
      rule.0.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: rule.1)
    }
  }
}

/// The internal header of a SNES ROM, found the way emulators find it.
struct SNESHeader: Equatable {
  var title: String
  var mapping: String
  var fastROM: Bool
  /// From the header's size byte; nil when it is out of range.
  var romKB: Int?
  var sramKB: Int
  var region: String
  var version: Int
  var checksum: UInt16
  var complement: UInt16
  /// Nil when the size has no standard mirroring to sum over.
  var computed: UInt16?
  var copierHeader: Bool
  var fileSize: Int

  var complementMatches: Bool { checksum ^ complement == 0xFFFF }

  private static let regions = ["Japan", "North America", "Europe", "Scandinavia", "Finland", "Denmark", "France",
                                "Netherlands", "Spain", "Germany", "Italy", "China", "Indonesia", "Korea"]

  /// Scores each place a header can be (LoROM, HiROM, ExHiROM): a checksum
  /// that matches its complement, a map mode that agrees, a printable title.
  /// Nil when no place scores 3, so other files with this extension don't pass.
  static func parse(_ file: Data) -> SNESHeader? {
    let copier = file.count % 1024 == 512 ? 512 : 0
    let rom = Data(file.dropFirst(copier))
    var best: (score: Int, header: SNESHeader)?
    for (mapping, offset, modes) in [("LoROM", 0x7FC0, [0, 2, 3]), ("HiROM", 0xFFC0, [1]), ("ExHiROM", 0x40FFC0, [5])]
    where offset + 32 <= rom.count {
      let bytes = [UInt8](rom[offset..<offset + 32])
      let mode = bytes[21]
      let complement = UInt16(bytes[28]) | UInt16(bytes[29]) << 8
      let checksum = UInt16(bytes[30]) | UInt16(bytes[31]) << 8
      let titleBytes = bytes[0..<21]
      var score = 0
      if checksum ^ complement == 0xFFFF { score += 4 }
      if modes.contains(Int(mode & 0x0F)) && mode & 0xE0 == 0x20 { score += 2 }
      if titleBytes.allSatisfy({ (0x20...0x7E).contains($0) }) { score += 1 }
      guard score >= 3, score > best?.score ?? -1 else { continue }
      let title = String(decoding: titleBytes.map { (0x20...0x7E).contains($0) ? $0 : 0x20 }, as: UTF8.self)
        .trimmingCharacters(in: .whitespaces)
      let header = SNESHeader(
        title: title, mapping: mapping, fastROM: mode & 0x10 != 0,
        romKB: (5...13).contains(bytes[23]) ? 1 << Int(bytes[23]) : nil,
        sramKB: bytes[24] == 0 || bytes[24] > 10 ? 0 : 1 << Int(bytes[24]),
        region: Int(bytes[25]) < regions.count ? regions[Int(bytes[25])] : "Code \(bytes[25])",
        version: Int(bytes[27]), checksum: checksum, complement: complement,
        computed: nil, copierHeader: copier > 0, fileSize: file.count)
      best = (score, header)
    }
    guard var header = best?.header else { return nil }
    header.computed = checksum(rom)
    return header
  }

  /// The byte sum the header's checksum should equal: a power-of-two ROM sums
  /// once; a larger one mirrors its remainder up to the next power of two.
  static func checksum(_ rom: Data) -> UInt16? {
    guard !rom.isEmpty else { return nil }
    var power = 1
    while power * 2 <= rom.count { power *= 2 }
    var total: UInt32 = rom.withUnsafeBytes { bytes in bytes.prefix(power).reduce(0) { $0 &+ UInt32($1) } }
    let rest = rom.count - power
    if rest > 0 {
      guard power % rest == 0 else { return nil }
      let tail: UInt32 = rom.withUnsafeBytes { bytes in bytes.dropFirst(power).reduce(0) { $0 &+ UInt32($1) } }
      total &+= tail &* UInt32(power / rest)
    }
    return UInt16(truncatingIfNeeded: total)
  }
}

/// The selected file, or the folder's AFS context when nothing is selected.
struct BrowserPreview: View {
  let entry: FileEntry?
  @ObservedObject var state: BrowserState
  @State private var content: PreviewContent?
  @State private var loadedFor: FileEntry?

  var body: some View {
    PaneWidth {
      if let entry {
        if entry.isFolder {
          details(entry)
        } else if loadedFor == entry, let content {
          view(for: content, entry: entry)
        } else {
          ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      } else if let context = state.contextRoot {
        ContextPanel(root: context, state: state)
      } else {
        Text("Select a file to preview it.").foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .background(Color.primary.opacity(0.02))
    // Keyed by the whole entry, so a save (new modified date) reloads it.
    .task(id: entry) {
      guard let entry, !entry.isFolder else { return }
      let url = entry.url
      let loaded = await Task.detached(priority: .userInitiated) { Preview.load(url) }.value
      guard !Task.isCancelled else { return }
      content = loaded
      loadedFor = entry
    }
  }

  @ViewBuilder
  private func view(for content: PreviewContent, entry: FileEntry) -> some View {
    switch content {
    case .document(let blocks):
      MarkdownDocumentView(blocks: blocks, base: entry.url.deletingLastPathComponent(), open: { $0.perform() })
    case .text(let text, let note, let spans):
      VStack(spacing: 0) {
        if let note {
          Text(note).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 4)
          Divider()
        }
        PlainTextView(text: text, spans: spans, line: entry.line)
      }
    case .rom(let header):
      ROMDetails(header: header, url: entry.url)
    case .image(let image):
      Image(nsImage: image).resizable().scaledToFit().padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .details:
      details(entry)
    }
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

private struct ROMDetails: View {
  let header: SNESHeader
  let url: URL

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        Label(header.title.isEmpty ? "Untitled ROM" : header.title, systemImage: "gamecontroller")
          .font(.title3.weight(.semibold))
        HStack {
          ForEach(ROMApp.installed, id: \.title) { app in
            Button(app.title) { app.open(url) }
          }
        }
        .controlSize(.small)
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
          row("Mapping", header.mapping + (header.fastROM ? ", FastROM" : ", SlowROM"))
          row("ROM size", (header.romKB.map { "\($0) KB in header, " } ?? "") + Preview.byteCount(header.fileSize) + " file")
          row("SRAM", header.sramKB == 0 ? "None" : "\(header.sramKB) KB")
          row("Region", header.region)
          row("Version", "1.\(header.version)")
          row("Checksum", String(format: "$%04X", header.checksum)
              + (header.complementMatches ? "" : " (its complement doesn't match)"))
          row("Computed", computed)
          if header.copierHeader { row("Copier header", "512 bytes, skipped") }
        }
        .font(.callout)
      }
      .textSelection(.enabled)
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var computed: String {
    guard let sum = header.computed else { return "Not computed: the size has no standard mirroring" }
    return String(format: "$%04X", sum) + (sum == header.checksum ? " ✓ matches" : " ✗ differs from the header")
  }

  private func row(_ label: String, _ value: String) -> some View {
    GridRow {
      Text(label).foregroundStyle(.secondary)
      Text(value)
    }
  }
}

/// Takes whatever width it's offered but reports one ideal width for every
/// kind of content; otherwise the split view collapses the pane to its
/// minimum whenever the content changes.
private struct PaneWidth: Layout {
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    CGSize(width: proposal.width ?? 320, height: proposal.height ?? 400)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
  }
}

/// Selectable monospaced text; AppKit's text view stays fast on a few
/// hundred kilobytes where a SwiftUI `Text` would not. Lines don't wrap, so
/// code keeps its columns and scrolls sideways.
private struct PlainTextView: NSViewRepresentable {
  let text: String
  let spans: [SyntaxSpan]
  /// A contents search's match, 1-based: scrolled to and selected.
  var line: Int?

  /// What the view shows, so an update redraws only when it changes; a
  /// rename can change the coloring and leave the text alone.
  final class Shown {
    var text = ""
    var spans: [SyntaxSpan] = []
    var line: Int?
  }

  func makeCoordinator() -> Shown { Shown() }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    scroll.drawsBackground = false
    scroll.hasHorizontalScroller = true
    if let view = scroll.documentView as? NSTextView {
      view.isEditable = false
      view.isSelectable = true
      view.drawsBackground = false
      view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
      view.textContainerInset = NSSize(width: 8, height: 8)
      view.isHorizontallyResizable = true
      view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
      view.textContainer?.widthTracksTextView = false
      view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                 height: .greatestFiniteMagnitude)
      show(in: view, context.coordinator)
    }
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    let shown = context.coordinator
    guard let view = scroll.documentView as? NSTextView,
          shown.text != text || shown.spans != spans || shown.line != line else { return }
    show(in: view, shown)
  }

  private func show(in view: NSTextView, _ shown: Shown) {
    (shown.text, shown.spans, shown.line) = (text, spans, line)
    view.string = text
    if let storage = view.textStorage, !spans.isEmpty {
      storage.beginEditing()
      for span in spans where NSMaxRange(span.range) <= storage.length {
        storage.addAttribute(.foregroundColor, value: Self.color(span.token), range: span.range)
      }
      storage.endEditing()
    }
    guard let line, let range = Preview.range(ofLine: line, in: text) else {
      view.scrollToBeginningOfDocument(nil)
      return
    }
    view.setSelectedRange(range)
    // The view has no window or layout yet when it was just made.
    DispatchQueue.main.async {
      view.scrollRangeToVisible(range)
      view.showFindIndicator(for: range)
    }
  }

  private static func color(_ token: SyntaxToken) -> NSColor {
    switch token {
    case .comment: return .secondaryLabelColor
    case .string: return .systemGreen
    case .number: return .systemOrange
    case .keyword: return .systemPink
    case .label: return .systemTeal
    }
  }
}