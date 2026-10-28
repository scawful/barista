import Foundation

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
