import XCTest
@testable import barista_agent

final class NewWindowTests: XCTestCase {
  func testPlainNewWindowRanksFirst() {
    XCTAssertEqual(NewWindow.rank("New Window"), 0)
    XCTAssertEqual(NewWindow.rank("New Finder Window"), 1)
    XCTAssertEqual(NewWindow.rank("New Frame"), 2)
  }

  func testPrivateWindowsAndOtherItemsDontCount() {
    XCTAssertNil(NewWindow.rank("New Private Window"))
    XCTAssertNil(NewWindow.rank("New Incognito Window"))
    XCTAssertNil(NewWindow.rank("New Tab"))
    XCTAssertNil(NewWindow.rank("New Document"))
    XCTAssertNil(NewWindow.rank("Window"))
  }
}
