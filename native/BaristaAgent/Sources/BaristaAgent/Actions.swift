import AppKit

/// A line of status in a group's popover, from the group's `info_command`.
struct InfoRow: Decodable, Equatable, Identifiable {
  enum Tone: String {
    case ok, warn, error, none
  }

  var title: String
  var detail: String?
  var tone: Tone?
  /// What a click does, first one set wins: run the group member with this
  /// title, run this command in the background, or open this path or URL.
  var action: String?
  var run: String?
  var open: String?

  var id: String { title + "\u{1F}" + (detail ?? "") }
  var isClickable: Bool { [action, run, open].contains { !($0 ?? "").isEmpty } }

  enum CodingKeys: String, CodingKey {
    case title, detail, tone, action, run, open
  }

  init(title: String, detail: String? = nil, tone: Tone? = nil,
       action: String? = nil, run: String? = nil, open: String? = nil) {
    self.title = title
    self.detail = detail
    self.tone = tone
    self.action = action
    self.run = run
    self.open = open
  }

  /// An unknown tone reads as none instead of dropping the payload.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    detail = try container.decodeIfPresent(String.self, forKey: .detail)
    tone = try container.decodeIfPresent(String.self, forKey: .tone).flatMap(Tone.init(rawValue:))
    action = try container.decodeIfPresent(String.self, forKey: .action)
    run = try container.decodeIfPresent(String.self, forKey: .run)
    open = try container.decodeIfPresent(String.self, forKey: .open)
  }

  /// The `rows` of `{"rows": [...]}`; anything else shows nothing.
  static func decode(_ output: String?) -> [InfoRow] {
    struct Payload: Decodable { var rows: [InfoRow] }
    guard let data = output?.data(using: .utf8),
          let payload = try? JSONDecoder().decode(Payload.self, from: data)
    else { return [] }
    return payload.rows.filter { !$0.title.isEmpty }
  }
}

/// Runs action tiles and badge commands. Each action writes its output to
/// its own log and keeps its last result on the tile: a ring while it runs,
/// a check for a while after it passes, and a cross until you look at a
/// failure.
final class ActionRunner: ObservableObject {
  enum State: Equatable {
    case running
    /// Stop was sent; some of the action's processes are still exiting.
    case stopping
    case succeeded
    case failed(Int32)

    var isActive: Bool { self == .running || self == .stopping }
  }

  @Published private(set) var states: [String: State] = [:]
  /// Badge text by tile ID, from each tile's `badge_command`.
  @Published private(set) var badges: [String: String] = [:]
  /// Popover rows by group tile ID, from each group's `info_command`.
  @Published private(set) var infos: [String: [InfoRow]] = [:]
  /// Extra right-click entries by tile ID, from each tile's `menu_command`.
  @Published private(set) var menus: [String: [DockItem]] = [:]

  /// How long a passing action keeps its check.
  static let successShown: TimeInterval = 120
  static let badgeInterval: TimeInterval = 20
  static let badgeTimeout: TimeInterval = 5

  static let logDirectory: URL = {
    let env = ProcessInfo.processInfo.environment
    if let override = env["BARISTA_DOCK_ACTION_LOGS"], !override.isEmpty {
      return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
    }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Logs/sketchybar-barista/dock-actions")
  }()

  /// How long Stop waits after SIGTERM before it sends SIGKILL to the group.
  static let stopGrace: TimeInterval = 5

  /// Process group (the shell's pid) by running action ID.
  private var groups: [String: pid_t] = [:]
  /// Running actions' `lock` names.
  private var locks: [String: String] = [:]
  /// Stopping actions whose shell has exited.
  private var exited: Set<String> = []
  private var runs: [String: Int] = [:]
  private var badgeRuns: [String: TimeInterval] = [:]
  private let badgeQueue = DispatchQueue(label: "dev.barista.agent.badges", qos: .utility, attributes: .concurrent)

  /// Called on the main queue with the ID of each background run that ends.
  var onFinish: ((String) -> Void)?

  func run(_ tile: DockTile, arguments: [String]) {
    run(tile.id, item: tile.item, title: tile.name, arguments: arguments)
  }

  /// Runs an action item under any ID: a tile, a menu entry, or an info row.
  func run(_ id: String, item: DockItem, title: String, arguments: [String] = []) {
    guard let command = item.command, !command.isEmpty else { return }
    if item.terminal == true {
      Self.openTerminal(command, arguments: arguments)
      return
    }
    guard groups[id] == nil else { return }
    if let lock = item.lock, let holder = locks.first(where: { $0.value == lock })?.key {
      DockStore.log("\(title) waits: \(holder) holds \(lock)")
      NSSound.beep()
      return
    }
    let log = logURL(for: id)
    let output: Int32
    do {
      try FileManager.default.createDirectory(at: Self.logDirectory, withIntermediateDirectories: true)
      try Data("# \(Date()) \(title)\n$ \(command)\n\n".utf8).write(to: log)
      output = open(log.path, O_WRONLY | O_APPEND)
      guard output >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    } catch {
      DockStore.log("could not open \(log.path): \(error)")
      return
    }
    let spawned = Self.spawnGroup(["/bin/zsh", "-lc", command, "barista-dock"] + arguments, output: output)
    close(output)
    guard let pid = spawned else {
      DockStore.log("could not run dock action \(title): \(String(cString: strerror(errno)))")
      states[id] = .failed(-1)
      return
    }
    let generation = (runs[id] ?? 0) + 1
    runs[id] = generation
    groups[id] = pid
    if let lock = item.lock { locks[id] = lock }
    states[id] = .running
    let notify = item.notify == true
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let status = Self.wait(pid)
      DispatchQueue.main.async {
        guard let self else { return }
        let stopped = self.states[id] == .stopping
        self.rootExited(id, generation: generation, status: status)
        if notify, !stopped { Self.notify(title: title, passed: status == 0) }
      }
    }
  }

  /// Ends the action's whole process group (the shell and everything it
  /// started without leaving the group) and keeps the tile stopping until
  /// none of them is left. Apps launched through `open` or a new session are
  /// not in the group and keep running.
  func stop(_ id: String) {
    guard let group = groups[id], states[id] == .running else { return }
    states[id] = .stopping
    killpg(group, SIGTERM)
    drain(id, group: group, deadline: Date().addingTimeInterval(Self.stopGrace))
  }

  /// Opens the last run's output and clears a failure.
  func showOutput(_ id: String) {
    if case .failed = states[id] { states[id] = nil }
    let log = logURL(for: id)
    guard FileManager.default.fileExists(atPath: log.path) else {
      NSSound.beep()
      return
    }
    NSWorkspace.shared.open(log)
  }

  func hasOutput(_ id: String) -> Bool {
    FileManager.default.fileExists(atPath: logURL(for: id).path)
  }

  func logURL(for id: String) -> URL {
    Self.logDirectory.appendingPathComponent(Self.slug(id) + ".log")
  }

  /// `action:Build ROM` becomes `Build-ROM`; long IDs are cut to 80 characters.
  static func slug(_ id: String) -> String {
    var name = id.hasPrefix("action:") ? String(id.dropFirst(7)) : id
    if let tab = name.firstIndex(of: "\t") { name = String(name[..<tab]) }
    let parts = name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    return parts.isEmpty ? "action" : String(parts.joined(separator: "-").prefix(80))
  }

  /// The next refresh reruns every info and menu command, such as after an
  /// action that changes what they report.
  func expireInfos() {
    badgeRuns = badgeRuns.filter { !$0.key.hasPrefix("info:") && !$0.key.hasPrefix("menu:") }
  }

  /// Runs each tile's badge command unless it ran recently. Output arrives
  /// asynchronously, so a reveal never waits on a slow command.
  func refreshBadges(_ commands: [String: String], now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    if !Set(badges.keys).subtracting(commands.keys).isEmpty {
      badges = badges.filter { commands[$0.key] != nil }
    }
    poll(commands, prefix: "badge", now: now) { [weak self] id, output in
      let text = Self.badgeText(output)
      guard let self, self.badges[id] != text else { return }
      self.badges[id] = text
    }
  }

  /// Same schedule as badges, for groups' `info_command`.
  func refreshInfos(_ commands: [String: String], now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    if !Set(infos.keys).subtracting(commands.keys).isEmpty {
      infos = infos.filter { commands[$0.key] != nil }
    }
    poll(commands, prefix: "info", now: now) { [weak self] id, output in
      let rows = InfoRow.decode(output)
      guard let self, self.infos[id] != rows else { return }
      self.infos[id] = rows
    }
  }

  /// Same schedule as badges, for tiles' `menu_command`.
  func refreshMenus(_ commands: [String: String], now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
    if !Set(menus.keys).subtracting(commands.keys).isEmpty {
      menus = menus.filter { commands[$0.key] != nil }
    }
    poll(commands, prefix: "menu", now: now) { [weak self] id, output in
      let entries = Self.menuEntries(output)
      guard let self, self.menus[id] != entries else { return }
      self.menus[id] = entries
    }
  }

  /// `{"menu": [...]}` as dock items; anything else is no entries.
  static func menuEntries(_ output: String?) -> [DockItem] {
    struct Feed: Decodable { let menu: [DockItem] }
    guard let data = output?.data(using: .utf8),
          let feed = try? JSONDecoder().decode(Feed.self, from: data)
    else { return [] }
    return feed.menu
  }

  /// The first non-empty line, trimmed; empty output and `0` show no badge.
  static func badgeText(_ output: String?) -> String? {
    guard let line = output?.split(whereSeparator: \.isNewline)
      .map({ $0.trimmingCharacters(in: .whitespaces) })
      .first(where: { !$0.isEmpty }),
      line != "0"
    else { return nil }
    return String(line.prefix(8))
  }

  // MARK: Private

  private func poll(_ commands: [String: String], prefix: String, now: TimeInterval,
                    apply: @escaping (String, String?) -> Void) {
    for (id, command) in commands {
      let key = prefix + ":" + id
      guard now - (badgeRuns[key] ?? -.infinity) >= Self.badgeInterval else { continue }
      badgeRuns[key] = now
      badgeQueue.async {
        let output = Self.capture(command, timeout: Self.badgeTimeout)
        DispatchQueue.main.async { apply(id, output) }
      }
    }
  }

  /// Ghostty when it's installed, otherwise Terminal. Ghostty's window keeps
  /// a login shell open after the command exits; dropped files are `$1`, ...
  static func openTerminal(_ command: String, arguments: [String]) {
    let shell = ["/bin/zsh", "-lc", command + "\nexec /bin/zsh -l", "barista-dock"] + arguments
    let process = Process()
    if let ghostty = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
      process.arguments = ["-na", ghostty.path, "--args", "-e"] + shell
    } else {
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-e", "on run argv",
                           "-e", "tell application \"Terminal\" to do script (item 1 of argv)",
                           "-e", "tell application \"Terminal\" to activate",
                           "-e", "end run", shell.map(shellQuote).joined(separator: " ")]
    }
    do {
      try process.run()
    } catch {
      DockStore.log("could not open a terminal: \(error)")
    }
  }

  static func shellQuote(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private func rootExited(_ id: String, generation: Int, status: Int32) {
    exited.insert(id)
    // A stopping run ends in `drain`, once its whole group is gone.
    guard states[id] != .stopping else { return }
    finish(id, generation: generation, status: status)
  }

  private func drain(_ id: String, group: pid_t, deadline: Date) {
    let empty = killpg(group, 0) != 0 && errno == ESRCH
    if empty && exited.contains(id) {
      if let handle = try? FileHandle(forWritingTo: logURL(for: id)) {
        handle.seekToEndOfFile()
        handle.write(Data("\n# stopped from the dock\n".utf8))
        try? handle.close()
      }
      release(id)
      states[id] = nil
      onFinish?(id)
      return
    }
    if Date() > deadline { killpg(group, SIGKILL) }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.drain(id, group: group, deadline: deadline)
    }
  }

  private func release(_ id: String) {
    groups[id] = nil
    locks[id] = nil
    exited.remove(id)
  }

  private func finish(_ id: String, generation: Int, status: Int32) {
    release(id)
    onFinish?(id)
    guard runs[id] == generation else { return }
    states[id] = status == 0 ? .succeeded : .failed(status)
    guard status == 0 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.successShown) { [weak self] in
      guard let self, self.runs[id] == generation, self.states[id] == .succeeded else { return }
      self.states[id] = nil
    }
  }

  /// Starts `arguments` as the leader of a new process group in the home
  /// directory, with stdin from /dev/null, stdout to `output`, stderr to
  /// `output` too or to /dev/null (`quiet`), and no other descriptors from
  /// the agent.
  private static func spawnGroup(_ arguments: [String], output: Int32, quiet: Bool = false) -> pid_t? {
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT
                                                | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
    posix_spawnattr_setpgroup(&attributes, 0)
    var signals = sigset_t()
    sigfillset(&signals)
    posix_spawnattr_setsigdefault(&attributes, &signals)
    sigemptyset(&signals)
    posix_spawnattr_setsigmask(&attributes, &signals)
    var files: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&files)
    defer { posix_spawn_file_actions_destroy(&files) }
    posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_adddup2(&files, output, 1)
    if quiet {
      posix_spawn_file_actions_addopen(&files, 2, "/dev/null", O_WRONLY, 0)
    } else {
      posix_spawn_file_actions_adddup2(&files, output, 2)
    }
    posix_spawn_file_actions_addchdir_np(&files, FileManager.default.homeDirectoryForCurrentUser.path)
    let argv = arguments.map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    var pid: pid_t = 0
    let result = posix_spawn(&pid, arguments[0], &files, &attributes, argv, environ)
    guard result == 0 else {
      errno = result
      return nil
    }
    return pid
  }

  /// Blocks until `pid` exits; a signal reads as 128 + its number, like a shell.
  private static func wait(_ pid: pid_t) -> Int32 {
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    let signal = status & 0x7f
    return signal == 0 ? (status >> 8) & 0xff : 128 + signal
  }

  /// A command's stdout, or nil when it fails or outlives `timeout`. The
  /// timeout kills the whole process group: killing only the shell would
  /// leave a pipeline's other commands holding the pipe open, and the read
  /// would never end.
  static func capture(_ command: String, timeout: TimeInterval) -> String? {
    let pipe = Pipe()
    let spawned = spawnGroup(["/bin/zsh", "-lc", command], output: pipe.fileHandleForWriting.fileDescriptor,
                             quiet: true)
    try? pipe.fileHandleForWriting.close()
    guard let pid = spawned else { return nil }
    let deadline = DispatchWorkItem { killpg(pid, SIGKILL) }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let status = wait(pid)
    deadline.cancel()
    try? pipe.fileHandleForReading.close()
    return status == 0 ? String(data: data, encoding: .utf8) : nil
  }

  /// The agent has no bundle to post notifications from, so AppleScript posts them.
  private static func notify(title: String, passed: Bool) {
    launch("/usr/bin/osascript", ["-e", "on run argv",
                                  "-e", "display notification (item 1 of argv) with title (item 2 of argv)",
                                  "-e", "end run",
                                  passed ? "Finished" : "Failed; click its dock tile for the output", title])
  }
}
