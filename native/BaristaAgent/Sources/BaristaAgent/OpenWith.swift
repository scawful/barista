import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Barista's own choice of app for an extension, under one folder or
/// everywhere, which Barista Files uses before the system's default.
struct OpenRule: Codable, Equatable {
  /// Lowercased, without the dot.
  var ext: String
  /// `~`-abbreviated; nil applies everywhere.
  var folder: String?
  var app: String

  enum CodingKeys: String, CodingKey { case ext = "extension", folder, app }

  var folderPath: String? { folder.map { ($0 as NSString).expandingTildeInPath } }
  var appURL: URL { URL(fileURLWithPath: (app as NSString).expandingTildeInPath) }

  func applies(to file: URL) -> Bool {
    file.pathExtension.lowercased() == ext && (folderPath.map { file.isWithin(URL(fileURLWithPath: $0)) } ?? true)
  }
}

/// The rules, in `files.json` beside `dock.json`, where they can be edited
/// by hand: `{"open_with": [{"extension": "asm", "folder": "~/src/x", "app": "/Applications/Cursor.app"}]}`.
enum OpenRules {
  static let url = DockConfigFile.url.deletingLastPathComponent().appendingPathComponent("files.json")

  private struct File: Codable {
    var openWith: [OpenRule] = []
    enum CodingKeys: String, CodingKey { case openWith = "open_with" }
  }

  static func load(from url: URL = url) -> [OpenRule] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    return (try? JSONDecoder().decode(File.self, from: data))?.openWith ?? []
  }

  /// The deepest folder's rule for `file`, else the one for everywhere.
  static func rule(for file: URL, in rules: [OpenRule]) -> OpenRule? {
    rules.filter { $0.applies(to: file) }.max { ($0.folderPath?.count ?? -1) < ($1.folderPath?.count ?? -1) }
  }

  /// The app Barista opens `file` with, when a rule names one still installed.
  static func app(for file: URL, from url: URL = url) -> URL? {
    guard let app = rule(for: file, in: load(from: url))?.appURL,
          FileManager.default.fileExists(atPath: app.path) else { return nil }
    return app
  }

  /// Opens `ext` files under `folder` (everywhere when nil) with `app`, or
  /// with `app` nil drops that rule.
  static func set(_ app: URL?, ext: String, folder: URL?, in url: URL = url) throws {
    func abbreviated(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }
    let ext = ext.lowercased()
    let folder = folder.map { abbreviated($0.standardizedFileURL.path) }
    var rules = load(from: url)
    rules.removeAll { $0.ext == ext && $0.folder == folder }
    if let app { rules.append(OpenRule(ext: ext, folder: folder, app: abbreviated(app.path))) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try (encoder.encode(File(openWith: rules)) + Data("\n".utf8)).write(to: url, options: .atomic)
  }
}

/// The system's default apps, as Finder's Open With and Get Info show them.
enum DefaultApps {
  /// The apps that open `file`, its default first, then the editors Barista
  /// knows even when they don't claim the type.
  static func choices(for file: URL) -> [URL] {
    var apps = NSWorkspace.shared.urlForApplication(toOpen: file).map { [$0] } ?? []
    for app in NSWorkspace.shared.urlsForApplications(toOpen: file) + PopoverController.editors.map(\.app)
    where !apps.contains(app) {
      apps.append(app)
    }
    return Array(apps.prefix(24))
  }

  static func name(_ app: URL) -> String {
    FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
  }

  /// Finder's Change All: every file of `file`'s type opens in `app`, in
  /// every app. Asks first, as Finder does.
  static func changeAll(to app: URL, for file: URL, problem: @escaping (String) -> Void, done: @escaping () -> Void) {
    guard let type = (try? file.resourceValues(forKeys: [.contentTypeKey]))?.contentType else {
      return problem("macOS doesn't know what kind of file “\(file.lastPathComponent)” is.")
    }
    let alert = NSAlert()
    alert.messageText = "Change all \(description(of: file)) to open with “\(name(app))”?"
    alert.informativeText = "This is the system's default, so Finder and other apps follow it too."
    alert.addButton(withTitle: "Change All")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { error in
      DispatchQueue.main.async {
        if let error { problem("Couldn't change the default app: \(error.localizedDescription)") } else { done() }
      }
    }
  }

  /// What opening `file` in Barista Files uses, in words.
  static func opener(for file: URL) -> String {
    if let rule = OpenRules.rule(for: file, in: OpenRules.load()) {
      let scope = rule.folderPath.map { " in \(DisplayNames.name(of: URL(fileURLWithPath: $0)))" } ?? ""
      return "\(name(rule.appURL)) (Barista's choice\(scope))"
    }
    if ViewerKind.of(file) != nil { return "Barista Viewer" }
    return NSWorkspace.shared.urlForApplication(toOpen: file).map { "\(name($0)) (default)" } ?? "No app"
  }

  /// "“.asm” documents", or the type's name when there's no extension.
  static func description(of file: URL) -> String {
    let ext = file.pathExtension
    if !ext.isEmpty { return "“.\(ext)” documents" }
    return (try? file.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription ?? "documents like this"
  }
}

/// Open With: Barista's choice and the default first, then the other apps;
/// below them, changing which app opens files like this one.
struct OpenWithMenu: View {
  @ObservedObject var state: BrowserState
  let url: URL

  var body: some View {
    let apps = DefaultApps.choices(for: url)
    let preferred = NSWorkspace.shared.urlForApplication(toOpen: url)
    let rule = OpenRules.rule(for: url, in: OpenRules.load())
    Menu("Open With") {
      if let rule, FileManager.default.fileExists(atPath: rule.appURL.path) {
        Button("\(DefaultApps.name(rule.appURL)) (Barista)") { open(with: rule.appURL) }
      } else if ViewerKind.of(url) != nil {
        Button("Barista Viewer (Barista)") { ViewerController.shared.open(url) }
      }
      if let preferred {
        Button("\(DefaultApps.name(preferred)) (default)") { open(with: preferred) }
      }
      Divider()
      ForEach(apps.filter { $0 != preferred }, id: \.self) { app in
        Button(DefaultApps.name(app)) { open(with: app) }
      }
      Divider()
      ChangeAppMenu(file: url, folder: state.location, apps: apps, rule: rule) { state.problem = $0 }
    }
  }

  private func open(with app: URL) {
    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
  }
}

/// Which app opens files like `file`: the system's default for the type,
/// or Barista's for the extension, in `folder` or everywhere.
struct ChangeAppMenu: View {
  let file: URL
  let folder: URL
  let apps: [URL]
  let rule: OpenRule?
  let problem: (String) -> Void
  var changed: () -> Void = {}

  var body: some View {
    let ext = file.pathExtension.lowercased()
    Menu("Always Open With") {
      ForEach(apps, id: \.self) { app in
        Button(DefaultApps.name(app)) {
          DefaultApps.changeAll(to: app, for: file, problem: problem, done: changed)
        }
      }
    }
    .help("Finder's Change All: the system's default for \(DefaultApps.description(of: file))")
    if !ext.isEmpty {
      Menu("In Barista, Open .\(ext) With") {
        Section("In \(DisplayNames.name(of: folder))") {
          ForEach(apps, id: \.self) { app in
            Button(DefaultApps.name(app)) { set(app, ext: ext, folder: folder) }
          }
        }
        Section("Everywhere") {
          ForEach(apps, id: \.self) { app in
            Button(DefaultApps.name(app)) { set(app, ext: ext, folder: nil) }
          }
        }
        if let rule {
          Divider()
          Button("Stop Opening .\(ext) with \(DefaultApps.name(rule.appURL))") {
            set(nil, ext: ext, folder: rule.folderPath.map { URL(fileURLWithPath: $0) })
          }
        }
      }
      .help("Barista Files only; kept in \((OpenRules.url.path as NSString).abbreviatingWithTildeInPath)")
    }
  }

  private func set(_ app: URL?, ext: String, folder: URL?) {
    do {
      try OpenRules.set(app, ext: ext, folder: folder)
      changed()
    } catch {
      problem(error.localizedDescription)
    }
  }
}
