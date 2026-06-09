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
        deviceLabel: label,
        timezone: identity.user.timezone ?? TimeZone.current.identifier
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
      do {
        let hydrated = try await accountHydratedConfig(imported, token: cleanToken)
        await install(config: hydrated, token: cleanToken)
      } catch {
        lastError = error.localizedDescription
      }
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
      deviceLabel: label,
      timezone: TimeZone.current.identifier
    )
    do {
      let hydrated = try await accountHydratedConfig(next, token: token)
      await install(config: hydrated, token: token)
    } catch {
      lastError = error.localizedDescription
    }
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
        let hydrated = try await accountHydratedConfig(imported.config, token: importedToken)
        await install(config: hydrated, token: importedToken)
      } else {
        var next = imported.config
        applyLocalTimezoneFallback(to: &next)
        config = next
        try configStore.save(next)
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
    let now = Date()
    let dayWindow = VibesDayWindow.current(
      now: now,
      timezone: config.identity.timezone ?? TimeZone.current.identifier
    )
    let nextStats = await scanner.scan(repos: config.repos, dayWindow: dayWindow, now: now)
    stats = nextStats
    do {
      let payload = StatusBuilder.payload(
        config: config,
        mode: mode,
        manualStatus: manualStatus,
        stats: nextStats,
        now: now,
        dayWindow: dayWindow
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

  // Builds a copy-to-clipboard prompt that hands the current config.json, its
  // schema, and instructions to an LLM so the user can edit settings via chat
  // and paste the result back into the pop-out. The user never hand-edits JSON.
  func buildSettingsPrompt() -> String {
    let currentJSON: String
    if let config, let data = try? JSONCoding.encoder.encode(config),
       let text = String(data: data, encoding: .utf8) {
      currentJSON = text
    } else {
      currentJSON = "{}"
    }
    return """
    You are helping me edit the settings file for a macOS app called Vibes.
    Below is my current configuration as JSON, followed by the schema. I will \
    describe the changes I want; you must reply with ONLY the complete, updated, \
    valid JSON for this config — no prose, no markdown fences, nothing else.

    Schema (all keys are exactly as shown; snake_case is required):
    - identity: { handle: string, display_name: string, timezone: string (IANA, e.g. "America/Denver") }
    - device: { id: string, label: string }
    - server: { relay_url: string (must be https unless localhost) }
    - repos: array of { id: string (uuid), path: string (absolute local path), alias: string, share_alias: bool }
    - sharing: { cards: { git_stats: bool, repo_aliases: bool, spotify: bool, weather: bool } }
    - presence: { mode: "online" | "offline", manual_status: string }

    Rules:
    - Preserve every field. Do not add or remove top-level keys.
    - Keep existing ids unless I explicitly ask to change them.
    - Output must be a single JSON object that parses cleanly.

    Current config.json:
    \(currentJSON)
    """
  }

  // Copies the LLM editing prompt to the pasteboard (mirrors copyLatestInvite).
  func copySettingsPrompt() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(buildSettingsPrompt(), forType: .string)
  }

  // Paste-back-and-validate: decode the pasted JSON with the SAME decoder used
  // by ConfigStore, persist + hot-reload on success, return a human-readable
  // error WITHOUT persisting on failure.
  @discardableResult
  func applyPastedConfig(_ pastedJSON: String) -> String? {
    let trimmed = pastedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return "Paste the JSON your LLM returned before saving."
    }
    guard let data = trimmed.data(using: .utf8) else {
      return "The pasted text could not be read as UTF-8."
    }
    let next: VibesConfig
    do {
      next = try JSONCoding.decoder.decode(VibesConfig.self, from: data)
    } catch {
      return decodeErrorMessage(error)
    }
    guard isAllowedRelayURL(next.server.relayURL) else {
      return "relay_url must use HTTPS unless it is localhost."
    }
    do {
      try configStore.save(next)
    } catch {
      return error.localizedDescription
    }
    // Hot-reload in-memory state (mirrors install / mutateConfig).
    config = next
    mode = next.presence.mode
    manualStatus = next.presence.manualStatus
    Task { await scanPublishAndFetch() }
    return nil
  }

  private func decodeErrorMessage(_ error: Error) -> String {
    guard let error = error as? DecodingError else {
      return "Invalid config: \(error.localizedDescription)"
    }
    switch error {
    case let .keyNotFound(key, context):
      return "Missing required field \"\(key.stringValue)\"\(pathSuffix(context))."
    case let .typeMismatch(_, context):
      return "Wrong type\(pathSuffix(context)): \(context.debugDescription)"
    case let .valueNotFound(_, context):
      return "Missing value\(pathSuffix(context)): \(context.debugDescription)"
    case let .dataCorrupted(context):
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      return path.isEmpty
        ? "The JSON is not valid: \(context.debugDescription)"
        : "Invalid value at \(path): \(context.debugDescription)"
    @unknown default:
      return "Invalid config: \(error.localizedDescription)"
    }
  }

  private func pathSuffix(_ context: DecodingError.Context) -> String {
    let path = context.codingPath.map(\.stringValue).joined(separator: ".")
    return path.isEmpty ? "" : " at \(path)"
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
        stats: DailyGitStats(),
        now: Date()
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

  private func accountHydratedConfig(_ config: VibesConfig, token rawToken: String) async throws -> VibesConfig {
    var next = config
    applyLocalTimezoneFallback(to: &next)
    do {
      let account = try await RelayClient(baseURL: config.server.relayURL, token: rawToken).me()
      next.identity.handle = account.user.handle
      next.identity.displayName = account.user.displayName
      if let timezone = account.user.timezone {
        next.identity.timezone = timezone
      }
    } catch {
      if (error as? RelayClientError)?.statusCode == 404 {
        return next
      }
      throw error
    }
    return next
  }

  private func applyLocalTimezoneFallback(to config: inout VibesConfig) {
    if config.identity.timezone == nil {
      config.identity.timezone = TimeZone.current.identifier
    }
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
