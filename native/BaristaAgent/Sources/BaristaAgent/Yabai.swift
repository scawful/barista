import AppKit

struct YabaiWindow: Decodable, Identifiable, Equatable {
  let id: Int
  let pid: Int32
  let app: String
  let title: String
  let space: Int
  let isMinimized: Bool
  let subrole: String
  let hasFocus: Bool
  let isFloating: Bool
  let isSticky: Bool
  let hasFullscreenZoom: Bool

  enum CodingKeys: String, CodingKey {
    case id, pid, app, title, space, subrole
    case isMinimized = "is-minimized"
    case hasFocus = "has-focus"
    case isFloating = "is-floating"
    case isSticky = "is-sticky"
    case hasFullscreenZoom = "has-fullscreen-zoom"
  }
}

struct YabaiWindowState: Decodable, Equatable {
  let id: Int
  let app: String
  let isFloating: Bool
  let subLayer: String?

  enum CodingKeys: String, CodingKey {
    case id, app
    case isFloating = "is-floating"
    case subLayer = "sub-layer"
  }

  var level: WindowLevel? { subLayer.flatMap(WindowLevel.init(subLayer:)) }
}

/// A floating window's size, centered on its display as a yabai grid.
enum WindowSize: String, CaseIterable {
  case small, medium, large

  var title: String {
    switch self {
    case .small: return "Small (half the screen)"
    case .medium: return "Medium (two thirds)"
    case .large: return "Large (four fifths)"
    }
  }

  var grid: String {
    switch self {
    case .small: return "4:4:1:1:2:2"
    case .medium: return "6:6:1:1:4:4"
    case .large: return "10:10:1:1:8:8"
    }
  }
}

/// Where a window stacks, as `yabai_control.sh` names app levels and the
/// sub-layer each one is.
enum WindowLevel: String, CaseIterable {
  case normal, raised, top

  var title: String {
    switch self {
    case .normal: return "Normal"
    case .raised: return "Raised"
    case .top: return "Always on Top"
    }
  }

  var subLayer: String {
    switch self {
    case .normal: return "below"
    case .raised: return "normal"
    case .top: return "above"
    }
  }

  init?(subLayer: String) {
    guard let level = Self.allCases.first(where: { $0.subLayer == subLayer }) else { return nil }
    self = level
  }
}

struct YabaiSpace: Decodable, Identifiable, Equatable {
  let index: Int
  let label: String
  let display: Int
  let hasFocus: Bool
  var id: Int { index }

  enum CodingKeys: String, CodingKey {
    case index, label, display
    case hasFocus = "has-focus"
  }

  var name: String { label.isEmpty ? "Space \(index)" : "\(index) · \(label)" }

  /// A group's `spaces` entry names a space by index or label.
  func matches(_ names: [String]) -> Bool {
    names.contains { $0 == String(index) || (!label.isEmpty && $0 == label) }
  }
}

enum Yabai {
  static let binary: String = {
    if let override = ProcessInfo.processInfo.environment["BARISTA_YABAI_BIN"], !override.isEmpty {
      return override
    }
    return ["/opt/homebrew/bin/yabai", "/usr/local/bin/yabai"]
      .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "yabai"
  }()

  /// Barista's `yabai_control.sh`, which applies the bar's window rules and
  /// layout adoption around each yabai command.
  static let controlScript: String = {
    let env = ProcessInfo.processInfo.environment
    if let override = env["BARISTA_YABAI_CONTROL_SCRIPT"], !override.isEmpty { return override }
    return NSHomeDirectory() + "/.config/sketchybar/scripts/yabai_control.sh"
  }()

  @discardableResult
  /// Callers share a serial queue, so a hung yabai would stall every later
  /// refresh; the timeout terminates it and the read ends at its exit.
  static func run(_ arguments: [String], timeout: TimeInterval = 2) -> Data? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: binary)
    process.arguments = ["-m"] + arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    deadline.cancel()
    return process.terminationStatus == 0 ? data : nil
  }

  static func query<T: Decodable>(_ kind: String, as type: T.Type) -> T? {
    guard let data = run(["query", "--\(kind)"]) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  static let viewerRuleLabel = "barista-agent-viewer"

  /// Viewer windows float on the raised layer; the file browser tiles like
  /// any app window. Rules only reach windows created after them, and a yabai
  /// restart forgets them, so this runs before each viewer window opens.
  static func ensureViewerRule() {
    if let data = run(["rule", "--list"]),
       let rules = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
       rules.contains(where: { $0["label"] as? String == viewerRuleLabel }) {
      return
    }
    run(["rule", "--add", "label=\(viewerRuleLabel)", "app=^barista-agent$",
         "title=\(ViewerController.titleSuffix.trimmingCharacters(in: .whitespaces))$",
         "manage=off", "sub-layer=normal"])
  }

  static func runAsync(_ arguments: [String]) {
    DispatchQueue.global(qos: .userInitiated).async { run(arguments) }
  }

  /// What a menu shows about one of Barista's own windows, whose window
  /// number is yabai's id; nil when yabai doesn't answer in time.
  static func state(of window: NSWindow, timeout: TimeInterval = 0.4) -> YabaiWindowState? {
    guard let data = run(["query", "--windows", "--window", String(window.windowNumber)], timeout: timeout)
    else { return nil }
    return try? JSONDecoder().decode(YabaiWindowState.self, from: data)
  }

  static let sizeRulePrefix = "barista-size-"

  /// The grid rules that give each app in `sizes` its default size, and the
  /// labels of Barista's size rules in `existing` that no longer belong.
  /// The label names the size, so a rule that's there is the right one.
  /// Another app's size applies when its windows float; Barista's own rule
  /// floats Files windows at that size, and leaves viewers, which size to
  /// what they show, alone.
  static func sizeRuleChanges(_ sizes: [String: String], existing: [String]) -> (remove: [String], add: [[String]]) {
    var wanted: [String: [String]] = [:]
    for (app, name) in sizes {
      guard let size = WindowSize(rawValue: name) else { continue }
      let slug = app.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
      let label = sizeRulePrefix + slug + "-" + size.rawValue
      var rule = ["rule", "--add", "label=\(label)", "app=^\(NSRegularExpression.escapedPattern(for: app))$"]
      if app == "barista-agent" {
        rule += ["title=\(BrowserController.titleSuffix.trimmingCharacters(in: .whitespaces))$", "manage=off"]
      }
      wanted[label] = rule + ["grid=\(size.grid)"]
    }
    let ours = existing.filter { $0.hasPrefix(sizeRulePrefix) }
    return (ours.filter { wanted[$0] == nil }.sorted(),
            wanted.filter { !ours.contains($0.key) }.sorted { $0.key < $1.key }.map(\.value))
  }

  /// Brings yabai's rules in line with `sizes`. A yabai restart forgets
  /// rules, so this runs again now and then, not only on a change.
  static func syncSizeRules(_ sizes: [String: String]) {
    guard let data = run(["rule", "--list"]),
          let rules = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
    let changes = sizeRuleChanges(sizes, existing: rules.compactMap { $0["label"] as? String })
    for label in changes.remove { run(["rule", "--remove", label]) }
    for rule in changes.add { run(rule) }
  }

  /// Runs `yabai_control.sh` actions in order, each bound to its window the
  /// way the bar's window menu binds them, then calls `done` on the main queue.
  static func control(_ steps: [(arguments: [String], window: YabaiWindow?)], done: @escaping () -> Void = {}) {
    DispatchQueue.global(qos: .userInitiated).async {
      for step in steps {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [controlScript] + step.arguments
        var env = ProcessInfo.processInfo.environment
        if let window = step.window {
          env["BARISTA_TARGET_WINDOW_ID"] = String(window.id)
          env["BARISTA_TARGET_APP"] = window.app
        }
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        do {
          try process.run()
        } catch {
          DockStore.log("could not run \(controlScript): \(error)")
          break
        }
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
          let text = String(data: message, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          DockStore.log("yabai_control.sh \(step.arguments.joined(separator: " ")) failed: \(text)")
        }
      }
      DispatchQueue.main.async(execute: done)
    }
  }
}
