import AppKit
import SwiftUI
import XCTest
@testable import barista_agent

final class SettingsViewTests: XCTestCase {
  func testSettingsTabs() {
    let tabs = SettingsTab.allCases
    XCTAssertEqual(tabs.count, 4)
    XCTAssertEqual(tabs, [.dock, .files, .viewer, .advanced])
    for tab in tabs {
      XCTAssertFalse(tab.systemImage.isEmpty)
      XCTAssertFalse(tab.id.isEmpty)
    }
  }

  func testViewerWindowDoubleTapMaximizes() {
    let window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
      styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    XCTAssertFalse(window.isZoomed, "Window starts unzoomed")

    ViewerController.toggleMaximize(window)
    XCTAssertTrue(window.isZoomed, "First toggle maximizes the window")

    ViewerController.toggleMaximize(window)
    XCTAssertFalse(window.isZoomed, "Second toggle restores the window")
  }

  func testSidebarPreferencesFontSizeAndCustomIcons() {
    let prefs = SidebarPreferences.shared
    let originalSize = prefs.fontSize
    let testURL = URL(fileURLWithPath: "/tmp/barista-test-\(UUID().uuidString)")

    prefs.fontSize = 14
    XCTAssertEqual(prefs.fontSize, 14)

    prefs.stepFontSize(by: 2)
    XCTAssertEqual(prefs.fontSize, 16)

    prefs.stepFontSize(by: -5)
    XCTAssertEqual(prefs.fontSize, 11)

    // Custom icons
    let defaultSymbol = prefs.symbol(for: testURL)
    prefs.setIcon("sparkles", for: testURL)
    XCTAssertEqual(prefs.symbol(for: testURL), "sparkles")

    prefs.setIcon(nil, for: testURL)
    XCTAssertEqual(prefs.symbol(for: testURL), defaultSymbol)

    // Preset icons
    XCTAssertFalse(SidebarPreferences.presetIcons.isEmpty)
    for category in SidebarPreferences.presetIcons {
      XCTAssertFalse(category.category.isEmpty)
      XCTAssertFalse(category.icons.isEmpty)
    }

    prefs.fontSize = originalSize
  }

  func testBrowserStateIconSizeStepping() {
    let state = BrowserState(location: FileManager.default.temporaryDirectory)
    state.layout = .icons
    state.iconSize = 64

    state.stepIconSize(1)
    XCTAssertGreaterThan(state.iconSize, 64)

    let larger = state.iconSize
    state.stepIconSize(-1)
    XCTAssertLessThan(state.iconSize, larger)
  }
}
