import AppKit

/// A mounted volume and how full it is, as Finder counts free space
/// (purgeable space included).
struct Volume: Identifiable, Equatable {
  let url: URL
  let name: String
  let total: Int64
  let available: Int64
  let ejectable: Bool

  var id: URL { url }
  var used: Int64 { max(0, total - available) }
  var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

  private static let keys: [URLResourceKey] = [
    .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    .volumeAvailableCapacityKey, .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsBrowsableKey,
  ]

  /// Blocking, and a network volume that went away can hold it up.
  static func mounted() -> [Volume] {
    let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                     options: [.skipHiddenVolumes]) ?? []
    return urls.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false,
            let total = values.volumeTotalCapacity, total > 0 else { return nil }
      let available = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init) ?? 0
      return Volume(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent, total: Int64(total),
                    available: available, ejectable: values.volumeIsEjectable == true || values.volumeIsRemovable == true)
    }
  }

  /// Free space on the volume holding `url`.
  static func available(at url: URL) -> Int64? {
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                   .volumeAvailableCapacityKey])
    return values?.volumeAvailableCapacityForImportantUsage ?? values?.volumeAvailableCapacity.map(Int64.init)
  }
}

/// Stops a folder walk: set on the main thread, read by the walker.
final class SizeRun: @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false

  var cancelled: Bool { lock.withLock { stopped } }

  func cancel() { lock.withLock { stopped = true } }
}

/// Reads the volumes one load at a time, at most every few seconds unless
/// one was mounted or unmounted, and tells every browser window.
final class VolumeMonitor: ObservableObject {
  static let shared = VolumeMonitor()

  @Published private(set) var volumes: [Volume] = []
  private let queue = DispatchQueue(label: "barista.volumes")
  private var loading = false
  private var loadedAt = Date.distantPast
  private var observers: [NSObjectProtocol] = []

  private init() {
    let center = NSWorkspace.shared.notificationCenter
    observers = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                 NSWorkspace.didRenameVolumeNotification].map { name in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refresh(force: true) }
    }
  }

  /// Free space changes as files come and go; a reload asks again.
  func refresh(force: Bool = false) {
    guard !loading, force || Date().timeIntervalSince(loadedAt) > 10 else { return }
    loading = true
    queue.async {
      let volumes = Volume.mounted()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.loading = false
        self.loadedAt = Date()
        if self.volumes != volumes { self.volumes = volumes }
      }
    }
  }

  static func eject(_ volume: Volume, failed: @escaping (String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
      } catch {
        DispatchQueue.main.async { failed("\(volume.name) couldn't be ejected: \(error.localizedDescription)") }
      }
    }
  }
}
