import AppKit
import Combine

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
/// agent as a distributed notification whose object is the absolute path;
/// `view` with several paths sends them a line each and tiles the pictures
/// and movies among them in one window.
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
  static private(set) var shared: AgentDelegate?
  let store = DockStore()
  private lazy var dock = DockController(store: store, onUseNativeDock: useNativeDock)
  private var viewerSettings: AnyCancellable?

  override init() {
    super.init()
    Self.shared = self
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSWindow.allowsAutomaticWindowTabbing = false
    AgentWindows.installEditMenu()
    viewerSettings = store.$settings.sink { ViewerPreferences.shared.apply($0) }
    WindowMenu.sizes = { [weak self] in self?.store.settings.windowSizes ?? [:] }
    WindowMenu.setSize = { [weak self] app, size in self?.store.setWindowSize(app: app, size: size) }
    ViewerPreferences.shared.persist = { [weak self] zoom, loops in
      self?.store.updateSettings { settings in
        settings.viewerScrollZoom = zoom.rawValue
        settings.viewerLoopsMovies = loops
      }
    }
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.dock.hide() }
    NotificationCenter.default.addObserver(forName: .browserAddToShelf, object: nil, queue: .main) { [weak self] note in
      if let urls = note.object as? [URL] { self?.store.shelf.add(urls) }
    }
    for request in OpenRequest.allCases {
      DistributedNotificationCenter.default().addObserver(forName: request.notification, object: nil,
                                                          queue: .main) { note in
        guard let object = note.object as? String else { return }
        let paths = object.split(separator: "\n").map(String.init)
        if request == .view, paths.count > 1 {
          ViewerController.shared.open(paths.filter { $0.hasPrefix("/") }.map { URL(fileURLWithPath: $0).standardizedFileURL })
        } else {
          request.route(object).perform()
        }
      }
    }
    DistributedNotificationCenter.default().addObserver(forName: groupRequest, object: nil, queue: .main) { [weak self] note in
      if let title = note.object as? String { self?.dock.openGroup(titled: title) }
    }
    DistributedNotificationCenter.default().addObserver(forName: galleryRequest, object: nil, queue: .main) { note in
      guard let path = note.object as? String, path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else {
        return
      }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      if !ViewerController.shared.openGallery(url) {
        ViewerController.shared.openGallery(url.deletingLastPathComponent(), focus: url)
      }
    }
    DistributedNotificationCenter.default().addObserver(forName: collectionRequest, object: nil, queue: .main) { note in
      guard let name = note.object as? String else { return }
      if !ViewerController.shared.openCollection(name) { DockStore.log("collection: no collection named \(name)") }
    }
    BrowserController.shared.dockPlaces = { [weak self] in
      guard let self else { return [] }
      return (self.store.pinned + self.store.others).flatMap { [$0] + $0.descendants }
        .filter { $0.item.kind == .folder }
        .compactMap { tile in tile.url.map { (tile.name, $0) } }
    }
    dock.start()
  }
}

/// `barista-agent group TITLE` opens that group's callout; its object is the title.
let groupRequest = Notification.Name("dev.barista.agent.group")
/// `barista-agent gallery PATH` shows a folder's pictures and movies as
/// thumbnails, or a file's folder with that file chosen; its object is the
/// absolute path.
let galleryRequest = Notification.Name("dev.barista.agent.gallery")
/// `barista-agent collection NAME` shows a collection the way it was last
/// shown; its object is the name. Favorites is made when first asked for.
let collectionRequest = Notification.Name("dev.barista.agent.collection")

/// Hands a request to the running agent.
func post(_ name: Notification.Name, _ object: String) {
  let me = ProcessInfo.processInfo.processIdentifier
  guard NSWorkspace.shared.runningApplications.contains(where: {
    $0.localizedName == "barista-agent" && $0.processIdentifier != me
  }) else {
    FileHandle.standardError.write(Data("barista-agent is not running; start it with barista_agent.sh dock barista\n".utf8))
    exit(1)
  }
  DistributedNotificationCenter.default().postNotificationName(name, object: object, userInfo: nil,
                                                               deliverImmediately: true)
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case nil, "run":
  OverlayScrollers.install()
  let app = NSApplication.shared
  let delegate = AgentDelegate()
  app.delegate = delegate
  app.setActivationPolicy(.accessory)
  app.run()
case let command? where OpenRequest(rawValue: command) != nil && arguments.count == 2
  || command == OpenRequest.view.rawValue && arguments.count > 2:
  let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  let paths = arguments.dropFirst().map { URL(fileURLWithPath: $0, relativeTo: here).standardizedFileURL.path }
  post(OpenRequest(rawValue: command)!.notification, paths.joined(separator: "\n"))
case "group" where arguments.count == 2:
  post(groupRequest, arguments[1])
case "gallery" where arguments.count == 2:
  let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  post(galleryRequest, URL(fileURLWithPath: arguments[1], relativeTo: here).standardizedFileURL.path)
case "collection" where arguments.count == 2:
  post(collectionRequest, arguments[1])
default:
  FileHandle.standardError.write(Data(("usage: barista-agent [run] | {view|browse|open|gallery} PATH | view PATH... "
    + "| group TITLE | collection NAME\n").utf8))
  exit(2)
}
