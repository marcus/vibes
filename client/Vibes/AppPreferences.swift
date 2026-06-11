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

  /// True when the user previously disabled the login item in System
  /// Settings: register() succeeds but the item stays inert until they
  /// re-enable it there.
  static var requiresApproval: Bool {
    SMAppService.mainApp.status == .requiresApproval
  }

  static func set(enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }

  static func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
}
