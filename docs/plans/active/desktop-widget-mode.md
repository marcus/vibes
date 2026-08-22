# Desktop Widget Mode

**Status:** Active — not started
**Created:** 2026-08-21
**Targets:** `client/` (SwiftUI macOS app)

## Goal

Add a widget mode where Vibes lives on the desktop as a transparent,
backmost window: when the user reveals the desktop, they see the presence
sky — the same content the main window shows today, but without any app
chrome (no wordmark row, no glass controls, no footer, no titlebar/traffic
lights, no window background). The window sits at the desktop layer so
normal app windows stack above it.

Ways back to the normal chrome:

1. Clicking the Vibes Dock icon ("taskbar" on macOS) restores the main
   window chrome.
2. Right-clicking the Vibes Dock icon offers explicit restore items.
3. The existing menu bar extra gains a widget-mode toggle and a
   show-main-window item.

## Corrections to the request assumptions

Two facts differ from how the feature was described; recorded here so the
plan matches reality:

- **A menu bar item already exists.** `MenuBarExtra("Vibes", …)` lives in
  `VibesApp.swift:186`. This plan extends it rather than creating new
  menu-bar infrastructure.
- **The Dock right-click menu does not exist yet.** There is no
  `applicationDockMenu(_:)` anywhere; adding it to the existing
  `AppDelegate` (`VibesApp.swift:5`) is genuinely new functionality.

## Current state (what the plan builds on)

- Single main scene: `Window("Vibes", id: "main")` (`VibesApp.swift:131`),
  `.windowStyle(.hiddenTitleBar)`, freely resizable.
- Chrome lives in `MainPanel` (`ContentView.swift:245`): wordmark +
  `GlassEffectContainer` controls (`FeedViewToggle`, `PresenceLight`,
  refresh glyph), `Footer` overlay (invite/settings), sheets, and the
  unified-toolbar traffic-light band from `TrafficLightAligner`
  (`ContentView.swift:28`).
- The circles are `OrbitView` (`OrbitView.swift:36`): `PulseCore` plus one
  `OrbView` per online member. Offline friends render in `DriftDock`
  (`OrbitView.swift:617`) — the "DRIFTING · sam 2h" band under the sky.
- Ambient motion (bob/breath/sheen) is Core Animation driven
  (`AmbientMotion.swift`), gated by `allowsMotion` =
  `windowAllowsAnimation && !reduceMotion`, where `windowAllowsAnimation`
  comes from `WindowAnimationVisibilityReader` (`OrbitView.swift:113`)
  observing occlusion state. No `TimelineView`, no per-frame timers.
- One shared `AppModel` drives everything: 180-second
  `scanPublishAndFetch()` loop, presence mode, feed, publish-on-quit via
  `AppDelegate.applicationShouldTerminate`.
- Existing preference plumbing to mirror: `@AppStorage` keys like
  `feedViewMode` (read both by views and by the App struct for menus),
  `hideDockIcon` → `DockIcon.applyCurrent()` (`AppPreferences.swift:50`),
  which runs the app as `.accessory` (no Dock tile) when set.

## Settled decisions

- **Separate scene, not a restyled main window.** Add a second
  `Window(id: "widget")` scene rendering a chrome-less content view that
  shares the same `AppModel` via `.environmentObject(model)` — feed, mode,
  and statuses update with zero extra plumbing. Entering widget mode closes
  the main window; leaving it reopens `id: "main"` and closes the widget.
  One content surface at a time avoids duplicate-sheet/duplicate-state bugs
  the project already hit once with a `WindowGroup` (see comment at
  `VibesApp.swift:125–130`).
- **Content = sky only.** The widget view renders `OrbitView`'s sky
  (pulse core + orbs) full-bleed over a transparent background. It omits:
  the header/controls row, `Footer`, sheets, the drift dock, and the empty-
  friends invite line (the widget is decoration; invites belong to the
  restored window).
- **No drifting vibers in widget mode.** Offline friends are simply not
  shown; the DRIFTING band is a dense text strip that reads poorly against
  a wallpaper and adds layout cost for no glance value.
- **Static sky in widget mode.** Ambient motion is disabled in widget mode
  (`allowsMotion` forced false there). The sky redraws only when the
  shared 180-second loop updates data. This is the low-CPU guarantee:
  zero timers, zero animation work at idle. (Reduce Motion already forces
  this same state in the normal window. Note: whether a backmost window
  under opaque windows reports `.visible` occlusion — and thus what
  `WindowAnimationVisibilityReader` would decide on its own — is not worth
  depending on either way; widget mode overrides it explicitly.)
- **Click-through widget with a fixed v1 frame.** The widget window sets
  `ignoresMouseEvents = true`: clicks fall through to whatever is beneath
  (wallpaper, desktop icons). All interaction — restore, settings, mode
  toggle — happens through the Dock, the menu bar extra, or the restored
  main window. The frame defaults to centered in the main display at the
  current default window size and is remembered via
  `setFrameAutosaveName("widget")`; placement UX (dragging a click-through
  window needs an affordance that doesn't exist yet) is deferred as a
  follow-up. Verify SwiftUI's own per-scene frame restoration doesn't
  clobber the autosave name — pick whichever persistence wins and drop the
  other.
- **Restore semantics — one entry point, many triggers.** Dock icon click
  (via `applicationShouldHandleReopen`), the dock menu's "Show Main
  Window", the menu bar's items, and the *existing* "Show Vibes" /
  "Invite a Friend…" menu items all mean the same thing: exit widget mode —
  close the widget window, reopen `id: "main"`, activate the app.
  "Turn Off Widget Mode" in the dock menu does the same thing. The
  invariant is: no state where both windows are open — which means every
  existing call to `openWindow(id: "main")` (`VibesApp.swift:187–195`) must
  route through the exit transition when widget mode is on, not open main
  unconditionally on top of the widget.
- **Invite deep links in widget mode.** `onOpenURL` is attached to the
  main scene (`VibesApp.swift:140`); with main closed it may not fire.
  Widget-mode entry points must ensure incoming `vibes://invite` URLs still
  work: either attach URL handling at the App level or run the exit
  transition before delivering the URL to `model.handleIncomingURL(_:)`.
  Confirm actual delivery behavior during implementation and wire whichever
  path holds.
- **Preference persistence.** `@AppStorage("widgetMode")` mirrors into the
  App struct (same pattern as `feedViewModeRaw`), so relaunching while in
  widget mode boots straight into it. Widget mode is only offered once
  `model.isConfigured`; the setup screen never hides behind it.

## Unresolved questions

- **Window layer choice.** Two viable placements for the backmost window:
  1. The desktop layer (`CGWindowLevelForKey(.desktopWindow)`, ordered
     below desktop icons) — truly part of the wallpaper; invisible in
     Mission Control's window strip.
  2. Just above the desktop icons but below all normal windows — simpler,
     still "backmost" for daily use, participates more normally in
     Spaces/Expose.
  Implementation starts with option 2 using a concrete level of
  `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)`
  (just above desktop icons, below `.normal`) with `collectionBehavior:
  [.canJoinAllSpaces, .stationary]`, because it is far less brittle across
  Spaces and fullscreen spaces; drop to the true desktop layer only if
  option 2 visibly misbehaves (e.g. appears in Mission Control or steals
  focus rings). Choosing a wrong value here silently lands the window in
  the desktop layer or the Mission Control strip — verify the actual
  stacking during implementation.
- **Fullscreen Spaces.** A stationary widget does not render over
  fullscreen apps. Accepted for v1; noted so nobody files it as a bug
  twice.
- **Hidden Dock icon interaction.** With `hideDockIcon` on, the app is
  `.accessory` and has no Dock tile — dock click/right-click restore paths
  vanish. The menu bar extra (which survives accessory policy) is the
  remaining control surface; its menu must therefore carry the full
  restore path on its own. No fix needed beyond making sure those items
  exist there.

## Work sequence

1. **Widget content view.** Extract/reuse the sky portion of `OrbitView`
   behind a flag (e.g. `showsDriftDock: Bool` / an environment value)
   rather than duplicating layout code. New `WidgetSkyView` composes it
   full-bleed with no chrome, no sheets, no invite line.
2. **Widget window scene + backmost configuration.**
   `Window(id: "widget")` in `VibesApp.body`, sharing the model. A small
   `NSViewRepresentable` (sibling of `TrafficLightAligner`) configures the
   backing `NSWindow` when it appears: `isOpaque = false`,
   `backgroundColor = .clear`, `hasShadow = false`, level +
   `collectionBehavior` per the layer decision, `ignoresMouseEvents`,
   `setFrameAutosaveName("widget")`, `standardWindowButton` visibility
   moot (no titlebar). Reapply on `updateNSView` since AppKit resets
   properties on style changes.
3. **Mode state machine.** `widgetMode` preference + enter/exit transitions
   owned by a small coordinator object shared by both scenes and
   AppDelegate (same pattern as `AppDelegate.model`). Programmatic closing:
   do **not** call `NSWindow.close()` on SwiftUI-managed windows — it can
   desync scene state so later `openWindow(id:)` calls no-op. Instead,
   capture `@Environment(\.dismiss)` inside each scene's root view (it
   closes the window when called from within) and hand it to the
   coordinator; enter = dismiss main + `openWindow(id: "widget")`; exit =
   dismiss widget + `openWindow(id: "main")`. Guard against double
   invocation. Boot restoration: when the stored flag is set, close or
   suppress the auto-restored main scene before it becomes visible (via
   `.defaultVisibility`-equivalent handling — e.g. dismiss from the main
   root view's first appearance — so relaunch doesn't flash or stack both
   scenes). Entering widget mode while Settings or a sheet is open closes
   those first (dismiss order: sheet → widget transition).
4. **Menu bar extra + dock menu + reopen handler.**
   - `MenuBarExtra`: add "Widget Mode" toggle (checked style consistent
     with Online/Offline labels) and, when active, "Show Main Window"
     performing the exit transition. Route the *existing* "Show Vibes" and
     "Invite a Friend…" items through the same exit transition so they can
     never stack main over the widget.
   - Invite deep links: verify whether `onOpenURL` fires for the closed
     main scene; if not, move URL handling to the App level or run the
     exit transition before delivering to `model.handleIncomingURL(_:)`.
   - `AppDelegate.applicationDockMenu(_:)` returning an `NSMenu` with
     "Show Main Window" and "Turn Off Widget Mode" (both no-ops/absent
     when not in widget mode), acting through the shared coordinator.
   - `applicationShouldHandleReopen(_:hasVisibleWindows:)`: when widget
     mode is active, run the exit transition and return `false` (so
     AppKit/SwiftUI default reopen handling doesn't *also* restore main in
     a race); return `true` otherwise.
5. **Performance gating.** Force `allowsMotion == false` for the widget
   instance (parameter or environment), confirm `DriftDock` and the empty-
   sky invite line are compiled out of the widget path, and confirm no new
   timers were introduced. Verify with Activity Monitor: idle widget CPU
   ≈ 0% sampled over 60s, memory delta negligible.
6. **Edge cases and polish.** Unconfigured state hides the toggle; hidden
   Dock icon leaves menu bar restore working; Reduce Motion unaffected
   (widget is already static); multi-display setups show the single widget
   frame wherever it was saved (acceptable for v1, stated here so it isn't
   mistaken for a bug); dark/light wallpapers get a subtle text shadow or
   contrast scrim only if testing shows orb labels are illegible — prefer
   none, per the quiet-style guidance.

## Acceptance

- `make client` builds clean.
- Manual proof: enable widget mode, screenshot showing chrome-less orbs on
  the wallpaper with a normal app window stacked above them; dock click
  restores the full-chrome window; dock right-click shows the restore
  menu; menu bar toggle round-trips both ways.
- Activity Monitor screenshot/sampling showing ≈0% CPU with the widget on
  screen and idle.
- Relaunch with the flag set boots directly into widget mode; quit still
  publishes offline presence (`applicationShouldTerminate` path untouched).

## Out of scope

- Interactive widget (dragging, scrolling, hover states).
- Rendering over fullscreen Spaces.
- Windows/Linux equivalents (Tauri client tracks its own plan).
- Any change to what is published to the relay — this is presentation only.
