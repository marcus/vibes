import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
  @Published var config: VibesConfig?
  @Published var token: String = ""
  @Published var mode: PresenceMode = .broadcasting
  @Published var manualStatus: String = ""
  @Published var feed: FeedResponse?
  @Published var stats = DailyGitStats()
  @Published var invites: [InviteSummary] = []
  @Published var latestInviteURL: URL?
  @Published var isBusy = false
  @Published var lastError: String?
  @Published var lastSyncedAt: Date?

  private let configStore = ConfigStore()
  private let keychain = KeychainStore()
  private let scanner = GitScanner()
  private var loopTask: Task<Void, Never>?

  var isConfigured: Bool {
    config != nil && !token.isEmpty
  }

  init() {
    loadLocalState()
  }

  func loadLocalState() {
    do {
      config = try configStore.load()
      token = try keychain.readToken() ?? ""
      mode = config?.presence.mode ?? .broadcasting
      manualStatus = config?.presence.manualStatus ?? ""
      if isConfigured {
        startLoop()
        Task { await refreshAll() }
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  func completeManualSetup(relayURLText: String, token: String, handle: String, displayName: String, deviceLabel: String) async {
    guard let relayURL = normalizeRelayURL(relayURLText) else {
      lastError = "Enter a valid relay URL."
      return
    }
    let label = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? Host.current().localizedName
      ?? "Mac"
    let next = VibesConfig.firstLaunch(
      relayURL: relayURL,
      handle: handle.trimmingCharacters(in: .whitespacesAndNewlines),
      displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
      deviceLabel: label
    )
    await install(config: next, token: token)
  }

  func importConfigFile() async {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.message = "Choose the Vibes config JSON from your invite page."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      let imported = try configStore.importConfig(from: url)
      if let importedToken = imported.token, !importedToken.isEmpty {
        await install(config: imported.config, token: importedToken)
      } else {
        config = imported.config
        try configStore.save(imported.config)
        lastError = "Config imported. Paste the one-time token to finish setup."
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  func install(config next: VibesConfig, token rawToken: String) async {
    let cleanToken = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanToken.isEmpty else {
      lastError = "Paste the token from the invite page."
      return
    }
    do {
      try keychain.saveToken(cleanToken)
      try configStore.save(next)
      config = next
      token = cleanToken
      mode = next.presence.mode
      manualStatus = next.presence.manualStatus
      startLoop()
      await refreshAll()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func refreshAll() async {
    await scanPublishAndFetch()
    await refreshInvites()
  }

  func scanPublishAndFetch() async {
    guard let config, isConfigured else { return }
    isBusy = true
    lastError = nil
    let nextStats = await scanner.scan(repos: config.repos)
    stats = nextStats
    do {
      let payload = StatusBuilder.payload(
        config: config,
        mode: mode,
        manualStatus: manualStatus,
        stats: nextStats
      )
      try await client(for: config).publish(payload)
      feed = try await client(for: config).feed()
      lastSyncedAt = Date()
      persistPresence()
    } catch {
      lastError = error.localizedDescription
    }
    isBusy = false
  }

  func refreshFeedOnly() async {
    guard let config, isConfigured else { return }
    do {
      feed = try await client(for: config).feed()
      lastSyncedAt = Date()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func setMode(_ next: PresenceMode) {
    mode = next
    persistPresence()
    Task { await scanPublishAndFetch() }
  }

  func updateManualStatus(_ value: String) {
    manualStatus = String(value.prefix(160))
    persistPresence()
  }

  func addRepo() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.message = "Choose a local Git repository to scan."
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let alias = url.lastPathComponent
    mutateConfig { config in
      if !config.repos.contains(where: { $0.path == url.path }) {
        config.repos.append(RepoConfig(path: url.path, alias: alias))
      }
    }
    Task { await scanPublishAndFetch() }
  }

  func removeRepo(_ repo: RepoConfig) {
    mutateConfig { config in
      config.repos.removeAll { $0.id == repo.id }
    }
    Task { await scanPublishAndFetch() }
  }

  func updateRepo(_ repo: RepoConfig) {
    mutateConfig { config in
      guard let index = config.repos.firstIndex(where: { $0.id == repo.id }) else { return }
      config.repos[index] = repo
    }
  }

  func toggleCard(_ keyPath: WritableKeyPath<SharingCardsConfig, Bool>) {
    mutateConfig { config in
      config.sharing.cards[keyPath: keyPath].toggle()
    }
    Task { await scanPublishAndFetch() }
  }

  func createInvite() async {
    guard let config, isConfigured else { return }
    do {
      let invite = try await client(for: config).createInvite()
      latestInviteURL = invite.inviteURL
      await refreshInvites()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func refreshInvites() async {
    guard let config, isConfigured else { return }
    do {
      invites = try await client(for: config).listInvites().invites
    } catch {
      lastError = error.localizedDescription
    }
  }

  func revokeInvite(_ invite: InviteSummary) async {
    guard let config, isConfigured else { return }
    do {
      try await client(for: config).revokeInvite(id: invite.id)
      await refreshInvites()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func copyLatestInvite() {
    guard let latestInviteURL else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(latestInviteURL.absoluteString, forType: .string)
  }

  func openConfigFolder() {
    NSWorkspace.shared.activateFileViewerSelecting([configStore.configURL])
  }

  func publishOfflineBeforeQuit() {
    mode = .offline
    persistPresence()
    Task { await scanPublishAndFetch() }
  }

  private func startLoop() {
    loopTask?.cancel()
    loopTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(180))
        await self?.scanPublishAndFetch()
      }
    }
  }

  private func client(for config: VibesConfig) -> RelayClient {
    RelayClient(baseURL: config.server.relayURL, token: token)
  }

  private func mutateConfig(_ mutate: (inout VibesConfig) -> Void) {
    guard var next = config else { return }
    mutate(&next)
    do {
      try configStore.save(next)
      config = next
    } catch {
      lastError = error.localizedDescription
    }
  }

  private func persistPresence() {
    mutateConfig { config in
      config.presence = PresenceConfig(mode: mode, manualStatus: manualStatus)
    }
  }

  private func normalizeRelayURL(_ raw: String) -> URL? {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.contains("://") {
      text = "https://\(text)"
    }
    guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
      return nil
    }
    return url
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
