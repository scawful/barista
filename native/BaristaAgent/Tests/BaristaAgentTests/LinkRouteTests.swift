import Foundation
import XCTest
@testable import barista_agent

final class LinkRouteTests: XCTestCase {
  private var folder: URL!

  override func setUpWithError() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("barista-links-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
    // A document's base, like the viewer's deletingLastPathComponent(), ends in a slash.
    folder = URL(fileURLWithPath: root.resolvingSymlinksInPath().path, isDirectory: true)
    try FileManager.default.createDirectory(at: folder.appendingPathComponent("Tool.app/Contents"),
                                            withIntermediateDirectories: true)
    for name in ["notes.md", "shot.png", "report.pdf", "run.command", "build.sh"] {
      try Data().write(to: folder.appendingPathComponent(name))
    }
    let script = folder.appendingPathComponent("tool")
    try Data("#!/bin/sh\n".utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: folder)
  }

  private func link(_ text: String) -> LinkRoute {
    LinkRoute.of(URL(string: text, relativeTo: folder)!, base: folder)
  }

  private func file(_ name: String) -> URL {
    folder.appendingPathComponent(name).standardizedFileURL
  }

  func testAnchorLinksStayInTheDocument() {
    XCTAssertEqual(link("#section"), .ignore)
  }

  func testDocumentLinksViewOrBrowse() {
    XCTAssertEqual(link("notes.md"), .view(file("notes.md")))
    XCTAssertEqual(link("notes.md#usage"), .view(file("notes.md")))
    XCTAssertEqual(link("shot.png"), .view(file("shot.png")))
    XCTAssertEqual(link("docs/"), .browse(file("docs")))
  }

  func testLinksNeverLaunchLocalPrograms() {
    XCTAssertEqual(link("Tool.app"), .reveal(file("Tool.app")))
    XCTAssertEqual(link("run.command"), .reveal(file("run.command")))
    XCTAssertEqual(link("report.pdf"), .reveal(file("report.pdf")))
    XCTAssertEqual(link("missing.md"), .ignore)
  }

  func testOnlyWebAndMailSchemesLeaveTheApp() {
    XCTAssertEqual(link("https://example.com"), .external(URL(string: "https://example.com")!))
    XCTAssertEqual(link("mailto:a@example.com"), .external(URL(string: "mailto:a@example.com")!))
    XCTAssertEqual(link("vscode://file/etc/passwd"), .ignore)
    XCTAssertEqual(link("httpx://example.com"), .ignore)
  }

  func testOpenRequestsNeverRunCode() {
    XCTAssertEqual(OpenRequest.open.route(file("report.pdf").path), .external(file("report.pdf")))
    for name in ["Tool.app", "run.command", "build.sh", "tool"] {
      XCTAssertEqual(OpenRequest.open.route(file(name).path), .reveal(file(name)), name)
    }
    XCTAssertEqual(OpenRequest.view.route(file("report.pdf").path), .reveal(file("report.pdf")))
    XCTAssertEqual(OpenRequest.view.route(file("notes.md").path), .view(file("notes.md")))
    XCTAssertEqual(OpenRequest.browse.route(file("docs").path), .browse(file("docs")))
    XCTAssertEqual(OpenRequest.browse.route(file("notes.md").path), .browse(file("notes.md")),
                   "browsing a file shows it in its folder")
    XCTAssertEqual(OpenRequest.browse.route(file("Tool.app").path), .browse(file("Tool.app")))
    XCTAssertEqual(OpenRequest.browse.route(file("missing.md").path), .ignore)
    XCTAssertEqual(OpenRequest.open.route("relative/notes.md"), .ignore)
  }
}
