import AppKit
import SwiftUI

/// Preference tabs in the Barista Settings window.
enum SettingsTab: String, CaseIterable, Identifiable {
  case dock = "Dock"
  case files = "Files"
  case viewer = "Viewer"
  case advanced = "Advanced"

  var id: String { rawValue }

  var systemImage: String {
    switch self {
    case .dock: return "dock.rectangle"
    case .files: return "folder"
    case .viewer: return "eye"
    case .advanced: return "gearshape"
    }
  }
}

/// Native macOS settings view for Barista: Dock appearance & behavior,
/// default file browser, media viewer preferences, and integration settings.
struct SettingsView: View {
  @ObservedObject var store: DockStore
  @ObservedObject private var sidebarPrefs = SidebarPreferences.shared
  @State private var selectedTab: SettingsTab = .dock
  @State private var confirmingReset = false

  private func binding<T>(_ keyPath: WritableKeyPath<DockSettings, T>) -> Binding<T> {
    Binding(
      get: { store.settings[keyPath: keyPath] },
      set: { val in store.updateSettings { $0[keyPath: keyPath] = val } }
    )
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      dockTab
        .tabItem { Label("Dock", systemImage: SettingsTab.dock.systemImage) }
        .tag(SettingsTab.dock)

      filesTab
        .tabItem { Label("Files", systemImage: SettingsTab.files.systemImage) }
        .tag(SettingsTab.files)

      viewerTab
        .tabItem { Label("Viewer", systemImage: SettingsTab.viewer.systemImage) }
        .tag(SettingsTab.viewer)

      advancedTab
        .tabItem { Label("Advanced", systemImage: SettingsTab.advanced.systemImage) }
        .tag(SettingsTab.advanced)
    }
    .frame(width: 520, height: 480)
  }

  // MARK: - Dock Tab

  private var dockTab: some View {
    Form {
      Section("Icons & Magnification") {
        HStack {
          Slider(value: binding(\.iconSize), in: 24...96, step: 1) {
            Text("Icon Size")
          }
          Text("\(Int(store.settings.iconSize)) pt")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 48, alignment: .trailing)
        }

        Toggle("Magnification", isOn: Binding(
          get: { store.settings.magnification > 1.0 },
          set: { enabled in
            store.updateSettings { $0.magnification = enabled ? 1.6 : 1.0 }
          }
        ))

        if store.settings.magnification > 1.0 {
          HStack {
            Slider(value: binding(\.magnification), in: 1.0...2.5, step: 0.1) {
              Text("Magnified Size")
            }
            Text(String(format: "%.1f×", store.settings.magnification))
              .monospacedDigit()
              .foregroundStyle(.secondary)
              .frame(width: 48, alignment: .trailing)
          }
        }

        HStack {
          Slider(value: binding(\.spacing), in: 0...16, step: 1) {
            Text("Tile Spacing")
          }
          Text("\(Int(store.settings.spacing)) pt")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 48, alignment: .trailing)
        }
      }

      Section("Auto-Hide & Reveal") {
        HStack {
          Slider(value: binding(\.revealDelay), in: 0.0...2.0, step: 0.1) {
            Text("Reveal Delay")
          }
          Text(String(format: "%.1f s", store.settings.revealDelay))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 48, alignment: .trailing)
        }

        HStack {
          Slider(value: binding(\.revealPush), in: 0...50, step: 2) {
            Text("Reveal Push")
          }
          Text("\(Int(store.settings.revealPush)) pt")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 48, alignment: .trailing)
        }

        HStack {
          Slider(value: binding(\.hideDelay), in: 0.0...3.0, step: 0.1) {
            Text("Hide Delay")
          }
          Text(String(format: "%.1f s", store.settings.hideDelay))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 48, alignment: .trailing)
        }
      }

      Section("Contents & Behavior") {
        Toggle("Show indicator lights for open applications", isOn: binding(\.showRunning))
        Toggle("Show Trash in Dock", isOn: binding(\.showTrash))
        Toggle("Show minimized windows in Dock", isOn: binding(\.showMinimized))
        Toggle("Expand active group automatically", isOn: binding(\.expandActiveGroup))
      }

      Section("Appearance") {
        Picker("Theme", selection: binding(\.theme)) {
          Text("Barista (follows sketchybar colors)").tag("barista")
          Text("System (native vibrancy)").tag("system")
        }
      }
    }
    .formStyle(.grouped)
    .padding(12)
  }

  // MARK: - Files Tab

  private var filesTab: some View {
    Form {
      Section("Default File Manager") {
        Picker("Open Folders With", selection: binding(\.filesBrowser)) {
          Text("Barista Files").tag("barista")
          Text("macOS Finder").tag("finder")
        }

        Text("When set to Barista Files, clicking folders or Finder in the dock opens Barista Files. Holding ⌥ (Option) while clicking opens native Finder instead.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Sidebar Appearance & Text Size") {
        HStack {
          Slider(value: $sidebarPrefs.fontSize, in: 9...22, step: 1) {
            Text("Sidebar Text Size")
          }
          Text("\(Int(sidebarPrefs.fontSize)) pt")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 44, alignment: .trailing)
        }

        HStack(spacing: 8) {
          Text("Presets:")
            .font(.caption)
            .foregroundStyle(.secondary)
          Button("Small (11 pt)") { sidebarPrefs.fontSize = 11 }.buttonStyle(.bordered).controlSize(.small)
          Button("Medium (13 pt)") { sidebarPrefs.fontSize = 13 }.buttonStyle(.bordered).controlSize(.small)
          Button("Large (15 pt)") { sidebarPrefs.fontSize = 15 }.buttonStyle(.bordered).controlSize(.small)
          Spacer()
        }

        VStack(alignment: .leading, spacing: 6) {
          Label("Custom Sidebar Icons", systemImage: "paintbrush")
            .font(.subheadline.bold())
          Text("Right-click any folder or location in the Barista Files sidebar to choose a custom icon from categorized presets or enter any SF Symbol name.")
            .font(.caption)
            .foregroundStyle(.secondary)

          if !sidebarPrefs.customIcons.isEmpty {
            HStack {
              Text("\(sidebarPrefs.customIcons.count) custom icon\(sidebarPrefs.customIcons.count == 1 ? "" : "s") configured")
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              Button("Reset All Custom Icons", role: .destructive) {
                sidebarPrefs.removeAllCustomIcons()
              }
              .buttonStyle(.bordered)
              .controlSize(.small)
            }
            .padding(.top, 2)
          }
        }
        .padding(.vertical, 4)
      }

      Section("Window Management & Tiling") {
        VStack(alignment: .leading, spacing: 8) {
          Label("yabai Space Coordination", systemImage: "macwindow.on.rectangle")
            .font(.subheadline.bold())

          Text("Barista integrates with yabai. Barista Files browser windows tile alongside active editors and terminals. Barista View media windows float on the below layer so you can click any tiled window to take focus over it without floating clutter.")
            .font(.caption)
            .foregroundStyle(.secondary)

          HStack {
            Button("Balance Space Windows") {
              Yabai.runAsync(["space", "--balance"])
            }
            .buttonStyle(.bordered)

            Spacer()
          }
          .padding(.top, 4)
        }
        .padding(.vertical, 4)
      }
    }
    .formStyle(.grouped)
    .padding(12)
  }

  // MARK: - Viewer Tab

  private var viewerTab: some View {
    Form {
      Section("Scroll Wheel Navigation") {
        Picker("Scroll Wheel Action", selection: binding(\.viewerScrollZoom)) {
          Text("Normal Zoom (12% per notch)").tag("normal")
          Text("Fine Zoom (5% per notch)").tag("fine")
          Text("Fast Zoom (35% per notch)").tag("fast")
          Text("Scrub / Scroll (Zoom Off)").tag("off")
        }

        Text("Turning the mouse scroll wheel or swiping the trackpad over pictures or videos zooms into the media at the pointer. In Scrub mode, scrolling navigates video frames instead.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Media Playback") {
        Toggle("Loop movies automatically", isOn: binding(\.viewerLoopsMovies))
      }

      Section("Window Gestures") {
        VStack(alignment: .leading, spacing: 6) {
          Label("Title Bar Double-Tap", systemImage: "arrow.up.left.and.arrow.down.right")
            .font(.subheadline.bold())

          Text("Double-tapping or double-clicking the top bar of a preview window maximizes it to fit the screen, or restores its previous dimensions.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
      }
    }
    .formStyle(.grouped)
    .padding(12)
  }

  // MARK: - Advanced Tab

  private var advancedTab: some View {
    Form {
      Section("Shelf & Staging") {
        Stepper(value: binding(\.shelfDays), in: 0.5...30, step: 0.5) {
          HStack {
            Text("Keep Shelf Items For")
            Spacer()
            Text(String(format: "%.1f days", store.settings.shelfDays))
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
        }

        Text("Dropped files and snippets in the dock shelf expire and are cleaned up after this period.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Shortcuts Automation") {
        TextField("Focus Shortcut Name", text: binding(\.focusShortcut))
        Text("Shortcuts workflow run when toggling Focus mode in the dock Control Center callout. Leave empty to open System Settings.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Configuration File") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Settings are saved automatically to ~/.config/barista/dock.json.")
            .font(.caption)
            .foregroundStyle(.secondary)

          HStack(spacing: 12) {
            Button("Open in Editor…") {
              NSWorkspace.shared.open(DockConfigFile.url)
            }

            Button("Reveal in Finder") {
              NSWorkspace.shared.activateFileViewerSelecting([DockConfigFile.url])
            }

            Spacer()

            Button("Reset to Defaults", role: .destructive) { confirmingReset = true }
              .confirmationDialog("Reset every Dock, Files, and Viewer setting?", isPresented: $confirmingReset) {
                Button("Reset to Defaults", role: .destructive) { store.updateSettings { $0 = DockSettings() } }
              }
          }
          .padding(.top, 4)
        }
        .padding(.vertical, 4)
      }
    }
    .formStyle(.grouped)
    .padding(12)
  }
}

/// Manages the single native Settings window instance.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
  static let shared = SettingsWindowController()
  /// Also what `Yabai.ensureSettingsRule` matches.
  static let title = "Barista Settings"

  private var closeObserver: NSObjectProtocol?

  func show(tab: SettingsTab? = nil) {
    Yabai.ensureSettingsRule()

    if let existingWindow = window {
      AgentWindows.bringForward(existingWindow)
      return
    }

    let newWindow = Self.makeWindow(store: AgentDelegate.shared?.store ?? DockStore())
    newWindow.delegate = self
    newWindow.center()

    self.window = newWindow

    if let observer = closeObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    closeObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: newWindow,
      queue: .main
    ) { [weak newWindow] _ in
      guard let newWindow else { return }
      AgentWindows.closed(newWindow)
    }

    AgentWindows.bringForward(newWindow)
  }

  private static func makeWindow(store: DockStore) -> NSWindow {
    let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
    window.title = title
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.tabbingMode = .disallowed
    window.isReleasedWhenClosed = false
    return window
  }
}
