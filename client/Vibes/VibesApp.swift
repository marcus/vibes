import AppKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  static var model: AppModel?
  private var isTerminatingAfterOfflinePublish = false
  /// Set when another copy of Vibes was already running at launch. This
  /// instance is then a duplicate: it forwards its launch URLs to the
  /// primary and exits without ever showing UI.
  private var primaryInstance: NSRunningApplication?
  private var capturedURLs: [URL] = []

  func applicationWillFinishLaunching(_ notification: Notification) {
    #if !DEBUG
      // Single-instance guard, release builds only (dev builds run alongside
      // a release copy on purpose). Clicking an invite link when Launch
      // Services resolves to a different copy on disk than the running one
      // spawns a second Vibes; defer to the one already running.
      let current = NSRunningApplication.current
      if let primary = NSRunningApplication
        .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        .first(where: { $0 != current && !$0.isTerminated })
      {
        primaryInstance = primary
        // No Dock bounce or window flash for the doomed duplicate.
        NSApp.setActivationPolicy(.prohibited)
        // Take over kAEGetURL from SwiftUI so the invite link that launched
        // us can be replayed against the primary instance instead of being
        // swallowed here. URL events arrive after this callback but before
        // applicationDidFinishLaunching.
        NSAppleEventManager.shared().setEventHandler(
          self,
          andSelector: #selector(captureURLEvent(_:replyEvent:)),
          forEventClass: AEEventClass(kInternetEventClass),
          andEventID: AEEventID(kAEGetURL)
        )
        return
      }
    #endif
    DockIcon.applyCurrent()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if let primary = primaryInstance {
      forwardLaunchAndTerminate(to: primary)
      return
    }
    AppAppearance.applyCurrent()
  }

  @objc private func captureURLEvent(
    _ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor
  ) {
    if let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
      let url = URL(string: string)
    {
      capturedURLs.append(url)
    }
  }

  /// Brings the already-running instance forward, hands it any URLs from
  /// this launch (invite links), and quits this duplicate.
  private func forwardLaunchAndTerminate(to primary: NSRunningApplication) {
    guard let bundleURL = primary.bundleURL else {
      primary.activate(options: [.activateAllWindows])
      NSApp.terminate(nil)
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    let terminate: (NSRunningApplication?, Error?) -> Void = { _, _ in
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
    if capturedURLs.isEmpty {
      // Plain relaunch (e.g. double-clicking another copy): send the primary
      // a reopen so it restores its main window, not just focus.
      NSWorkspace.shared.openApplication(
        at: bundleURL, configuration: configuration, completionHandler: terminate)
    } else {
      NSWorkspace.shared.open(
        capturedURLs, withApplicationAt: bundleURL, configuration: configuration,
        completionHandler: terminate)
    }
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    // The duplicate must not publish offline presence on its way out — the
    // primary instance is still online.
    guard primaryInstance == nil, !isTerminatingAfterOfflinePublish, let model = Self.model,
      model.isConfigured
    else {
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
  @Environment(\.openSettings) private var openSettings
  @StateObject private var model = AppModel()
  @State private var showInviteFriend = false
  // Mirrors the views' shared "feedViewMode" key so the ⌘L command can flip it;
  // @AppStorage works in an App struct, and MainPanel/HomeView re-render off the
  // same UserDefaults key with no extra plumbing.
  @AppStorage("feedViewMode") private var feedViewModeRaw = FeedViewMode.orbit.rawValue

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
      CommandMenu("Friends") {
        Button("Invite a Friend…") { showInviteFriend = true }
          .keyboardShortcut(Shortcuts.invite)
      }
      CommandGroup(after: .toolbar) {
        Button(feedViewModeRaw == FeedViewMode.orbit.rawValue ? "Switch to List" : "Switch to Orbit") {
          feedViewModeRaw = (feedViewModeRaw == FeedViewMode.orbit.rawValue
            ? FeedViewMode.list : FeedViewMode.orbit).rawValue
        }
        .keyboardShortcut(Shortcuts.toggleFeed)
        Button("Scan Now") {
          // Mirror the refresh button's re-entry guard: scanPublishAndFetch
          // doesn't self-guard, and .disabled isn't available on a menu command.
          guard !model.isBusy else { return }
          Task { await model.scanPublishAndFetch() }
        }
        .keyboardShortcut(Shortcuts.scan)
      }
    }

    Settings {
      SettingsView()
        .environmentObject(model)
        // The native Settings scene ignores ESC; treat it like a modal and
        // close the focused (Settings) window on the cancel command.
        .onExitCommand { NSApp.keyWindow?.performClose(nil) }
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
      .keyboardShortcut(Shortcuts.invite)
      CheckForUpdatesView(updater: updaterController.updater)
      Divider()
      // Menu counterpart of the in-app PresenceLight (ContentView.swift). The
      // one-dot toggle reads poorly as a menu item, so the menu keeps explicit
      // Online/Offline entries: the active mode is "lit" (filled dot), the
      // other is at-rest.
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
      .keyboardShortcut(Shortcuts.scan)
      Divider()
      // With the Dock icon hidden there is no app menu, so the menu bar item
      // is the only always-available way into Settings.
      Button("Settings...") {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
      }
      Button("Quit") {
        NSApp.terminate(nil)
      }
    }
  }
}
