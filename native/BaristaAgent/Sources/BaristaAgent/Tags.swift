import AppKit
import SwiftUI

/// A Finder tag: its name and Finder's color number (0 none, 1 gray, 2 green,
/// 3 purple, 4 blue, 5 yellow, 6 red, 7 orange).
struct FinderTag: Hashable {
  let name: String
  var color: Int

  /// Finder's seven, in its Tags menu's order.
  static let standard = [("Red", 6), ("Orange", 7), ("Yellow", 5), ("Green", 2), ("Blue", 4), ("Purple", 3),
                         ("Gray", 1)].map { FinderTag(name: $0.0, color: $0.1) }

  /// Finder treats `Red` and `red` as one tag.
  func matches(_ other: FinderTag) -> Bool { name.caseInsensitiveCompare(other.name) == .orderedSame }

  var nsColor: NSColor? {
    switch color {
    case 1: return .systemGray
    case 2: return .systemGreen
    case 3: return .systemPurple
    case 4: return .systemBlue
    case 5: return .systemYellow
    case 6: return .systemRed
    case 7: return .systemOrange
    default: return nil
    }
  }

  /// A colored dot for menus, which draw SF Symbols in the text color.
  var menuImage: NSImage {
    let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
      let dot = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
      if let color = self.nsColor {
        color.setFill()
        dot.fill()
      } else {
        NSColor.secondaryLabelColor.setStroke()
        dot.stroke()
      }
      return true
    }
    image.isTemplate = false
    return image
  }
}

/// Finder's tags live in one extended attribute, a binary plist array of
/// `name\ncolor` strings. Written directly, since the URL resource key takes
/// colors from Finder's tag list and wrote `Red` uncolored here.
enum FinderTags {
  static let attribute = "com.apple.metadata:_kMDItemUserTags"

  static func decode(_ data: Data) -> [FinderTag] {
    guard let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else {
      return []
    }
    return values.compactMap { value in
      if let newline = value.range(of: "\n", options: .backwards), let color = Int(value[newline.upperBound...]) {
        return FinderTag(name: String(value[..<newline.lowerBound]), color: color)
      }
      return value.isEmpty ? nil : FinderTag(name: value, color: 0)
    }
  }

  static func encode(_ tags: [FinderTag]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: tags.map { "\($0.name)\n\($0.color)" }, format: .binary,
                                       options: 0)
  }

  /// The tags on `url` itself; a symlink's are its own, as Finder shows them.
  static func read(_ url: URL) -> [FinderTag] {
    url.withUnsafeFileSystemRepresentation { path -> [FinderTag] in
      guard let path else { return [] }
      let size = getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
      guard size > 0 else { return [] }
      var data = Data(count: size)
      let read = data.withUnsafeMutableBytes { getxattr(path, attribute, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
      return read > 0 ? decode(data.prefix(read)) : []
    }
  }

  /// No tags removes the attribute.
  static func write(_ tags: [FinderTag], to url: URL) throws {
    let data = tags.isEmpty ? nil : try encode(tags)
    try url.withUnsafeFileSystemRepresentation { path in
      guard let path else { throw CocoaError(.fileNoSuchFile) }
      let status: Int32
      if let data {
        status = data.withUnsafeBytes { setxattr(path, attribute, $0.baseAddress, data.count, 0, XATTR_NOFOLLOW) }
      } else {
        status = removexattr(path, attribute, XATTR_NOFOLLOW)
        if status != 0 && errno == ENOATTR { return }
      }
      guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
  }

  /// Finder's Tags menu: `tag` comes off every item when all have it, and
  /// otherwise goes on the ones without it.
  static func toggle(_ tag: FinderTag, on urls: [URL]) throws {
    let current = urls.map(read)
    let everyOne = current.allSatisfy { $0.contains { $0.matches(tag) } }
    for (url, tags) in zip(urls, current) {
      if everyOne {
        try write(tags.filter { !$0.matches(tag) }, to: url)
      } else if !tags.contains(where: { $0.matches(tag) }) {
        try write(tags + [tag], to: url)
      }
    }
  }
}

/// The tags the Tags menu and sidebar offer: Finder's seven, then the others
/// files carry, which Spotlight finds. Main thread only.
final class TagCatalog: ObservableObject {
  static let shared = TagCatalog()
  @Published private(set) var tags = FinderTag.standard
  private var refreshing = false
  private var refreshed = Date.distantPast

  /// Looks again at most once a minute; each window asks when it opens.
  func refresh() {
    guard !refreshing, Date().timeIntervalSince(refreshed) > 60 else { return }
    refreshing = true
    DispatchQueue.global(qos: .utility).async {
      let found = Self.inUse()
      DispatchQueue.main.async {
        self.refreshing = false
        self.refreshed = Date()
        self.tags = Self.merged(FinderTag.standard, found)
      }
    }
  }

  /// A tag put on a file here, before Spotlight has seen it.
  func add(_ tag: FinderTag) {
    if !tags.contains(where: { $0.matches(tag) }) { tags.append(tag) }
  }

  /// `extra` after `base` in name order, each name once.
  static func merged(_ base: [FinderTag], _ extra: [FinderTag]) -> [FinderTag] {
    var tags = base
    for tag in extra.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    where !tags.contains(where: { $0.matches(tag) }) {
      tags.append(tag)
    }
    return tags
  }

  /// The tags on the files Spotlight knows to have any, up to `limit` files.
  /// Spotlight keeps names only, so the colors come from each file. Blocking.
  static func inUse(limit: Int = 2000) -> [FinderTag] {
    guard let output = ToolRun().lines("/usr/bin/mdfind", ["kMDItemUserTags == \"*\""], limit: limit) else {
      return []
    }
    var found: [FinderTag] = []
    for path in output.lines where path.hasPrefix("/") {
      for tag in FinderTags.read(URL(fileURLWithPath: path)) where !found.contains(where: { $0.matches(tag) }) {
        found.append(tag)
      }
    }
    return found
  }
}

/// A row's colored tags as overlapping dots, as Finder draws them; hovering
/// names them all.
struct TagDots: View {
  let tags: [FinderTag]
  var size: CGFloat = 8

  var body: some View {
    let colors = tags.compactMap(\.nsColor).prefix(3)
    if !colors.isEmpty {
      HStack(spacing: -size * 0.35) {
        ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
          Circle()
            .fill(Color(nsColor: color))
            .overlay(Circle().strokeBorder(Color(nsColor: .controlBackgroundColor), lineWidth: 1))
            .frame(width: size, height: size)
        }
      }
      .help(tags.map(\.name).joined(separator: ", "))
    }
  }
}

/// The selection's Tags submenu: each tag checked when every item has it.
struct TagsMenu: View {
  @ObservedObject var state: BrowserState
  @ObservedObject private var catalog = TagCatalog.shared
  let urls: [URL]

  var body: some View {
    let chosen = Set(urls)
    let entries = state.shown.filter { chosen.contains($0.url) }
    Menu("Tags") {
      ForEach(catalog.tags, id: \.name) { tag in
        let all = !entries.isEmpty && entries.allSatisfy { $0.tags.contains { $0.matches(tag) } }
        Toggle(isOn: Binding(get: { all }, set: { _ in state.toggleTag(tag, on: urls) })) {
          Label { Text(tag.name) } icon: { Image(nsImage: tag.menuImage) }
        }
      }
      Divider()
      Button("Remove All Tags") { state.removeTags(from: urls) }
        .disabled(entries.allSatisfy { $0.tags.isEmpty })
    }
  }
}
