import Combine
import SwiftUI

// Widget mode — Vibes as a transparent, backmost desktop window (plan:
// docs/plans/active/desktop-widget-mode.md). The widget renders only the
// presence sky: no chrome, no sheets, no drift dock, no ambient motion.
// Exactly one content surface exists at a time; entering widget mode
// dismisses the main window and vice versa.

/// Owns the widget-mode state machine. One process-wide instance, reachable
/// from both scenes (via environmentObject) and from AppKit-side code such as
/// AppDelegate handlers (`WidgetModeCoordinator.shared`).
///
/// Window closing goes through dismiss actions captured *inside* each scene's
/// root view — calling NSWindow.close() on SwiftUI-managed windows desyncs
/// scene state so later openWindow(id:) calls silently no-op. Each scene hands
/// over its own dismiss plus an openWindow closure for the other scene on
/// appear; transitions are therefore only possible while their source window
/// is alive, which is exactly when they are meaningful.
@MainActor
final class WidgetModeCoordinator: ObservableObject {
  static let shared = WidgetModeCoordinator()
  static let storageKey = "widgetMode"
  static let mainWindowID = "main"
  static let widgetWindowID = "widget"

  /// Mirrors the "widgetMode" preference; published so menu/dock surfaces can
  /// observe flips made through any path.
  @Published private(set) var isActive: Bool
  /// Re-entry guard for the enter/exit transitions.
  @Published private(set) var isTransitioning = false
  /// Armed when an exit could not reopen the main window because no live
  /// openWindow closure existed (stale boots where the stored flag says
  /// widget-mode but the widget window never restored, so the widget scene
  /// never registered). The reopen handler returns true in that state so
  /// AppKit's default reopen brings some window back; whichever scene root
  /// appears next completes the recovery (see the two consume methods).
  @Published private(set) var pendingExit = false

  private var dismissMain: (() -> Void)?
  private var openWidget: (() -> Void)?
  private var dismissWidget: (() -> Void)?
  private var openMain: (() -> Void)?

  private init() {
    isActive = UserDefaults.standard.bool(forKey: Self.storageKey)
  }

  // MARK: - Scene registration

  func registerMainScene(dismiss: @escaping () -> Void, openWidget: @escaping () -> Void) {
    dismissMain = dismiss
    self.openWidget = openWidget
  }

  func registerWidgetScene(dismiss: @escaping () -> Void, openMain: @escaping () -> Void) {
    dismissWidget = dismiss
    self.openMain = openMain
  }

  // MARK: - Transitions

  /// Main → widget. Sheets attached to the main scene die with its dismissal;
  /// the standalone Settings window gets a best-effort close so it cannot keep
  /// floating over a desktop that now hosts the widget.
  func enter() {
    // Either captured closure suffices to attempt the transition; requiring
    // both would dead-end edge states where one window never materialized
    // (e.g. a dock click racing first launch).
    guard !isTransitioning, !isActive, dismissMain != nil || openWidget != nil else { return }
    isTransitioning = true
    defer { isTransitioning = false }
    isActive = true
    UserDefaults.standard.set(true, forKey: Self.storageKey)
    closeSettingsBestEffort()
    dismissMain?()
    openWidget?()
  }

  /// Widget → main, bringing the app forward so the restored window lands on
  /// top of whatever the user was doing.
  ///
  /// Always makes forward progress: the stored/published flag flips first,
  /// then whatever window closures are live run. In a stale session (widget
  /// scene never appeared this session, so `openMain` is nil) nothing can be
  /// opened here; `pendingExit` arms recovery instead and the reopen handler
  /// lets AppKit's default reopen put a window back on screen.
  func exit() {
    guard !isTransitioning, isActive else { return }
    isTransitioning = true
    defer { isTransitioning = false }
    isActive = false
    UserDefaults.standard.set(false, forKey: Self.storageKey)
    dismissWidget?()
    if let openMain {
      openMain()
    } else {
      pendingExit = true
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Main-scene root, on appear: main being open IS the completed transition.
  func consumePendingExit() {
    pendingExit = false
  }

  /// Widget-scene root, on appear while mode is already off: default reopen
  /// (or a lost race) materialized the widget during a pending-exit recovery.
  /// Finish the swap with the closures this very appearance just captured.
  func completePendingExitFromWidgetScene() {
    guard pendingExit, !isActive else {
      pendingExit = false
      return
    }
    pendingExit = false
    isTransitioning = true
    defer { isTransitioning = false }
    dismissWidget?()
    openMain?()
    NSApp.activate(ignoringOtherApps: true)
  }

  // MARK: - Deep links

  /// Single deep-link entry point, shared by both scenes' `onOpenURL`
  /// (VibesApp main scene + WidgetSkyView).
  ///
  /// Delivery behavior, verified empirically (temporary DEBUG harness: launch,
  /// enter() into widget mode so the main window is dismissed, then
  /// `open vibes://invite/…`): the main scene's handler STILL fires while its
  /// window is dismissed — this SDK routes open-URL events at scene level even
  /// though `onOpenURL` is a View modifier and the root view is gone. The exit
  /// transition ran before delivery in the same tick and the reopened main
  /// window was visible immediately after.
  ///
  /// WidgetSkyView registers the same handler anyway as defense in depth:
  /// closed-scene non-delivery has historically varied across SwiftUI
  /// versions/platforms, and the widget view is the one receiver guaranteed
  /// alive for the whole widget session. Double delivery costs nothing —
  /// AppModel.handleIncomingURL treats a repeat of the already-pending invite
  /// code as a no-op, so the second call cannot blank the sheet's inviter
  /// name or re-fire the lookup.
  ///
  /// Either way the invite/pairing UI (`pendingInvite` sheet, setup banner)
  /// lives in the main window, so an active widget session is exited before
  /// the model state lands; exit() closes the widget, reopens id:"main", and
  /// activates. Setting pendingInvite before the reopened MainPanel mounts is
  /// safe — the sheet(item:) binding presents it as soon as the window exists.
  func deliverDeepLink(_ url: URL, to model: AppModel) {
    NSApp.activate(ignoringOtherApps: true)
    if isActive {
      exit()
    }
    model.handleIncomingURL(url)
  }

  // The Settings scene is its own window, not part of either content surface,
  // and SwiftUI gives no stable handle to it; close it by title as a best
  // effort. performClose (not close()) keeps the close semantics honest.
  private func closeSettingsBestEffort() {
    for window in NSApp.windows where window.isVisible {
      let title = window.title.lowercased()
      if title.contains("settings") || title.contains("einstellungen") {
        window.performClose(nil)
      }
    }
  }
}

// MARK: - Widget scene

/// The widget's entire content: OrbitView's sky (pulse core + orbs) full-bleed
/// over a transparent background. No header, footer, sheets, drift dock, or
/// invite line; motion forced off regardless of what occlusion state reports.
struct WidgetSkyView: View {
  @EnvironmentObject private var model: AppModel
  @EnvironmentObject private var widgetModes: WidgetModeCoordinator
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Group {
      if let feed = model.feed {
        OrbitView(
          you: feed.you,
          friends: feed.friends,
          pulse: feed.pulse,
          showsDriftDock: false,
          showsInviteLine: false,
          forcesStatic: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      // No feed yet (or unconfigured): stay empty and transparent — the
      // shared loop fills the sky the moment data arrives.
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ignoresSafeArea()
    .background(Color.clear)
    // Backmost/clear/draggable configuration (lightless chrome too),
    // reapplied on every update because AppKit resets these properties on
    // style changes.
    .background(WidgetWindowConfigurator())
    // Deep-link receiver for widget mode (defense in depth). Verified on this
    // SDK the dismissed main scene still receives open-URL events, but that
    // routing has varied across SwiftUI versions; this view is the one
    // receiver guaranteed alive for the whole widget session, so it registers
    // too. Both routes converge on deliverDeepLink — see there for details.
    .onOpenURL { url in
      widgetModes.deliverDeepLink(url, to: model)
    }
    .onAppear {
      // The main scene may never appear when booting in widget mode, but quit
      // still has to publish offline presence — keep both statics current
      // from whichever surface runs.
      AppDelegate.model = model
      AppDelegate.widgetModes = widgetModes
      widgetModes.registerWidgetScene(
        dismiss: { dismiss() },
        openMain: { openWindow(id: WidgetModeCoordinator.mainWindowID) }
      )
      // Invariant enforcement from the widget side: if this window ever
      // materializes while widget mode is off, it must not stay. During a
      // pending-exit recovery this window may be exactly what default reopen
      // restored — in that case finish the swap with the closures registered
      // above (fresh this tick) so main opens; otherwise just remove self.
      if !widgetModes.isActive {
        let completingRecovery = widgetModes.pendingExit
        if completingRecovery {
          widgetModes.completePendingExitFromWidgetScene()
        } else {
          dismiss()
        }
      }
    }
  }
}

/// Configures the backing NSWindow as a clear, shadowless, draggable-anywhere
/// desktop layer just above the desktop icons (below every normal window).
/// Sibling pattern of TrafficLightAligner; properties are set in makeNSView
/// AND updateNSView since AppKit resets them on style changes.
private struct WidgetWindowConfigurator: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { Self.configure(view.window) }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async { Self.configure(nsView.window) }
  }

  static func configure(_ window: NSWindow?) {
    guard let window else { return }
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    // Lightless: .hiddenTitleBar on macOS 26 still renders floating traffic
    // lights plus a hairline titlebar backdrop above them, which reads as a
    // bug over the wallpaper. Kill all of it; reapplied every pass because
    // AppKit resets these properties on style changes.
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    for button in [
      window.standardWindowButton(.closeButton),
      window.standardWindowButton(.miniaturizeButton),
      window.standardWindowButton(.zoomButton),
    ] {
      button?.isHidden = true
      button?.alphaValue = 0
    }
    // Drag anywhere (user decision, supersedes the v1 click-through rule):
    // the sky has no interactive surfaces — orbs and labels render only,
    // hover/tooltip affordances install no mouse-down handlers — so the whole
    // window can act as its own drag handle.
    window.isMovableByWindowBackground = true
    // Just above the desktop icons, below .normal — plan option 2, less
    // brittle across Spaces/fullscreen than the true desktop layer.
    window.level = NSWindow.Level(
      rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    window.collectionBehavior = [.canJoinAllSpaces, .stationary]
    // Frame persistence: the autosave name is the only writer that works.
    // Verified empirically (temporary DEBUG harness, isolated bundle id):
    // after moving the widget and force-killing the app, SwiftUI's implicit
    // per-scene frame restoration never participated — no Saved Application
    // State was ever written for the app, and with setFrameAutosaveName
    // skipped the window relaunched at its default centered position. With
    // the autosave name set, "NSWindow Frame widget" was written to defaults
    // immediately on move and the restored session loaded it in configure()
    // (AppKit adjusting X across displays per its own recorded-screen logic).
    // Keep this call; there is no competing mechanism to remove. Dragged
    // positions therefore persist across relaunches for free.
    if window.frameAutosaveName.isEmpty {
      window.setFrameAutosaveName("widget")
    }
  }
}
