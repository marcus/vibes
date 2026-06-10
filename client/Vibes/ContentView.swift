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
    .frame(width: 460, height: 620)
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
          .font(.system(size: 18, weight: .light))
        Text("This stays on your Mac.")
          .font(.system(size: 13))
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
        .buttonStyle(AccentButtonStyle())
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
            .buttonStyle(PlainVibeButtonStyle())

            Button {
              Task { await model.importConfigFile() }
            } label: {
              Label("Import JSON", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(PlainVibeButtonStyle())
          }
        }
        .padding(.top, 12)
      }
      .font(.system(size: 13))

      if let error = model.lastError {
        Text(error)
          .font(.caption)
          .foregroundStyle(Color.red)
      }

      Spacer()
    }
    .padding(28)
  }
}

private struct MainPanel: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.openSettings) private var openSettings
  @Binding var showInviteFriend: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        Header(title: "vibes")
        Spacer()
        HStack(spacing: 10) {
          PresenceToggle(
            mode: model.mode,
            setMode: { model.setMode($0) }
          )
          Button {
            Task { await model.scanPublishAndFetch() }
          } label: {
            Image(systemName: model.isBusy ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
          }
          .buttonStyle(IconButtonStyle())
          .disabled(model.isBusy)
          .accessibilityLabel("Scan Now")
        }
      }

      HomeView()

      Footer(
        openInviteFriend: { showInviteFriend = true },
        openSettings: { openSettings() }
      )
    }
    .padding(22)
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
    .frame(width: 560, height: 500)
  }
}

private struct GeneralSettingsPane: View {
  @EnvironmentObject private var model: AppModel
  @State private var displayName = ""
  @State private var handle = ""
  @State private var deviceLabel = ""
  @State private var relayURL = ""

  var body: some View {
    SettingsPane {
      SettingsHeading(
        title: "general",
        detail: "Account and relay details for this Mac."
      )

      EditableSettingField(
        label: "display name",
        prompt: "Marcus",
        text: $displayName,
        save: { model.updateDisplayName(displayName) }
      )

      EditableSettingField(
        label: "handle",
        prompt: "marcus",
        text: $handle,
        save: { model.updateHandle(handle) }
      )

      EditableSettingField(
        label: "device label",
        prompt: "MacBook",
        text: $deviceLabel,
        save: { model.updateDeviceLabel(deviceLabel) }
      )

      EditableSettingField(
        label: "relay url",
        prompt: "https://vibes.opentangle.com",
        text: $relayURL,
        save: { model.updateRelayURL(relayURL) }
      )

      VStack(alignment: .leading, spacing: 8) {
        Text("local identifiers")
          .font(.caption)
          .foregroundStyle(Color.secondary)
        Text("Device ID: \(displayDeviceID)")
          .font(.system(size: 12))
          .foregroundStyle(Color.secondary)
          .textSelection(.enabled)
        Text("Timezone: \(model.config?.identity.timezone ?? TimeZone.current.identifier)")
          .font(.system(size: 12))
          .foregroundStyle(Color.secondary)
      }
    }
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
    SettingsPane {
      SettingsHeading(
        title: "repositories",
        detail: "Added repos contribute the repo name and daily activity to your friends' feed."
      )
      ReposSection()
    }
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
    SettingsPane {
      SettingsHeading(title: "profile icon")

      if model.avatarSupported == false {
        unavailableNote
      }

      preview

      VStack(alignment: .leading, spacing: 6) {
        Text("prompt")
          .font(.caption)
          .foregroundStyle(Color.secondary)
        TextField("a sleepy fox with headphones", text: $prompt)
          .textFieldStyle(.plain)
          .padding(10)
          .background(Color(nsColor: .quaternarySystemFill))
          .clipShape(RoundedRectangle(cornerRadius: 4))
          .disabled(!canGenerate)
          .onSubmit { generate() }
      }

      HStack(spacing: 10) {
        Button {
          generate()
        } label: {
          Label(model.avatarPreviewPNG == nil ? "Generate" : "Regenerate", systemImage: "sparkles")
        }
        .buttonStyle(PlainVibeButtonStyle())
        .disabled(!canGenerate || isWorking)

        if model.avatarPreviewPNG != nil {
          Button {
            Task { await model.useGeneratedAvatar() }
          } label: {
            Label("Use this", systemImage: "checkmark")
          }
          .buttonStyle(PlainVibeButtonStyle())
          .disabled(isWorking)
        }

        Button {
          Task { await model.removeAvatar() }
        } label: {
          Label("Remove", systemImage: "trash")
        }
        .buttonStyle(PlainVibeButtonStyle())
        .disabled(isWorking || !hasCurrentAvatar)

        if isWorking {
          ProgressView()
            .controlSize(.small)
        }
      }

      if let status = workingStatus {
        Text(status)
          .font(.system(size: 12))
          .foregroundStyle(Color.secondary)
      }

      if let error = model.avatarError {
        VStack(alignment: .leading, spacing: 8) {
          if model.avatarMaySetupNeeded {
            Text("Apple Intelligence may still be setting up image generation. Open Image Playground once to finish the download, then try again.")
              .font(.system(size: 12))
              .foregroundStyle(Color.secondary)
              .fixedSize(horizontal: false, vertical: true)
            Button {
              model.openImagePlayground()
            } label: {
              Label("Open Image Playground", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(PlainVibeButtonStyle())
          } else {
            Text(error)
              .font(.system(size: 12))
              .foregroundStyle(Color.red)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }

      Divider()

      gradientSection
    }
    .task {
      await model.prepareAvatarSettings()
    }
  }

  // Gradient fallback — two native ColorPickers, a live circular preview, and a
  // "Use gradient" button. Works regardless of Apple-Intelligence availability.
  @ViewBuilder
  private var gradientSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("gradient")
        .font(.caption)
        .foregroundStyle(Color.secondary)

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
            .font(.system(size: 28, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
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
        .font(.system(size: 13))

        Button {
          Task { await model.setGradientAvatar() }
        } label: {
          Label("Use gradient", systemImage: "circle.lefthalf.filled")
        }
        .buttonStyle(PlainVibeButtonStyle())
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
      .font(.system(size: 13))
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
    SettingsPane {
      SettingsHeading(
        title: "sharing",
        detail: "Optional cards will appear here as they become available."
      )

      VStack(alignment: .leading, spacing: 12) {
        Text("cards")
          .font(.caption)
          .foregroundStyle(Color.secondary)

        UnavailableCardRow(title: "Spotify", detail: "Not available yet")
        UnavailableCardRow(title: "Weather", detail: "Not available yet")
      }
    }
  }
}

private struct AdvancedSettingsPane: View {
  @EnvironmentObject private var model: AppModel
  @State private var copied = false

  var body: some View {
    SettingsPane {
      SettingsHeading(
        title: "advanced"
      )

      VStack(alignment: .leading, spacing: 8) {
        Text("setup help")
          .font(.caption)
          .foregroundStyle(Color.secondary)
        Text("Copy this summary into your agent chat if you'd like help configuring repos.")
          .font(.system(size: 13))
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("diagnostics")
          .font(.caption)
          .foregroundStyle(Color.secondary)
        Text(model.diagnosticSummary())
          .font(.system(size: 12))
          .foregroundStyle(Color.secondary)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }

      Button {
        model.copyDiagnosticSummary()
        copied = true
      } label: {
        Label(copied ? "Copied" : "Copy Summary", systemImage: "doc.on.doc")
      }
      .buttonStyle(PlainVibeButtonStyle())
    }
  }
}

private struct UnavailableCardRow: View {
  var title: String
  var detail: String

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 14, weight: .regular))
        Text(detail)
          .font(.system(size: 12))
          .foregroundStyle(Color.secondary)
      }
      Spacer()
      Text("Soon")
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .quaternarySystemFill))
        .clipShape(Capsule())
    }
    .padding(.vertical, 8)
  }
}

private struct SettingsPane<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        content
      }
      .padding(28)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollContentBackground(.hidden)
  }
}

private struct SettingsHeading: View {
  var title: String
  var detail: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 22, weight: .light))
      if let detail {
        Text(detail)
          .font(.system(size: 13))
          .foregroundStyle(Color.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

private struct EditableSettingField: View {
  var label: String
  var prompt: String
  @Binding var text: String
  var save: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.caption)
        .foregroundStyle(Color.secondary)
      HStack(spacing: 8) {
        TextField(prompt, text: $text)
          .textFieldStyle(.plain)
          .padding(10)
          .background(Color(nsColor: .quaternarySystemFill))
          .clipShape(RoundedRectangle(cornerRadius: 4))
          .onSubmit(save)
        Button("Save") {
          save()
        }
        .buttonStyle(PlainVibeButtonStyle())
      }
    }
  }
}

// The primary view: manual-status field, then the Aurora II presence column —
// "you" first, online friends as full cards, offline friends compressed into
// quiet rows under an "away" divider. EmptyState when there are no friends.
private struct HomeView: View {
  @EnvironmentObject private var model: AppModel

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
      }
    }
  }
}

// TE-inspired tactile two-state presence control. Online = "lit" (saturated
// accent), Offline = "at-rest" (dimmed neutral). A pill track with two segments
// you press — reads as a labeled Online/Offline state, not a checkbox. Shares
// the DESIGN.md token vocabulary with FriendCard; the menu-bar control (td-583670)
// reuses this shape.
private struct PresenceToggle: View {
  var mode: PresenceMode
  var setMode: (PresenceMode) -> Void

  private let controlHeight: CGFloat = 34
  private let segmentMinWidth: CGFloat = 64

  var body: some View {
    HStack(spacing: 0) {
      segment(.online, label: "Online")
      segment(.offline, label: "Offline")
    }
    .padding(3)
    .background(Color(nsColor: .quaternarySystemFill))
    .clipShape(Capsule())
    .overlay(Capsule().stroke(Color(nsColor: .separatorColor), lineWidth: 1))
  }

  private func segment(_ target: PresenceMode, label: String) -> some View {
    let isSelected = mode == target
    return Button {
      setMode(target)
    } label: {
      Text(label)
        .font(.system(size: 13, weight: .medium))
        .frame(minWidth: segmentMinWidth)
        .frame(height: controlHeight - 6)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
        .clipShape(Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

private struct ReposSection: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("repositories")
          .font(.caption)
          .foregroundStyle(Color.secondary)
        Spacer()
        Button {
          model.addRepo()
        } label: {
          Label("Add", systemImage: "plus")
        }
        .buttonStyle(PlainVibeButtonStyle())
      }

      if let repos = model.config?.repos, !repos.isEmpty {
        VStack(spacing: 12) {
          ForEach(repos) { repo in
            RepoRow(repo: repo)
          }
        }
      } else {
        EmptyState(text: "Add local Git repositories to share aggregate daily activity.")
      }
    }
  }
}

private struct RepoRow: View {
  @EnvironmentObject private var model: AppModel
  @State var repo: RepoConfig

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("repo name", text: $repo.alias)
          .textFieldStyle(.plain)
          .onSubmit { model.updateRepo(repo) }
        Spacer()
        Button {
          model.removeRepo(repo)
        } label: {
          Image(systemName: "minus")
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel("Remove Repository")
      }
      Text(repo.path)
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .padding(.vertical, 8)
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
            .font(.system(size: 22, weight: .light))
          Text("Send a one-time link. Each link connects one friend.")
            .font(.system(size: 13))
            .foregroundStyle(Color.secondary)
        }
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel("Close")
      }

      Button {
        Task { await model.createInvite() }
      } label: {
        Label("Create Invite Link", systemImage: "link")
      }
      .buttonStyle(AccentButtonStyle())
      .disabled(model.isBusy)

      if let url = model.latestInviteURL {
        VStack(alignment: .leading, spacing: 8) {
          Text(url.absoluteString)
            .font(.system(size: 12))
            .lineLimit(2)
            .textSelection(.enabled)
          Button {
            model.copyLatestInvite()
          } label: {
            Label("Copy Link", systemImage: "doc.on.doc")
          }
          .buttonStyle(PlainVibeButtonStyle())
          ShareLink(item: url) {
            Label("Share", systemImage: "square.and.arrow.up")
          }
          .buttonStyle(PlainVibeButtonStyle())
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
          .buttonStyle(PlainVibeButtonStyle())
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
                .buttonStyle(PlainVibeButtonStyle())
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
          .font(.system(size: 22, weight: .light))
        Text("Someone invited you to Vibes.")
          .font(.system(size: 14))
          .foregroundStyle(Color.secondary)
        Text(invite.code)
          .font(.caption)
          .foregroundStyle(Color.secondary)
          .textSelection(.enabled)
      }

      Text("Accepting lets you both see each other's presence.")
        .font(.system(size: 13))
        .foregroundStyle(Color.secondary)

      HStack(spacing: 10) {
        Button("Accept") {
          Task { await model.acceptPendingInvite() }
        }
        .buttonStyle(AccentButtonStyle())
        .disabled(model.isBusy)

        Button("Not now") {
          model.pendingInvite = nil
        }
        .buttonStyle(PlainVibeButtonStyle())
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
      HStack(spacing: 8) {
        Button("Invite") {
          openInviteFriend()
        }
        .buttonStyle(FooterTextButtonStyle())
        .accessibilityLabel("Invite a Friend")

        Button {
          openSettings()
        } label: {
          Image(systemName: "gearshape")
        }
        .buttonStyle(IconButtonStyle())
        .accessibilityLabel("Open Settings")
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
        .font(.system(size: 34, weight: .light))
      if let subtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(.system(size: 13, weight: .regular))
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
        .font(.system(size: 14))
        .foregroundStyle(Color.secondary)
        .multilineTextAlignment(.center)
      if let actionTitle, let action {
        Button(actionTitle) {
          action()
        }
        .buttonStyle(PlainVibeButtonStyle())
      }
    }
    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    .padding(.horizontal, 30)
  }
}

private struct AccentButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .regular))
      .padding(.horizontal, 13)
      .padding(.vertical, 9)
      .background(.tint.opacity(configuration.isPressed ? 0.8 : 1))
      .foregroundStyle(.white)
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}

private struct PlainVibeButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .regular))
      .padding(.horizontal, 11)
      .padding(.vertical, 8)
      .background(Color(nsColor: .quaternarySystemFill).opacity(configuration.isPressed ? 0.6 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}

private struct FooterTextButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .regular))
      .padding(.horizontal, 11)
      .frame(height: 30)
      .background(Color(nsColor: .quaternarySystemFill).opacity(configuration.isPressed ? 0.6 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}

private struct IconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(width: 30, height: 30)
      .background(Color(nsColor: .quaternarySystemFill).opacity(configuration.isPressed ? 0.6 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}

#Preview {
  ContentView(showInviteFriend: .constant(false))
    .environmentObject(AppModel())
}
