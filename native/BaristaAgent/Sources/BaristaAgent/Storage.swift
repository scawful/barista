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

/// An SSHFS remote the `mounts` tool (~/src/tools/mounts) knows, mounted or
/// not. The tool does the mounting, so the watchdog and the shell agree.
struct RemoteMount: Identifiable, Equatable {
  /// The tool's name for it, which is also the command that mounts it: "mm-d".
  let name: String
  /// The volume name it mounts as: "MM-D".
  let title: String
  /// Host and path: "mm:/D:/".
  let source: String
  let url: URL

  var id: String { name }

  /// Reads `mounts status`: a name, a state, a volume name, and a source per
  /// remote, then "Mount points: <folder>".
  static func parse(_ status: String) -> [RemoteMount] {
    let lines = status.split(separator: "\n").map(String.init)
    let prefix = "Mount points: "
    guard let folder = lines.first(where: { $0.hasPrefix(prefix) })?.dropFirst(prefix.count) else { return [] }
    let base = URL(fileURLWithPath: folder.trimmingCharacters(in: .whitespaces), isDirectory: true)
    return lines.compactMap { line in
      let fields = line.split(separator: " ").map(String.init)
      guard fields.count >= 4, ["mounted", "not-mounted", "stale"].contains(fields[1]) else { return nil }
      return RemoteMount(name: fields[0], title: fields[2], source: fields[3...].joined(separator: " "),
                         url: base.appendingPathComponent(fields[0], isDirectory: true))
    }
  }

  /// BARISTA_MOUNTS_TOOL, else `mounts` on a tool path, else its checkout.
  static let tool: String? = {
    let files = FileManager.default
    if let set = ProcessInfo.processInfo.environment["BARISTA_MOUNTS_TOOL"], files.isExecutableFile(atPath: set) {
      return set
    }
    let checkout = files.homeDirectoryForCurrentUser.path + "/src/tools/mounts/mounts"
    return Tool.find("mounts") ?? (files.isExecutableFile(atPath: checkout) ? checkout : nil)
  }()

  /// The tool's remotes; none without the tool. Blocking.
  static func known() -> [RemoteMount] {
    let result = run(["status"], within: 20)
    return result.ok ? parse(result.output) : []
  }

  /// Mounts `remote`, or remounts it when its server stopped answering. Nil
  /// once it answers, else why not. Blocking.
  static func connect(_ remote: RemoteMount) -> String? {
    let result = run([remote.name], within: 40)
    guard !result.ok else { return nil }
    let last = result.output.split(separator: "\n").last.map(String.init) ?? "the mounts tool failed"
    return "\(remote.title) couldn't connect: \(last)"
  }

  /// Runs the tool with Homebrew on PATH, where sshfs and `timeout` live, and
  /// its output in a file: sshfs stays behind holding it, so a pipe would
  /// never end. Blocking, for at most `seconds`.
  private static func run(_ arguments: [String], within seconds: Int) -> (ok: Bool, output: String) {
    guard let tool else { return (false, "The mounts tool isn't installed.") }
    let files = FileManager.default
    let log = files.temporaryDirectory.appendingPathComponent("barista-mounts-\(UUID().uuidString).log")
    guard files.createFile(atPath: log.path, contents: nil), let handle = try? FileHandle(forWritingTo: log) else {
      return (false, "The mounts tool couldn't start.")
    }
    defer { try? files.removeItem(at: log) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
    process.environment = environment
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = handle
    process.standardError = handle
    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }
    do { try process.run() } catch {
      try? handle.close()
      return (false, error.localizedDescription)
    }
    try? handle.close()
    if finished.wait(timeout: .now() + .seconds(seconds)) == .timedOut {
      process.terminate()
      return (false, "the server didn't answer in \(seconds) seconds")
    }
    return (process.terminationStatus == 0, (try? String(contentsOf: log, encoding: .utf8)) ?? "")
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
  /// The `mounts` tool's remotes. Its list rarely changes, and asking checks
  /// every mounted one, so it's read every few minutes, apart from volumes.
  @Published private(set) var remotes: [RemoteMount] = []
  /// Names of the remotes being mounted.
  @Published private(set) var connecting: Set<String> = []
  private let queue = DispatchQueue(label: "barista.volumes")
  private var loading = false
  private var loadedAt = Date.distantPast
  private var loadingRemotes = false
  private var remotesAt = Date.distantPast
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
    refreshRemotes()
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

  private func refreshRemotes() {
    guard RemoteMount.tool != nil, !loadingRemotes, Date().timeIntervalSince(remotesAt) > 300 else { return }
    loadingRemotes = true
    DispatchQueue.global(qos: .utility).async {
      let remotes = RemoteMount.known()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.loadingRemotes = false
        self.remotesAt = Date()
        if self.remotes != remotes { self.remotes = remotes }
      }
    }
  }

  /// The remote a mounted volume came from.
  func remote(for volume: Volume) -> RemoteMount? {
    remotes.first { $0.url.standardizedFileURL.path == volume.url.standardizedFileURL.path }
  }

  /// The remotes that aren't mounted now.
  var offline: [RemoteMount] {
    let mounted = Set(volumes.map(\.url.standardizedFileURL.path))
    return remotes.filter { !mounted.contains($0.url.standardizedFileURL.path) }
  }

  /// Mounts `remote`, or remounts it when its server stopped answering.
  func connect(_ remote: RemoteMount, done: @escaping () -> Void, failed: @escaping (String) -> Void) {
    guard !connecting.contains(remote.name) else { return }
    connecting.insert(remote.name)
    DispatchQueue.global(qos: .userInitiated).async {
      let problem = RemoteMount.connect(remote)
      DispatchQueue.main.async { [weak self] in
        self?.connecting.remove(remote.name)
        if let problem { failed(problem) } else { done() }
        self?.refresh(force: true)
      }
    }
  }

  /// Disk Arbitration ejects drives; FUSE and some network mounts only
  /// unmount, which `diskutil` does for them, by force once their server
  /// stopped answering.
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
          unmount.arguments = volume.responding ? ["unmount", volume.url.path] : ["unmount", "force", volume.url.path]
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
