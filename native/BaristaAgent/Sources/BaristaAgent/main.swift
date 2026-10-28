import AppKit

/// Hands control back to the native Dock. The script restores the Dock's
/// settings before unloading this agent's LaunchAgent, which ends this process.
func useNativeDock() {
  let script = ProcessInfo.processInfo.environment["BARISTA_AGENT_SCRIPT"]
    ?? NSHomeDirectory() + "/.config/sketchybar/scripts/barista_agent.sh"
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/bin/bash")
  process.arguments = [script, "dock", "native"]
  try? process.run()
}

/// `barista-agent view|browse|open PATH` from a shell reaches the running
/// agent as a distributed notification whose object is the absolute path.
enum OpenRequest: String, CaseIterable {
  case view, browse, open

  var notification: Notification.Name { Notification.Name("dev.barista.agent.\(rawValue)") }

  /// Any process in the session can post these, so a request never runs code:
  /// folders browse, Markdown and images view, `open` hands other documents to
  /// their default app, and anything else is revealed in Finder. `browse` on a
  /// file shows it selected in its folder, like `open -R`.
  func route(_ path: String) -> LinkRoute {
    guard path.hasPrefix("/") else { return .ignore }
    let route = LinkRoute.local(URL(fileURLWithPath: path).standardizedFileURL)
    switch (self, route) {
    case (.browse, .browse), (.view, _): return route
    case (.browse, .view(let file)), (.browse, .reveal(let file)): return .browse(file)
    case (.browse, _): return .ignore
    case (.open, .reveal(let file)): return LinkRoute.runsCode(file) ? route : .external(file)
    case (.open, _): return route
    }
  }
}

final class AgentDelegate: NSObject, NSApplicationDelegate {
  private let store = DockStore()
  private lazy var dock = DockController(store: store, onUseNativeDock: useNativeDock)

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSWindow.allowsAutomaticWindowTabbing = false
    AgentWindows.installEditMenu()
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.dock.hide() }
    NotificationCenter.default.addObserver(forName: .browserAddToShelf, object: nil, queue: .main) { [weak self] note in
      if let urls = note.object as? [URL] { self?.store.shelf.add(urls) }
    }
    for request in OpenRequest.allCases {
      DistributedNotificationCenter.default().addObserver(forName: request.notification, object: nil,
                                                          queue: .main) { note in
        guard let path = note.object as? String else { return }
        request.route(path).perform()
      }
    }
    BrowserController.shared.dockPlaces = { [weak self] in
      guard let self else { return [] }
      return (self.store.pinned + self.store.others).flatMap { [$0] + $0.children }
        .filter { $0.item.kind == .folder }
        .compactMap { tile in tile.url.map { (tile.name, $0) } }
    }
    dock.start()
  }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case nil, "run":
  let app = NSApplication.shared
  let delegate = AgentDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.accessory)
  app.run()
case let command? where OpenRequest(rawValue: command) != nil && arguments.count == 2:
  let path = URL(fileURLWithPath: arguments[1],
                 relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL.path
  let me = ProcessInfo.processInfo.processIdentifier
  guard NSWorkspace.shared.runningApplications.contains(where: {
    $0.localizedName == "barista-agent" && $0.processIdentifier != me
  }) else {
    FileHandle.standardError.write(Data("barista-agent is not running; start it with barista_agent.sh dock barista\n".utf8))
    exit(1)
  }
  DistributedNotificationCenter.default().postNotificationName(
    OpenRequest(rawValue: command)!.notification, object: path, userInfo: nil, deliverImmediately: true)
default:
  FileHandle.standardError.write(Data("usage: barista-agent [run] | {view|browse|open} PATH\n".utf8))
  exit(2)
}
