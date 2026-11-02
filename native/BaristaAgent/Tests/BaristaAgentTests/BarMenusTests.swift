import XCTest
@testable import barista_agent

final class BarMenusTests: XCTestCase {
  private func row(_ name: String, click: String? = "run", hover: String = "0x40f5c2e7", drawing: Bool = true,
                   popup: [String] = []) -> BarItem {
    var row = BarItem(name: name)
    row.position = "popup"
    row.drawing = drawing
    row.clickScript = click
    row.color = "0xe021162f"
    row.hoverColor = hover
    row.popupItems = popup
    return row
  }

  private func menu(_ name: String, x: Double, width: Double = 26, position: String = "left") -> BarItem {
    var menu = BarItem(name: name)
    menu.position = position
    menu.drawing = true
    menu.popupItems = ["\(name).row"]
    menu.x = x
    menu.width = width
    return menu
  }

  func testObjectsCutJoinedQueriesApartAndSkipBracesInStrings() {
    let output = """
    {
      "name": "a",
      "scripting": { "click_script": "echo \\"}{\\" '{'" }
    }
    [!] Query: Item 'gone' not found
    {
      "name": "b"
    }
    """
    let items = BarMenus.items(Data(output.utf8))
    XCTAssertEqual(Set(items.keys), ["a", "b"])
    XCTAssertEqual(items["a"]?.clickScript, "echo \"}{\" '{'")
  }

  func testItemsReadSketchyBarsFields() throws {
    let json = """
    {"name":"cc.more","geometry":{"drawing":"on","position":"popup","background":{"drawing":"off",
    "color":"0xe021162f","hover_color":"0x40f5c2e7"}},"popup":{"drawing":"on","items":["cc.more.a","cc.more.b"]},
    "scripting":{"click_script":"popup_switch submenu cc.more"},
    "bounding_rects":{"display-2":{"origin":[900.0,0.0],"size":[10.0,28.0]},"display-1":{"origin":[15.0,0.0],"size":[26.0,28.0]}}}
    """
    let item = try XCTUnwrap(BarMenus.items(Data(json.utf8))["cc.more"])
    XCTAssertEqual(item.position, "popup")
    XCTAssertTrue(item.drawing)
    XCTAssertTrue(item.popupDrawing)
    XCTAssertEqual(item.popupItems, ["cc.more.a", "cc.more.b"])
    XCTAssertFalse(item.background)
    XCTAssertEqual(item.hoverColor, "0x40f5c2e7")
    XCTAssertEqual(item.x, 15, "the first display, by name")
    XCTAssertEqual(item.width, 26)

    let header = try XCTUnwrap(BarItem(["name": "cc.header", "scripting": ["click_script": "(null)"]]))
    XCTAssertNil(header.clickScript)
  }

  func testMenusAreTheBarsDrawnPopupOwnersLeftToRight() {
    var hidden = menu("afs_approvals", x: -9999)
    hidden.drawing = false
    var empty = menu("front_app", x: 168, width: 0)
    empty.popupItems = ["front_app.move"]
    var plain = menu("spaces", x: 60)
    plain.popupItems = []
    let items = [menu("clock", x: 1298, position: "right"), menu("agents", x: 119), hidden, empty, plain,
                 row("cc.more", popup: ["cc.more.a"]), menu("control_center", x: 15), menu("triforce", x: 49)]
    XCTAssertEqual(BarMenus.menus(items), ["control_center", "triforce", "agents", "clock"])
  }

  func testOnlyRowsThatActAndLightUpAreSelectable() {
    XCTAssertTrue(BarMenus.selectable(row("cc.layout.float")))
    XCTAssertFalse(BarMenus.selectable(row("cc.header", click: nil)), "headers have no click")
    XCTAssertFalse(BarMenus.selectable(row("agents.sessions.sep", hover: "0x0")), "separators don't light")
    XCTAssertFalse(BarMenus.selectable(row("cc.feedback", drawing: false)), "hidden rows")
  }

  func testStepSkipsWhatCantBeChosenAndWraps() {
    let rows = [row("header", click: nil), row("a"), row("sep", hover: "0x0"), row("b"), row("c", drawing: false)]
    XCTAssertEqual(BarMenus.step(rows, from: nil, by: 1), "a")
    XCTAssertEqual(BarMenus.step(rows, from: nil, by: -1), "b")
    XCTAssertEqual(BarMenus.step(rows, from: "a", by: 1), "b")
    XCTAssertEqual(BarMenus.step(rows, from: "b", by: 1), "a", "wraps past the end")
    XCTAssertEqual(BarMenus.step(rows, from: "a", by: -1), "b", "wraps past the start")
    XCTAssertEqual(BarMenus.step(rows, from: "c", by: 1), "a", "from a row that hid since")
    XCTAssertEqual(BarMenus.step(rows, from: "gone", by: 1), "a")
    XCTAssertNil(BarMenus.step([row("header", click: nil)], from: nil, by: 1))
    XCTAssertEqual(BarMenus.step([row("only")], from: "only", by: 1), "only")
  }

  func testLightingPaintsTheHoverColorAndRestoreGivesTheRowsOwnBack() {
    let plain = row("cc.layout.float")
    let (lit, changes) = BarMenus.light(plain)
    XCTAssertEqual(changes, ["--set", "cc.layout.float", "background.drawing=on", "background.color=0x40f5c2e7"])

    var painted = plain
    painted.background = true
    painted.color = "0x40F5C2E7"
    XCTAssertTrue(BarMenus.isLit(painted))
    XCTAssertEqual(BarMenus.restore(lit, current: painted),
                   ["--set", "cc.layout.float", "background.drawing=off", "background.color=0xe021162f"])

    var repainted = painted
    repainted.color = "0xff0000ff"
    XCTAssertEqual(BarMenus.restore(lit, current: repainted), [], "something else painted it since")
    XCTAssertEqual(BarMenus.restore(lit, current: nil), [], "the row is gone")
  }
}
