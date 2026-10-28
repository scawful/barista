import AppKit
import AudioToolbox
import CoreAudio
import CoreWLAN
import IOKit.ps
import IOKit.pwr_mgt

/// The dock's controls callout: Control Center's everyday switches. Public
/// APIs where macOS has them; brightness and Night Shift go through private
/// frameworks loaded at runtime and drop out when those don't answer.
/// Bluetooth takes `blueutil`: the agent has no Info.plist, and touching
/// IOBluetooth without a usage string gets it killed by privacy checks.
struct ControlsState: Equatable {
  /// Nil without a Wi-Fi interface.
  var wifi: Bool?
  /// Nil without `blueutil`, or until it answers.
  var bluetooth: Bool?
  var dark = false
  var nightShift: Bool?
  var keepAwake = false
  var lowPower = false
  var battery: Battery?
  var brightness: Float?
  var volume: Float?
  var muted = false
  var output: AudioDeviceID?
  var outputs: [AudioOutput] = []

  /// Everything but Bluetooth, which takes a helper run.
  static func read() -> ControlsState {
    let output = Sound.output
    return ControlsState(
      wifi: WiFi.on, dark: Appearance.dark, nightShift: NightShift.enabled, keepAwake: KeepAwake.on,
      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, battery: Battery.read(),
      brightness: Display.brightness(), volume: output.flatMap(Sound.volume), muted: output.map(Sound.muted) ?? false,
      output: output, outputs: Sound.outputs())
  }
}

/// A System Settings pane the callout links to.
struct SettingsPane: Identifiable {
  let id: String
  let title: String
  let symbol: String

  var url: URL { URL(string: "x-apple.systempreferences:\(id)")! }

  static let all = [
    SettingsPane(id: "com.apple.wifi-settings-extension", title: "Wi-Fi", symbol: "wifi"),
    SettingsPane(id: "com.apple.BluetoothSettings", title: "Bluetooth", symbol: "dot.radiowaves.left.and.right"),
    SettingsPane(id: "com.apple.Network-Settings.extension", title: "Network", symbol: "network"),
    SettingsPane(id: "com.apple.Sound-Settings.extension", title: "Sound", symbol: "speaker.wave.2"),
    SettingsPane(id: "com.apple.Displays-Settings.extension", title: "Displays", symbol: "display"),
    SettingsPane(id: "com.apple.Focus-Settings.extension", title: "Focus", symbol: "moon"),
    SettingsPane(id: "com.apple.Battery-Settings.extension", title: "Battery", symbol: "battery.75"),
    SettingsPane(id: "com.apple.Appearance-Settings.extension", title: "Appearance", symbol: "circle.lefthalf.filled"),
    SettingsPane(id: "com.apple.Desktop-Settings.extension", title: "Dock", symbol: "dock.rectangle"),
    SettingsPane(id: "com.apple.Keyboard-Settings.extension", title: "Keyboard", symbol: "keyboard"),
    SettingsPane(id: "com.apple.settings.PrivacySecurity.extension", title: "Privacy", symbol: "hand.raised"),
    SettingsPane(id: "", title: "Settings", symbol: "gearshape"),
  ]

  static func named(_ title: String) -> SettingsPane? { all.first { $0.title == title } }
}

struct Battery: Equatable {
  var percent: Int
  var charging: Bool
  var onAC: Bool
  /// To full while charging, to empty otherwise; nil while macOS estimates.
  var minutes: Int?

  init(percent: Int, charging: Bool, onAC: Bool, minutes: Int?) {
    self.percent = percent
    self.charging = charging
    self.onAC = onAC
    self.minutes = minutes
  }

  /// One IOKit power source description; nil for anything but the internal battery.
  init?(description: [String: Any]) {
    guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
          let current = description[kIOPSCurrentCapacityKey] as? Int,
          let capacity = description[kIOPSMaxCapacityKey] as? Int, capacity > 0 else { return nil }
    percent = Int((Double(current) / Double(capacity) * 100).rounded())
    charging = description[kIOPSIsChargingKey] as? Bool ?? false
    onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
    let time = description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int ?? -1
    minutes = time > 0 ? time : nil
  }

  var summary: String {
    var text = "\(percent)%"
    if charging {
      text += " · charging"
    } else if onAC {
      text += " · on power"
    }
    if let minutes {
      text += (charging || onAC ? ", " : " · ")
        + String(format: "%d:%02d %@", minutes / 60, minutes % 60, charging ? "to full" : "left")
    }
    return text
  }

  var symbol: String {
    if charging { return "battery.100.bolt" }
    return ["battery.0", "battery.25", "battery.50", "battery.75", "battery.100"][min(4, (percent + 12) / 25)]
  }

  static func read() -> Battery? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    return sources.lazy
      .compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
      .compactMap(Battery.init(description:))
      .first
  }
}

struct AudioOutput: Equatable, Identifiable {
  let id: AudioDeviceID
  let name: String
}

enum Sound {
  private static let system = AudioObjectID(kAudioObjectSystemObject)

  static var output: AudioDeviceID? {
    value(system, address(kAudioHardwarePropertyDefaultOutputDevice), AudioDeviceID(0)).flatMap { $0 == 0 ? nil : $0 }
  }

  static func volume(_ device: AudioDeviceID) -> Float? {
    value(device, address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput),
        Float32(0))
  }

  static func setVolume(_ volume: Float, on device: AudioDeviceID) {
    write(device, address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput),
        Float32(min(max(volume, 0), 1)))
  }

  static func muted(_ device: AudioDeviceID) -> Bool {
    value(device, address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput), UInt32(0)) == 1
  }

  static func setMuted(_ muted: Bool, on device: AudioDeviceID) {
    write(device, address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput), UInt32(muted ? 1 : 0))
  }

  /// Devices with output streams, in CoreAudio's order.
  static func outputs() -> [AudioOutput] {
    var devices = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &devices, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &devices, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { id in
      var streams = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
      var bytes: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
      return AudioOutput(id: id, name: name(id))
    }
  }

  static func select(_ device: AudioDeviceID) {
    write(system, address(kAudioHardwarePropertyDefaultOutputDevice), device)
  }

  private static func name(_ device: AudioDeviceID) -> String {
    var property = address(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &name) == noErr,
          let name else { return "Output" }
    return name.takeRetainedValue() as String
  }

  private static func address(_ selector: AudioObjectPropertySelector,
                              _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
  }

  private static func value<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ initial: T) -> T? {
    var address = address
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
  }

  private static func write<T: BitwiseCopyable>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) {
    var address = address
    var value = value
    AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &value)
  }
}

enum WiFi {
  static var on: Bool? { CWWiFiClient.shared().interface()?.powerOn() }

  static func set(_ on: Bool) {
    do {
      try CWWiFiClient.shared().interface()?.setPower(on)
    } catch {
      DockStore.log("could not turn Wi-Fi \(on ? "on" : "off"): \(error)")
    }
  }
}

enum Bluetooth {
  static var tool: String? { Tool.find("blueutil") }

  /// Blocking; nil without `blueutil`.
  static func read() -> Bool? {
    guard let tool, let output = Tool.output(tool, ["--power"]) else { return nil }
    return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
  }

  static func set(_ on: Bool, done: @escaping () -> Void) {
    guard let tool else { return }
    launch(tool, ["--power", on ? "1" : "0"], onExit: done)
  }
}

/// The built-in display only: external ones speak DDC, which this doesn't.
enum Display {
  private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
  private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

  private static let services = dlopen(
    "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

  private static var builtIn: CGDirectDisplayID? {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return nil }
    return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
  }

  static func brightness() -> Float? {
    guard let services, let symbol = dlsym(services, "DisplayServicesGetBrightness"), let display = builtIn
    else { return nil }
    var value: Float = 0
    return unsafeBitCast(symbol, to: Get.self)(display, &value) == 0 ? value : nil
  }

  static func setBrightness(_ value: Float) {
    guard let services, let symbol = dlsym(services, "DisplayServicesSetBrightness"), let display = builtIn
    else { return }
    _ = unsafeBitCast(symbol, to: Set.self)(display, min(max(value, 0), 1))
  }
}

enum NightShift {
  private typealias Status = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
  private typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool) -> Bool

  private static let client: NSObject? = {
    dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
    return (NSClassFromString("CBBlueLightClient") as? NSObject.Type)?.init()
  }()

  /// `getBlueLightStatus:` fills a struct whose second byte is whether
  /// Night Shift is on; the buffer has room to spare for the rest.
  static var enabled: Bool? {
    let selector = NSSelectorFromString("getBlueLightStatus:")
    guard let client, client.responds(to: selector) else { return nil }
    var status = [UInt8](repeating: 0, count: 64)
    let read = status.withUnsafeMutableBytes { bytes in
      unsafeBitCast(client.method(for: selector), to: Status.self)(client, selector, bytes.baseAddress!)
    }
    return read ? status[1] != 0 : nil
  }

  static func set(_ on: Bool) {
    let selector = NSSelectorFromString("setEnabled:")
    guard let client, client.responds(to: selector) else { return }
    _ = unsafeBitCast(client.method(for: selector), to: SetEnabled.self)(client, selector, on)
  }
}

enum Appearance {
  /// Read from the global domain each time, so a switch made elsewhere shows.
  static var dark: Bool {
    CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String == "Dark"
  }

  /// Through System Events; macOS asks once to allow the agent to control it.
  static func set(dark: Bool, done: @escaping () -> Void) {
    launch("/usr/bin/osascript",
           ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"],
           onExit: done)
  }
}

/// Holds the display awake while on; it ends with the agent.
enum KeepAwake {
  private static var assertion: IOPMAssertionID?

  static var on: Bool { assertion != nil }

  static func set(_ on: Bool) {
    if on, assertion == nil {
      var id = IOPMAssertionID(0)
      let result = IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleDisplaySleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Barista Keep Awake" as CFString, &id)
      if result == kIOReturnSuccess { assertion = id }
    } else if !on, let id = assertion {
      IOPMAssertionRelease(id)
      assertion = nil
    }
  }
}

enum LowPower {
  /// `pmset` needs an administrator, so macOS asks for a password each time.
  static func set(_ on: Bool, done: @escaping () -> Void) {
    launch("/usr/bin/osascript",
           ["-e", "do shell script \"pmset -a lowpowermode \(on ? 1 : 0)\" with administrator privileges"],
           quiet: true, onExit: done)
  }
}

/// The open callout's state. It polls so volume keys and switches flipped
/// elsewhere show up, but not right after a change made here, which the
/// system may not report back yet.
final class ControlsModel: ObservableObject {
  @Published private(set) var state = ControlsState.read()
  private var timer: Timer?
  private var changed = Date.distantPast

  func start() {
    readBluetooth()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func toggleWiFi() {
    guard let on = state.wifi else { return }
    change { $0.wifi = !on }
    WiFi.set(!on)
  }

  func toggleBluetooth() {
    guard let on = state.bluetooth else { return }
    change { $0.bluetooth = !on }
    Bluetooth.set(!on) { [weak self] in self?.readBluetooth() }
  }

  func toggleDark() {
    let dark = !state.dark
    change { $0.dark = dark }
    Appearance.set(dark: dark) { [weak self] in self?.reload() }
  }

  func toggleNightShift() {
    guard let on = state.nightShift else { return }
    change { $0.nightShift = !on }
    NightShift.set(!on)
  }

  func toggleKeepAwake() {
    KeepAwake.set(!KeepAwake.on)
    change { $0.keepAwake = KeepAwake.on }
  }

  func toggleLowPower() {
    LowPower.set(!state.lowPower) { [weak self] in self?.reload() }
  }

  func setBrightness(_ value: Float) {
    change { $0.brightness = value }
    Display.setBrightness(value)
  }

  func setVolume(_ value: Float) {
    guard let device = state.output else { return }
    change {
      $0.volume = value
      $0.muted = false
    }
    Sound.setVolume(value, on: device)
    if Sound.muted(device) { Sound.setMuted(false, on: device) }
  }

  func toggleMute() {
    guard let device = state.output else { return }
    let muted = !state.muted
    change { $0.muted = muted }
    Sound.setMuted(muted, on: device)
  }

  func select(_ output: AudioOutput) {
    Sound.select(output.id)
    reload()
  }

  private func change(_ edit: (inout ControlsState) -> Void) {
    changed = Date()
    edit(&state)
  }

  private func poll() {
    guard Date().timeIntervalSince(changed) > 1.5 else { return }
    reload()
  }

  private func reload() {
    var next = ControlsState.read()
    next.bluetooth = state.bluetooth
    if next != state { state = next }
  }

  private func readBluetooth() {
    guard Bluetooth.tool != nil else { return }
    DispatchQueue.global(qos: .userInitiated).async {
      let on = Bluetooth.read()
      DispatchQueue.main.async { [weak self] in
        if self?.state.bluetooth != on { self?.state.bluetooth = on }
      }
    }
  }
}
