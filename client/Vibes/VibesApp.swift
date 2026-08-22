import AppKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  static var model: AppModel?
  /// Widget-mode state machine; assigned by whichever scene root runs first
  /// (the main scene may never appear when booting straight into widget mode).
  static var widgetModes = WidgetModeCoordinator.shared
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
    #if DEBUG
    // DEMO MODE (VIBES_DEMO_WIDGET=1): enter widget mode ~2s after launch so
    // an unattended script can screenshot the widget without UI interaction.
    // Requires the main scene's onAppear to have run first — it opens at
    // launch, so +2s is comfortably late. Writes the widgetMode defaults key
    // by design of enter() (shared with production; see client-runbook.md).
    if ProcessInfo.processInfo.environment["VIBES_DEMO_WIDGET"] == "1" {
      DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        WidgetModeCoordinator.shared.enter()
      }
    }
    #endif
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

  /// Dock-icon click. In widget mode the click means "restore": run the exit
  /// transition (closes the widget, reopens `id: "main"`, activates) and
  /// return false so AppKit/SwiftUI default reopen handling doesn't also
  /// unarchive the main scene in a race. A stale-session exit (widget window
  /// never restored this session, so no live opener exists) arms `pendingExit`
  /// instead: return true there and let default reopen put some window back —
  /// whichever scene root appears consumes pendingExit and finishes the swap.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    guard Self.widgetModes.isActive else { return true }
    Self.widgetModes.exit()
    return Self.widgetModes.pendingExit
  }

  /// Dock right-click menu — present only while widget mode is active, where
  /// both items are exits from it ("Turn Off Widget Mode" does exactly what
  /// "Show Main Window" does; both wordings are offered because either may be
  /// the one a user reaches for). Returning nil leaves the normal-mode dock
  /// menu untouched, per plan step 4.
  func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    guard Self.widgetModes.isActive else { return nil }
    let showItem = NSMenuItem(
      title: "Show Main Window",
      action: #selector(dockShowMainWindow),
      keyEquivalent: "")
    let offItem = NSMenuItem(
      title: "Turn Off Widget Mode",
      action: #selector(dockTurnOffWidgetMode),
      keyEquivalent: "")
    // Explicit targets, not the responder-chain fallback: with every app
    // window closed (the normal widget-mode state) there is no key window to
    // trust routing a nil-target action back here. NSMenuItem retains its
    // target and the delegate lives for the app's lifetime.
    showItem.target = self
    offItem.target = self
    let menu = NSMenu()
    menu.addItem(showItem)
    menu.addItem(offItem)
    return menu
  }

  @objc private func dockShowMainWindow() {
    Self.widgetModes.exit()
  }

  @objc private func dockTurnOffWidgetMode() {
    Self.widgetModes.exit()
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
  // Process-wide widget-mode state machine; scenes receive it via
  // environmentObject, AppKit-side handlers reach it through AppDelegate.
  // Menus read `widgetModes.isActive` directly — it is published precisely so
  // menu surfaces observe flips made through any path.
  @ObservedObject private var widgetModes = WidgetModeCoordinator.shared
  @State private var showInviteFriend = false
  // Mirrors the views' shared "feedViewMode" key so the ⌘L command can flip it;
  // @AppStorage works in an App struct, and MainPanel/HomeView re-render off the
  // same UserDefaults key with no extra plumbing.
  @AppStorage("feedViewMode") private var feedViewModeRaw = FeedViewMode.orbit.rawValue

  // Owns the Sparkle updater for the app's lifetime; starts it immediately so
  // background checks run and `canCheckForUpdates` is observable.
  // DEMO MODE (DEBUG only, VIBES_DEMO_FEED=1): no updater at all — unattended
  // screenshot runs must never trip update prompts or Sparkle's prefs writes.
  // Optional in BOTH configurations so call sites stay uniform.
  #if DEBUG
  private let updaterController: SPUStandardUpdaterController? =
    ProcessInfo.processInfo.environment["VIBES_DEMO_FEED"] == "1"
      ? nil
      : SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
      )
  #else
  private let updaterController: SPUStandardUpdaterController? =
    SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  #endif

  var body: some Scene {
    // A single, unique main window. This was a WindowGroup, which let every
    // openWindow(id: "main") — the menu bar's Show Vibes / Invite items, ⌘N,
    // an invite link — stack up another copy of the app UI. Duplicates all
    // shared the same invite state, so one click opened a sheet on each of
    // them and activation raised the whole pile. Window reuses the one
    // window instead, and drops File ▸ New Window along with it.
    Window("Vibes", id: "main") {
      ContentView(showInviteFriend: $showInviteFriend)
        .environmentObject(model)
        .environmentObject(widgetModes)
        // Resizable main window (macOS 26): anchor the top-left during resizes
        // so the header stays put and the window grows down/right.
        .windowResizeAnchor(.topLeading)
        .onOpenURL { url in
          widgetModes.deliverDeepLink(url, to: model)
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
        // DEMO MODE: no updater, so no check-for-updates item either.
        if let updaterController {
          CheckForUpdatesView(updater: updaterController.updater)
        }
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

    // Widget mode: the same sky, chrome-less, as a transparent backmost
    // desktop window. Shares the AppModel so feed/presence updates flow with
    // zero extra plumbing; the mode state machine guarantees only one content
    // surface is open at a time.
    Window("Vibes Widget", id: "widget") {
      WidgetSkyView()
        .environmentObject(model)
        .environmentObject(widgetModes)
    }
    .windowStyle(.hiddenTitleBar)
    // First appearance matches the main window's default proportions, centered
    // by the system; the frame is then remembered via setFrameAutosaveName
    // ("widget") in WidgetWindowConfigurator.
    .defaultSize(width: 460, height: 620)

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
        restoreMainWindow()
      }
      Button("Invite a Friend...") {
        restoreMainWindow()
        showInviteFriend = true
      }
      .keyboardShortcut(Shortcuts.invite)
      // Widget mode hides every window, and a hidden Dock icon (accessory
      // policy) removes dock-based restore too — this explicit item keeps the
      // menu bar carrying the full restore path on its own.
      if widgetModes.isActive {
        Button("Show Main Window") {
          widgetModes.exit()
        }
      }
      // DEMO MODE: no updater, so no check-for-updates item here either.
      if let updaterController {
        CheckForUpdatesView(updater: updaterController.updater)
      }
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
      // Widget-mode toggle in the same filled/at-rest circle language. Only
      // offered once configured — the setup screen must never end up hidden
      // behind a desktop widget.
      if model.isConfigured {
        Button {
          if widgetModes.isActive {
            widgetModes.exit()
          } else {
            widgetModes.enter()
          }
        } label: {
          Label(
            "Widget Mode",
            systemImage: widgetModes.isActive ? "largecircle.fill.circle" : "circle")
        }
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

  /// Menu-bar route to the main window. While widget mode is active every
  /// such route goes through the coordinator's exit transition — openWindow
  /// alone would stack main over the widget; exit() closes the widget first.
  private func restoreMainWindow() {
    if widgetModes.isActive {
      widgetModes.exit()  // also activates the app
    } else {
      NSApp.activate(ignoringOtherApps: true)
      openWindow(id: WidgetModeCoordinator.mainWindowID)
    }
  }
}
