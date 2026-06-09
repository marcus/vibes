import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    Group {
      if model.isConfigured {
        MainPanel()
      } else {
        SetupPanel()
      }
    }
    .frame(width: 460, height: 620)
    .background(VibeColor.background)
    .foregroundStyle(VibeColor.foreground)
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
          .foregroundStyle(VibeColor.muted)
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
              .foregroundStyle(VibeColor.muted)
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
          .foregroundStyle(VibeColor.accent)
      }

      Spacer()
    }
    .padding(28)
  }
}

private struct MainPanel: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.openSettings) private var openSettings

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        Header(title: "vibes", subtitle: model.config?.identity.displayName ?? "")
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
        }
      }

      HomeView()

      Footer(openSettings: { openSettings() })
    }
    .padding(22)
    .sheet(item: $model.pendingInvite) { invite in
      InviteSheet(invite: invite)
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
    .background(VibeColor.background)
    .foregroundStyle(VibeColor.foreground)
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
          .foregroundStyle(VibeColor.muted)
        Text("Device ID: \(displayDeviceID)")
          .font(.system(size: 12))
          .foregroundStyle(VibeColor.muted)
          .textSelection(.enabled)
        Text("Timezone: \(model.config?.identity.timezone ?? TimeZone.current.identifier)")
          .font(.system(size: 12))
          .foregroundStyle(VibeColor.muted)
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
        detail: "Choose local Git repos to scan. Raw paths stay on this Mac."
      )
      ReposSection()
    }
  }
}

private struct SharingSettingsPane: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    SettingsPane {
      SettingsHeading(
        title: "sharing",
        detail: "Aggregate activity can leave the Mac. Paths, branches, commits, filenames, editor activity, and assistant attribution do not."
      )

      VStack(alignment: .leading, spacing: 12) {
        Text("cards")
          .font(.caption)
          .foregroundStyle(VibeColor.muted)

        cardToggle("Git stats", keyPath: \.gitStats)
        cardToggle("Repo aliases", keyPath: \.repoAliases)
        cardToggle("Spotify", keyPath: \.spotify)
        cardToggle("Weather", keyPath: \.weather)
      }

      VStack(alignment: .leading, spacing: 12) {
        Text("redactions")
          .font(.caption)
          .foregroundStyle(VibeColor.muted)

        redactionToggle("Repo paths", keyPath: \.repoPaths)
        redactionToggle("Branch names", keyPath: \.branchNames)
        redactionToggle("Commit messages", keyPath: \.commitMessages)
        redactionToggle("Filenames", keyPath: \.fileNames)
        redactionToggle("Editor activity", keyPath: \.editorActivity)
        redactionToggle("Assistant attribution", keyPath: \.assistantAttribution)
      }
    }
  }

  private func cardToggle(
    _ label: String,
    keyPath: WritableKeyPath<SharingCardsConfig, Bool>
  ) -> some View {
    Toggle(label, isOn: Binding(
      get: { model.config?.sharing.cards[keyPath: keyPath] ?? false },
      set: { model.setCard(keyPath, enabled: $0) }
    ))
  }

  private func redactionToggle(
    _ label: String,
    keyPath: WritableKeyPath<SharingRedactionsConfig, Bool>
  ) -> some View {
    Toggle("Redact \(label.lowercased())", isOn: Binding(
      get: { model.config?.sharing.redactions[keyPath: keyPath] ?? true },
      set: { model.setRedaction(keyPath, enabled: $0) }
    ))
  }
}

private struct AdvancedSettingsPane: View {
  @EnvironmentObject private var model: AppModel
  @State private var copied = false

  var body: some View {
    SettingsPane {
      SettingsHeading(
        title: "advanced",
        detail: "Use this local summary when reasoning about Vibes settings. It redacts secrets and raw repo paths."
      )

      VStack(alignment: .leading, spacing: 8) {
        Text("diagnostics")
          .font(.caption)
          .foregroundStyle(VibeColor.muted)
        Text(model.diagnosticSummary())
          .font(.system(size: 12))
          .foregroundStyle(VibeColor.muted)
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
    .background(VibeColor.background)
  }
}

private struct SettingsHeading: View {
  var title: String
  var detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 22, weight: .light))
      Text(detail)
        .font(.system(size: 13))
        .foregroundStyle(VibeColor.muted)
        .fixedSize(horizontal: false, vertical: true)
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
        .foregroundStyle(VibeColor.muted)
      HStack(spacing: 8) {
        TextField(prompt, text: $text)
          .textFieldStyle(.plain)
          .padding(10)
          .background(VibeColor.field)
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

// The primary view: manual-status field, local stats, then a scrolling column
// of FriendCards — "you" first, then each friend, EmptyState when none.
private struct HomeView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text("status")
          .font(.caption)
          .foregroundStyle(VibeColor.muted)
        TextField("what are you working on?", text: Binding(
          get: { model.manualStatus },
          set: { model.updateManualStatus($0) }
        ))
        .textFieldStyle(.plain)
        .padding(10)
        .background(VibeColor.field)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onSubmit {
          Task { await model.scanPublishAndFetch() }
        }
      }

      LocalStatsView(stats: model.stats)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if let you = model.feed?.you {
            FriendCard(status: you, isYou: true)
          }
          let friends = model.feed?.friends ?? []
          if friends.isEmpty {
            EmptyState(text: "No friends yet. Create one invite link and send it directly.")
          } else {
            ForEach(friends) { status in
              FriendCard(status: status, isYou: false)
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
    .background(VibeColor.chassis)
    .clipShape(Capsule())
    .overlay(Capsule().stroke(VibeColor.cardBorder, lineWidth: 1))
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
        .foregroundStyle(isSelected ? VibeColor.controlLitForeground : VibeColor.controlAtRestForeground)
        .background(isSelected ? VibeColor.controlLit : Color.clear)
        .clipShape(Capsule())
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

private struct LocalStatsView: View {
  var stats: DailyGitStats

  var body: some View {
    HStack(spacing: 18) {
      StatCell(value: "\(stats.reposTouched)", label: "repos")
      StatCell(value: "\(stats.commits)", label: "commits")
      StatCell(value: "+\(stats.insertions)", label: "added")
      StatCell(value: "-\(stats.deletions)", label: "removed")
    }
    .padding(.vertical, 8)
  }
}

private struct ReposSection: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("repositories")
          .font(.caption)
          .foregroundStyle(VibeColor.muted)
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

      Toggle("share Git stats", isOn: Binding(
        get: { model.config?.sharing.cards.gitStats ?? true },
        set: { _ in model.toggleCard(\.gitStats) }
      ))
    }
  }
}

private struct RepoRow: View {
  @EnvironmentObject private var model: AppModel
  @State var repo: RepoConfig

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        TextField("alias", text: $repo.alias)
          .textFieldStyle(.plain)
          .onSubmit { model.updateRepo(repo) }
        Spacer()
        Button {
          model.removeRepo(repo)
        } label: {
          Image(systemName: "minus")
        }
        .buttonStyle(IconButtonStyle())
      }
      Text(repo.path)
        .font(.caption)
        .foregroundStyle(VibeColor.muted)
        .lineLimit(1)
        .truncationMode(.middle)
      HStack {
        Toggle("share alias", isOn: Binding(
          get: { repo.shareAlias },
          set: {
            repo.shareAlias = $0
            model.updateRepo(repo)
          }
        ))
      }
    }
    .padding(.vertical, 8)
  }
}

private struct FriendsSection: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Add a friend")
          .font(.system(size: 18, weight: .light))
        Text("Send a one-time link. They tap it and you're connected.")
          .font(.system(size: 13))
          .foregroundStyle(VibeColor.muted)
      }

      Button {
        Task { await model.createInvite() }
      } label: {
        Label("Create invite link", systemImage: "link")
      }
      .buttonStyle(AccentButtonStyle())

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
        }
        .padding(.vertical, 8)
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Have an invite code?")
          .font(.caption)
          .foregroundStyle(VibeColor.muted)
        HStack(spacing: 8) {
          TextField("7Qm3-X2pK", text: $model.inviteCodeInput)
            .textFieldStyle(.plain)
            .padding(10)
            .background(VibeColor.field)
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

      Text("Pending invites")
        .font(.caption)
        .foregroundStyle(VibeColor.muted)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 10) {
        if model.invites.isEmpty {
          EmptyState(text: "Create an invite link when you're ready to connect with someone.")
        } else {
          ForEach(model.invites) { invite in
              HStack {
                VStack(alignment: .leading) {
                  Text(invite.state)
                  Text(invite.acceptedBy.map { "accepted by \($0)" } ?? "expires \(relative(invite.expiresAt))")
                    .font(.caption)
                    .foregroundStyle(VibeColor.muted)
                }
                Spacer()
                if invite.state == "open" {
                  Button("Revoke") {
                    Task { await model.revokeInvite(invite) }
                  }
                  .buttonStyle(PlainVibeButtonStyle())
                }
              }
              .padding(.vertical, 8)
          }
        }
      }
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
          .foregroundStyle(VibeColor.muted)
        Text(invite.code)
          .font(.caption)
          .foregroundStyle(VibeColor.muted)
          .textSelection(.enabled)
      }

      Text("Accepting lets you both see each other's presence.")
        .font(.system(size: 13))
        .foregroundStyle(VibeColor.muted)

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
    .background(VibeColor.background)
    .foregroundStyle(VibeColor.foreground)
  }
}

private struct Footer: View {
  @EnvironmentObject private var model: AppModel
  var openSettings: () -> Void

  var body: some View {
    HStack {
      if let error = model.lastError {
        Text(error)
          .foregroundStyle(VibeColor.accent)
          .lineLimit(1)
      } else if let message = model.successMessage {
        Text(message)
          .foregroundStyle(VibeColor.muted)
          .lineLimit(1)
      } else {
        Text(model.lastSyncedAt.map { "synced \($0.formatted(.relative(presentation: .named)))" } ?? "not synced")
          .foregroundStyle(VibeColor.muted)
      }
      Spacer()
      Button {
        openSettings()
      } label: {
        Image(systemName: "gearshape")
      }
      .buttonStyle(IconButtonStyle())
    }
    .font(.caption)
  }
}

private struct Header: View {
  var title: String
  var subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.system(size: 34, weight: .light))
      Text(subtitle)
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(VibeColor.muted)
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
        .foregroundStyle(VibeColor.muted)
      TextField(prompt, text: $text)
        .textFieldStyle(.plain)
        .padding(10)
        .background(VibeColor.field)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
  }
}

private struct StatCell: View {
  var value: String
  var label: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.system(size: 22, weight: .light))
      Text(label)
        .font(.caption)
        .foregroundStyle(VibeColor.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct EmptyState: View {
  var text: String

  var body: some View {
    Text(text)
      .font(.system(size: 14))
      .foregroundStyle(VibeColor.muted)
      .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 30)
  }
}

enum VibeColor {
  static let ink = NSColor(red: 0.102, green: 0.090, blue: 0.078, alpha: 1)
  static let paper = NSColor(red: 0.949, green: 0.933, blue: 0.902, alpha: 1)
  static let accent = Color(red: 0.878, green: 0.325, blue: 0.122)
  static let online = Color(red: 0.18, green: 0.55, blue: 0.34)
  static let background = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.isDarkMode ? ink : paper
  })
  static let foreground = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.isDarkMode ? paper : ink
  })
  static let muted = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.isDarkMode
      ? NSColor(red: 0.659, green: 0.624, blue: 0.573, alpha: 1)
      : NSColor(red: 0.431, green: 0.400, blue: 0.357, alpha: 1)
  })
  static let field = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.isDarkMode
      ? paper.withAlphaComponent(0.06)
      : ink.withAlphaComponent(0.045)
  })
  static let accentForeground = Color(nsColor: paper)

  // --- TE-derived tokens (see client/Vibes/DESIGN.md). Shared by the presence
  // Online/Offline control AND the friend card. ---

  // Chassis & surfaces — the neutral body controls sit on.
  static let chassis = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.isDarkMode
      ? NSColor(red: 0.149, green: 0.133, blue: 0.114, alpha: 1)
      : NSColor(red: 0.894, green: 0.871, blue: 0.812, alpha: 1)
  })
  static let cardSurface = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.isDarkMode
      ? NSColor(red: 0.188, green: 0.169, blue: 0.145, alpha: 1)
      : NSColor(red: 0.984, green: 0.973, blue: 0.949, alpha: 1)
  })
  static let cardBorder = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.isDarkMode
      ? paper.withAlphaComponent(0.09)
      : ink.withAlphaComponent(0.08)
  })

  // Secondary accent — petrol blue. Orange leads; use this sparingly.
  static let accentSecondary = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.isDarkMode
      ? NSColor(red: 0.243, green: 0.561, blue: 0.722, alpha: 1)
      : NSColor(red: 0.173, green: 0.431, blue: 0.569, alpha: 1)
  })

  // Control state language: "lit" (saturated/active) vs "at-rest" (dimmed/idle).
  static let controlLit = accent
  static let controlLitForeground = Color(nsColor: paper)
  static let controlAtRest = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.isDarkMode
      ? NSColor(red: 0.227, green: 0.204, blue: 0.176, alpha: 1)
      : NSColor(red: 0.847, green: 0.820, blue: 0.753, alpha: 1)
  })
  static let controlAtRestForeground = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.isDarkMode
      ? NSColor(red: 0.659, green: 0.624, blue: 0.573, alpha: 1)
      : NSColor(red: 0.431, green: 0.400, blue: 0.357, alpha: 1)
  })
}

private struct AccentButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .regular))
      .padding(.horizontal, 13)
      .padding(.vertical, 9)
      .background(VibeColor.accent.opacity(configuration.isPressed ? 0.8 : 1))
      .foregroundStyle(VibeColor.accentForeground)
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}

private struct PlainVibeButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .regular))
      .padding(.horizontal, 11)
      .padding(.vertical, 8)
      .background(VibeColor.field.opacity(configuration.isPressed ? 0.6 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}

private struct IconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(width: 30, height: 30)
      .background(VibeColor.field.opacity(configuration.isPressed ? 0.6 : 1))
      .clipShape(RoundedRectangle(cornerRadius: 4))
  }
}

private extension NSAppearance {
  var isDarkMode: Bool {
    bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  }
}

#Preview {
  ContentView()
    .environmentObject(AppModel())
}
