import AppKit
import ServiceManagement
import SwiftUI

/// App-wide appearance override. `.system` (the default) leaves
/// `NSApp.appearance` nil so the app tracks the macOS setting.
enum AppAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  static let storageKey = "appAppearance"

  var id: String { rawValue }

  var label: String {
    switch self {
    case .system: "Follow System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  private var nsAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }

  /// Reads the stored preference and applies it to the running app.
  static func applyCurrent() {
    let raw = UserDefaults.standard.string(forKey: storageKey)
    let appearance = raw.flatMap(AppAppearance.init(rawValue:)) ?? .system
    NSApp.appearance = appearance.nsAppearance
  }
}

/// Thin wrapper over SMAppService for the "open at login" toggle.
/// Unregistered (off) is the default for new installs.
enum LaunchAtLogin {
  static var isEnabled: Bool {
    SMAppService.mainApp.status == .enabled
  }

  static func set(enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}
