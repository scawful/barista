import Foundation
import XCTest
@testable import barista_agent

final class ActionRunnerTests: XCTestCase {
  private static let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("barista-action-tests-\(ProcessInfo.processInfo.processIdentifier)")

  override class func setUp() {
    super.setUp()
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    setenv("BARISTA_DOCK_ACTION_LOGS", scratch.appendingPathComponent("logs").path, 1)
  }

  override class func tearDown() {
    try? FileManager.default.removeItem(at: scratch)
    super.tearDown()
  }

  func testCaptureKeepsStdoutOnlyAndKillsAHungPipeline() {
    XCTAssertEqual(ActionRunner.capture("echo out; echo err >&2", timeout: 5), "out\n")
    XCTAssertNil(ActionRunner.capture("exit 3", timeout: 5))
    let start = Date()
    XCTAssertNil(ActionRunner.capture("sleep 30 | cat", timeout: 0.5))
    XCTAssertLessThan(Date().timeIntervalSince(start), 5, "the timeout ends the whole pipeline")
  }

  private func action(_ command: String, lock: String? = nil) -> DockItem {
    var item = DockItem(kind: .action, title: "Test", command: command)
    item.lock = lock
    return item
  }

  private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
  }

  private func alive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 }

  func testStopEndsTheWholeGroupAndLeavesOtherProcesses() throws {
    let pidFile = Self.scratch.appendingPathComponent("child.pid")
    let bystander = Process()
    bystander.executableURL = URL(fileURLWithPath: "/bin/sleep")
    bystander.arguments = ["30"]
    try bystander.run()
    defer { bystander.terminate() }

    let runner = ActionRunner()
    var finished: [String] = []
    runner.onFinish = { finished.append($0) }
    runner.run("stop-test", item: action("sleep 30 & echo $! > '\(pidFile.path)'; wait"), title: "Stop test")
    XCTAssertEqual(runner.states["stop-test"], .running)
    XCTAssertTrue(waitUntil { FileManager.default.fileExists(atPath: pidFile.path) })
    let child = try XCTUnwrap(pid_t(String(contentsOf: pidFile).trimmingCharacters(in: .whitespacesAndNewlines)))

    runner.stop("stop-test")
    XCTAssertEqual(runner.states["stop-test"], .stopping)
    XCTAssertTrue(waitUntil { !self.alive(child) }, "the action's child outlived Stop")
    XCTAssertTrue(waitUntil(ActionRunner.stopGrace + 5) { runner.states["stop-test"] == nil })
    XCTAssertEqual(finished, ["stop-test"])
    XCTAssertTrue(alive(bystander.processIdentifier), "Stop reached a process outside the group")
    let log = try String(contentsOf: runner.logURL(for: "stop-test"))
    XCTAssertTrue(log.contains("stopped from the dock"))
  }

  func testStopKillsAChildThatIgnoresTerm() throws {
    let pidFile = Self.scratch.appendingPathComponent("stubborn.pid")
    let runner = ActionRunner()
    let stubborn = "perl -e '$SIG{TERM}=\"IGNORE\"; open(F, \">\", $ARGV[0]); print F $$; close F; sleep 30' "
    runner.run("stubborn", item: action(stubborn + "'\(pidFile.path)' & wait"), title: "Stubborn")
    XCTAssertTrue(waitUntil { ((try? String(contentsOf: pidFile)) ?? "").isEmpty == false })
    let child = try XCTUnwrap(pid_t(String(contentsOf: pidFile)))

    let stopped = Date()
    runner.stop("stubborn")
    XCTAssertTrue(waitUntil { runner.states["stubborn"] == .stopping && kill(child, 0) == 0 })
    XCTAssertTrue(waitUntil(ActionRunner.stopGrace + 5) { runner.states["stubborn"] == nil })
    XCTAssertFalse(alive(child))
    XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(stopped), ActionRunner.stopGrace)
  }

  func testActionsSharingALockNeverOverlap() {
    let runner = ActionRunner()
    runner.run("build", item: action("sleep 5", lock: "oracle-roms"), title: "Build")
    runner.run("validate", item: action("true", lock: "oracle-roms"), title: "Validate")
    runner.run("other", item: action("true"), title: "Other")
    XCTAssertEqual(runner.states["build"], .running)
    XCTAssertNil(runner.states["validate"])
    XCTAssertTrue(waitUntil { runner.states["other"] == .succeeded })

    runner.stop("build")
    XCTAssertTrue(waitUntil { runner.states["build"] == nil })
    runner.run("validate", item: action("true", lock: "oracle-roms"), title: "Validate")
    XCTAssertTrue(waitUntil { runner.states["validate"] == .succeeded })
  }

  func testFailuresKeepTheirExitStatus() {
    let runner = ActionRunner()
    runner.run("fails", item: action("exit 3"), title: "Fails")
    XCTAssertTrue(waitUntil { runner.states["fails"] == .failed(3) })
  }

  func testMenuCommandEntriesDecodeWithDisabledReasons() {
    let output = """
    {"menu": [{"kind": "group", "title": "Debug Sessions", "items": [
      {"kind": "action", "title": "Maku", "command": "oos-session maku"},
      {"kind": "action", "title": "Kalyxo", "command": "oos-session kalyxo", "disabled": "no trusted save state"}
    ]}]}
    """
    let entries = ActionRunner.menuEntries(output)
    XCTAssertEqual(entries.first?.title, "Debug Sessions")
    XCTAssertEqual(entries.first?.items?.map(\.disabled), [nil, "no trusted save state"])
    XCTAssertEqual(ActionRunner.menuEntries("not json"), [])
    XCTAssertEqual(ActionRunner.menuEntries(nil), [])
  }
}
