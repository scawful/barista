import XCTest
@testable import barista_agent

final class DockSceneTests: XCTestCase {
  private let input = DockScene.Input(pinned: ["a", "b", "c", "d"], trash: ["trash"],
                                      icon: 44, magnification: 1.6, spacing: 4)
  private var now: CFTimeInterval = 100

  /// Steps at 120 Hz; returns whether the scene still wanted frames at the end.
  @discardableResult
  private func run(_ scene: DockScene, seconds: Double) -> Bool {
    var more = true
    for _ in 0..<Int(seconds * 120) {
      now += 1.0 / 120
      more = scene.step(now: now)
    }
    return more
  }

  private func makeScene() -> DockScene {
    let scene = DockScene()
    scene.currentTime = { [unowned self] in now }
    scene.update(input)
    return scene
  }

  private func revealed() -> DockScene {
    let scene = makeScene()
    scene.show()
    run(scene, seconds: 1.5)
    return scene
  }

  private func rect(_ scene: DockScene, _ id: String) -> CGRect {
    scene.frame.items.first { $0.id == id }?.rect ?? .null
  }

  func testRevealSettlesThenStopsAskingForFrames() {
    let scene = makeScene()
    scene.show()
    XCTAssertTrue(scene.frame.items.allSatisfy { $0.rise == 0 }, "the first frame is hidden")
    XCTAssertFalse(run(scene, seconds: 1.5))
    XCTAssertTrue(scene.frame.items.allSatisfy { abs($0.rise - 1) < 0.01 && $0.opacity > 0.99 })
    XCTAssertEqual(scene.frame.items.map(\.id), ["a", "b", "c", "d", "divider.1", "trash"])
  }

  func testMagnificationEasesInUnderThePointer() {
    let scene = revealed()
    let rest = rect(scene, "b")
    scene.setPointer(CGPoint(x: rest.midX, y: rest.midY))
    run(scene, seconds: 1 / 60)
    let early = rect(scene, "b").width
    run(scene, seconds: 0.5)
    let full = rect(scene, "b").width
    XCTAssertGreaterThan(early, rest.width)
    XCTAssertLessThan(early, full, "magnification eases in rather than jumping")
    XCTAssertEqual(full, 44 * 1.6 + DockLayout.inset * 2, accuracy: 1)
    XCTAssertEqual(scene.frame.hoveredID, "b")
  }

  func testCalloutAnchorFollowsTheTileAsDrawn() {
    let scene = revealed()
    let rest = rect(scene, "b")
    XCTAssertEqual(scene.anchor(of: "b"), CGPoint(x: rest.midX, y: min(rest.minY, scene.frame.bar.minY) - 2))
    scene.setPointer(CGPoint(x: rest.midX, y: rest.midY))
    run(scene, seconds: 0.5)
    let grown = rect(scene, "b")
    XCTAssertEqual(scene.anchor(of: "b"), CGPoint(x: grown.midX, y: grown.minY - 2),
                   "a magnified tile rises above the bar, and so does its callout")
    XCTAssertNil(scene.anchor(of: "missing"))
  }

  func testDragReordersCommitsAndLowersThePanelAfterLanding() {
    let scene = revealed()
    var lifts: [Bool] = []
    var outcomes: [DockScene.Outcome] = []
    scene.onLiftChange = { lifts.append($0) }
    scene.onCommit = { outcomes.append($0) }

    let start = CGPoint(x: 500, y: 20)
    scene.dragChanged(id: "a", scope: .list(.pinned), mouse: start, translation: .zero)
    scene.dragChanged(id: "a", scope: .list(.pinned), mouse: CGPoint(x: 620, y: 20), translation: CGSize(width: 120, height: 0))
    run(scene, seconds: 0.5)
    XCTAssertEqual(scene.frame.items.prefix(4).map(\.id), ["b", "c", "a", "d"])
    XCTAssertEqual(scene.frame.draggedID, "a")
    XCTAssertEqual(lifts, [true])

    scene.dragEnded(commit: true)
    XCTAssertEqual(outcomes, [.move(id: "a", scope: .list(.pinned), index: 2)])
    XCTAssertTrue(scene.isDragging, "the panel stays tall while the tile lands")
    run(scene, seconds: 1)
    XCTAssertEqual(lifts, [true, false])
    XCTAssertFalse(scene.isDragging)
    XCTAssertEqual(scene.frame.items.prefix(4).map(\.id), ["b", "c", "a", "d"], "the new order holds before the store confirms")
  }

  func testDraggingWellAboveRemovesAndCancelDoesNothing() {
    let scene = revealed()
    var outcomes: [DockScene.Outcome] = []
    scene.onCommit = { outcomes.append($0) }

    scene.dragChanged(id: "c", scope: .list(.pinned), mouse: CGPoint(x: 500, y: 20), translation: .zero)
    scene.dragChanged(id: "c", scope: .list(.pinned), mouse: CGPoint(x: 500, y: 90), translation: CGSize(width: 0, height: -70))
    run(scene, seconds: 0.1)
    XCTAssertTrue(scene.frame.removing)
    scene.dragEnded(commit: false)
    XCTAssertEqual(outcomes, [])

    scene.dragChanged(id: "c", scope: .list(.pinned), mouse: CGPoint(x: 500, y: 20), translation: .zero)
    scene.dragChanged(id: "c", scope: .list(.pinned), mouse: CGPoint(x: 500, y: 90), translation: CGSize(width: 0, height: -70))
    scene.dragEnded(commit: true)
    XCTAssertEqual(outcomes, [.remove(id: "c")])
    run(scene, seconds: 1)
    XCTAssertFalse(scene.frame.items.contains { $0.id == "c" })
  }

  func testDroppingOnAGroupsMiddleAddsToItAndItsEdgesStillReorder() {
    var grouped = input
    grouped.groups = ["c"]
    let scene = makeScene()
    scene.update(grouped)
    scene.show()
    run(scene, seconds: 1.5)
    var outcomes: [DockScene.Outcome] = []
    scene.onCommit = { outcomes.append($0) }
    let a = rect(scene, "a"), c = rect(scene, "c")
    let start = CGPoint(x: 500, y: 20)

    // Past the group's edge: an ordinary reorder, nothing highlighted.
    let edge = c.midX - a.midX + c.width * 0.4
    scene.dragChanged(id: "a", scope: .list(.pinned), mouse: start, translation: .zero)
    scene.dragChanged(id: "a", scope: .list(.pinned), mouse: CGPoint(x: start.x + edge, y: start.y),
                      translation: CGSize(width: edge, height: 0))
    run(scene, seconds: 0.1)
    XCTAssertNil(scene.frame.intoID)

    // Over its middle: the group lights up and the order stays put.
    let middle = c.midX - a.midX
    scene.dragChanged(id: "a", scope: .list(.pinned), mouse: CGPoint(x: start.x + middle, y: start.y),
                      translation: CGSize(width: middle, height: 0))
    run(scene, seconds: 0.5)
    XCTAssertEqual(scene.frame.intoID, "c")
    XCTAssertEqual(rect(scene, "c").midX, c.midX, accuracy: 1)
    scene.dragEnded(commit: true)
    XCTAssertEqual(outcomes, [.group(id: "a", into: "c")])
    run(scene, seconds: 1)
    XCTAssertFalse(scene.frame.items.contains { $0.id == "a" })
    XCTAssertNil(scene.frame.intoID)
  }

  func testTilesSlideFromWhereTheyWereWhenTheOrderChanges() {
    let scene = revealed()
    let trashBefore = rect(scene, "trash")
    var launched = input
    launched.running = ["x"]
    scene.update(launched)
    run(scene, seconds: 1 / 120)
    XCTAssertEqual(rect(scene, "trash").midX, trashBefore.midX, accuracy: 2, "no jump on the first frame")
    XCTAssertLessThan(scene.frame.items.first { $0.id == "x" }?.opacity ?? 1, 0.2, "new tiles fade in")
    run(scene, seconds: 1)
    XCTAssertGreaterThan(rect(scene, "trash").midX, trashBefore.midX + 40)
    XCTAssertEqual(scene.frame.items.first { $0.id == "x" }?.opacity ?? 0, 1, accuracy: 0.01)
  }

  func testMinimizedWindowsGetASectionBeforeTheTrash() {
    var docked = input
    docked.others = ["f"]
    docked.minimized = ["w1", "w2"]
    XCTAssertEqual(docked.sections, [["a", "b", "c", "d"], [], ["f"], ["w1", "w2"], ["trash"]])

    let scene = DockScene()
    scene.currentTime = { [unowned self] in now }
    scene.update(docked)
    scene.show()
    run(scene, seconds: 1.5)
    XCTAssertEqual(scene.frame.items.map(\.id),
                   ["a", "b", "c", "d", "divider.1", "f", "divider.2", "w1", "w2", "divider.3", "trash"])
  }

  func testSystemTilesShareTheTrashSectionAndReorderAmongThemselves() {
    var docked = input
    docked.system = ["shelf", "controls"]
    XCTAssertEqual(docked.sections, [["a", "b", "c", "d"], [], [], [], ["shelf", "controls", "trash"]])

    let scene = DockScene()
    scene.currentTime = { [unowned self] in now }
    scene.update(docked)
    scene.show()
    run(scene, seconds: 1.5)
    XCTAssertEqual(scene.frame.items.map(\.id), ["a", "b", "c", "d", "divider.1", "shelf", "controls", "trash"])
    XCTAssertEqual(scene.insertionIndex(in: .system, x: .greatestFiniteMagnitude), 2)
  }

  func testAnOpenGroupGetsItsOwnSectionAndKeepsItsPlaceInDrags() {
    var open = input
    open.pinned = ["a", "g", "b"]
    open.others = ["f"]
    open.expanded = ["g": ["m1", "m2"]]
    XCTAssertEqual(open.sections, [["a"], ["m1", "m2"], ["b"], [], ["f"], [], ["trash"]])

    let scene = DockScene()
    scene.currentTime = { [unowned self] in now }
    scene.update(open)
    scene.show()
    run(scene, seconds: 1.5)
    XCTAssertEqual(scene.frame.items.map(\.id),
                   ["a", "divider.1", "m1", "m2", "divider.2", "b", "divider.3", "f", "divider.4", "trash"])

    var outcomes: [DockScene.Outcome] = []
    scene.onCommit = { outcomes.append($0) }
    let start = rect(scene, "b")
    let target = rect(scene, "a").midX - 10
    scene.dragChanged(id: "b", scope: .list(.pinned), mouse: CGPoint(x: 500, y: 20), translation: .zero)
    scene.dragChanged(id: "b", scope: .list(.pinned), mouse: CGPoint(x: 500 + target - start.midX, y: 20),
                      translation: CGSize(width: target - start.midX, height: 0))
    scene.dragEnded(commit: true)
    XCTAssertEqual(outcomes, [.move(id: "b", scope: .list(.pinned), index: 0)], "the open group counts as one slot")
    run(scene, seconds: 1)
    XCTAssertEqual(scene.frame.items.prefix(3).map(\.id), ["b", "a", "divider.1"])

    let member = rect(scene, "m1")
    let past = rect(scene, "m2").midX + 10
    scene.dragChanged(id: "m1", scope: .group("g"), mouse: CGPoint(x: 500, y: 20), translation: .zero)
    scene.dragChanged(id: "m1", scope: .group("g"), mouse: CGPoint(x: 500 + past - member.midX, y: 20),
                      translation: CGSize(width: past - member.midX, height: 0))
    scene.dragEnded(commit: true)
    XCTAssertEqual(outcomes.last, .move(id: "m1", scope: .group("g"), index: 1), "members reorder inside their group")
    run(scene, seconds: 1)
    XCTAssertEqual(scene.frame.items.map(\.id).filter { $0.hasPrefix("m") }, ["m2", "m1"])

    scene.dragChanged(id: "m2", scope: .group("g"), mouse: CGPoint(x: 500, y: 20), translation: .zero)
    scene.dragChanged(id: "m2", scope: .group("g"), mouse: CGPoint(x: 500, y: 90), translation: CGSize(width: 0, height: -70))
    scene.dragEnded(commit: true)
    XCTAssertEqual(outcomes.last, .remove(id: "m2"))
    run(scene, seconds: 1)
    XCTAssertFalse(scene.frame.items.contains { $0.id == "m2" })
  }

  func testAttentionHopsOnceAfterTheRevealLands() {
    var asking = input
    asking.attention = ["c"]
    let scene = DockScene()
    scene.currentTime = { [unowned self] in now }
    scene.update(asking)
    scene.show()
    run(scene, seconds: 0.4)
    let rest = rect(scene, "b").minY
    XCTAssertEqual(rect(scene, "c").minY, rest, accuracy: 0.5, "no hop while the dock rises")
    run(scene, seconds: 0.2)
    XCTAssertLessThan(rect(scene, "c").minY, rest - 5, "then it hops")
    XCTAssertFalse(run(scene, seconds: 2), "and settles")
    XCTAssertEqual(rect(scene, "c").minY, rest, accuracy: 0.5)
    run(scene, seconds: 1)
    XCTAssertEqual(rect(scene, "c").minY, rest, accuracy: 0.5, "once per reveal")
  }

  func testRestingRectMatchesTheSettledUnmagnifiedTile() {
    let scene = revealed()
    XCTAssertEqual(scene.restingRect(of: "c"), rect(scene, "c"))
    scene.setPointer(CGPoint(x: rect(scene, "a").midX, y: rect(scene, "a").midY))
    run(scene, seconds: 1)
    XCTAssertNotEqual(rect(scene, "a").width, scene.restingRect(of: "a")?.width, "magnified while hovered")
    XCTAssertNil(scene.restingRect(of: "missing"))
  }

  func testHideDropsEverythingAndStops() {
    let scene = revealed()
    scene.hide()
    XCTAssertFalse(run(scene, seconds: 0.3))
    XCTAssertTrue(scene.frame.items.allSatisfy { $0.rise == 0 && $0.opacity == 0 })
    XCTAssertFalse(scene.step(now: now + 1), "a hidden scene asks for no frames")
  }

  func testEdgeTriggerNeedsAPushOrARest() {
    var trigger = EdgeTrigger()
    XCTAssertFalse(trigger.update(deltaY: 30, now: 0, push: 10, delay: 0.5), "arriving at the edge is not a push")
    XCTAssertFalse(trigger.update(deltaY: 4, now: 0.05, push: 10, delay: 0.5))
    XCTAssertFalse(trigger.update(deltaY: -20, now: 0.1, push: 10, delay: 0.5), "moving up does not count")
    XCTAssertTrue(trigger.update(deltaY: 6, now: 0.15, push: 10, delay: 0.5))

    trigger.reset()
    XCTAssertFalse(trigger.update(deltaY: 0, now: 1, push: 10, delay: 0.5))
    XCTAssertTrue(trigger.update(deltaY: 0, now: 1.5, push: 10, delay: 0.5), "resting reveals too")

    trigger.reset()
    XCTAssertTrue(trigger.update(deltaY: 0, now: 2, push: 0, delay: 0.5), "push 0 reveals on touch")
  }

  func testEdgeTriggerPreservesSinceUntilReset() {
    var trigger = EdgeTrigger()
    XCTAssertNil(trigger.since)
    _ = trigger.update(deltaY: 5, now: 10.0, push: 10, delay: 0.5)
    XCTAssertEqual(trigger.since, 10.0)
    _ = trigger.update(deltaY: 2, now: 10.2, push: 10, delay: 0.5)
    XCTAssertEqual(trigger.since, 10.0)
    trigger.reset()
    XCTAssertNil(trigger.since)
  }

  func testRectSpringKeepsTheDrawnRectThenSettlesOnTheTarget() {
    var spring = RectSpring()
    let drawn = CGRect(x: 0, y: 0, width: 50, height: 50)
    let target = CGRect(x: 100, y: 0, width: 60, height: 60)
    spring.retarget(from: drawn, to: target)
    XCTAssertEqual(spring.apply(to: target), drawn)
    for _ in 0..<120 { spring.step(1.0 / 120, omega: 2 * .pi / 0.3) }
    XCTAssertTrue(spring.settled)
    XCTAssertEqual(spring.apply(to: target).midX, target.midX, accuracy: 0.1)
  }
}
