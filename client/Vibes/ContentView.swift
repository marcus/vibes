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
      Header(title: "vibes", subtitle: "private presence for coding friends")

      VStack(alignment: .leading, spacing: 8) {
        Text("Let's set you up.")
          .font(.title3.weight(.light))
        Text("This stays on your Mac.")
          .font(.subheadline)
          .foregroundStyle(Color.secondary)
      }

      Field("display name", text: $displayName, prompt: "Marcus")

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
          Label("Create my identity", systemImage: "checkmark")
        }
        .buttonStyle(.glassProminent)
        .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
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
              Field("handle", text: $handle, prompt: "marcus")
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
        if let count = onlineCount {
          HStack(spacing: 5) {
            Circle()
              .fill(Color(nsColor: .systemGreen))
              .frame(width: 6, height: 6)
            Text(feedViewModeRaw == FeedViewMode.list.rawValue ? "\(count) online" : "\(count) in orbit")
              .font(.caption)
              .foregroundStyle(Color.secondary)
              .monospacedDigit()
          }
          .padding(.top, 2)
          .accessibilityElement(children: .combine)
        }
        Spacer()
        GlassEffectContainer(spacing: 10) {
          HStack(spacing: 10) {
            FeedViewToggle(selectionRaw: $feedViewModeRaw)
            PresenceLight(
              mode: model.mode,
              toggle: { model.setMode(model.mode == .online ? .offline : .online) }
            )
            Button {
              Task { await model.scanPublishAndFetch() }
            } label: {
              Image(systemName: model.isBusy ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .disabled(model.isBusy)
            .accessibilityLabel("Scan Now")
          }
        }
      }
      // Clear the traffic lights horizontally: in the unified-toolbar band
      // (TrafficLightAligner) the buttons end ~86pt from the window edge, so
      // inset the wordmark past them with a small gap.
      .padding(.leading, 72)

      HomeView()

      Footer(
        openInviteFriend: { showInviteFriend = true },
        openSettings: { openSettings() }
      )
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

  // You + friends currently online; nil before the first feed so the count
  // doesn't flash "0" during launch.
  private var onlineCount: Int? {
    guard let feed = model.feed else { return nil }
    let you = feed.you.mode == .online ? 1 : 0
    return you + feed.friends.filter { $0.mode == .online }.count
  }
}

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    TabView {
      GeneralSettingsPane()
        .tabItem {
          Label("General", systemImage: "gearshape")
        }

      ProfileIconSettingsPane()
        .tabItem {
          Label("Profile Icon", systemImage: "person.crop.circle")
        }

      RepositoriesSettingsPane()
        .tabItem {
          Label("Repositories", systemImage: "folder")
        }

      SharingSettingsPane()
        .tabItem {
          Label("Sharing", systemImage: "hand.raised")
        }

      AdvancedSettingsPane()
        .tabItem {
          Label("Advanced", systemImage: "wrench.and.screwdriver")
        }
    }
    .frame(width: 600, height: 520)
  }
}

private struct GeneralSettingsPane: View {
  @EnvironmentObject private var model: AppModel
  @State private var displayName = ""
  @State private var handle = ""
  @State private var deviceLabel = ""
  @State private var relayURL = ""

  var body: some View {
    Form {
      Section {
        Text("Account and relay details for this Mac.")
          .foregroundStyle(.secondary)
      }

      Section("Identity") {
        EditableSettingField(
          label: "Display Name",
          prompt: "Marcus",
          text: $displayName,
          save: { model.updateDisplayName(displayName) }
        )
        EditableSettingField(
          label: "Handle",
          prompt: "marcus",
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
  }

  private func populate() {
    displayName = model.config?.identity.displayName ?? ""
    handle = model.config?.identity.handle ?? ""
    deviceLabel = model.config?.device.label ?? ""
    relayURL = model.config?.server.relayURL.absoluteString ?? ""
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
            Text("Apple Intelligence may still be setting up image generation. Open Image Playground once to finish the download, then try again.")
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
  var body: some View {
    Form {
      Section {
        Text("Optional cards will appear here as they become available.")
          .foregroundStyle(.secondary)
      }

      Section("Cards") {
        UnavailableCardRow(title: "Spotify", detail: "Not available yet")
        UnavailableCardRow(title: "Weather", detail: "Not available yet")
      }
    }
    .formStyle(.grouped)
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

private struct UnavailableCardRow: View {
  var title: String
  var detail: String

  var body: some View {
    LabeledContent {
      Text("Soon")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .quaternarySystemFill))
        .clipShape(Capsule())
    } label: {
      Text(title)
      Text(detail)
    }
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

// The primary view: manual-status field, then the Aurora II presence column —
// "you" first, online friends as full cards, offline friends compressed into
// quiet rows under an "away" divider. EmptyState when there are no friends.
private struct HomeView: View {
  @EnvironmentObject private var model: AppModel
  @AppStorage("feedViewMode") private var feedViewModeRaw = FeedViewMode.orbit.rawValue

  private var feedViewMode: FeedViewMode {
    FeedViewMode(rawValue: feedViewModeRaw) ?? .orbit
  }

  // Orbit just needs a feed — with no friends yet it shows your own orb plus
  // an invite nudge, so the header toggle always visibly switches views. The
  // list layout covers the not-yet-synced case.
  private var showsOrbit: Bool {
    feedViewMode == .orbit && model.feed != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text("status")
          .font(.caption)
          .foregroundStyle(Color.secondary)
        TextField("what are you working on?", text: Binding(
          get: { model.manualStatus },
          set: { model.updateManualStatus($0) }
        ))
        .textFieldStyle(.plain)
        .padding(10)
        .background(Color(nsColor: .quaternarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onSubmit {
          Task { await model.scanPublishAndFetch() }
        }
      }

      if showsOrbit, let feed = model.feed {
        OrbitView(you: feed.you, friends: feed.friends)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        feedList
      }
    }
  }

  private var feedList: some View {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if let you = model.feed?.you {
            FriendCard(status: you, isYou: true)
          }
          let friends = model.feed?.friends ?? []
          if friends.isEmpty {
            EmptyState(
              text: "No friends yet. Create one invite link and send it directly."
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
  }

  private func segment(_ title: String, icon: String, mode: FeedViewMode) -> some View {
    let isActive = selectionRaw == mode.rawValue
    return Button {
      selectionRaw = mode.rawValue
    } label: {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.system(size: 9, weight: .semibold))
        Text(title)
          .font(.caption.weight(.medium))
      }
      .padding(.horizontal, 11)
      .padding(.vertical, 4)
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
        .frame(width: 9, height: 9)
        .shadow(
          color: mode == .online ? Color(nsColor: .systemGreen).opacity(0.7) : .clear,
          radius: 4
        )
        .padding(.horizontal, 5)
        .padding(.vertical, 6)
    }
    .buttonStyle(.glass)
    .help(mode == .online ? "Online — click to go offline" : "Offline — click to go online")
    .accessibilityLabel(mode == .online ? "Online" : "Offline")
    .accessibilityHint("Toggles your presence")
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

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        TextField("repo name", text: $repo.alias)
          .textFieldStyle(.plain)
          .onSubmit { model.updateRepo(repo) }
        Text(repo.path)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer()
      Button {
        model.removeRepo(repo)
      } label: {
        Image(systemName: "minus")
      }
      .buttonStyle(.bordered)
      .accessibilityLabel("Remove Repository")
    }
  }
}

private struct InviteFriendView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss

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
        Task { await model.createInvite() }
      } label: {
        Label("Create Invite Link", systemImage: "link")
      }
      .buttonStyle(.glassProminent)
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
              } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
              }
              .buttonStyle(.glassProminent)
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
        Text("Someone invited you to Vibes.")
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
      if let error = model.lastError {
        Text(error)
          .foregroundStyle(Color.red)
          .lineLimit(1)
      } else if let message = model.successMessage {
        Text(message)
          .foregroundStyle(Color.secondary)
          .lineLimit(1)
      } else {
        Text(model.lastSyncedAt.map { "synced \($0.formatted(.relative(presentation: .named)))" } ?? "not synced")
          .foregroundStyle(Color.secondary)
      }
      Spacer()
      GlassEffectContainer(spacing: 8) {
        HStack(spacing: 8) {
          Button("Invite") {
            openInviteFriend()
          }
          .buttonStyle(.glass)
          .accessibilityLabel("Invite a Friend")

          Button {
            openSettings()
          } label: {
            Image(systemName: "gearshape")
          }
          .buttonStyle(.glass)
          .accessibilityLabel("Open Settings")
        }
      }
    }
    .font(.caption)
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
