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
  @State private var section = Section.feed

  enum Section: String, CaseIterable, Identifiable {
    case feed
    case repos
    case friends

    var id: String { rawValue }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top) {
        Header(title: "vibes", subtitle: model.config?.identity.displayName ?? "")
        Spacer()
        Picker("Mode", selection: Binding(
          get: { model.mode },
          set: { model.setMode($0) }
        )) {
          ForEach(PresenceMode.allCases) { mode in
            Text(mode.label).tag(mode)
          }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150)
      }

      HStack(spacing: 8) {
        ForEach(Section.allCases) { item in
          Button(item.rawValue) { section = item }
            .buttonStyle(SegmentButtonStyle(isSelected: section == item))
        }
        Spacer()
        Button {
          Task { await model.scanPublishAndFetch() }
        } label: {
          Image(systemName: model.isBusy ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
        }
        .buttonStyle(IconButtonStyle())
        .disabled(model.isBusy)
      }

      switch section {
      case .feed:
        FeedSection()
      case .repos:
        ReposSection()
      case .friends:
        FriendsSection()
      }

      Footer()
    }
    .padding(22)
    .sheet(item: $model.pendingInvite) { invite in
      InviteSheet(invite: invite)
        .environmentObject(model)
    }
  }
}

private struct FeedSection: View {
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
            StatusRow(status: you, isYou: true)
          }
          let friends = model.feed?.friends ?? []
          if friends.isEmpty {
            EmptyState(text: "No friends yet. Create one invite link and send it directly.")
          } else {
            ForEach(friends) { status in
              StatusRow(status: status, isYou: false)
            }
          }
        }
      }
    }
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

private struct StatusRow: View {
  var status: MergedStatus
  var isYou: Bool
  @State private var showDetail = false

  var body: some View {
    Button {
      showDetail.toggle()
    } label: {
      VStack(alignment: .leading, spacing: 7) {
        HStack(alignment: .firstTextBaseline) {
          Text(isYou ? "you" : status.user.displayName)
            .font(.system(size: 16, weight: .medium))
          Text(status.derivedStatus)
            .font(.system(size: 13))
            .foregroundStyle(tint)
          Spacer()
          Text(relative(status.updatedAt))
            .font(.caption)
            .foregroundStyle(VibeColor.muted)
        }

        if let manual = status.manualStatus, !manual.isEmpty {
          Text(manual)
            .font(.system(size: 14))
            .foregroundStyle(VibeColor.foreground)
            .lineLimit(2)
        } else if status.mode != .broadcasting {
          Text(status.mode == .quiet ? "online, not broadcasting" : "offline")
            .font(.system(size: 14))
            .foregroundStyle(VibeColor.muted)
        }

        if let stats = status.cards.first(where: { $0.type == "git_stats" })?.summary {
          Text(stats)
            .font(.system(size: 13))
            .foregroundStyle(VibeColor.muted)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.vertical, 10)
    .popover(isPresented: $showDetail) {
      DetailPopover(status: status)
    }
  }

  private var tint: Color {
    switch status.derivedStatus {
    case "ship mode": Color(red: 0.82, green: 0.18, blue: 0.08)
    case "deep work", "vibing": Color(red: 0.18, green: 0.45, blue: 0.34)
    case "yak shaving", "rage fixing": Color(red: 0.78, green: 0.43, blue: 0.10)
    default: VibeColor.muted
    }
  }

  private func relative(_ date: Date?) -> String {
    guard let date else { return "never" }
    return date.formatted(.relative(presentation: .named))
  }
}

private struct DetailPopover: View {
  var status: MergedStatus

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(status.user.displayName)
        .font(.headline)
      Text(status.mode.label)
        .foregroundStyle(VibeColor.muted)
      ForEach(status.cards) { card in
        if let summary = card.summary {
          VStack(alignment: .leading, spacing: 2) {
            Text(card.type.replacingOccurrences(of: "_", with: " "))
              .font(.caption)
              .foregroundStyle(VibeColor.muted)
            Text(summary)
          }
        }
      }
    }
    .padding(16)
    .frame(width: 260)
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
        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(repos) { repo in
              RepoRow(repo: repo)
            }
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

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 10) {
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
        model.openConfigFolder()
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

private enum VibeColor {
  static let ink = NSColor(red: 0.102, green: 0.090, blue: 0.078, alpha: 1)
  static let paper = NSColor(red: 0.949, green: 0.933, blue: 0.902, alpha: 1)
  static let accent = Color(red: 0.878, green: 0.325, blue: 0.122)
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

private struct SegmentButtonStyle: ButtonStyle {
  var isSelected: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13))
      .foregroundStyle(isSelected ? VibeColor.accentForeground : VibeColor.foreground)
      .padding(.horizontal, 11)
      .padding(.vertical, 7)
      .background(isSelected ? VibeColor.foreground : VibeColor.field)
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
