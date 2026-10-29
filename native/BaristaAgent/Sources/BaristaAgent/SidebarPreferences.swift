import AppKit
import SwiftUI

/// Sidebar display preferences for Barista Files: font sizing and custom icons.
final class SidebarPreferences: ObservableObject {
  static let shared = SidebarPreferences()

  @Published var fontSize: Double {
    didSet {
      UserDefaults.standard.set(fontSize, forKey: "BaristaFilesSidebarFontSize")
    }
  }

  @Published var customIcons: [String: String] {
    didSet {
      if let data = try? JSONEncoder().encode(customIcons) {
        UserDefaults.standard.set(data, forKey: "BaristaFilesSidebarCustomIcons")
      }
    }
  }

  init() {
    let savedSize = UserDefaults.standard.double(forKey: "BaristaFilesSidebarFontSize")
    self.fontSize = savedSize >= 9 && savedSize <= 24 ? savedSize : 12.0

    if let data = UserDefaults.standard.data(forKey: "BaristaFilesSidebarCustomIcons"),
       let icons = try? JSONDecoder().decode([String: String].self, from: data) {
      self.customIcons = icons
    } else {
      self.customIcons = [:]
    }
  }

  /// Returns the symbol for `url`, checking custom overrides first, then Finder defaults.
  func symbol(for url: URL) -> String {
    let path = url.standardizedFileURL.path
    let tilde = (path as NSString).abbreviatingWithTildeInPath
    let name = url.lastPathComponent
    if let custom = customIcons[path] ?? customIcons[tilde] ?? customIcons[name] {
      return custom
    }
    return FinderFavorites.symbol(for: url)
  }

  /// Sets or clears a custom icon symbol for `url`.
  func setIcon(_ symbol: String?, for url: URL) {
    let path = url.standardizedFileURL.path
    let tilde = (path as NSString).abbreviatingWithTildeInPath
    if let symbol = symbol?.trimmingCharacters(in: .whitespaces), !symbol.isEmpty {
      customIcons[path] = symbol
    } else {
      customIcons.removeValue(forKey: path)
      customIcons.removeValue(forKey: tilde)
      customIcons.removeValue(forKey: url.lastPathComponent)
    }
  }

  /// Clears all custom icons.
  func removeAllCustomIcons() {
    customIcons.removeAll()
  }

  /// Steps the font size up or down within [9, 22].
  func stepFontSize(by delta: Double) {
    let newSize = min(max(fontSize + delta, 9), 22)
    if newSize != fontSize {
      fontSize = newSize
    }
  }

  /// Popular SF Symbols grouped by category for quick customization.
  static let presetIcons: [(category: String, icons: [String])] = [
    ("Folders & Places", [
      "folder", "folder.fill", "house", "building.columns", "briefcase", "archivebox", "cloud"
    ]),
    ("Development", [
      "curlybraces", "terminal", "hammer", "wrench.and.screwdriver", "cpu", "gearshape", "arrow.triangle.branch"
    ]),
    ("Media & Creative", [
      "photo", "film", "music.note", "waveform", "paintpalette", "camera", "theatermasks"
    ]),
    ("Documents & Notes", [
      "doc", "doc.text", "book", "note.text", "list.bullet.clipboard", "newspaper"
    ]),
    ("Symbols & Badges", [
      "star", "star.fill", "heart", "heart.fill", "tag", "bookmark", "sparkles", "flame", "gamecontroller"
    ]),
  ]

  /// Displays a native alert to prompt for a custom SF Symbol name.
  static func promptForCustomIcon(for url: URL, current: String, onDone: @escaping (String?) -> Void) {
    let alert = NSAlert()
    alert.messageText = "Custom Sidebar Icon"
    alert.informativeText = "Enter any SF Symbol name (e.g. gamecontroller, hammer.fill, sparkles, chevron.left.forwardslash.chevron.right):"
    alert.alertStyle = .informational

    let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
    input.stringValue = current
    alert.accessoryView = input
    alert.addButton(withTitle: "Set Icon")
    alert.addButton(withTitle: "Cancel")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      let symbol = input.stringValue.trimmingCharacters(in: .whitespaces)
      onDone(symbol.isEmpty ? nil : symbol)
    }
  }
}
