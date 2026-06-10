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
  @Environment(\.openWindow) private var openWindow
  @StateObject private var model = AppModel()
  @State private var showInviteFriend = false

  // Owns the Sparkle updater for the app's lifetime; starts it immediately so
  // background checks run and `canCheckForUpdates` is observable.
  private let updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: nil,
    userDriverDelegate: nil
  )

  var body: some Scene {
    WindowGroup("Vibes", id: "main") {
      ContentView(showInviteFriend: $showInviteFriend)
        .environmentObject(model)
        // Resizable main window (macOS 26): anchor the top-left during resizes
        // so the header stays put and the window grows down/right.
        .windowResizeAnchor(.topLeading)
        .onAppear {
          AppDelegate.model = model
        }
        .onOpenURL { url in
          NSApp.activate(ignoringOtherApps: true)
          model.handleIncomingURL(url)
        }
    }
    // Seamless macOS 26 Liquid Glass titlebar: hide the titlebar chrome so the
    // content flows continuously up under the (now floating) traffic lights —
    // no separator line between the window controls and the app content.
    .windowStyle(.hiddenTitleBar)
    // First launch matches the historical 460×620 proportions; the window
    // remembers user resizes thereafter. No .windowResizability(.contentSize)
    // here — the main window is freely resizable (min frame set on ContentView).
    .defaultSize(width: 460, height: 620)
    .commands {
      CommandGroup(after: .appInfo) {
        CheckForUpdatesView(updater: updaterController.updater)
      }
    }

    Settings {
      SettingsView()
        .environmentObject(model)
    }
    .windowResizability(.contentSize)

    MenuBarExtra("Vibes", systemImage: "dot.radiowaves.left.and.right") {
      Button("Show Vibes") {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
      }
      Button("Invite a Friend...") {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        showInviteFriend = true
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
