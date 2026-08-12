import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @Binding var showInviteFriend: Bool

  var body: some View {
    Group {
      if model.isConfigured {
        MainPanel(showInviteFriend: $showInviteFriend)
      } else {
        SetupPanel()
      }
    }
    // Resizable main window: hold a sensible minimum and let the window grow
    // freely. The feed caps card width internally so cards don't stretch
    // edge-to-edge on wide windows.
    .frame(minWidth: 460, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
    .background(TrafficLightAligner())
  }
}

// Drops the traffic lights so they center on the header row. The hidden
// titlebar parks the buttons in a fixed 28pt band that AppKit won't let us
// move directly; installing an empty unified toolbar makes that band tall
// enough that the system centers the buttons lower, level with the wordmark
// row (which lays out from the true window top via ignoresSafeArea).
private struct TrafficLightAligner: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { configure(view.window) }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async { configure(nsView.window) }
  }

  private func configure(_ window: NSWindow?) {
    guard let window, window.toolbar == nil else { return }
    let toolbar = NSToolbar(identifier: "vibes-titlebar-spacer")
    toolbar.showsBaselineSeparator = false
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
  }
}

private struct SetupPanel: View {
  @EnvironmentObject private var model: AppModel
  @State private var relayURL = "https://vibes.opentangle.com"
  @State private var token = ""
  @State private var handle = ""
  @State private var displayName = ""
  @State private var deviceLabel = Host.current().localizedName ?? "Mac"
  @State private var showAdvanced = false

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Header(title: "vibes")

      // An invite arrived before sign-in — via the clipboard handoff from the
      // invite page or a vibes://invite deep link. Registration below accepts
      // it automatically (AppModel.install), so the banner promises that.
      if let invite = model.pendingInvite {
        VStack(alignment: .leading, spacing: 8) {
          Text(invite.inviterName.map { "\($0) invited you to Vibes." } ?? "You have a Vibes invite.")
            .font(.title3.weight(.light))
          Text(
            invite.inviterName.map {
              "Enter a display name to create your account and connect with \($0)."
            } ?? "Enter a display name to create your account and accept the invite."
          )
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
        }
      }

      // Zero-effort path: iCloud Keychain carried the account over from
      // another Mac. One click mints this Mac its own token and signs in.
      if let synced = model.syncedAccount {
        VStack(alignment: .leading, spacing: 8) {
          Text("Welcome back, \(synced.displayName).")
            .font(.title3.weight(.light))
          Text("Found your account in iCloud Keychain.")
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
          Button {
            Task { await model.continueAsSyncedAccount(deviceLabel: deviceLabel) }
          } label: {
            Label("Use this Mac as @\(synced.handle)", systemImage: "person.crop.circle.badge.checkmark")
          }
          .buttonStyle(.glassProminent)
          .disabled(model.isBusy)
        }

        Divider()

        Text("Or set up something else:")
          .font(.caption)
          .foregroundStyle(Color.secondary)
      }

      Text("Let's set you up.")
        .font(.title3.weight(.light))

      Field("display name", text: $displayName, prompt: "your name")

      HStack(spacing: 10) {
        Button {
          Task {
            await model.register(
              displayName: displayName,
              deviceLabel: deviceLabel,
              relayURLText: relayURL
            )
          }
        } label: {
          Label(
            model.pendingInvite == nil ? "Save display name" : "Create account and accept invite",
            systemImage: "checkmark"
          )
        }
        .buttonStyle(.glassProminent)
        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
      }

      Divider()

      // Second Mac, same account: pairing-code flow. The code comes from the
      // already-signed-in Mac (Settings → General → Link Another Mac).
      VStack(alignment: .leading, spacing: 8) {
        Text("Already using Vibes on another Mac?")
          .font(.subheadline)
        Text(
          "In Vibes on that Mac, open Settings -> General -> Link Another Mac, then enter the code here. This is for your own second Mac, not a friend invite."
        )
          .font(.caption)
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
          TextField("KQ4M-7XW2", text: $model.linkCodeInput)
            .textFieldStyle(.plain)
            .padding(10)
            .background(Color(nsColor: .quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(maxWidth: 160)
            .onSubmit { linkThisMac() }
          Button {
            linkThisMac()
          } label: {
            Label("Link this Mac", systemImage: "laptopcomputer")
          }
          .buttonStyle(.glass)
          .disabled(model.linkCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
        }
      }

      DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
        VStack(alignment: .leading, spacing: 12) {
          Field("relay url", text: $relayURL, prompt: "https://vibes.opentangle.com")

          VStack(alignment: .leading, spacing: 8) {
            Text("I already have a token")
              .font(.caption)
              .foregroundStyle(Color.secondary)
            Field("token", text: $token, prompt: "existing relay token")
            HStack(spacing: 12) {
              Field("handle", text: $handle, prompt: "yourname")
              Field("device", text: $deviceLabel, prompt: "MacBook")
            }
          }

          GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
              Button {
                Task {
                  await model.completeManualSetup(
                    relayURLText: relayURL,
                    token: token,
                    handle: handle,
                    displayName: displayName,
                    deviceLabel: deviceLabel
                  )
                }
              } label: {
                Label("Use token", systemImage: "key")
              }
              .buttonStyle(.glass)

              Button {
                Task { await model.importConfigFile() }
              } label: {
                Label("Import JSON", systemImage: "square.and.arrow.down")
              }
              .buttonStyle(.glass)
            }
          }
        }
        .padding(.top, 12)
      }
      .font(.subheadline)

      if let error = model.lastError {
        Text(error)
          .font(.caption)
          .foregroundStyle(Color.red)
      }

      Spacer()
    }
    .padding(28)
    // Clear the floating traffic lights (hidden-titlebar main window): drop the
    // header below the ~28pt window-control band so the "vibes" wordmark doesn't
    // collide with the red/yellow/green controls.
    .safeAreaPadding(.top, 28)
    // iCloud Keychain may deliver the synced account minutes after first
    // launch — re-check whenever the unconfigured app comes to the front.
    // Same moment re-checks the clipboard: the user may have copied their
    // invite link after launching the app.
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      model.recheckSyncedAccount()
      model.checkClipboardForInvite()
    }
    // A vibes://link deep link can carry the source relay (self-hosted setups).
    .onReceive(model.$linkRelayHint) { hint in
      if let hint {
        relayURL = hint
      }
    }
  }

  private func linkThisMac() {
    Task {
      await model.linkThisMac(
        code: model.linkCodeInput,
        deviceLabel: deviceLabel,
        relayURLText: relayURL
      )
    }
  }
}

private struct MainPanel: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.openSettings) private var openSettings
  @Binding var showInviteFriend: Bool
  // Orbit is the default sky; the list is the staid fallback, one toggle away.
  // Shared with HomeView through UserDefaults (same key).
  @AppStorage("feedViewMode") private var feedViewModeRaw = FeedViewMode.orbit.rawValue

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      // Slim titlebar-style header (design/mockups): the row shares the
      // traffic-light band — wordmark + live count just right of the window
      // controls, floating controls on the right — instead of sitting in its
      // own block below them.
      HStack(alignment: .center, spacing: 10) {
        Text("vibes")
          // Exact size kept: the wordmark is a deliberate display mark, at the
          // mockups' titlebar scale.
          .font(.system(size: 17, weight: .light))
        Spacer()
        GlassEffectContainer(spacing: 10) {
          HStack(spacing: 10) {
            FeedViewToggle(selectionRaw: $feedViewModeRaw)
            PresenceLight(
              mode: model.mode,
              toggle: { model.setMode(model.mode == .online ? .offline : .online) }
            )
            Button {
              // Guard re-entry in the action rather than via .disabled():
              // .disabled dims the whole button, which would wash out the green
              // busy tint. scanPublishAndFetch doesn't self-guard.
              guard !model.isBusy else { return }
              Task { await model.scanPublishAndFetch() }
            } label: {
              RefreshGlyph(isBusy: model.isBusy)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Scan Now")
            .help("Scan Now (⌘R)")
          }
        }
      }
      // Clear the traffic lights horizontally: in the unified-toolbar band
      // (TrafficLightAligner) the buttons end ~86pt from the window edge, so
      // inset the wordmark past them with a small gap.
      .padding(.leading, 72)

      // Float the actions over the feed instead of parking them in their own
      // footer row: they sit bottom-trailing, overlapping the drifting dock /
      // the tail of the last status — which is fine to overlay — and reclaim
      // the vertical band the footer used to cost the sky.
      HomeView(openInviteFriend: { showInviteFriend = true })
        .overlay(alignment: .bottom) {
          Footer(
            openInviteFriend: { showInviteFriend = true },
            openSettings: { openSettings() }
          )
          .padding(.trailing, 8)
          .padding(.bottom, 5)
        }
    }
    .padding(.horizontal, 22)
    .padding(.bottom, 22)
    .padding(.top, 14)
    // Share the traffic-light band (mockup titlebar): lay out from the true
    // window top instead of below the hidden titlebar's safe-area inset; the
    // 14pt top padding centers the header row on the unified-toolbar lights.
    .ignoresSafeArea(.container, edges: .top)
    .sheet(item: $model.pendingInvite) { invite in
      InviteSheet(invite: invite)
        .environmentObject(model)
    }
    .sheet(isPresented: $showInviteFriend) {
      InviteFriendView()
        .environmentObject(model)
    }
  }

}

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    TabView(selection: $model.settingsTab) {
      GeneralSettingsPane()
        .tabItem {
          Label("General", systemImage: "gearshape")
        }
        .tag(SettingsTab.general)

      ProfileIconSettingsPane()
        .tabItem {
          Label("Profile Icon", systemImage: "person.crop.circle")
        }
        .tag(SettingsTab.profileIcon)

      RepositoriesSettingsPane()
        .tabItem {
          Label("Repositories", systemImage: "folder")
        }
        .tag(SettingsTab.repositories)

      SharingSettingsPane()
        .tabItem {
          Label("Sharing", systemImage: "hand.raised")
        }
        .tag(SettingsTab.sharing)

      AdvancedSettingsPane()
        .tabItem {
          Label("Advanced", systemImage: "wrench.and.screwdriver")
        }
        .tag(SettingsTab.advanced)
    }
    .frame(width: 600, height: 520)
    .background(SettingsTrafficLightInsetter())
  }
}

// The Settings window's default titlebar parks the traffic lights hard in the
// top-left corner. The main window gets a roomier liquid-glass placement via a
// unified toolbar (TrafficLightAligner), but Settings can't borrow that trick —
// its TabView already owns the window toolbar for the tab strip. So we nudge the
// three standard window buttons down and to the right ourselves, re-applying
// whenever AppKit re-lays-out the titlebar (resize, key changes). Offsets are
// measured from each button's AppKit-default origin so repeated applies don't
// compound.
private struct SettingsTrafficLightInsetter: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView { InsetView() }
  func updateNSView(_ nsView: NSView, context: Context) {
    // Re-apply after the current layout pass: a tab switch re-lays-out the
    // titlebar buttons after SwiftUI's update runs, so a synchronous call here
    // would be overwritten.
    DispatchQueue.main.async { (nsView as? InsetView)?.applyInset() }
  }

  final class InsetView: NSView {
    private static let extraInset = CGSize(width: 8, height: 8)
    private static let buttonTypes: [NSWindow.ButtonType] = [
      .closeButton, .miniaturizeButton, .zoomButton,
    ]
    private var defaults: [NSWindow.ButtonType: CGPoint] = [:]
    private var observers: [Any] = []
    private var applying = false

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      observers.forEach(NotificationCenter.default.removeObserver)
      observers.removeAll()
      guard let window else { return }
      // The button container re-lays-out on resize, tab switch, and key
      // changes; watch its frame so we re-apply whenever AppKit resets the
      // buttons to their default corner.
      if let bar = window.standardWindowButton(.closeButton)?.superview {
        bar.postsFrameChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
          forName: NSView.frameDidChangeNotification, object: bar, queue: .main
        ) { [weak self] _ in self?.applyInset() })
      }
      for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification] {
        observers.append(NotificationCenter.default.addObserver(
          forName: name, object: window, queue: .main
        ) { [weak self] _ in self?.applyInset() })
      }
      DispatchQueue.main.async { [weak self] in self?.applyInset() }
    }

    func applyInset() {
      guard let window, !applying else { return }
      applying = true
      defer { applying = false }
      for type in Self.buttonTypes {
        guard let button = window.standardWindowButton(type) else { continue }
        // Capture AppKit's default origin once; the titlebar lays the buttons
        // out from the left so it stays put across width changes.
        let base = defaults[type] ?? {
          let origin = button.frame.origin
          defaults[type] = origin
          return origin
        }()
        // Titlebar uses a top-left-ish flipped feel but NSView origin is
        // bottom-left, so "down" is a smaller y.
        let target = CGPoint(
          x: base.x + Self.extraInset.width, y: base.y - Self.extraInset.height
        )
        if button.frame.origin != target { button.setFrameOrigin(target) }
      }
    }
  }
}

private struct GeneralSettingsPane: View {
  @EnvironmentObject private var model: AppModel
  @AppStorage("feedTextSize") private var feedTextSizeRaw = FeedTextSize.large.rawValue
  @State private var displayName = ""
  @State private var handle = ""
  @State private var deviceLabel = ""
  @State private var relayURL = ""
  @State private var copiedLinkCode = 0
  @State private var copiedLinkURL = 0
  @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue
  // populate() seeds this from SMAppService; a literal here avoids an XPC
  // status query on every struct init.
  @State private var launchAtLogin = false
  @State private var launchAtLoginError: String?
  @State private var launchAtLoginNeedsApproval = false
  @AppStorage(DockIcon.storageKey) private var hideDockIcon = false

  var body: some View {
    Form {
      Section {
        Text("Account and relay details for this Mac.")
          .foregroundStyle(.secondary)
      }

      Section("Appearance") {
        Picker("Theme", selection: $appearanceRaw) {
          ForEach(AppAppearance.allCases) { appearance in
            Text(appearance.label).tag(appearance.rawValue)
          }
        }
        .onChange(of: appearanceRaw) {
          AppAppearance.applyCurrent()
        }
        Picker("Feed text size", selection: $feedTextSizeRaw) {
          ForEach(FeedTextSize.allCases) { size in
            Text(size.label).tag(size.rawValue)
          }
        }
      }

      Section("Startup") {
        Toggle("Open Vibes at login", isOn: $launchAtLogin)
          .onChange(of: launchAtLogin) { _, enabled in
            // The toggle can also be flipped back here when registration fails,
            // so only touch SMAppService when the value actually diverges.
            // "Registered but awaiting approval in System Settings" counts as
            // on here, so toggling off still unregisters the inert item.
            let registered = LaunchAtLogin.isEnabled || LaunchAtLogin.requiresApproval
            guard enabled != registered else { return }
            do {
              try LaunchAtLogin.set(enabled: enabled)
              launchAtLoginError = nil
              launchAtLoginNeedsApproval = enabled && LaunchAtLogin.requiresApproval
            } catch {
              launchAtLogin = LaunchAtLogin.isEnabled
              launchAtLoginError = error.localizedDescription
              launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
            }
          }
        if launchAtLoginNeedsApproval {
          HStack {
            Text("macOS is blocking this login item. Enable Vibes in System Settings.")
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button("Open Login Items") {
              LaunchAtLogin.openSystemSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }
        } else if let launchAtLoginError {
          Text(launchAtLoginError)
            .font(.caption)
            .foregroundStyle(.red)
        }
        Toggle("Hide Dock icon", isOn: $hideDockIcon)
          .onChange(of: hideDockIcon) { _, hidden in
            DockIcon.set(hidden: hidden)
          }
        if hideDockIcon {
          Text("Vibes keeps running in the menu bar — use the menu bar item to reopen or quit it.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Identity") {
        EditableSettingField(
          label: "Display Name",
          prompt: "your name",
          text: $displayName,
          save: { model.updateDisplayName(displayName) }
        )
        EditableSettingField(
          label: "Handle",
          prompt: "yourname",
          text: $handle,
          save: { model.updateHandle(handle) }
        )
        EditableSettingField(
          label: "Device Label",
          prompt: "MacBook",
          text: $deviceLabel,
          save: { model.updateDeviceLabel(deviceLabel) }
        )
      }

      Section("Relay") {
        EditableSettingField(
          label: "Relay URL",
          prompt: "https://vibes.opentangle.com",
          text: $relayURL,
          save: { model.updateRelayURL(relayURL) }
        )
      }

      Section("Devices") {
        if model.devices.isEmpty {
          Text("Your Macs appear here once they connect.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(model.devices) { device in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(device.label ?? "Mac")
                Text(deviceSubtitle(device))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              if device.current {
                Text("This Mac")
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(Color(nsColor: .quaternarySystemFill))
                  .clipShape(Capsule())
              } else {
                Button("Remove") {
                  Task { await model.revokeDevice(device) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
              }
            }
          }
        }
      }

      Section("Link Another Mac") {
        if let link = activeLinkCode {
          LabeledContent("Code") {
            Text(link.code)
              .font(.system(.title3, design: .monospaced).weight(.medium))
              .textSelection(.enabled)
          }
          Text("On your new Mac, open Vibes and choose “Link this Mac”, then enter this code. It expires \(link.expiresAt.formatted(.relative(presentation: .named))) and works once. Copy Link gives a vibes:// URL you can message to yourself instead.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 8) {
            Button {
              model.copyDeviceLinkCode()
              copiedLinkCode += 1
            } label: {
              ConfirmingLabel("Copy Code", systemImage: "doc.on.doc", trigger: copiedLinkCode)
            }
            .buttonStyle(.bordered)
            .actionFeedback(trigger: copiedLinkCode)
            Button {
              model.copyDeviceLinkURL()
              copiedLinkURL += 1
            } label: {
              ConfirmingLabel("Copy Link", systemImage: "link", trigger: copiedLinkURL)
            }
            .buttonStyle(.bordered)
            .actionFeedback(trigger: copiedLinkURL)
            Button("New Code") {
              Task { await model.createDeviceLinkCode() }
            }
            .buttonStyle(.bordered)
          }
        } else {
          LabeledContent("Use this account on another Mac") {
            Button("Generate Code") {
              Task { await model.createDeviceLinkCode() }
            }
            .buttonStyle(.bordered)
          }
        }
      }

      Section("Local Identifiers") {
        LabeledContent("Device ID") {
          Text(displayDeviceID)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        LabeledContent("Timezone") {
          Text(model.config?.identity.timezone ?? TimeZone.current.identifier)
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear(perform: populate)
    .task {
      await model.refreshDevices()
    }
  }

  private func populate() {
    displayName = model.config?.identity.displayName ?? ""
    handle = model.config?.identity.handle ?? ""
    deviceLabel = model.config?.device.label ?? ""
    relayURL = model.config?.server.relayURL.absoluteString ?? ""
    // The user may have changed the login item in System Settings.
    launchAtLogin = LaunchAtLogin.isEnabled
    launchAtLoginNeedsApproval = LaunchAtLogin.requiresApproval
  }

  private func deviceSubtitle(_ device: DeviceSummary) -> String {
    guard let lastUsed = device.lastUsedAt else {
      return "added \(device.createdAt.formatted(.relative(presentation: .named)))"
    }
    return "active \(lastUsed.formatted(.relative(presentation: .named)))"
  }

  // An expired code is useless — fall back to the Generate button instead of
  // showing "expires 5 minutes ago".
  private var activeLinkCode: DeviceLinkCode? {
    guard let link = model.deviceLinkCode, link.expiresAt > Date() else { return nil }
    return link
  }

  private var displayDeviceID: String {
    guard let id = model.config?.device.id.trimmingCharacters(in: .whitespacesAndNewlines),
          !id.isEmpty
    else {
      return "unconfigured"
    }
    return id
  }
}

private struct RepositoriesSettingsPane: View {
  var body: some View {
    Form {
      Section {
        Text("Added repos contribute the repo name and daily activity to your friends' feed.")
          .foregroundStyle(.secondary)
      }
      ReposSection()
    }
    .formStyle(.grouped)
  }
}

// Settings → Profile Icon. Generates a personal avatar from a short prompt using
// on-device Apple Intelligence (ImageCreator), previews it, and uploads via
// `uploadAvatar` (or clears via DELETE). When the device can't generate, the
// controls are disabled with an explanation — never a crash.
private struct ProfileIconSettingsPane: View {
  @EnvironmentObject private var model: AppModel
  @State private var prompt = ""

  private let previewDiameter: CGFloat = 96

  var body: some View {
    Form {
      if model.avatarSupported == false {
        Section {
          unavailableNote
        }
      }

      Section {
        preview
      }

      Section("Generate") {
        TextField("Prompt", text: $prompt, prompt: Text("a sleepy fox with headphones"))
          .disabled(!canGenerate)
          .onSubmit { generate() }

        HStack(spacing: 10) {
          Button {
            generate()
          } label: {
            Label(model.avatarPreviewPNG == nil ? "Generate" : "Regenerate", systemImage: "sparkles")
          }
          .buttonStyle(.borderedProminent)
          .disabled(!canGenerate || isWorking)

          if model.avatarPreviewPNG != nil {
            Button {
              Task { await model.useGeneratedAvatar() }
            } label: {
              Label("Use this", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            .disabled(isWorking)
          }

          Button {
            Task { await model.removeAvatar() }
          } label: {
            Label("Remove", systemImage: "trash")
          }
          .buttonStyle(.bordered)
          .disabled(isWorking || !hasCurrentAvatar)

          if isWorking {
            ProgressView()
              .controlSize(.small)
          }
        }

        if let status = workingStatus {
          Text(status)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        if let error = model.avatarError {
          if model.avatarMaySetupNeeded {
            Text("Couldn't generate that icon. Try rewording the prompt — Apple Intelligence declines some subjects, like real people. If it's still setting up, open Image Playground once to finish the download, then try again.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Button {
              model.openImagePlayground()
            } label: {
              Label("Open Image Playground", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
          } else {
            Text(error)
              .font(.callout)
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      gradientSection
    }
    .formStyle(.grouped)
    .task {
      await model.prepareAvatarSettings()
    }
  }

  // Gradient fallback — two native ColorPickers, a live circular preview, and a
  // "Use gradient" button. Works regardless of Apple-Intelligence availability.
  @ViewBuilder
  private var gradientSection: some View {
    Section("Gradient") {
      HStack(alignment: .center, spacing: 16) {
        ZStack {
          Circle()
            .fill(
              LinearGradient(
                colors: [model.gradientStart, model.gradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
          Text(gradientPreviewInitial)
            // Exact size: glyph must fit the fixed 72pt gradient preview circle,
            // not scale with Dynamic Type.
            .font(.system(size: 28, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            // Decorative shadow kept: lifts the initial off the user's custom
            // avatar gradient (the out-of-scope Color(hex:) gradient exception).
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
        .frame(width: 72, height: 72)
        .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))

        // Labels in column 1, color wells in column 2 → the wells line up
        // vertically regardless of label width.
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
          GridRow {
            Text("Start")
            ColorPicker("", selection: $model.gradientStart, supportsOpacity: false)
              .labelsHidden()
          }
          GridRow {
            Text("End")
            ColorPicker("", selection: $model.gradientEnd, supportsOpacity: false)
              .labelsHidden()
          }
        }
        .font(.subheadline)

        Button {
          Task { await model.setGradientAvatar() }
        } label: {
          Label("Use gradient", systemImage: "circle.lefthalf.filled")
        }
        .buttonStyle(.bordered)
        .disabled(isWorking)

        Spacer()
      }
    }
  }

  // The generated-but-unuploaded PNG takes precedence; otherwise show the current
  // avatar (or initials) for "you" via the shared AvatarView.
  @ViewBuilder
  private var preview: some View {
    HStack {
      Spacer()
      if let png = model.avatarPreviewPNG, let image = NSImage(data: png) {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: previewDiameter, height: previewDiameter)
          .clipShape(Circle())
          .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
      } else if let you = model.feed?.you {
        AvatarView(status: you, size: .comfortable, isOnline: you.mode == .online)
          .scaleEffect(previewDiameter / AvatarView.outerDiameter(for: .comfortable))
          .frame(width: previewDiameter, height: previewDiameter)
      } else {
        Circle()
          .fill(Color(nsColor: .quaternarySystemFill))
          .frame(width: previewDiameter, height: previewDiameter)
      }
      Spacer()
    }
  }

  private var unavailableNote: some View {
    Text("On-device image generation isn't available on this Mac. It requires an Apple-Intelligence-capable Mac on the latest macOS, with the models downloaded. You can still remove an existing icon.")
      .font(.subheadline)
      .foregroundStyle(Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .quaternarySystemFill))
      .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var canGenerate: Bool {
    model.avatarSupported == true && model.houseStyle != nil
  }

  private var isWorking: Bool {
    model.isGeneratingAvatar || model.isUploadingAvatar
  }

  private var hasCurrentAvatar: Bool {
    guard let user = model.feed?.you.user else { return false }
    if let raw = user.avatarUrl, !raw.isEmpty { return true }
    if user.avatarKind == "gradient" { return true }
    return false
  }

  private var workingStatus: String? {
    if model.isGeneratingAvatar { return "Generating on device..." }
    return nil
  }

  private var gradientPreviewInitial: String {
    let handle = model.feed?.you.user.handle ?? ""
    return (handle.first.map(String.init) ?? "?").uppercased()
  }

  private func generate() {
    Task { await model.generateAvatar(prompt: prompt) }
  }
}

private struct SharingSettingsPane: View {
  @EnvironmentObject private var model: AppModel
  @State private var cityDraft: String = ""

  var body: some View {
    Form {
      Section {
        Text("Optional cards on your orb and presence card. Friends only see what you turn on.")
          .foregroundStyle(.secondary)
      }

      Section("Music") {
        Toggle("Now playing", isOn: musicEnabled)
        Text(
          musicEnabled.wrappedValue
            ? "Sharing the track playing in Spotify or Apple Music. It disappears when you pause — and macOS may ask once to let Vibes check what's already playing."
            : "Share the track you're playing in Spotify or Apple Music."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section("Weather") {
        Toggle("Local weather", isOn: weatherEnabled)
        Text("Friends see conditions and temperature only — your location never leaves this Mac.")
          .font(.caption)
          .foregroundStyle(.secondary)
        if weatherEnabled.wrappedValue {
          EditableSettingField(
            label: "City",
            prompt: "Current location",
            text: $cityDraft,
            save: { model.updateWeatherCity(cityDraft) }
          )
          Text(
            cityDraft.trimmingCharacters(in: .whitespaces).isEmpty
              ? "Leave blank to use Location Services — macOS will ask once."
              : "Weather is looked up for this city; Location Services stay untouched."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Toggle("Include city name", isOn: shareCity)
          WeatherProblemRow(provider: model.weatherProvider)
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { cityDraft = model.config?.sharing.weather.manualCity ?? "" }
  }

  private var musicEnabled: Binding<Bool> {
    Binding(
      get: { model.config?.sharing.cards.music ?? false },
      set: { model.setCard(\.music, enabled: $0) }
    )
  }

  private var weatherEnabled: Binding<Bool> {
    Binding(
      get: { model.config?.sharing.cards.weather ?? false },
      set: { model.setCard(\.weather, enabled: $0) }
    )
  }

  private var shareCity: Binding<Bool> {
    Binding(
      get: { model.config?.sharing.weather.shareCity ?? false },
      set: { model.setWeatherShareCity($0) }
    )
  }
}

// Surfaces provider failures (denied location, unknown city, network) next to
// the weather toggle — the card silently not appearing is undebuggable.
// Separate view so the nested ObservableObject actually drives updates.
private struct WeatherProblemRow: View {
  @ObservedObject var provider: WeatherProvider

  var body: some View {
    if let problem = provider.lastProblem {
      Label(problem, systemImage: "exclamationmark.triangle")
        .font(.caption)
        .foregroundStyle(.orange)
    }
  }
}

private struct AdvancedSettingsPane: View {
  @EnvironmentObject private var model: AppModel
  @State private var copied = false

  var body: some View {
    Form {
      Section("Setup Help") {
        Text("Copy this summary into your agent chat if you'd like help configuring repos.")
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Section {
        Text(model.diagnosticSummary())
          .font(.callout)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      } header: {
        Text("Diagnostics")
      } footer: {
        Button {
          model.copyDiagnosticSummary()
          copied = true
        } label: {
          Label(copied ? "Copied" : "Copy Summary", systemImage: "doc.on.doc")
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .formStyle(.grouped)
  }
}

// A standard grouped-Form row: a labeled TextField that persists on submit or
// via an explicit Save button. The Save closure is the same binding-backed
// persistence path used before the macOS 26 Form conversion.
private struct EditableSettingField: View {
  var label: String
  var prompt: String
  @Binding var text: String
  var save: () -> Void

  var body: some View {
    LabeledContent(label) {
      HStack(spacing: 8) {
        TextField(label, text: $text, prompt: Text(prompt))
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .onSubmit(save)
        Button("Save", action: save)
          .buttonStyle(.bordered)
          .controlSize(.small)
      }
    }
  }
}

// Feed text size (Settings → General → Appearance): scales the text inside
// the feed — orbit labels, repo chips, list cards — without touching the
// window chrome. macOS SwiftUI ignores `.dynamicTypeSize`, so the feed views
// multiply their base sizes by `feedTextScale` (see OrbitView.swift) instead.
// Defaults one notch up, a deliberate readability bump.
enum FeedTextSize: String, CaseIterable, Identifiable {
  case standard
  case large
  case extraLarge

  var id: String { rawValue }

  var label: String {
    switch self {
    case .standard: "Standard"
    case .large: "Large"
    case .extraLarge: "Extra Large"
    }
  }

  var scale: CGFloat {
    switch self {
    case .standard: 1.0
    case .large: 1.15
    case .extraLarge: 1.3
    }
  }
}

// The primary view: manual-status field, then the Aurora II presence column —
// "you" first, online friends as full cards, offline friends compressed into
// quiet rows under an "away" divider. EmptyState when there are no friends.
private struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  var openInviteFriend: () -> Void
  @AppStorage("feedViewMode") private var feedViewModeRaw = FeedViewMode.orbit.rawValue
  @AppStorage("feedTextSize") private var feedTextSizeRaw = FeedTextSize.large.rawValue

  private var feedViewMode: FeedViewMode {
    FeedViewMode(rawValue: feedViewModeRaw) ?? .orbit
  }

  private var feedTextSize: FeedTextSize {
    FeedTextSize(rawValue: feedTextSizeRaw) ?? .large
  }

  // Orbit just needs a feed — with no friends yet it shows your own orb plus
  // an invite nudge, so the header toggle always visibly switches views. The
  // list layout covers the not-yet-synced case.
  private var showsOrbit: Bool {
    feedViewMode == .orbit && model.feed != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      // The inline status row must keep roughly the original two-line height:
      // when it's too short the field sits up against the header (which lives in
      // the titlebar/toolbar band via ignoresSafeArea), and the window's
      // draggable region swallows clicks on the orbit/list, presence and refresh
      // buttons. The minHeight preserves that clearance.
      HStack(spacing: 12) {
        Text("Status")
          .font(.body)
          .foregroundStyle(.primary)
        TextField("what are you working on?", text: Binding(
          get: { model.manualStatus },
          set: { model.updateManualStatus($0) }
        ))
        .textFieldStyle(.plain)
        .foregroundStyle(.primary)
        .onSubmit {
          Task { await model.scanPublishAndFetch() }
        }
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
      .background(Color(nsColor: .quaternarySystemFill))
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .frame(minHeight: 60)

      if showsOrbit, let feed = model.feed {
        OrbitView(you: feed.you, friends: feed.friends, pulse: feed.pulse)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        feedList
      }
    }
    .environment(\.feedTextScale, feedTextSize.scale)
  }

  private var feedList: some View {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          // The network pulse history pins to the top of the list (no footer),
          // only when the server emits it.
          if let pulse = model.feed?.pulse {
            PulseHistory(pulse: pulse)
          }
          if let you = model.feed?.you {
            FriendCard(status: you, isYou: true)
          }
          let friends = model.feed?.friends ?? []
          if friends.isEmpty {
            EmptyState(
              text: "No friends yet. Create one invite link and send it directly.",
              actionTitle: "Invite a Friend",
              action: openInviteFriend
            )
          } else {
            let online = friends.filter { $0.mode == .online }
            let away = friends.filter { $0.mode != .online }
            ForEach(online) { status in
              FriendCard(status: status)
            }
            if !away.isEmpty {
              AwaySectionHeader()
                .padding(.top, 6)
              ForEach(away) { status in
                AwayFriendRow(status: status)
              }
            }
          }
        }
        // Cap the feed width and center it so cards stay readable instead of
        // stretching edge-to-edge on a wide, resizable window.
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
      }
      // Content scrolls under a soft system edge effect rather than hitting a
      // hard divider against the header/status field above and footer below.
      .scrollEdgeEffectStyle(.soft, for: .all)
  }
}

// Preview-style floating controls: every glass control in the header and
// footer shares one height — circles for single-icon buttons, capsule pills
// for grouped or labeled ones.
enum FloatingControl {
  static let height: CGFloat = 32
  static let iconSize: CGFloat = 13
}

// Orbit ↔ list switcher, sitting with the other floating header controls: one
// glass capsule with two labeled segments ("✦ orbit" / "☰ list" per the
// mockups), the active one raised on a brighter pill. The raw-string binding
// round-trips through @AppStorage in MainPanel/HomeView.
private struct FeedViewToggle: View {
  @Binding var selectionRaw: String

  var body: some View {
    HStack(spacing: 2) {
      segment("orbit", icon: "sparkles", mode: .orbit)
      segment("list", icon: "list.bullet", mode: .list)
    }
    .padding(3)
    .glassEffect(.regular, in: .capsule)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Feed View")
    .help("Toggle Orbit / List (⌘L)")
  }

  private func segment(_ title: String, icon: String, mode: FeedViewMode) -> some View {
    let isActive = selectionRaw == mode.rawValue
    return Button {
      selectionRaw = mode.rawValue
    } label: {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.system(size: 10, weight: .semibold))
        Text(title)
          .font(.callout.weight(.medium))
      }
      .padding(.horizontal, 12)
      .frame(height: FloatingControl.height - 6)
      .foregroundStyle(isActive ? Color.primary : Color.secondary)
      .background(
        isActive ? AnyShapeStyle(Color(nsColor: .quaternarySystemFill)) : AnyShapeStyle(.clear),
        in: Capsule()
      )
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(title) view")
    .accessibilityAddTraits(isActive ? [.isSelected] : [])
  }
}

// One-dot presence control (the mockups' status light): a small glass button
// whose dot is lit green when online, at rest when offline; clicking toggles.
// The menu-bar extra keeps explicit Online/Offline items for discoverability.
private struct PresenceLight: View {
  var mode: PresenceMode
  var toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      Circle()
        .fill(
          mode == .online
            ? Color(nsColor: .systemGreen)
            : Color(nsColor: .tertiaryLabelColor)
        )
        .frame(width: 10, height: 10)
        .shadow(
          color: mode == .online ? Color(nsColor: .systemGreen).opacity(0.7) : .clear,
          radius: 4
        )
        .frame(width: FloatingControl.height, height: FloatingControl.height)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .glassEffect(.regular.interactive(), in: .circle)
    .help(mode == .online ? "Online — click to go offline" : "Offline — click to go online")
    .accessibilityLabel(mode == .online ? "Online" : "Offline")
    .accessibilityHint("Toggles your presence")
  }
}

// The scan/refresh icon. A single steady glyph — no symbol swap — so a quick
// refresh no longer blinks. While busy the glyph turns green and a soft green
// glow breathes around it: present if you're watching the button, easy to miss
// if you're not. Reduce Motion holds a steady green glow instead of breathing.
private struct RefreshGlyph: View {
  var isBusy: Bool
  @State private var pulsing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Image(systemName: "arrow.clockwise")
      .font(.system(size: FloatingControl.iconSize, weight: .medium))
      // Glyph stays a fully-opaque green while busy so it reads clearly green in
      // both light and dark — dimming the glyph instead would just wash the
      // green toward the light glass.
      .foregroundStyle(isBusy ? Color(nsColor: .systemGreen) : .primary)
      // The pulse is a soft green glow that breathes, not an opacity dip.
      .shadow(color: glowColor, radius: glowRadius)
      .frame(width: FloatingControl.height, height: FloatingControl.height)
      .contentShape(Circle())
      .animation(.easeInOut(duration: 0.4), value: isBusy)
      .onChange(of: isBusy) { _, busy in
        guard !reduceMotion else { return }
        if busy {
          pulsing = false
          withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            pulsing = true
          }
        } else {
          withAnimation(.easeInOut(duration: 0.3)) { pulsing = false }
        }
      }
  }

  private var glowColor: Color {
    guard isBusy else { return .clear }
    let strength = reduceMotion ? 0.4 : (pulsing ? 0.6 : 0.15)
    return Color(nsColor: .systemGreen).opacity(strength)
  }

  private var glowRadius: CGFloat {
    guard isBusy, !reduceMotion else { return isBusy ? 3 : 0 }
    return pulsing ? 4.5 : 1.5
  }
}

private struct ReposSection: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Section {
      if let repos = model.config?.repos, !repos.isEmpty {
        ForEach(repos) { repo in
          RepoRow(repo: repo)
        }
      } else {
        Text("Add local Git repositories to share aggregate daily activity.")
          .foregroundStyle(.secondary)
      }
    } header: {
      HStack {
        Text("Repositories")
        Spacer()
        Button {
          model.addRepo()
        } label: {
          Label("Add", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }
    }
  }
}

private struct RepoRow: View {
  @EnvironmentObject private var model: AppModel
  @State var repo: RepoConfig
  @State private var isRemoveHovering = false
  @State private var isHideHovering = false

  var body: some View {
    // Mirror EditableSettingField's LabeledContent layout: the path is the
    // label (head-truncated so a long repo path collapses from the start to a
    // single line) and the alias field + remove button are the trailing value.
    // LabeledContent owns the label/value width split, so the row stays one
    // clean line at any path length instead of wrapping.
    LabeledContent {
      HStack(spacing: 8) {
        TextField("", text: $repo.alias, prompt: Text("repo name"))
          .labelsHidden()
          .multilineTextAlignment(.trailing)
          .onSubmit { model.updateRepo(repo) }
          .accessibilityLabel("Repo Alias")
          .opacity(repo.hidden ? 0.45 : 1)

        Button {
          repo.hidden.toggle()
          model.setRepoHidden(repo)
        } label: {
          Image(systemName: repo.hidden ? "eye.slash" : "eye")
            .imageScale(.large)
            .foregroundStyle(isHideHovering ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { isHideHovering = $0 }
        .accessibilityLabel(repo.hidden ? "Show Repository" : "Hide Repository")
        .help(repo.hidden ? "Show in friends’ feed" : "Hide from friends’ feed")

        Button {
          model.removeRepo(repo)
        } label: {
          Image(systemName: isRemoveHovering ? "minus.circle.fill" : "minus.circle")
            .imageScale(.large)
            .foregroundStyle(isRemoveHovering ? Color.red : Color.secondary)
        }
        .buttonStyle(.plain)
        .onHover { isRemoveHovering = $0 }
        .accessibilityLabel("Remove Repository")
      }
    } label: {
      Text(repo.path)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.head)
        .opacity(repo.hidden ? 0.45 : 1)
    }
  }
}

private struct InviteFriendView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var createdInvite = 0
  @State private var copiedLink = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Text("invite a friend")
            .font(.title.weight(.light))
          Text("Send a one-time link. Each link connects one friend.")
            .font(.subheadline)
            .foregroundStyle(Color.secondary)
        }
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.glass)
        .accessibilityLabel("Close")
      }

      Button {
        Task {
          if await model.createInvite() { createdInvite += 1 }
        }
      } label: {
        Label("Create Invite Link", systemImage: "link")
      }
      .buttonStyle(.glassProminent)
      .actionFeedback(trigger: createdInvite)
      .disabled(model.isBusy)

      if let url = model.latestInviteURL {
        VStack(alignment: .leading, spacing: 8) {
          Text(url.absoluteString)
            .font(.caption)
            .lineLimit(2)
            .textSelection(.enabled)
          GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
              Button {
                model.copyLatestInvite()
                copiedLink += 1
              } label: {
                ConfirmingLabel("Copy Link", systemImage: "doc.on.doc", trigger: copiedLink)
              }
              .buttonStyle(.glassProminent)
              .actionFeedback(trigger: copiedLink)
              ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
              }
              .buttonStyle(.glass)
            }
          }
        }
        .padding(.vertical, 8)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Have an invite code?")
          .font(.caption)
          .foregroundStyle(Color.secondary)
        HStack(spacing: 8) {
          TextField("7Qm3-X2pK", text: $model.inviteCodeInput)
            .textFieldStyle(.plain)
            .padding(10)
            .background(Color(nsColor: .quaternarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .onSubmit {
              Task { await model.acceptInvite(code: model.inviteCodeInput) }
            }

          Button("Accept") {
            Task { await model.acceptInvite(code: model.inviteCodeInput) }
          }
          .buttonStyle(.glassProminent)
          .disabled(model.inviteCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
        }
      }

      Text("Open invites")
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 10) {
        let openInvites = model.invites.filter { $0.state == "open" }
        if openInvites.isEmpty {
          EmptyState(text: "Create an invite link when you're ready to connect with someone.")
        } else {
          ForEach(openInvites) { invite in
              HStack {
                VStack(alignment: .leading) {
                  Text("Invite")
                  Text("expires \(relative(invite.expiresAt))")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                }
                Spacer()
                Button("Revoke") {
                  Task { await model.revokeInvite(invite) }
                }
                .buttonStyle(.glass)
              }
              .padding(.vertical, 8)
          }
        }
      }
    }
    .padding(24)
    .frame(width: 420)
    .task {
      await model.refreshInvites()
    }
  }

  private func relative(_ date: Date?) -> String {
    guard let date else { return "never" }
    return date.formatted(.relative(presentation: .named))
  }
}

private struct InviteSheet: View {
  @EnvironmentObject private var model: AppModel
  var invite: PendingInvite

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        Text("You've been invited")
          .font(.title.weight(.light))
        Text(invite.inviterName.map { "\($0) invited you to Vibes." } ?? "Someone invited you to Vibes.")
          .font(.callout)
          .foregroundStyle(Color.secondary)
        Text(invite.code)
          .font(.caption)
          .foregroundStyle(Color.secondary)
          .textSelection(.enabled)
      }

      Text("Accepting lets you both see each other's presence.")
        .font(.subheadline)
        .foregroundStyle(Color.secondary)

      GlassEffectContainer(spacing: 10) {
        HStack(spacing: 10) {
          Button("Accept") {
            Task { await model.acceptPendingInvite() }
          }
          .buttonStyle(.glassProminent)
          .disabled(model.isBusy)

          Button("Not now") {
            model.pendingInvite = nil
          }
          .buttonStyle(.glass)
        }
      }
    }
    .padding(24)
    .frame(width: 340)
  }
}

private struct Footer: View {
  @EnvironmentObject private var model: AppModel
  var openInviteFriend: () -> Void
  var openSettings: () -> Void

  var body: some View {
    HStack {
      // Quiet corner: nothing when sync is healthy. A small warning surfaces
      // problems; transient success messages still flash through.
      if let error = model.lastError {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(Color.red)
          .lineLimit(1)
      } else if let message = model.successMessage {
        Text(message)
          .foregroundStyle(Color.secondary)
          .lineLimit(1)
      }
      Spacer()
      GlassEffectContainer(spacing: 8) {
        HStack(spacing: 8) {
          Button {
            openInviteFriend()
          } label: {
            Text("Invite")
              .font(.callout.weight(.medium))
              .padding(.horizontal, 16)
              .frame(height: FloatingControl.height)
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .glassEffect(.regular.interactive(), in: .capsule)
          .accessibilityLabel("Invite a Friend")
          .help("Invite a Friend (⌘I)")
          .overlay(alignment: .top) {
            if needsFriends {
              OnboardingNudge(text: "invite a friend", anchor: .center)
            }
          }

          Button {
            // First-run routing: with no repos yet, land directly on the
            // Repositories pane the nudge arrow is pointing toward.
            if needsRepos {
              model.settingsTab = .repositories
            }
            openSettings()
          } label: {
            Image(systemName: "gearshape")
              .font(.system(size: FloatingControl.iconSize, weight: .medium))
              .frame(width: FloatingControl.height, height: FloatingControl.height)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .glassEffect(.regular.interactive(), in: .circle)
          .accessibilityLabel("Open Settings")
          .overlay(alignment: .topTrailing) {
            if needsRepos {
              OnboardingNudge(text: "add your repos", anchor: .trailing)
            }
          }
        }
      }
    }
    .font(.caption)
  }

  // Onboarding ladder: repos first, then a friend. One nudge at a time.
  private var needsRepos: Bool {
    (model.config?.repos ?? []).isEmpty
  }

  // Wait for the first feed so the nudge doesn't flash during launch.
  private var needsFriends: Bool {
    guard !needsRepos, let feed = model.feed else { return false }
    return feed.friends.isEmpty
  }
}

// A quiet onboarding pointer: caption text over a gently bobbing arrow,
// floated above the control it points at. Purely decorative — never blocks
// clicks on the control underneath. `.trailing` keeps the text inside the
// window when the target hugs the right edge (the settings gear); the arrow
// stays centered over the 32pt control either way.
private struct OnboardingNudge: View {
  enum Anchor {
    case center
    case trailing
  }

  var text: String
  var anchor: Anchor
  @State private var bob = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: anchor == .trailing ? .trailing : .center, spacing: 5) {
      Text(text)
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .fixedSize()
      Image(systemName: "arrow.down")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.secondary)
        .padding(.trailing, anchor == .trailing ? (FloatingControl.height - 14) / 2 : 0)
    }
    // Lift the whole nudge clear of the control it overlays (overlay aligns
    // tops, so without this it would sit on the button), then bob gently.
    .offset(y: -50 + (bob ? -3 : 3))
    .onAppear {
      guard !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
        bob = true
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct Header: View {
  var title: String
  var subtitle: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        // Exact size kept: this is the "vibes" wordmark — a deliberate display
        // size, not body text that should scale with Dynamic Type.
        .font(.system(size: 34, weight: .light))
      if let subtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
      }
    }
  }
}

private struct Field: View {
  var label: String
  @Binding var text: String
  var prompt: String

  init(_ label: String, text: Binding<String>, prompt: String) {
    self.label = label
    _text = text
    self.prompt = prompt
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.caption)
        .foregroundStyle(Color.secondary)
      TextField(prompt, text: $text)
        .textFieldStyle(.plain)
        .padding(10)
        .background(Color(nsColor: .quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
  }
}

private struct EmptyState: View {
  var text: String
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    VStack(spacing: 12) {
      Text(text)
        .font(.callout)
        .foregroundStyle(Color.secondary)
        .multilineTextAlignment(.center)
      if let actionTitle, let action {
        Button(actionTitle) {
          action()
        }
        .buttonStyle(.bordered)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    .padding(.horizontal, 30)
  }
}

#Preview {
  ContentView(showInviteFriend: .constant(false))
    .environmentObject(AppModel())
}
