import AVFoundation
import AppKit
import Combine
import QuickLookThumbnailing
import SwiftUI

/// How a gallery window shows its pictures and movies: all of them as
/// thumbnails, several as tiles, or one filling the window.
enum ViewMode: String, Codable, CaseIterable, Identifiable {
  case gallery, tiles, one

  var id: String { rawValue }

  var title: String {
    switch self {
    case .gallery: return "Gallery"
    case .tiles: return "Tiles"
    case .one: return "One at a Time"
    }
  }

  /// Pressed with ⌘.
  var key: String {
    switch self {
    case .gallery: return "1"
    case .tiles: return "2"
    case .one: return "3"
    }
  }
}

enum GalleryLayout: String, Codable, CaseIterable, Identifiable {
  /// Square cells in even rows.
  case grid
  /// Rows the window's width, each picture its own shape.
  case justified
  /// Masonry: even columns, each picture its own height.
  case columns
  /// Square cells, with the featured ones spanning several.
  case featured

  var id: String { rawValue }

  var title: String {
    switch self {
    case .grid: return "Even Grid"
    case .justified: return "Justified Rows"
    case .columns: return "Columns"
    case .featured: return "Featured"
    }
  }

  var symbol: String {
    switch self {
    case .grid: return "square.grid.3x3"
    case .justified: return "rectangle.grid.1x2"
    case .columns: return "rectangle.split.3x1"
    case .featured: return "square.split.bottomrightquarter"
    }
  }
}

/// How much of the width a featured picture takes.
enum FeatureShare: String, Codable, CaseIterable, Identifiable {
  case half, twoThirds

  var id: String { rawValue }
  var fraction: CGFloat { self == .half ? 0.5 : 2.0 / 3 }
  var title: String { self == .half ? "½ Width" : "⅔ Width" }
}

/// Where each thumbnail goes, top-left origin, in a gallery `width` wide.
/// Drawing, clicks, arrow keys, and drops all use the same frames.
enum GalleryGrid {
  static let gap: CGFloat = 4
  /// The thumbnail sizes − and + step through, in points: a grid cell's
  /// side, a justified row's height, or a column's width.
  static let sizes: [CGFloat] = [80, 110, 150, 200, 260, 340, 440]
  static let defaultSize = 3

  enum Direction {
    case left, right, up, down
  }

  /// Where dragged thumbnails land: `index` counts the items they leave,
  /// and `marker` is the bar drawn between two thumbnails.
  struct Insertion: Equatable {
    let index: Int
    let marker: CGRect
  }

  /// `featured` holds indices; with none, the first item is featured.
  static func frames(aspects: [CGFloat], width: CGFloat, layout: GalleryLayout, target: CGFloat,
                     featured: Set<Int> = [], share: FeatureShare = .half) -> (frames: [CGRect], height: CGFloat) {
    guard !aspects.isEmpty else { return ([], 0) }
    let width = max(width, 1)
    let aspects = aspects.map { $0.isFinite && $0 > 0 ? min(max($0, 0.2), 5) : 1 }
    switch layout {
    case .grid:
      return grid(aspects.count, width: width, target: target)
    case .justified:
      return justified(aspects, width: width, target: target)
    case .columns:
      return columns(aspects, width: width, target: target)
    case .featured:
      return feature(aspects.count, width: width, target: target,
                     featured: featured.isEmpty ? [0] : featured, share: share)
    }
  }

  static func columnCount(width: CGFloat, target: CGFloat) -> Int {
    max(1, Int(((width + gap) / (target + gap)).rounded()))
  }

  private static func cell(_ columns: Int, width: CGFloat) -> CGFloat {
    (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
  }

  private static func grid(_ count: Int, width: CGFloat, target: CGFloat) -> ([CGRect], CGFloat) {
    let columns = columnCount(width: width, target: target)
    let side = cell(columns, width: width)
    let frames = (0..<count).map { index in
      CGRect(x: CGFloat(index % columns) * (side + gap), y: CGFloat(index / columns) * (side + gap),
             width: side, height: side)
    }
    let rows = (count + columns - 1) / columns
    return (frames, CGFloat(rows) * (side + gap) - gap)
  }

  /// Fills a row until it would be shorter than `target`, then closes it
  /// with or without the last picture, whichever height is nearer. The last
  /// row keeps `target`'s height rather than stretching a few pictures.
  private static func justified(_ aspects: [CGFloat], width: CGFloat, target: CGFloat) -> ([CGRect], CGFloat) {
    var frames: [CGRect] = []
    var y: CGFloat = 0
    func height(_ count: Int, _ sum: CGFloat) -> CGFloat { (width - gap * CGFloat(count - 1)) / sum }
    func place(_ range: Range<Int>, height: CGFloat, stretch: Bool) {
      var x: CGFloat = 0
      for index in range {
        // The last one takes up rounding so the row ends flush.
        let cellWidth = stretch && index == range.upperBound - 1 ? width - x : aspects[index] * height
        frames.append(CGRect(x: x, y: y, width: max(cellWidth, 1), height: height))
        x += cellWidth + gap
      }
      y += height + gap
    }
    var start = 0
    var sum: CGFloat = 0
    var index = 0
    while index < aspects.count {
      sum += aspects[index]
      let count = index - start + 1
      let with = height(count, sum)
      guard with <= target else {
        index += 1
        continue
      }
      if count > 1 {
        let without = height(count - 1, sum - aspects[index])
        if max(without / target, target / without) < max(with / target, target / with) {
          place(start..<index, height: without, stretch: true)
          // This picture starts the next row.
          start = index
          sum = 0
          continue
        }
      }
      place(start..<(index + 1), height: with, stretch: true)
      start = index + 1
      sum = 0
      index += 1
    }
    if start < aspects.count {
      place(start..<aspects.count, height: min(target, height(aspects.count - start, sum)), stretch: false)
    }
    return (frames, y - gap)
  }

  /// Each picture goes under the shortest column, the leftmost on a tie.
  private static func columns(_ aspects: [CGFloat], width: CGFloat, target: CGFloat) -> ([CGRect], CGFloat) {
    let columns = columnCount(width: width, target: target)
    let columnWidth = cell(columns, width: width)
    var heights = [CGFloat](repeating: 0, count: columns)
    let frames = aspects.map { aspect -> CGRect in
      let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
      let frame = CGRect(x: CGFloat(column) * (columnWidth + gap), y: heights[column],
                         width: columnWidth, height: columnWidth / aspect)
      heights[column] += frame.height + gap
      return frame
    }
    return (frames, (heights.max() ?? gap) - gap)
  }

  /// Square cells packed densely: each thumbnail takes the first free spot
  /// big enough, so small ones fill the holes beside a featured one.
  private static func feature(_ count: Int, width: CGFloat, target: CGFloat, featured: Set<Int>,
                               share: FeatureShare) -> ([CGRect], CGFloat) {
    let columns = columnCount(width: width, target: target)
    let side = cell(columns, width: width)
    let span = min(columns, max(min(2, columns), Int((CGFloat(columns) * share.fraction).rounded())))
    var taken: [[Bool]] = []
    var firstOpen = 0
    func open(_ row: Int, _ column: Int, _ size: Int) -> Bool {
      for r in row..<(row + size) where r < taken.count {
        for c in column..<(column + size) where taken[r][c] { return false }
      }
      return true
    }
    var frames: [CGRect] = []
    for index in 0..<count {
      let size = featured.contains(index) ? span : 1
      var row = firstOpen
      var column: Int?
      while column == nil {
        column = (0...(columns - size)).first { open(row, $0, size) }
        if column == nil { row += 1 }
      }
      let left = column ?? 0
      while taken.count < row + size { taken.append([Bool](repeating: false, count: columns)) }
      for r in row..<(row + size) {
        for c in left..<(left + size) { taken[r][c] = true }
      }
      while firstOpen < taken.count, !taken[firstOpen].contains(false) { firstOpen += 1 }
      let extent = CGFloat(size) * (side + gap) - gap
      frames.append(CGRect(x: CGFloat(left) * (side + gap), y: CGFloat(row) * (side + gap),
                           width: extent, height: extent))
    }
    return (frames, CGFloat(taken.count) * (side + gap) - gap)
  }

  static func index(at point: CGPoint, in frames: [CGRect]) -> Int? {
    frames.firstIndex { $0.contains(point) }
  }

  /// Left and right go back and forth in the gallery's order. Up and down
  /// go to the nearest thumbnail above or below the middle of this one, or
  /// else in the nearest row, the one nearest across.
  static func neighbor(of index: Int, in frames: [CGRect], direction: Direction) -> Int? {
    guard frames.indices.contains(index) else { return frames.isEmpty ? nil : 0 }
    switch direction {
    case .left:
      return index > 0 ? index - 1 : nil
    case .right:
      return index < frames.count - 1 ? index + 1 : nil
    case .up, .down:
      let here = frames[index]
      let up = direction == .up
      let edge = { (frame: CGRect) in up ? frame.maxY : frame.minY }
      let candidates = frames.indices.filter {
        $0 != index && (up ? frames[$0].maxY <= here.minY + 1 : frames[$0].minY >= here.maxY - 1)
      }
      let across = candidates.filter { frames[$0].minX <= here.midX && frames[$0].maxX >= here.midX }
      if !across.isEmpty {
        return up ? across.max { edge(frames[$0]) < edge(frames[$1]) }
          : across.min { edge(frames[$0]) < edge(frames[$1]) }
      }
      guard let nearest = up ? candidates.map({ edge(frames[$0]) }).max()
        : candidates.map({ edge(frames[$0]) }).min()
      else { return nil }
      return candidates.filter { abs(edge(frames[$0]) - nearest) < 1 }
        .min { abs(frames[$0].midX - here.midX) < abs(frames[$1].midX - here.midX) }
    }
  }

  /// Before or after the thumbnail nearest `point`, by which half it is in.
  static func insertion(at point: CGPoint, in frames: [CGRect]) -> Insertion? {
    func distance(_ frame: CGRect) -> CGFloat {
      let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
      let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
      return dx * dx + dy * dy
    }
    guard let nearest = frames.indices.min(by: { distance(frames[$0]) < distance(frames[$1]) }) else { return nil }
    let frame = frames[nearest]
    let after = point.x > frame.midX
    let x = (after ? frame.maxX + gap / 2 : frame.minX - gap / 2) - 1.5
    return Insertion(index: after ? nearest + 1 : nearest,
                     marker: CGRect(x: x, y: frame.minY, width: 3, height: frame.height))
  }
}

/// Quick Look thumbnails in a few sizes, so one drawn bigger stands in for a
/// smaller one and the gallery keeps few sizes of each picture.
final class GalleryThumbnails: @unchecked Sendable {
  static let shared = GalleryThumbnails()
  static let buckets = [256, 512, 1024, 2048]

  private let cache = NSCache<NSString, NSImage>()

  private init() {
    cache.countLimit = 2000
    cache.totalCostLimit = 256 << 20
  }

  /// The smallest size with two pixels to a point at `points`.
  static func pixels(for points: CGFloat) -> Int {
    buckets.first { CGFloat($0) >= points * 2 } ?? buckets[buckets.count - 1]
  }

  private static func key(_ url: URL, _ pixels: Int, _ modified: Date?) -> NSString {
    "\(pixels)|\(Int(modified?.timeIntervalSince1970 ?? 0))|\(url.path)" as NSString
  }

  /// The thumbnail at `pixels`, or another size already drawn, bigger first.
  func cached(_ url: URL, pixels: Int, modified: Date?) -> NSImage? {
    if let image = cache.object(forKey: Self.key(url, pixels, modified)) { return image }
    for other in Self.buckets.reversed() where other != pixels {
      if let image = cache.object(forKey: Self.key(url, other, modified)) { return image }
    }
    return nil
  }

  /// Nil when Quick Look cannot draw the file or the cell scrolled away.
  func image(for url: URL, pixels: Int, modified: Date?) async -> NSImage? {
    let key = Self.key(url, pixels, modified)
    if let image = cache.object(forKey: key) { return image }
    let points = CGFloat(pixels) / 2
    let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: points, height: points),
                                               scale: 2, representationTypes: .all)
    let image = await withTaskCancellationHandler {
      try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    } onCancel: {
      QLThumbnailGenerator.shared.cancel(request)
    }
    if let image { cache.setObject(image, forKey: key, cost: pixels * pixels * 4) }
    return image
  }
}

/// What the gallery reads about a file before drawing it: its shape, read
/// from the header without decoding, and its date for the thumbnail cache.
struct GalleryItem: Equatable {
  var aspect: CGFloat = 1
  var modified: Date?
  var isVideo = false
  var exists = true

  static func read(_ url: URL) async -> GalleryItem {
    var item = GalleryItem()
    item.isVideo = ViewerKind.of(url) == .video
    item.exists = FileManager.default.fileExists(atPath: url.path)
    guard item.exists else { return item }
    item.modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    if item.isVideo {
      if let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
         let loaded = try? await track.load(.naturalSize, .preferredTransform) {
        let upright = loaded.0.applying(loaded.1)
        if upright.height != 0 { item.aspect = abs(upright.width / upright.height) }
      }
    } else if let points = ImageHeader.read(url)?.points, points.height > 0 {
      item.aspect = points.width / points.height
    }
    return item
  }
}

/// The pictures and movies a gallery window shows, in its order, with the
/// selection and how they are laid out. A folder's gallery follows the
/// folder; what is removed from it is only hidden until the window closes.
/// A collection's gallery saves every change to its collection.
final class GalleryModel: ObservableObject {
  enum Source: Equatable {
    case folder(URL)
    case collection(String)
  }

  @Published private(set) var source: Source
  @Published private(set) var items: [URL] = [] {
    didSet { revision += 1 }
  }
  /// Files removed from a folder's gallery; they stay on disk.
  @Published private(set) var hidden: Set<URL> = []
  @Published private(set) var selection: Set<URL> = []
  /// The thumbnail the arrow keys move from.
  @Published private(set) var focus: URL?
  @Published private(set) var layout = GalleryLayout.justified
  /// Index into `GalleryGrid.sizes`.
  @Published private(set) var size = GalleryGrid.defaultSize
  @Published private(set) var featured: Set<URL> = [] {
    didSet { revision += 1 }
  }
  @Published private(set) var share = FeatureShare.half
  @Published private(set) var info: [URL: GalleryItem] = [:] {
    didSet { revision += 1 }
  }
  @Published private(set) var status: String?
  /// How the window last showed it, kept with a collection.
  private(set) var mode = ViewMode.gallery
  private(set) var tileLayout = TileLayout.grid
  /// The window's, where removing and moving leave their Undo.
  weak var undoManager: UndoManager?

  private let store: CollectionStore
  private let defaults: UserDefaults
  /// The folder's order was changed by hand; new files go at the end.
  private var reordered = false
  /// Where ⇧-click and ⇧-arrow extend from.
  private var anchor: URL?
  private var watcher: FileWatcher?
  private var sink: AnyCancellable?
  private var loading = false
  private var saving = false
  private var reading: Set<URL> = []
  /// Where trashed files were, for Undo to put them back.
  private var trashedAt: [URL: Int] = [:]
  private var statusWork: DispatchWorkItem?
  private var revision = 0
  private var memo: (key: LayoutKey, frames: [CGRect], height: CGFloat)?
  /// The width last laid out, which the arrow keys move in.
  private var width: CGFloat = 0

  private struct LayoutKey: Equatable {
    let width: CGFloat
    let layout: GalleryLayout
    let size: Int
    let share: FeatureShare
    let revision: Int
  }

  private struct Snapshot: Equatable {
    let items: [URL]
    let hidden: Set<URL>
    let reordered: Bool
    let featured: Set<URL>
  }

  /// A folder's gallery. Its layout and size are shared by all folders.
  init(folder: URL, store: CollectionStore = .shared, defaults: UserDefaults = .standard) {
    source = .folder(folder.standardizedFileURL)
    self.store = store
    self.defaults = defaults
    layout = defaults.string(forKey: "Gallery.layout").flatMap(GalleryLayout.init) ?? .justified
    if defaults.object(forKey: "Gallery.size") != nil {
      size = min(max(defaults.integer(forKey: "Gallery.size"), 0), GalleryGrid.sizes.count - 1)
    }
    share = defaults.string(forKey: "Gallery.share").flatMap(FeatureShare.init) ?? .half
    refresh()
    watcher = FileWatcher(url: folder) { [weak self] in self?.refresh() }
  }

  /// A collection's gallery, following edits to the collection made elsewhere.
  init(collection name: String, store: CollectionStore = .shared, defaults: UserDefaults = .standard) {
    source = .collection(name)
    self.store = store
    self.defaults = defaults
    if let collection = store.collection(named: name) { apply(collection) }
    // The store publishes before it changes, so the new list comes in the value.
    sink = store.$collections.dropFirst().sink { [weak self] collections in
      guard let self, !self.saving, case .collection(let name) = self.source,
            let collection = collections.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
      else { return }
      self.apply(collection)
      self.loadInfo()
    }
    loadInfo()
  }

  var title: String {
    switch source {
    case .folder(let url): return url.lastPathComponent
    case .collection(let name): return name
    }
  }

  var isCollection: Bool {
    if case .collection = source { return true }
    return false
  }

  var folder: URL? {
    if case .folder(let url) = source { return url }
    return nil
  }

  var removeTitle: String { isCollection ? "Remove from Collection" : "Remove from Gallery" }

  /// Every thumbnail's frame in a gallery `width` wide, and their height.
  func layout(width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
    self.width = width
    let key = LayoutKey(width: width, layout: layout, size: size, share: share, revision: revision)
    if let memo, memo.key == key { return (memo.frames, memo.height) }
    let indices = Set(items.indices.filter { featured.contains(items[$0]) })
    let placed = GalleryGrid.frames(aspects: items.map { info[$0]?.aspect ?? 1 }, width: width, layout: layout,
                                    target: GalleryGrid.sizes[size], featured: indices, share: share)
    memo = (key, placed.frames, placed.height)
    return placed
  }

  // MARK: Loading

  /// Lists the folder again: files gone leave, new ones come in at the end
  /// of a hand-made order or in name order.
  func refresh() {
    guard case .folder(let folder) = source else { return }
    let listed = Self.media(in: folder)
    let present = Set(listed)
    if !hidden.isSubset(of: present) { hidden.formIntersection(present) }
    let shown: [URL]
    if reordered {
      let known = Set(items)
      shown = items.filter(present.contains) + listed.filter { !known.contains($0) && !hidden.contains($0) }
    } else {
      shown = listed.filter { !hidden.contains($0) }
    }
    if shown != items { items = shown }
    if !featured.isSubset(of: present) { featured.formIntersection(present) }
    trimSelection()
    loadInfo()
  }

  /// Reads every file's shape again, as after editing them elsewhere.
  func reload() {
    info = [:]
    if case .collection(let name) = source {
      store.refresh()
      if let collection = store.collection(named: name) { apply(collection) }
      loadInfo()
    } else {
      refresh()
    }
  }

  /// The folder's pictures and movies in Finder's name order.
  static func media(in folder: URL) -> [URL] {
    let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? []
    return urls.filter { ViewerKind.of($0)?.isMedia == true }.map(\.standardizedFileURL)
      .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
  }

  private func apply(_ collection: MediaCollection) {
    loading = true
    defer { loading = false }
    if source != .collection(collection.name) { source = .collection(collection.name) }
    let urls = collection.urls
    if urls != items { items = urls }
    let featured = collection.featuredURLs.intersection(urls)
    if featured != self.featured { self.featured = featured }
    if layout != collection.layout { layout = collection.layout }
    if size != collection.size { size = collection.size }
    if share != collection.share { share = collection.share }
    mode = collection.mode
    tileLayout = collection.tileLayout
    trimSelection()
  }

  /// Reads the files' shapes in the gallery's order, a hundred at a time.
  private func loadInfo() {
    let missing = items.filter { info[$0] == nil && !reading.contains($0) }
    guard !missing.isEmpty else { return }
    reading.formUnion(missing)
    Task { @MainActor [weak self] in
      for start in stride(from: 0, to: missing.count, by: 100) {
        let chunk = missing[start..<min(start + 100, missing.count)]
        let read = await withTaskGroup(of: (URL, GalleryItem).self) { group in
          for url in chunk { group.addTask { (url, await GalleryItem.read(url)) } }
          var read: [URL: GalleryItem] = [:]
          for await (url, item) in group { read[url] = item }
          return read
        }
        guard let self else { return }
        self.reading.subtract(read.keys)
        self.info.merge(read) { $1 }
      }
    }
  }

  private func trimSelection() {
    let present = Set(items)
    if !selection.isSubset(of: present) { selection.formIntersection(present) }
    if let anchor, !present.contains(anchor) { self.anchor = nil }
    if focus.map(present.contains) != true { focus = selected.first ?? items.first }
  }

  // MARK: Selection

  /// A click: alone, with ⇧ everything from the last click to it, with ⌘
  /// added or taken out.
  func select(_ url: URL, extend: Bool = false, toggle: Bool = false) {
    if extend, let start = anchor ?? focus, let from = items.firstIndex(of: start),
       let to = items.firstIndex(of: url) {
      anchor = start
      selection = Set(items[min(from, to)...max(from, to)])
    } else if toggle {
      if selection.contains(url) { selection.remove(url) } else { selection.insert(url) }
      anchor = url
    } else {
      if selection != [url] { selection = [url] }
      anchor = url
    }
    focus = url
  }

  func setFocus(_ url: URL) {
    if focus != url { focus = url }
  }

  func selectAll() {
    selection = Set(items)
  }

  func clearSelection() {
    if !selection.isEmpty { selection = [] }
  }

  /// The selection in the gallery's order.
  var selected: [URL] { items.filter(selection.contains) }

  /// What the keys act on: the selection, or the focused thumbnail.
  var selectedOrFocus: [URL] {
    selection.isEmpty ? focus.map { [$0] } ?? [] : selected
  }

  /// What a thumbnail's menu acts on: the selection when it is in it.
  func targets(for url: URL) -> [URL] {
    selection.contains(url) ? selected : [url]
  }

  /// Focuses `url`, selecting it unless it is already selected, as when
  /// coming back from viewing it.
  func reveal(_ url: URL) {
    guard items.contains(url) else { return }
    if !selection.contains(url) {
      selection = [url]
      anchor = url
    }
    setFocus(url)
  }

  func moveFocus(_ direction: GalleryGrid.Direction, extend: Bool) {
    guard let first = items.first else { return }
    guard let focus, let index = items.firstIndex(of: focus) else { return select(first) }
    guard let next = GalleryGrid.neighbor(of: index, in: layout(width: width).frames, direction: direction)
    else { return }
    select(items[next], extend: extend)
  }

  func moveToEdge(end: Bool, extend: Bool) {
    guard let url = end ? items.last : items.first else { return }
    select(url, extend: extend)
  }

  // MARK: Editing

  /// Hides `urls` from the gallery; the files stay where they are.
  func remove(_ urls: [URL]) {
    let gone = Set(urls)
    guard items.contains(where: gone.contains) else { return }
    let next = neighbor(after: gone)
    change(removeTitle) {
      items.removeAll(where: gone.contains)
      if case .folder = source { hidden.formUnion(gone) }
      if !featured.isDisjoint(with: gone) { featured.subtract(gone) }
    }
    trimSelection()
    if let next, selection.isEmpty { select(next) }
  }

  /// Puts `urls` together at `index`, counted before they leave their places.
  func move(_ urls: [URL], to index: Int) {
    let moving = Set(urls)
    let block = items.filter(moving.contains)
    guard !block.isEmpty else { return }
    let before = items[..<min(max(index, 0), items.count)].filter { !moving.contains($0) }.count
    var moved = items.filter { !moving.contains($0) }
    moved.insert(contentsOf: block, at: before)
    guard moved != items else { return }
    change("Rearrange") {
      items = moved
      reordered = true
    }
  }

  /// Moves the selection one place earlier or later, past its neighbor.
  func moveSelection(by offset: Int) {
    let urls = selectedOrFocus
    guard let first = urls.first.flatMap(items.firstIndex), let last = urls.last.flatMap(items.firstIndex) else {
      return
    }
    let index = offset < 0 ? first - 1 : last + 2
    guard index >= 0, index <= items.count else { return }
    move(urls, to: index)
  }

  /// Brings back what was removed from a folder's gallery.
  func showHidden() {
    guard !isCollection, !hidden.isEmpty else { return }
    let count = hidden.count
    change("Show Removed Items") {
      hidden = []
      refresh()
    }
    show(status: count == 1 ? "1 item back" : "\(count) items back")
  }

  /// Features `urls`, or unfeatures them when all are; featuring switches
  /// to the Featured layout.
  func toggleFeatured(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    let adding = !featured.isSuperset(of: urls)
    change(adding ? "Feature" : "Unfeature") {
      if adding { featured.formUnion(urls) } else { featured.subtract(urls) }
    }
    if adding, layout != .featured { set(layout: .featured) }
  }

  /// A collection's gallery takes pictures and movies from anywhere; a
  /// folder's takes back the ones removed from it.
  func add(_ urls: [URL]) {
    var known = Set(items)
    let fresh = urls.map(\.standardizedFileURL).filter {
      ViewerKind.of($0)?.isMedia == true && known.insert($0).inserted
    }
    guard let first = fresh.first else { return }
    guard isCollection else {
      let back = hidden.intersection(fresh)
      if !back.isEmpty { change("Add") { hidden.subtract(back); refresh() } }
      if back.count < fresh.count { show(status: "Only a collection takes files from other folders") }
      if items.contains(first) { select(first) }
      return
    }
    change("Add") { items += fresh }
    select(first)
    loadInfo()
  }

  /// Every edit to the order, what is hidden, or what is featured undoes
  /// as one step, and saves.
  private func change(_ name: String, _ edit: () -> Void) {
    let before = snapshot
    edit()
    guard snapshot != before else { return }
    register(before, name)
    save()
  }

  private var snapshot: Snapshot {
    Snapshot(items: items, hidden: hidden, reordered: reordered, featured: featured)
  }

  private func register(_ snapshot: Snapshot, _ name: String) {
    // Registered while undoing, it becomes the Redo.
    undoManager?.registerUndo(withTarget: self) { model in
      let current = model.snapshot
      model.restore(snapshot)
      model.register(current, name)
      model.save()
    }
    undoManager?.setActionName(name)
  }

  private func restore(_ snapshot: Snapshot) {
    if items != snapshot.items { items = snapshot.items }
    if hidden != snapshot.hidden { hidden = snapshot.hidden }
    reordered = snapshot.reordered
    if featured != snapshot.featured { featured = snapshot.featured }
    trimSelection()
    loadInfo()
  }

  // MARK: Settings

  func set(layout: GalleryLayout) {
    guard layout != self.layout else { return }
    self.layout = layout
    save()
  }

  func set(share: FeatureShare) {
    guard share != self.share else { return }
    self.share = share
    save()
  }

  func resize(by step: Int) {
    let next = min(max(size + step, 0), GalleryGrid.sizes.count - 1)
    guard next != size else { return }
    size = next
    save()
  }

  func cycleLayout() {
    let all = GalleryLayout.allCases
    set(layout: all[((all.firstIndex(of: layout) ?? 0) + 1) % all.count])
    show(status: layout.title)
  }

  func remember(_ mode: ViewMode) {
    guard mode != self.mode else { return }
    self.mode = mode
    save()
  }

  func remember(tileLayout: TileLayout) {
    guard tileLayout != self.tileLayout else { return }
    self.tileLayout = tileLayout
    save()
  }

  // MARK: Collections

  func isFavorite(_ urls: [URL]) -> Bool {
    !urls.isEmpty && urls.allSatisfy { store.contains($0, in: CollectionStore.favorites) }
  }

  /// Adds `urls` to Favorites, or takes them out when all are in it.
  func toggleFavorite(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    let favorites = CollectionStore.favorites
    if case .collection(let name) = source, name.caseInsensitiveCompare(favorites) == .orderedSame {
      return remove(urls)
    }
    if isFavorite(urls) {
      store.remove(urls, from: favorites)
      show(status: "Removed from \(favorites)")
    } else {
      show(status: CollectionMenu.add(urls, to: favorites, store: store))
    }
  }

  /// A new collection of what the gallery shows, in its order and layout.
  @discardableResult
  func saveAsCollection(_ name: String) -> String {
    var settings = MediaCollection(name: name)
    settings.mode = mode
    settings.layout = layout
    settings.tileLayout = tileLayout
    settings.size = size
    settings.share = share
    settings.featured = items.filter(featured.contains).map(MediaCollection.path)
    let created = store.create(name, urls: items, like: settings)
    show(status: "Saved as \(created)")
    return created
  }

  func rename(to name: String) {
    guard case .collection(let current) = source, let renamed = store.rename(current, to: name) else { return }
    source = .collection(renamed)
  }

  func deleteCollection() {
    guard case .collection(let name) = source else { return }
    store.delete(name)
  }

  // MARK: Files

  func copy(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
    show(status: urls.count == 1 ? "Copied \(urls[0].lastPathComponent)" : "Copied \(urls.count) files")
  }

  /// Moves `urls` to the Trash; they leave the gallery, and ⌘Z puts them
  /// back in the Trash's Undo, where they were in the gallery too.
  func trash(_ urls: [URL], restored: @escaping ([URL]) -> Void = { _ in }) {
    guard !urls.isEmpty else { return }
    for url in urls { if let index = items.firstIndex(of: url) { trashedAt[url] = index } }
    let next = neighbor(after: Set(urls))
    FileOperations.trash(urls, undo: undoManager, target: self) { [weak self] trashed, back, problem in
      guard let self else { return }
      if let problem { self.show(status: problem) }
      if !trashed.isEmpty { self.forget(trashed, next: next) }
      if !back.isEmpty {
        self.putBack(back)
        restored(back)
      }
    }
  }

  private func forget(_ urls: [URL], next: URL?) {
    let gone = Set(urls.map(\.standardizedFileURL))
    for url in gone { if let index = items.firstIndex(of: url) { trashedAt[url] = index } }
    let focusGone = focus.map(gone.contains) == true
    if items.contains(where: gone.contains) { items.removeAll(where: gone.contains) }
    if !featured.isDisjoint(with: gone) { featured.subtract(gone) }
    trimSelection()
    if focusGone, let next, items.contains(next) { select(next) }
    save()
  }

  private func putBack(_ urls: [URL]) {
    let back = urls.map(\.standardizedFileURL)
    let order = back.filter { !items.contains($0) }
      .sorted { (trashedAt[$0] ?? .max) < (trashedAt[$1] ?? .max) }
    for url in order {
      items.insert(url, at: min(trashedAt.removeValue(forKey: url) ?? items.count, items.count))
    }
    if !hidden.isDisjoint(with: back) { hidden.subtract(back) }
    selection = Set(back).intersection(items)
    if let first = order.first { focus = first }
    save()
    loadInfo()
  }

  /// The first item after the first of `gone`, or before it at the end.
  private func neighbor(after gone: Set<URL>) -> URL? {
    guard let first = items.firstIndex(where: gone.contains) else { return nil }
    return items[first...].first { !gone.contains($0) } ?? items[..<first].last { !gone.contains($0) }
  }

  func show(status: String) {
    self.status = status
    statusWork?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.status = nil }
    statusWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
  }

  /// A folder keeps only its layout, shared by every folder; a collection
  /// keeps everything.
  private func save() {
    guard !loading else { return }
    switch source {
    case .folder:
      defaults.set(layout.rawValue, forKey: "Gallery.layout")
      defaults.set(size, forKey: "Gallery.size")
      defaults.set(share.rawValue, forKey: "Gallery.share")
    case .collection(let name):
      saving = true
      defer { saving = false }
      let paths = items.map(MediaCollection.path)
      let featured = items.filter(self.featured.contains).map(MediaCollection.path)
      store.update(name) { collection in
        collection.items = paths
        collection.featured = featured
        collection.layout = layout
        collection.size = size
        collection.share = share
        collection.mode = mode
        collection.tileLayout = tileLayout
      }
    }
  }
}

// MARK: Views

/// Every picture and movie as a thumbnail. A click selects (⇧ a run, ⌘ one
/// more), a drag rearranges the selection, a double-click opens one, and
/// right-click has the rest.
struct GalleryView: View {
  @ObservedObject var model: ViewerModel
  @ObservedObject var gallery: GalleryModel
  @State private var top: CGFloat = 0
  @State private var press: Press?
  @State private var drop: GalleryGrid.Insertion?

  private static let inset = EdgeInsets(top: 44, leading: 6, bottom: 12, trailing: 6)
  private static let space = "gallery"
  private static let focusID = "gallery.focus"

  private struct Press {
    let url: URL?
    let wasSelected: Bool
    let plain: Bool
    var dragging = false
  }

  private struct Placed: Identifiable {
    let url: URL
    let frame: CGRect
    var id: URL { url }
  }

  var body: some View {
    GeometryReader { geometry in
      let width = max(geometry.size.width - Self.inset.leading - Self.inset.trailing, 1)
      let placed = gallery.layout(width: width)
      ScrollViewReader { proxy in
        ScrollView(.vertical) {
          canvas(placed.frames, height: placed.height, size: geometry.size)
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(GalleryOffset.self) { offset in
          // Coarse steps, so scrolling redraws only when cells come and go.
          let step = (offset / 100).rounded(.down) * 100
          if step != top { top = step }
        }
        .onChange(of: gallery.focus) { _, _ in
          DispatchQueue.main.async { proxy.scrollTo(Self.focusID) }
        }
      }
    }
    .background(Color.black)
    .overlay(alignment: .top) {
      GalleryBar(model: model, gallery: gallery)
        .opacity(model.showsChrome ? 1 : 0)
        .allowsHitTesting(model.showsChrome)
        .animation(.easeOut(duration: 0.2), value: model.showsChrome)
    }
    .overlay {
      if gallery.items.isEmpty {
        Text(gallery.isCollection ? "Drop pictures or movies here" : "No pictures or movies")
          .foregroundStyle(.secondary)
      }
    }
    .overlay(alignment: .bottom) {
      if let status = gallery.status {
        Text(status)
          .font(.callout)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(.regularMaterial, in: Capsule())
          .padding(.bottom, 14)
      }
    }
    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
      let dropped = DroppedURLs()
      let group = DispatchGroup()
      for (index, provider) in providers.enumerated() {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          if let url { dropped.set(index, url) }
          group.leave()
        }
      }
      group.notify(queue: .main) { gallery.add(dropped.urls) }
      return true
    }
    .environment(\.colorScheme, .dark)
    .ignoresSafeArea()
  }

  private func canvas(_ frames: [CGRect], height: CGFloat, size: CGSize) -> some View {
    let inset = Self.inset
    // Only the cells within a screen of the visible part are made.
    let low = top - size.height
    let high = top + size.height * 2
    let shown = frames.indices.compactMap { index -> Placed? in
      let frame = frames[index].offsetBy(dx: inset.leading, dy: inset.top)
      guard frame.maxY >= low, frame.minY <= high, index < gallery.items.count else { return nil }
      return Placed(url: gallery.items[index], frame: frame)
    }
    let focusFrame = gallery.focus.flatMap(gallery.items.firstIndex).flatMap { frames.indices.contains($0) ? $0 : nil }
      .map { frames[$0].offsetBy(dx: inset.leading, dy: inset.top) }
    let dragging = press?.dragging == true
    return ZStack(alignment: .topLeading) {
      Color.black
      ForEach(shown) { cell in
        GalleryCell(url: cell.url, item: gallery.info[cell.url], size: cell.frame.size,
                    selected: gallery.selection.contains(cell.url), focused: gallery.focus == cell.url,
                    featured: gallery.featured.contains(cell.url),
                    dimmed: dragging && gallery.selection.contains(cell.url))
          .frame(width: cell.frame.width, height: cell.frame.height)
          // Before .position, which makes the view as big as the canvas.
          .contextMenu { GalleryCellMenu(model: model, gallery: gallery, urls: gallery.targets(for: cell.url)) }
          .position(x: cell.frame.midX, y: cell.frame.midY)
      }
      if let focusFrame {
        // Scrolled to on focus changes; it reaches under the bar.
        Color.clear
          .frame(width: focusFrame.width, height: focusFrame.height + inset.top + inset.bottom)
          .position(x: focusFrame.midX, y: focusFrame.midY + (inset.bottom - inset.top) / 2)
          .allowsHitTesting(false)
          .id(Self.focusID)
      }
      if let drop {
        Capsule().fill(Color.accentColor)
          .frame(width: drop.marker.width, height: drop.marker.height)
          .position(x: drop.marker.midX + inset.leading, y: drop.marker.midY + inset.top)
          .allowsHitTesting(false)
      }
    }
    .frame(width: size.width, height: max(height + inset.top + inset.bottom, size.height))
    .background {
      GeometryReader { proxy in
        Color.clear.preference(key: GalleryOffset.self, value: -proxy.frame(in: .named(Self.space)).minY)
      }
    }
    .contentShape(Rectangle())
    .gesture(pressGesture(frames))
  }

  private func pressGesture(_ frames: [CGRect]) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let point = CGPoint(x: value.location.x - Self.inset.leading, y: value.location.y - Self.inset.top)
        if press == nil {
          let start = CGPoint(x: value.startLocation.x - Self.inset.leading,
                              y: value.startLocation.y - Self.inset.top)
          begin(at: start, frames: frames)
        }
        guard var current = press, current.plain, current.url != nil else { return }
        if !current.dragging, hypot(value.translation.width, value.translation.height) > 6 {
          current.dragging = true
          press = current
        }
        if current.dragging { drop = GalleryGrid.insertion(at: point, in: frames) }
      }
      .onEnded { _ in
        defer {
          press = nil
          drop = nil
        }
        guard let current = press, let url = current.url else { return }
        if current.dragging {
          if let drop { gallery.move(gallery.selected, to: drop.index) }
          return
        }
        if current.plain, current.wasSelected { gallery.select(url) }
        if NSApp.currentEvent?.clickCount == 2 { model.open([url]) }
      }
  }

  /// A plain press on a selected thumbnail waits for the release to select
  /// only it, so a drag can take the whole selection.
  private func begin(at point: CGPoint, frames: [CGRect]) {
    let flags = NSEvent.modifierFlags
    let extend = flags.contains(.shift)
    let toggle = flags.contains(.command)
    let url = GalleryGrid.index(at: point, in: frames).flatMap { $0 < gallery.items.count ? gallery.items[$0] : nil }
    let wasSelected = url.map(gallery.selection.contains) ?? false
    if let url {
      if extend || toggle {
        gallery.select(url, extend: extend, toggle: toggle && !extend)
      } else if wasSelected {
        gallery.setFocus(url)
      } else {
        gallery.select(url)
      }
    } else if !extend, !toggle {
      gallery.clearSelection()
    }
    press = Press(url: url, wasSelected: wasSelected, plain: !extend && !toggle)
  }
}

private struct GalleryOffset: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Files dropped together arrive one by one on other threads.
private final class DroppedURLs: @unchecked Sendable {
  private let lock = NSLock()
  private var found: [Int: URL] = [:]

  func set(_ index: Int, _ url: URL) {
    lock.lock()
    found[index] = url
    lock.unlock()
  }

  var urls: [URL] {
    lock.lock()
    defer { lock.unlock() }
    return found.keys.sorted().compactMap { found[$0] }
  }
}

private struct GalleryCell: View {
  let url: URL
  let item: GalleryItem?
  let size: CGSize
  let selected: Bool
  let focused: Bool
  let featured: Bool
  let dimmed: Bool
  @State private var image: NSImage?

  init(url: URL, item: GalleryItem?, size: CGSize, selected: Bool, focused: Bool, featured: Bool, dimmed: Bool) {
    self.url = url
    self.item = item
    self.size = size
    self.selected = selected
    self.focused = focused
    self.featured = featured
    self.dimmed = dimmed
    _image = State(initialValue: item.flatMap {
      GalleryThumbnails.shared.cached(url, pixels: Self.pixels(size, aspect: $0.aspect), modified: $0.modified)
    })
  }

  /// Filling the cell draws the picture's long side past the cell's.
  private static func pixels(_ size: CGSize, aspect: CGFloat) -> Int {
    let drawn = max(max(size.width, size.height * aspect), max(size.height, size.width / aspect))
    return GalleryThumbnails.pixels(for: min(drawn, 1024))
  }

  var body: some View {
    let pixels = item.map { Self.pixels(size, aspect: $0.aspect) } ?? 0
    ZStack {
      Color.white.opacity(0.06)
      if let image {
        Image(nsImage: image).resizable().interpolation(.medium).scaledToFill()
          .frame(width: size.width, height: size.height)
      }
      if item?.exists == false {
        Image(systemName: "questionmark.square.dashed").font(.title2).foregroundStyle(.white.opacity(0.5))
          .help("\(url.path) is gone")
      }
    }
    .frame(width: size.width, height: size.height)
    .clipped()
    .overlay(alignment: .bottomLeading) {
      if item?.isVideo == true {
        Image(systemName: "play.fill").font(.caption).foregroundStyle(.white).shadow(radius: 2).padding(6)
      }
    }
    .overlay(alignment: .topTrailing) {
      if featured {
        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).shadow(radius: 2).padding(6)
      }
    }
    .overlay {
      ZStack {
        if selected { Rectangle().strokeBorder(Color.accentColor, lineWidth: 3) }
        if focused { Rectangle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5).padding(selected ? 3 : 0) }
      }
      .allowsHitTesting(false)
    }
    .opacity(dimmed ? 0.45 : 1)
    // Waits for the file's shape and date, so it asks once at the right size.
    .task(id: "\(pixels)|\(item?.modified?.timeIntervalSince1970 ?? 0)|\(url.path)") {
      guard let item, item.exists else { return }
      if let loaded = await GalleryThumbnails.shared.image(for: url, pixels: pixels, modified: item.modified) {
        image = loaded
      }
    }
  }
}

private struct GalleryBar: View {
  @ObservedObject var model: ViewerModel
  @ObservedObject var gallery: GalleryModel
  @ObservedObject private var store = CollectionStore.shared

  var body: some View {
    HStack(spacing: 4) {
      Text(gallery.title).font(.headline).lineLimit(1).truncationMode(.middle)
      Text(count).font(.caption).foregroundStyle(.white.opacity(0.7)).fixedSize()
      Spacer(minLength: 8)
      ForEach(GalleryLayout.allCases) { layout in
        icon(layout.symbol, "\(layout.title) (L for the next)", on: gallery.layout == layout) {
          gallery.set(layout: layout)
        }
      }
      Divider().frame(height: 16).padding(.horizontal, 2)
      icon("minus", "Smaller (−)") { gallery.resize(by: -1) }
      icon("plus", "Bigger (+)") { gallery.resize(by: 1) }
      more
    }
    .controlSize(.small)
    .foregroundStyle(.white)
    .buttonStyle(.borderless)
    .padding(.leading, 78)
    .padding(.trailing, 10)
    .frame(height: 38)
    .background {
      ZStack {
        LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
        WindowDragArea()
      }
    }
  }

  private var count: String {
    let total = gallery.items.count
    let items = total == 1 ? "1 item" : "\(total) items"
    return gallery.selection.isEmpty ? items : "\(gallery.selection.count) of \(items) selected"
  }

  private var more: some View {
    Menu {
      Picker("Show As", selection: Binding(get: { model.mode }, set: { model.show($0) })) {
        ForEach(ViewMode.allCases) { Text("\($0.title)  ⌘\($0.key)").tag($0) }
      }
      .pickerStyle(.menu)
      Picker("Featured Size", selection: Binding(get: { gallery.share }, set: { gallery.set(share: $0) })) {
        ForEach(FeatureShare.allCases) { Text($0.title).tag($0) }
      }
      .pickerStyle(.menu)
      Divider()
      Button("Select All") { gallery.selectAll() }
      if !gallery.selection.isEmpty {
        AddToCollectionMenu(urls: { gallery.selected }, done: { gallery.show(status: $0) })
      }
      if gallery.isCollection {
        Button("Add Pictures or Movies…") {
          gallery.add(MediaMenu.chooseFiles(near: gallery.items.first ?? URL(fileURLWithPath: NSHomeDirectory() + "/")))
        }
      }
      Divider()
      Button(gallery.isCollection ? "Duplicate Collection…" : "Save as Collection…") { saveAs() }
      Menu("Open Collection") {
        ForEach(CollectionMenu.names(store), id: \.self) { name in
          Button(name) { ViewerController.shared.openCollection(name) }
        }
      }
      if gallery.isCollection {
        Button("Rename Collection…") { rename() }
        Button("Delete Collection…") { delete() }
      } else {
        Button("Show Removed Items") { gallery.showHidden() }.disabled(gallery.hidden.isEmpty)
        Button("Show Folder in Files") {
          if let url = gallery.focus ?? gallery.folder { BrowserController.shared.open(url) }
        }
      }
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help("More")
  }

  private func saveAs() {
    let title = gallery.isCollection ? "Duplicate Collection" : "Save as Collection"
    guard let name = CollectionPrompt.name(title, message: "Keeps this order and layout.",
                                           value: store.uniqueName(gallery.title))
    else { return }
    gallery.saveAsCollection(name)
  }

  private func rename() {
    guard let name = CollectionPrompt.name("Rename Collection", value: gallery.title) else { return }
    gallery.rename(to: name)
    model.retitle()
  }

  private func delete() {
    guard CollectionPrompt.confirmDelete(gallery.title) else { return }
    gallery.deleteCollection()
    model.onEmpty?()
  }

  private func icon(_ symbol: String, _ help: String, on: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .frame(width: 24, height: 24)
        .background(on ? Color.white.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
    }
    .help(help)
  }
}

/// A thumbnail's menu, acting on the selection when the thumbnail is in it.
private struct GalleryCellMenu: View {
  let model: ViewerModel
  let gallery: GalleryModel
  let urls: [URL]

  var body: some View {
    Button(urls.count == 1 ? "Open" : "Open \(urls.count) as Tiles") { model.open(urls) }
    Button("Open in New Window") { ViewerController.shared.open(urls) }
    Divider()
    Button(gallery.featured.isSuperset(of: urls) ? "Unfeature" : "Feature") { gallery.toggleFeatured(urls) }
    Button(gallery.isFavorite(urls) ? "Remove from Favorites" : "Add to Favorites") { gallery.toggleFavorite(urls) }
    AddToCollectionMenu(urls: { urls }, done: { gallery.show(status: $0) })
    Divider()
    Button("Move to Start") { gallery.move(urls, to: 0) }
    Button("Move to End") { gallery.move(urls, to: gallery.items.count) }
    Button(gallery.removeTitle) { gallery.remove(urls) }
    Divider()
    if let first = urls.first {
      Button("Show in Files") { BrowserController.shared.open(first) }
    }
    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    Button(urls.count == 1 ? "Copy" : "Copy \(urls.count) Files") { gallery.copy(urls) }
    Button("Move to Trash") { model.trash(urls) }
  }
}
