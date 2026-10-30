import AppKit
import os

/// A mounted volume and how full it is, as Finder counts free space
/// (purgeable space included).
struct Volume: Identifiable, Equatable {
  let url: URL
  let name: String
  /// Zero when the volume doesn't say, as network and FUSE mounts often don't.
  let total: Int64
  let available: Int64
  let ejectable: Bool
  /// False for network and FUSE mounts (sshfs, a remote drive).
  var isLocal = true
  var isInternal = true
  /// A network mount whose server went away still lists but can't be read.
  var responding = true

  var id: URL { url }
  var used: Int64 { max(0, total - available) }
  var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
  var isStartup: Bool { url.path == "/" }

  /// Finder's sidebar symbols for each kind of volume.
  var symbol: String {
    if !responding { return "externaldrive.badge.xmark" }
    if !isLocal { return "network" }
    if isStartup || isInternal { return "internaldrive" }
    return "externaldrive"
  }

  /// Any mounted volume but the startup disk can be let go.
  var canEject: Bool { !isStartup && (ejectable || !isLocal || !isInternal) }

  private static let keys: [URLResourceKey] = [
    .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
    .volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsBrowsableKey,
    .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsReadOnlyKey,
  ]

  /// Blocking, and a network volume that went away can hold it up.
  static func mounted() -> [Volume] {
    let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                     options: [.skipHiddenVolumes]) ?? []
    return urls.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsBrowsable != false else { return nil }
      let isLocal = values.volumeIsLocal != false
      let total = Int64(values.volumeTotalCapacity ?? 0)
      // A local volume without a size is a system mount, not a drive.
      guard total > 0 || !isLocal else { return nil }
      let available = free(at: url, values)
      return Volume(url: url, name: values.volumeLocalizedName ?? url.lastPathComponent, total: total,
                    available: available, ejectable: values.volumeIsEjectable == true || values.volumeIsRemovable == true,
                    isLocal: isLocal, isInternal: values.volumeIsInternal ?? false,
                    responding: isLocal || (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil)
    }
  }

  /// The mounted volume holding `url`: the deepest whose root contains it.
  static func holding(_ url: URL, in volumes: [Volume]) -> Volume? {
    volumes.filter { url.isWithin($0.url) }.max { $0.url.path.count < $1.url.path.count }
  }

  /// Free space on the volume holding `url`. Asking costs about 15 ms (APFS
  /// counts purgeable space), so an answer stands for its volume a while.
  static func available(at url: URL) -> Int64? {
    let volume = (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume?.path
    let now = Date()
    if let volume, let known = freeSpace.withLock({ $0[volume] }), now.timeIntervalSince(known.at) < 20 {
      return known.bytes
    }
    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeIsLocalKey,
                                                   .volumeIsReadOnlyKey])
    let bytes = values.map { free(at: url, $0) }
    if let volume, let bytes { freeSpace.withLock { $0[volume] = (bytes, now) } }
    return bytes
  }

  private static let freeSpace = OSAllocatedUnfairLock(initialState: [String: (bytes: Int64, at: Date)]())

  /// The larger count: APFS's for important use adds purgeable space, but
  /// exFAT and other non-APFS drives answer it with zero. Network mounts and
  /// read-only disk images aren't asked: that lookup fails for them and logs
  /// a CacheDelete error on every read.
  static func free(at url: URL, _ values: URLResourceValues) -> Int64 {
    let plain = Int64(values.volumeAvailableCapacity ?? 0)
    guard values.volumeIsLocal != false, values.volumeIsReadOnly != true else { return plain }
    let important = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
      .volumeAvailableCapacityForImportantUsage
    return max(important ?? 0, plain)
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

  /// Disk Arbitration ejects drives; FUSE and some network mounts only
  /// unmount, which `diskutil` does for them.
  static func eject(_ volume: Volume, done: @escaping () -> Void = {}, failed: @escaping (String) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      var problem: String?
      do {
        try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
      } catch {
        problem = error.localizedDescription
        if !volume.isLocal {
          let unmount = Process()
          unmount.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
          unmount.arguments = ["unmount", volume.url.path]
          unmount.standardOutput = FileHandle.nullDevice
          unmount.standardError = FileHandle.nullDevice
          if (try? unmount.run()) != nil {
            unmount.waitUntilExit()
            if unmount.terminationStatus == 0 { problem = nil }
          }
        }
      }
      DispatchQueue.main.async {
        if let problem { failed("\(volume.name) couldn't be ejected: \(problem)") } else { done() }
        VolumeMonitor.shared.refresh(force: true)
      }
    }
  }
}
