import AppKit
import UniformTypeIdentifiers

/// Where a clicked link or an open request goes. Clicking text in a document,
/// or a request from another process, must never launch a program: local files
/// only reach the viewer or the file browser, and anything else is revealed in
/// Finder.
enum LinkRoute: Equatable {
  case ignore
  case view(URL)
  case browse(URL)
  case external(URL)
  case reveal(URL)

  /// A link in a document whose relative links resolve against `base`.
  static func of(_ url: URL, base: URL) -> LinkRoute {
    guard url.isFileURL else {
      return ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .external(url) : .ignore
    }
    let file = URL(fileURLWithPath: url.path).standardizedFileURL
    if url.fragment != nil, file.path == base.standardizedFileURL.path { return .ignore }
    return local(file)
  }

  /// An existing folder browses and a viewer file views; missing files are ignored.
  static func local(_ file: URL) -> LinkRoute {
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder) else { return .ignore }
    if isFolder.boolValue && !NSWorkspace.shared.isFilePackage(atPath: file.path) { return .browse(file) }
    return ViewerKind.of(file) == nil ? .reveal(file) : .view(file)
  }

  /// Apps, scripts, and executables, which opening would run.
  static func runsCode(_ file: URL) -> Bool {
    var isFolder: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isFolder)
    if exists && !isFolder.boolValue && FileManager.default.isExecutableFile(atPath: file.path) { return true }
    if ["command", "terminal", "tool", "webloc", "inetloc", "fileloc", "workflow", "pkg", "mpkg"]
      .contains(file.pathExtension.lowercased()) { return true }
    guard let type = UTType(filenameExtension: file.pathExtension) else { return false }
    return [UTType.application, .applicationBundle, .executable, .script].contains { type.conforms(to: $0) }
  }

  func perform() {
    switch self {
    case .ignore: break
    case .view(let url): ViewerController.shared.open(url)
    case .browse(let url): BrowserController.shared.open(url)
    case .external(let url): NSWorkspace.shared.open(url)
    case .reveal(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
    }
  }
}
