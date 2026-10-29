import IOKit.ps
import XCTest
@testable import barista_agent

final class ControlsTests: XCTestCase {
  func testBatteryReadsTheInternalBattery() {
    let charging: [String: Any] = [
      kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 91, kIOPSMaxCapacityKey: 100,
      kIOPSIsChargingKey: true, kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSTimeToFullChargeKey: 30,
    ]
    let battery = Battery(description: charging)
    XCTAssertEqual(battery, Battery(percent: 91, charging: true, onAC: true, minutes: 30))
    XCTAssertEqual(battery?.summary, "91% · charging, 0:30 to full")
    XCTAssertEqual(battery?.symbol, "battery.100.bolt")

    let draining: [String: Any] = [
      kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 40, kIOPSMaxCapacityKey: 80,
      kIOPSIsChargingKey: false, kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue, kIOPSTimeToEmptyKey: 185,
    ]
    XCTAssertEqual(Battery(description: draining)?.summary, "50% · 3:05 left")
    XCTAssertEqual(Battery(description: draining)?.symbol, "battery.50")

    var estimating = draining
    estimating[kIOPSTimeToEmptyKey] = -1
    XCTAssertEqual(Battery(description: estimating)?.summary, "50%", "no time while macOS estimates")
    XCTAssertEqual(Battery(percent: 100, charging: false, onAC: true, minutes: nil).summary, "100% · on power")

    var ups = charging
    ups[kIOPSTypeKey] = kIOPSUPSType
    XCTAssertNil(Battery(description: ups), "a UPS is not the Mac's battery")
  }

  func testSettingsPanesOpenSystemSettings() {
    XCTAssertEqual(Set(SettingsPane.all.map(\.id)).count, SettingsPane.all.count)
    XCTAssertEqual(Set(SettingsPane.all.map(\.title)).count, SettingsPane.all.count, "titles name panes")
    XCTAssertEqual(SettingsPane.named("Sound")?.url.absoluteString,
                   "x-apple.systempreferences:com.apple.Sound-Settings.extension")
    XCTAssertEqual(SettingsPane.named("Settings")?.url.absoluteString, "x-apple.systempreferences:")
    XCTAssertNotNil(SettingsPane.named("Bluetooth"), "the Bluetooth switch falls back to its pane")
    XCTAssertNotNil(SettingsPane.named("Focus"), "the Focus switch falls back to its pane")
  }

  func testControlsTileRoundTripsOncePerDock() throws {
    let json = #"""
    {"settings": {"focus_shortcut": "Toggle Work Focus"},
     "others": [{"kind": "shelf"}, {"kind": "controls"}]}
    """#
    var config = try DockConfigFile.decode(Data(json.utf8))
    XCTAssertEqual(config.settings.focusShortcut, "Toggle Work Focus")
    XCTAssertEqual(config.system.map(\.key), ["shelf", "controls"])
    config.insert([DockItem(kind: .controls)], at: nil, in: .pinned)
    XCTAssertEqual(config.pinned.count, 0, "one controls tile per dock")
    XCTAssertEqual(try DockConfigFile.decode(DockConfigFile.encode(config)), config)
    XCTAssertEqual(try DockConfigFile.decode(Data("{}".utf8)).settings.focusShortcut, "")
  }
}
