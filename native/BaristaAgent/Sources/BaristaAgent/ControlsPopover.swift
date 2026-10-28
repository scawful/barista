import SwiftUI

/// The controls tile's callout: switches two to a row, the built-in
/// display's brightness, the output's volume and device, then System
/// Settings panes.
struct ControlsPopover: View {
  static let width: CGFloat = 2 * ControlTile.size.width + 8

  @ObservedObject var model: ControlsModel
  let theme: DockTheme
  let arrowX: CGFloat?
  /// A Shortcuts shortcut the Focus switch runs; empty opens Focus settings.
  let focusShortcut: String
  let onPane: (SettingsPane) -> Void

  var body: some View {
    let state = model.state
    Callout(theme: theme, arrowX: arrowX) {
      CalloutTitle(title: "Controls", subtitle: state.battery?.summary ?? "System switches and settings") {
        Image(systemName: "switch.2").font(.system(size: 20, weight: .medium))
      }
    } content: {
      VStack(alignment: .leading, spacing: 12) {
        LazyVGrid(columns: [GridItem(.fixed(ControlTile.size.width), spacing: 8),
                            GridItem(.fixed(ControlTile.size.width))], spacing: 8) {
          switches(state)
        }
        sliders(state)
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.width / 4), spacing: 0), count: 4), spacing: 4) {
          ForEach(SettingsPane.all) { pane in
            PaneCell(pane: pane, theme: theme) { onPane(pane) }
          }
        }
      }
      .frame(width: Self.width)
    }
  }

  @ViewBuilder private func switches(_ state: ControlsState) -> some View {
    if let on = state.wifi {
      ControlTile(title: "Wi-Fi", detail: on ? "On" : "Off", symbol: on ? "wifi" : "wifi.slash", on: on,
                  theme: theme, action: model.toggleWiFi)
    }
    if let on = state.bluetooth {
      ControlTile(title: "Bluetooth", detail: on ? "On" : "Off", symbol: "dot.radiowaves.left.and.right", on: on,
                  theme: theme, action: model.toggleBluetooth)
    } else {
      ControlTile(title: "Bluetooth", detail: "Settings", symbol: "dot.radiowaves.left.and.right", on: false,
                  theme: theme) { open("Bluetooth") }
        .help("Install blueutil (brew install blueutil) to switch Bluetooth here.")
    }
    ControlTile(title: "Focus", detail: focusShortcut.isEmpty ? "Settings" : focusShortcut, symbol: "moon.fill",
                on: false, theme: theme) {
      if focusShortcut.isEmpty {
        open("Focus")
      } else {
        launch("/usr/bin/shortcuts", ["run", focusShortcut])
      }
    }
    .help(focusShortcut.isEmpty ? "Set focus_shortcut in dock.json to a Shortcut that toggles a Focus." : "")
    ControlTile(title: "Dark Mode", detail: state.dark ? "On" : "Off", symbol: "circle.lefthalf.filled",
                on: state.dark, theme: theme, action: model.toggleDark)
    if let on = state.nightShift {
      ControlTile(title: "Night Shift", detail: on ? "On" : "Off", symbol: "sun.haze", on: on,
                  theme: theme, action: model.toggleNightShift)
    }
    ControlTile(title: "Keep Awake", detail: state.keepAwake ? "Display stays on" : "Off",
                symbol: "cup.and.saucer.fill", on: state.keepAwake, theme: theme, action: model.toggleKeepAwake)
    if let battery = state.battery {
      ControlTile(title: "Low Power", detail: state.lowPower ? "On" : "Off", symbol: battery.symbol,
                  on: state.lowPower, theme: theme, action: model.toggleLowPower)
        .help("Changing Low Power Mode asks for an administrator password.")
    }
  }

  @ViewBuilder private func sliders(_ state: ControlsState) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if let brightness = state.brightness {
        LevelRow(symbol: "sun.max.fill", value: brightness, theme: theme, onSymbol: nil,
                 onChange: model.setBrightness)
      }
      if let volume = state.volume {
        LevelRow(symbol: state.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                 value: state.muted ? 0 : volume, theme: theme, onSymbol: model.toggleMute,
                 onChange: model.setVolume)
      }
      if state.outputs.count > 1 {
        Menu {
          ForEach(state.outputs) { output in
            Button {
              model.select(output)
            } label: {
              if output.id == state.output {
                Label(output.name, systemImage: "checkmark")
              } else {
                Text(output.name)
              }
            }
          }
        } label: {
          Text(state.outputs.first { $0.id == state.output }?.name ?? "Output")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.system(size: 11))
        .padding(.leading, 26)
      }
    }
  }

  private func open(_ title: String) {
    if let pane = SettingsPane.named(title) { onPane(pane) }
  }
}

/// One switch: a round icon filled with the accent while on, its name, and
/// its state. Clicking flips it.
private struct ControlTile: View {
  static let size = CGSize(width: 140, height: 44)

  let title: String
  let detail: String
  let symbol: String
  let on: Bool
  let theme: DockTheme
  let action: () -> Void

  var body: some View {
    PointerHover { hovered in
      HStack(spacing: 8) {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 28, height: 28)
          .background(Circle().fill(on ? theme.accent : theme.label.opacity(0.12)))
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
          Text(detail).font(.system(size: 10)).opacity(0.6).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 8)
      .frame(width: Self.size.width, height: Self.size.height)
      .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(theme.label.opacity(hovered ? 0.16 : 0.08)))
      .animation(.easeOut(duration: 0.12), value: hovered)
      .animation(.easeOut(duration: 0.12), value: on)
    }
    .frame(width: Self.size.width, height: Self.size.height)
    .contentShape(Rectangle())
    .onTapGesture(perform: action)
  }
}

/// An icon, a slider, and the level in percent. `onSymbol` makes the icon a
/// button, such as mute.
private struct LevelRow: View {
  let symbol: String
  let value: Float
  let theme: DockTheme
  let onSymbol: (() -> Void)?
  let onChange: (Float) -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.system(size: 12))
        .frame(width: 18)
        .contentShape(Rectangle())
        .onTapGesture { onSymbol?() }
      Slider(value: Binding(get: { Double(value) }, set: { onChange(Float($0)) }), in: 0...1)
        .controlSize(.small)
        .tint(theme.accent)
      Text("\(Int((value * 100).rounded()))%")
        .font(.system(size: 11).monospacedDigit())
        .opacity(0.6)
        .frame(width: 34, alignment: .trailing)
    }
  }
}

private struct PaneCell: View {
  let pane: SettingsPane
  let theme: DockTheme
  let action: () -> Void

  var body: some View {
    PointerHover { hovered in
      VStack(spacing: 4) {
        Image(systemName: pane.symbol).font(.system(size: 13)).frame(height: 16)
        Text(pane.title).font(.system(size: 10)).lineLimit(1)
      }
      .padding(.top, 5)
      .frame(width: ControlsPopover.width / 4 - 4, height: 40, alignment: .top)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(hovered ? theme.hover : Color.clear))
      .animation(.easeOut(duration: 0.12), value: hovered)
    }
    .frame(width: ControlsPopover.width / 4 - 4, height: 40)
    .contentShape(Rectangle())
    .onTapGesture(perform: action)
    .help(pane.id.isEmpty ? "Open System Settings" : "Open \(pane.title) settings")
  }
}
