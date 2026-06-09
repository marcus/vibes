import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
  @Published var config: VibesConfig?
  @Published var token: String = ""
  @Published var mode: PresenceMode = .online
  @Published var manualStatus: String = ""
  @Published var feed: FeedResponse?
  @Published var stats = DailyGitStats()
  @Published var invites: [InviteSummary] = []
  @Published var latestInviteURL: URL?
  @Published var pendingInvite: PendingInvite?
  @Published var inviteCodeInput: String = ""
  @Published var isBusy = false
  @Published var lastError: String?
  @Published var successMessage: String?
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
      if let loaded = try configStore.load() {
        guard isAllowedRelayURL(loaded.server.relayURL) else {
          lastError = "Saved relay URL must use HTTPS unless it is localhost."
          config = nil
          token = ""
          return
        }
        config = loaded
      }
      token = try keychain.readToken() ?? ""
      mode = config?.presence.mode ?? .online
      manualStatus = config?.presence.manualStatus ?? ""
      if isConfigured {
        startLoop()
        Task { await refreshAll() }
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  func register(displayName: String, deviceLabel: String, relayURLText: String) async {
    let cleanName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanName.isEmpty else {
      lastError = "Display name is required."
      return
    }
    guard let relayURL = normalizeRelayURL(relayURLText.nilIfBlank ?? "https://vibes.opentangle.com") else {
      lastError = "Use HTTPS for hosted relays. HTTP is only allowed for localhost."
      return
    }

    let label = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? Host.current().localizedName
      ?? "Mac"

    isBusy = true
    lastError = nil
    successMessage = nil
    do {
      let identity = try await RelayClient(baseURL: relayURL, token: "").register(
        displayName: cleanName,
        deviceLabel: label
      )
      let next = VibesConfig.firstLaunch(
        relayURL: relayURL,
        handle: identity.user.handle,
        displayName: identity.user.displayName,
        deviceLabel: label
      )
      await install(config: next, token: identity.token)
    } catch {
      lastError = error.localizedDescription
    }
    isBusy = false
  }

  func completeManualSetup(relayURLText: String, token: String, handle: String, displayName: String, deviceLabel: String) async {
    let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    if let imported = config, !cleanToken.isEmpty {
      await install(config: imported, token: cleanToken)
      return
    }

    guard let relayURL = normalizeRelayURL(relayURLText) else {
      lastError = "Use HTTPS for hosted relays. HTTP is only allowed for localhost."
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
      guard isAllowedRelayURL(imported.config.server.relayURL) else {
        lastError = "Imported relay URL must use HTTPS unless it is localhost."
        return
      }
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
    guard isAllowedRelayURL(next.server.relayURL) else {
      lastError = "Relay URL must use HTTPS unless it is localhost."
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
      if pendingInvite != nil {
        successMessage = nil
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  func handleIncomingURL(_ url: URL) {
    guard url.scheme?.lowercased() == "vibes",
          url.host(percentEncoded: false)?.lowercased() == "invite",
          let code = url.pathComponents.first(where: { component in
            component != "/" && !component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          })?.trimmingCharacters(in: .whitespacesAndNewlines),
          !code.isEmpty
    else {
      return
    }

    pendingInvite = PendingInvite(code: code)
    inviteCodeInput = code
    successMessage = nil
    NSApp.activate(ignoringOtherApps: true)
  }

  func acceptPendingInvite() async {
    guard let pendingInvite else { return }
    await acceptInvite(code: pendingInvite.code)
  }

  func acceptInvite(code rawCode: String) async {
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else { return }
    guard let config, isConfigured else {
      pendingInvite = PendingInvite(code: code)
      inviteCodeInput = code
      return
    }

    isBusy = true
    lastError = nil
    successMessage = nil
    do {
      let result = try await client(for: config).acceptInvite(code: code)
      pendingInvite = nil
      inviteCodeInput = ""
      await refreshFeedOnly()
      await refreshInvites()
      successMessage = "Now friends with \(result.inviter.displayName)."
    } catch {
      lastError = error.localizedDescription
    }
    isBusy = false
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

  func publishOfflineForQuit() async {
    mode = .offline
    persistPresence()
    guard let config, isConfigured else { return }
    do {
      let payload = StatusBuilder.payload(
        config: config,
        mode: .offline,
        manualStatus: "",
        stats: DailyGitStats()
      )
      try await client(for: config).publish(payload)
    } catch {
      lastError = error.localizedDescription
    }
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
    guard let url = URL(string: text), url.scheme != nil else {
      return nil
    }
    return isAllowedRelayURL(url) ? url : nil
  }

  private func isAllowedRelayURL(_ url: URL) -> Bool {
    if url.scheme == "https" { return true }
    return url.scheme == "http" && url.isLoopback
  }
}

private extension URL {
  var isLoopback: Bool {
    guard let host = host(percentEncoded: false)?.lowercased() else { return false }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }

  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
