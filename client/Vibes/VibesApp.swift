import AppKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  static var model: AppModel?
  private var isTerminatingAfterOfflinePublish = false

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard !isTerminatingAfterOfflinePublish, let model = Self.model, model.isConfigured else {
      return .terminateNow
    }
    isTerminatingAfterOfflinePublish = true
    Task {
      await model.publishOfflineForQuit()
      sender.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }
}

@main
struct VibesApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = AppModel()

  // Owns the Sparkle updater for the app's lifetime; starts it immediately so
  // background checks run and `canCheckForUpdates` is observable.
  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
        .onAppear {
          AppDelegate.model = model
        }
        .onOpenURL { url in
          NSApp.activate(ignoringOtherApps: true)
          model.handleIncomingURL(url)
        }
    }
    .windowResizability(.contentSize)
    .commands {
      CommandGroup(after: .appInfo) {
        CheckForUpdatesView(updater: updaterController.updater)
      }
    }

    Settings {
      SettingsView()
        .environmentObject(model)
    }

    MenuBarExtra("Vibes", systemImage: "dot.radiowaves.left.and.right") {
      Button("Show Vibes") {
        NSApp.activate(ignoringOtherApps: true)
      }
      CheckForUpdatesView(updater: updaterController.updater)
      Divider()
      // Compact variant of the in-app PresenceToggle (ContentView.swift).
      // A native menu can't honor the Capsule/lit-accent styling, so we mirror
      // the same Online/Offline two-segment vocabulary as discrete menu items:
      // the active mode is "lit" (filled dot + checkmark), the other is at-rest.
      Button {
        model.setMode(.online)
      } label: {
        Label("Online", systemImage: model.mode == .online ? "largecircle.fill.circle" : "circle")
      }
      Button {
        model.setMode(.offline)
      } label: {
        Label("Offline", systemImage: model.mode == .offline ? "largecircle.fill.circle" : "circle")
      }
      Button("Scan Now") {
        Task { await model.scanPublishAndFetch() }
      }
      Divider()
      Button("Quit") {
        NSApp.terminate(nil)
      }
    }
  }
}
