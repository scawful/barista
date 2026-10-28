import XCTest
@testable import barista_agent

final class DockLayoutTests: XCTestCase {
  private func layout(magnification: CGFloat = 1.6, maxWidth: CGFloat = .greatestFiniteMagnitude) -> DockLayout {
    DockLayout(slots: DockLayout.slots(for: [["a", "b", "c", "d"], [], ["e", "f"]]),
               icon: 44, magnification: magnification, spacing: 4, maxWidth: maxWidth)
  }

  func testSectionsAreSeparatedByOneDividerEach() {
    XCTAssertEqual(layout().slots.map(\.id), ["a", "b", "c", "d", "divider.1", "e", "f"])
  }

  func testTileUnderPointerGetsFullMagnification() {
    let layout = layout()
    let rest = layout.frames(baseX: nil)
    let target = rest.slots[2]
    let scales = layout.scales(baseX: layout.baseX(forCanvasX: target.midX))
    XCTAssertEqual(scales[2], 1.6, accuracy: 0.02)
    XCTAssertLessThan(scales[0], scales[2])
    XCTAssertEqual(scales[4], 1, "dividers never scale")
  }

  func testPointerMappingRoundTrips() {
    let layout = layout()
    for x in stride(from: layout.frames(baseX: nil).bar.minX, to: layout.frames(baseX: nil).bar.maxX, by: 7) {
      XCTAssertEqual(layout.canvasX(ofBaseX: layout.baseX(forCanvasX: x)), x, accuracy: 0.5)
    }
  }

  func testCanvasFitsTheWidestMagnifiedBar() {
    let layout = layout()
    let rest = layout.frames(baseX: nil).bar
    for u in stride(from: CGFloat(0), through: rest.width, by: 3) {
      let bar = layout.frames(baseX: u).bar
      XCTAssertGreaterThanOrEqual(bar.minX, 0)
      XCTAssertLessThanOrEqual(bar.maxX, layout.canvas.width)
      XCTAssertGreaterThanOrEqual(layout.frames(baseX: u).slots.map(\.minY).min() ?? 0, 0)
    }
  }

  func testNoMagnificationKeepsRestingFrames() {
    let layout = layout(magnification: 1)
    XCTAssertEqual(layout.frames(baseX: 80).slots, layout.frames(baseX: nil).slots)
    XCTAssertEqual(layout.headroom, 0)
  }

  func testIconsShrinkToFitNarrowScreens() {
    let wide = layout()
    let narrow = layout(maxWidth: 300)
    XCTAssertEqual(wide.icon, 44)
    XCTAssertLessThan(narrow.icon, 44)
    XCTAssertLessThanOrEqual(narrow.frames(baseX: nil).bar.width + DockLayout.margin * 2, 300)
  }
}
