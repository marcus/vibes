import AppKit
import Combine
import Foundation
import SwiftUI
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

  // AI profile-icon state. `houseStyle` is the server-owned art-direction
  // template cached from /api/me. `avatarSupported` is the on-device ImageCreator
  // probe (nil = not yet checked). The rest drive the Settings → Profile Icon
  // pane's preview / progress / error display.
  @Published var houseStyle: HouseStyle?
  @Published var avatarSupported: Bool?
  @Published var avatarPreviewPNG: Data?
  @Published var avatarLastStyle: String?
  @Published var avatarLastPrompt: String = ""
  @Published var isGeneratingAvatar = false
  @Published var isUploadingAvatar = false
  @Published var avatarError: String?
  // Set when an AI generation fails with a likely "model still downloading"
  // transient (`.creationFailed`), so the UI can offer an "Open Image Playground"
  // button + clearer copy. Cleared on the next generate attempt.
  @Published var avatarMaySetupNeeded = false

  // Gradient-fallback state for the Profile Icon pane: two picker selections that
  // default to the brand accent → a complementary teal. `setGradientAvatar()` PUTs
  // them as "#RRGGBB" hex and refreshes the feed.
  @Published var gradientStart: Color = Color(hex: "#E05420") ?? .orange
  @Published var gradientEnd: Color = Color(hex: "#1F6F8B") ?? .teal

  private let configStore = ConfigStore()
  private let keychain = KeychainStore()
  private let scanner = GitScanner()
  private var loopTask: Task<Void, Never>?

  var isConfigured: Bool {
    config != nil && !token.isEmpty
  }

  var configPath: String {
    configStore.configURL.path
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

  func updateDisplayName(_ value: String) {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      lastError = "Display name is required."
      return
    }
    mutateConfig { config in
      config.identity.displayName = clean
    }
  }

  func updateHandle(_ value: String) {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      lastError = "Handle is required."
      return
    }
    mutateConfig { config in
      config.identity.handle = clean
    }
  }

  func updateDeviceLabel(_ value: String) {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? Host.current().localizedName
      ?? "Mac"
    mutateConfig { config in
      config.device.label = clean
    }
  }

  func updateRelayURL(_ value: String) {
    guard let relayURL = normalizeRelayURL(value) else {
      lastError = "Use HTTPS for hosted relays. HTTP is only allowed for localhost."
      return
    }
    mutateConfig { config in
      config.server.relayURL = relayURL
    }
    Task { await refreshAll() }
  }

  func toggleCard(_ keyPath: WritableKeyPath<SharingCardsConfig, Bool>) {
    guard let current = config?.sharing.cards[keyPath: keyPath] else { return }
    setCard(keyPath, enabled: !current)
  }

  func setCard(_ keyPath: WritableKeyPath<SharingCardsConfig, Bool>, enabled: Bool) {
    mutateConfig { config in
      config.sharing.cards[keyPath: keyPath] = enabled
    }
    Task { await scanPublishAndFetch() }
  }

  func toggleRedaction(_ keyPath: WritableKeyPath<SharingRedactionsConfig, Bool>) {
    guard let current = config?.sharing.redactions[keyPath: keyPath] else { return }
    setRedaction(keyPath, enabled: !current)
  }

  func setRedaction(_ keyPath: WritableKeyPath<SharingRedactionsConfig, Bool>, enabled: Bool) {
    mutateConfig { config in
      config.sharing.redactions[keyPath: keyPath] = enabled
    }
  }

  func copyDiagnosticSummary() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(diagnosticSummary(), forType: .string)
  }

  // MARK: - Profile icon (AI avatar)

  // Probe on-device ImageCreator support and load the server house-style template
  // if it isn't cached yet. Called when the Profile Icon pane appears.
  func prepareAvatarSettings() async {
    // Seed the gradient pickers from the user's already-saved gradient so
    // re-opening the pane shows their current colors (not the defaults) and a
    // stray "Use gradient" tap can't silently overwrite them.
    if let g = feed?.you.user.avatarGradient,
       let start = Color(hex: g.start), let end = Color(hex: g.end) {
      gradientStart = start
      gradientEnd = end
    }
    if #available(macOS 15.4, *) {
      // Cheap synchronous eligibility gate shows/hides the AI path instantly;
      // the async probe then refines it (it also catches a missing model).
      avatarSupported = AvatarGenerator.isAvailableSync
      avatarSupported = await AvatarGenerator.isSupported
    } else {
      avatarSupported = false
    }
    if houseStyle == nil {
      await refreshHouseStyle()
    }
  }

  // Fetch (and cache) the server-owned house style from /api/me.
  func refreshHouseStyle() async {
    guard let config, isConfigured else { return }
    do {
      let account = try await client(for: config).me()
      if let style = account.houseStyle {
        houseStyle = style
      }
    } catch {
      avatarError = error.localizedDescription
    }
  }

  // Generate a preview PNG on device from the user's prompt + house style. Stores
  // the bytes + chosen prompt/style for a subsequent `useGeneratedAvatar()`.
  func generateAvatar(prompt rawPrompt: String) async {
    let prompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty else {
      avatarError = "Enter a short prompt first."
      return
    }
    guard let house = houseStyle else {
      avatarError = "Couldn't load the house style. Try again."
      return
    }
    guard #available(macOS 15.4, *), avatarSupported == true else {
      avatarError = "Profile-icon generation isn't available on this Mac."
      return
    }

    avatarError = nil
    avatarMaySetupNeeded = false
    isGeneratingAvatar = true
    do {
      let generated = try await AvatarGenerator().generate(prompt: prompt, house: house)
      avatarPreviewPNG = generated.data
      avatarLastPrompt = prompt
      // Record the style the creator actually used (it may fall back from the
      // server's first preference) so the upload header reflects what was used.
      avatarLastStyle = generated.style
    } catch let error as AvatarGenerationError {
      avatarPreviewPNG = nil
      avatarError = error.localizedDescription
      // A `.failed` after the generator's own one retry is the warm-up/"model
      // still downloading" case — offer the Image Playground affordance.
      avatarMaySetupNeeded = (error == .failed)
    } catch {
      avatarPreviewPNG = nil
      avatarError = error.localizedDescription
    }
    isGeneratingAvatar = false
  }

  // Open the system Image Playground app (surfaces/primes the model download).
  func openImagePlayground() {
    if #available(macOS 15.4, *) {
      AvatarGenerator.openImagePlayground()
    }
  }

  // Patch the locally-displayed "you" avatar fields from an authoritative server
  // response so the UI updates immediately and correctly, independent of the
  // follow-up feed GET (which is best-effort and may transiently fail).
  private func applyAvatarToYou(kind: String?, gradient: AvatarGradient?, url: String?) {
    guard var snapshot = feed else { return }
    snapshot.you.user.avatarKind = kind
    snapshot.you.user.avatarGradient = gradient
    snapshot.you.user.avatarUrl = url
    feed = snapshot
  }

  // Apply the two selected gradient colors as the profile icon. PUTs them as
  // "#RRGGBB" hex, applies the server's echoed fields to "you" immediately, then
  // best-effort refreshes the feed to propagate to friends.
  func setGradientAvatar() async {
    guard let config, isConfigured else { return }
    avatarError = nil
    isUploadingAvatar = true
    do {
      let result = try await client(for: config).setAvatarGradient(
        start: gradientStart.hexRGB,
        end: gradientEnd.hexRGB
      )
      avatarPreviewPNG = nil
      // Prefer the locally-known inputs over the loosely-decoded echo so a thin
      // or partial server response can't momentarily blank the gradient.
      applyAvatarToYou(
        kind: result.avatarKind ?? "gradient",
        gradient: result.avatarGradient ?? AvatarGradient(start: gradientStart.hexRGB, end: gradientEnd.hexRGB),
        url: nil
      )
      successMessage = "Profile icon updated."
      await refreshFeedOnly()
    } catch {
      avatarError = error.localizedDescription
    }
    isUploadingAvatar = false
  }

  // Upload the current preview PNG as the profile icon, apply the result to "you"
  // immediately, then best-effort refresh the feed.
  func useGeneratedAvatar() async {
    guard let config, isConfigured else { return }
    guard let png = avatarPreviewPNG else {
      avatarError = "Generate an icon first."
      return
    }
    avatarError = nil
    isUploadingAvatar = true
    do {
      let result = try await client(for: config).uploadAvatar(
        pngData: png,
        prompt: avatarLastPrompt,
        style: avatarLastStyle ?? ""
      )
      avatarPreviewPNG = nil
      applyAvatarToYou(kind: "image", gradient: nil, url: result.avatarURL)
      successMessage = "Profile icon updated."
      await refreshFeedOnly()
    } catch {
      avatarError = error.localizedDescription
    }
    isUploadingAvatar = false
  }

  // Clear the current profile icon (revert to initials), apply locally, then
  // best-effort refresh the feed.
  func removeAvatar() async {
    guard let config, isConfigured else { return }
    avatarError = nil
    avatarMaySetupNeeded = false
    isUploadingAvatar = true
    do {
      try await client(for: config).deleteAvatar()
      avatarPreviewPNG = nil
      applyAvatarToYou(kind: nil, gradient: nil, url: nil)
      successMessage = "Profile icon removed."
      await refreshFeedOnly()
    } catch {
      avatarError = error.localizedDescription
    }
    isUploadingAvatar = false
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

  func diagnosticSummary() -> String {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
    let cards = enabledSharingCards().joined(separator: ", ")
    return """
    Vibes diagnostics
    App: \(appVersion) (\(build))
    Config path: \(configPath)
    Relay URL: \(config?.server.relayURL.absoluteString ?? "unconfigured")
    Handle: \(config?.identity.handle ?? "unconfigured")
    Device: \(config?.device.label ?? "unconfigured")
    Last sync: \(lastSyncedAt?.formatted(date: .numeric, time: .standard) ?? "never")
    Sharing cards: \(cards.isEmpty ? "none" : cards)
    Repos: \(config?.repos.count ?? 0) configured (paths redacted)
    Token: stored in Keychain (redacted)
    """
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

  private func enabledSharingCards() -> [String] {
    guard let cards = config?.sharing.cards else { return [] }
    var enabled: [String] = []
    if cards.gitStats { enabled.append("git_stats") }
    if cards.repoAliases { enabled.append("repo_aliases") }
    if cards.spotify { enabled.append("spotify") }
    if cards.weather { enabled.append("weather") }
    return enabled
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
      if let style = account.houseStyle {
        houseStyle = style
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
