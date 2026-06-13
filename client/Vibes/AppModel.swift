import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// Settings tabs, selectable in code so onboarding can land the user on the
// right pane (e.g. the footer gear opens straight to Repositories when none
// are configured yet).
enum SettingsTab: Hashable {
  case general
  case profileIcon
  case repositories
  case sharing
  case advanced
}

@MainActor
final class AppModel: ObservableObject {
  @Published var config: VibesConfig?
  @Published var settingsTab: SettingsTab = .general
  @Published var token: String = ""
  @Published var mode: PresenceMode = .online
  @Published var manualStatus: String = ""
  @Published var feed: FeedResponse?
  @Published var stats = DailyGitStats()
  @Published var invites: [InviteSummary] = []
  @Published var latestInviteURL: URL?
  @Published var pendingInvite: PendingInvite?
  @Published var inviteCodeInput: String = ""
  // Device-linking state: the code minted on this (signed-in) Mac for adding
  // another one, and the code typed into setup on a new Mac.
  @Published var deviceLinkCode: DeviceLinkCode?
  @Published var linkCodeInput: String = ""
  // The account's active devices (Settings → General → Devices).
  @Published var devices: [DeviceSummary] = []
  // An account found in iCloud Keychain on a not-yet-configured Mac — drives
  // the setup screen's one-click "continue as @handle" card.
  @Published var syncedAccount: SyncedAccount?
  // Relay URL carried by a vibes://link/<code>?relay=… deep link or a
  // clipboard invite from a non-default relay, so self-hosted setups work
  // without touching the Advanced field.
  @Published var linkRelayHint: String?
  @Published var isBusy = false
  @Published var lastError: String?
  @Published var successMessage: String? {
    didSet {
      scheduleSuccessMessageDismissal()
    }
  }
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
  private let keychain = TokenStore()
  private let syncedAccountStore = SyncedAccountStore()
  private let scanner = GitScanner()
  private var loopTask: Task<Void, Never>?

  // Sender-side providers for the optional cards. Internal (not private) so
  // the sharing settings pane can observe provider problems (e.g. a denied
  // location prompt) next to the toggles.
  let musicProvider = MusicProvider()
  let weatherProvider = WeatherProvider()
  private var musicPublishTask: Task<Void, Never>?
  private var weatherRefreshTask: Task<Void, Never>?
  private var successMessageDismissTask: Task<Void, Never>?
  private var lastDeviceStatusPayload: StatusPayload?
  // The synced-account item is (re)written only after this device's token has
  // proven itself against the relay, so a revoked Mac can't keep advertising
  // a dead credential to the user's other Macs via iCloud Keychain.
  private var syncedAccountAdvertised = false

  static let defaultRelayURL = URL(string: "https://vibes.opentangle.com")!

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
      } else {
        recheckSyncedAccount()
        checkClipboardForInvite()
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  // Look for an account carried over via iCloud Keychain. Called at launch
  // and whenever the unconfigured app comes to the foreground — on a brand-new
  // Mac the item often syncs minutes after first launch.
  func recheckSyncedAccount() {
    guard !isConfigured else { return }
    guard let found = syncedAccountStore.read(),
          isAllowedRelayURL(found.relayURL),
          !found.token.isEmpty
    else { return }
    syncedAccount = found
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

  // "Link this Mac": exchange a pairing code from the other Mac for a fresh
  // per-device token, then install the hydrated account exactly like register.
  func linkThisMac(code rawCode: String, deviceLabel: String, relayURLText: String) async {
    let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else {
      lastError = "Enter the code from your other Mac."
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
      let identity = try await RelayClient(baseURL: relayURL, token: "").claimDeviceLinkCode(
        code: code,
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
      linkCodeInput = ""
      showSuccess("This Mac is now linked to @\(identity.user.handle).")
    } catch {
      lastError = error.localizedDescription
    }
    isBusy = false
  }

  // One-click setup from an account found in iCloud Keychain: use the synced
  // token once to mint this Mac its own per-device token, then install like
  // register. The synced credential is never stored as this Mac's token.
  func continueAsSyncedAccount(deviceLabel: String) async {
    guard let synced = syncedAccount else { return }
    let label = deviceLabel.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
      ?? Host.current().localizedName
      ?? "Mac"

    isBusy = true
    lastError = nil
    successMessage = nil
    do {
      let identity = try await RelayClient(baseURL: synced.relayURL, token: synced.token)
        .mintDeviceToken(label: label)
      let next = VibesConfig.firstLaunch(
        relayURL: synced.relayURL,
        handle: identity.user.handle,
        displayName: identity.user.displayName,
        deviceLabel: label,
        timezone: identity.user.timezone ?? TimeZone.current.identifier
      )
      await install(config: next, token: identity.token)
      syncedAccount = nil
      showSuccess("This Mac is now linked to @\(identity.user.handle).")
    } catch {
      // The synced credential is stale (its device was revoked, or the
      // account changed). Drop the dead item and fall back to the code flow.
      if (error as? RelayClientError)?.statusCode == 401 {
        syncedAccountStore.delete()
        syncedAccount = nil
        lastError = "The account saved in iCloud Keychain no longer works. Link with a code from your other Mac instead."
      } else {
        lastError = error.localizedDescription
      }
    }
    isBusy = false
  }

  // Keep the iCloud-synced account item fresh so a future new Mac can offer
  // one-click setup. Best-effort: failures (iCloud Keychain off, dev-build
  // keychain limits) silently leave the manual paths as the way in.
  private func refreshSyncedAccountItem() {
    guard let config, !token.isEmpty, !config.identity.handle.isEmpty else { return }
    syncedAccountStore.save(
      SyncedAccount(
        relayURL: config.server.relayURL,
        handle: config.identity.handle,
        displayName: config.identity.displayName,
        token: token
      )
    )
  }

  // Advertise once per launch, and only after a sync proves the token works.
  private func advertiseSyncedAccountIfNeeded() {
    guard !syncedAccountAdvertised else { return }
    syncedAccountAdvertised = true
    refreshSyncedAccountItem()
  }

  private func handleSyncFailure(_ error: Error) {
    guard (error as? RelayClientError)?.statusCode == 401 else {
      lastError = error.localizedDescription
      return
    }
    // This Mac's token was revoked (likely removed from another Mac's device
    // list). Stop advertising it, and pull it from iCloud Keychain if it's
    // the credential stored there — leaving it would break welcome-back on
    // the user's next Mac.
    syncedAccountAdvertised = true
    if let synced = syncedAccountStore.read(), synced.token == token {
      syncedAccountStore.delete()
    }
    lastError = "This Mac's access was removed. Link it again from another Mac (Settings → General)."
  }

  // Quiet on failure: this runs when Settings opens, and a transient network
  // error there shouldn't paint the main window's footer red.
  func refreshDevices() async {
    guard let config, isConfigured else { return }
    if let response = try? await client(for: config).listDevices() {
      devices = response.devices
    }
  }

  // Revoke another Mac's token. The server allows revoking your own token,
  // but the UI never offers it for the current device ("This Mac").
  func revokeDevice(_ device: DeviceSummary) async {
    guard let config, isConfigured, !device.current else { return }
    do {
      try await client(for: config).revokeToken(id: device.tokenId)
      await refreshDevices()
      showSuccess("Removed \(device.label ?? "device").")
    } catch {
      lastError = error.localizedDescription
    }
  }

  // Mint a pairing code on this (signed-in) Mac for Settings → General →
  // Link Another Mac.
  func createDeviceLinkCode() async {
    guard let config, isConfigured else { return }
    lastError = nil
    do {
      deviceLinkCode = try await client(for: config).createDeviceLinkCode()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func copyDeviceLinkCode() {
    guard let deviceLinkCode else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(deviceLinkCode.code, forType: .string)
  }

  // A vibes://link/<code>?relay=… URL to message/AirDrop to yourself: opening
  // it on the new Mac prefills both the code and the relay (so self-hosted
  // relays work without touching Advanced).
  func copyDeviceLinkURL() {
    guard let deviceLinkCode, let config else { return }
    var components = URLComponents()
    components.scheme = "vibes"
    components.host = "link"
    components.path = "/\(deviceLinkCode.code)"
    components.queryItems = [
      URLQueryItem(name: "relay", value: config.server.relayURL.absoluteString)
    ]
    guard let url = components.url else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
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
      // This token just came from the relay, so it's proven — advertise now.
      syncedAccountAdvertised = true
      refreshSyncedAccountItem()
      startLoop()
      // Invite-first onboarding: when setup started from an invite (deep link
      // or clipboard handoff), finish the job here instead of bouncing the
      // freshly signed-in user to a sheet. Taking the invite before the first
      // refresh keeps MainPanel's pendingInvite sheet from flashing open.
      let invite = pendingInvite
      pendingInvite = nil
      await refreshAll()
      if let invite {
        successMessage = nil
        await acceptInvite(code: invite.code)
      }
    } catch {
      lastError = error.localizedDescription
    }
  }

  // MARK: - Clipboard invite handoff

  // The invite landing page copies the invite link to the clipboard when the
  // visitor clicks "Download for Mac", so a brand-new install can greet them
  // with "<name> invited you" instead of making them return to the browser.
  // Only runs while unconfigured, and only reads the pasteboard once pattern
  // detection (which never shows a prompt) says a web URL is present — so the
  // system's "paste from another app" alert can't fire on an unrelated
  // clipboard.
  func checkClipboardForInvite() {
    guard !isConfigured, pendingInvite == nil else { return }
    Task { @MainActor in
      let pasteboard = NSPasteboard.general
      guard let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL]),
            patterns.contains(\.probableWebURL),
            !isConfigured, pendingInvite == nil,
            let text = pasteboard.string(forType: .string),
            let found = Self.invite(inCopiedText: text)
      else { return }
      pendingInvite = PendingInvite(code: found.code)
      inviteCodeInput = found.code
      if let relay = found.relayURL, isAllowedRelayURL(relay),
         relay != Self.defaultRelayURL {
        linkRelayHint = relay.absoluteString
      }
      fetchPendingInviteInviter(code: found.code, relayHint: found.relayURL)
    }
  }

  struct ClipboardInvite: Equatable {
    var code: String
    // Origin of an https invite link — a relay hint for self-hosted setups.
    var relayURL: URL?
  }

  // Recognize an invite in copied text: the landing page's canonical
  // https://<relay>/i/<code> (or /invite/<code>) link, a vibes://invite/<code>
  // deep link, or either of those embedded in a larger copied message.
  static func invite(inCopiedText text: String) -> ClipboardInvite? {
    let trimmed = String(text.prefix(4096)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let direct = invite(fromURLString: trimmed) {
      return direct
    }
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
      let range = NSRange(trimmed.startIndex..., in: trimmed)
      for match in detector.matches(in: trimmed, range: range) {
        if let url = match.url, let found = invite(from: url) {
          return found
        }
      }
    }
    // NSDataDetector skips custom schemes — find a vibes:// link by hand.
    if let vibesRange = trimmed.range(of: #"vibes://invite/[A-Za-z0-9_\-]+"#, options: .regularExpression) {
      return invite(fromURLString: String(trimmed[vibesRange]))
    }
    return nil
  }

  private static func invite(fromURLString string: String) -> ClipboardInvite? {
    guard let url = URL(string: string) else { return nil }
    return invite(from: url)
  }

  private static func invite(from url: URL) -> ClipboardInvite? {
    let code: String?
    var relayURL: URL?
    switch url.scheme?.lowercased() {
    case "vibes":
      guard url.host(percentEncoded: false)?.lowercased() == "invite" else { return nil }
      code = url.pathComponents.first { $0 != "/" }
    case "https", "http":
      let parts = url.pathComponents.filter { $0 != "/" }
      guard parts.count == 2, parts[0] == "i" || parts[0] == "invite" else { return nil }
      code = parts[1]
      var origin = URLComponents()
      origin.scheme = url.scheme
      origin.host = url.host(percentEncoded: false)
      origin.port = url.port
      relayURL = origin.url
    default:
      return nil
    }
    // Invite codes are base64url; the length window keeps short path slugs
    // and arbitrary long tokens from masquerading as one.
    guard let code, (16...64).contains(code.count),
          code.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    else { return nil }
    return ClipboardInvite(code: code, relayURL: relayURL)
  }

  func handleIncomingURL(_ url: URL) {
    guard url.scheme?.lowercased() == "vibes",
          let host = url.host(percentEncoded: false)?.lowercased(),
          let code = url.pathComponents.first(where: { component in
            component != "/" && !component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          })?.trimmingCharacters(in: .whitespacesAndNewlines),
          !code.isEmpty
    else {
      return
    }

    switch host {
    case "invite":
      pendingInvite = PendingInvite(code: code)
      inviteCodeInput = code
      successMessage = nil
      fetchPendingInviteInviter(code: code)
    case "link":
      // A pairing code only makes sense on a Mac that isn't set up yet — it
      // prefills the "Link this Mac" field on the setup screen, and an
      // optional ?relay=… carries the source relay for self-hosted setups.
      guard !isConfigured else { return }
      linkCodeInput = code
      if let relayText = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "relay" })?.value,
         let relayURL = URL(string: relayText),
         isAllowedRelayURL(relayURL) {
        linkRelayHint = relayText
      }
      successMessage = nil
    default:
      return
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  // Best-effort name lookup so the invite sheet / setup banner can say who
  // sent it. Works before sign-in too (the endpoint is unauthenticated — the
  // code is the capability). Failures (offline, expired code, old relay) just
  // leave the generic copy in place.
  private func fetchPendingInviteInviter(code: String, relayHint: URL? = nil) {
    let baseURL = config?.server.relayURL ?? relayHint ?? Self.defaultRelayURL
    Task {
      guard let lookup = try? await RelayClient(baseURL: baseURL, token: "").inviteLookup(code: code),
            let name = lookup.inviter,
            !name.isEmpty,
            pendingInvite?.code == code
      else { return }
      pendingInvite?.inviterName = name
    }
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
      showSuccess("Now friends with \(result.inviter.displayName).")
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
    // Refresh weather off to the side; this cycle publishes whatever's already
    // cached and the new reading is ready for the next one. Never awaited here.
    refreshWeatherInBackground()
    let nextStats = await scanner.scan(repos: config.repos, dayWindow: dayWindow, now: now)
    stats = nextStats
    do {
      let payload = StatusBuilder.payload(
        config: config,
        mode: mode,
        manualStatus: manualStatus,
        stats: nextStats,
        now: now,
        dayWindow: dayWindow,
        extraCards: sharedExtraCards(config: config)
      )
      try await client(for: config).publish(payload)
      lastDeviceStatusPayload = payload
      feed = preservingYouSnapshot(try await client(for: config).feed(), fallbackPayload: payload)
      lastSyncedAt = Date()
      persistPresence()
      advertiseSyncedAccountIfNeeded()
    } catch {
      handleSyncFailure(error)
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
    if next == .offline {
      Task { await publishCurrentSnapshotAndFetch() }
    } else {
      Task { await scanPublishAndFetch() }
    }
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
    syncProviders()
    Task { await scanPublishAndFetch() }
  }

  func updateWeatherCity(_ value: String) {
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard config?.sharing.weather.manualCity != clean else { return }
    mutateConfig { config in
      config.sharing.weather.manualCity = clean
    }
    // The cached coordinate belongs to the old city (or to Location Services).
    weatherProvider.invalidate()
    Task { await scanPublishAndFetch() }
  }

  func setWeatherShareCity(_ enabled: Bool) {
    mutateConfig { config in
      config.sharing.weather.shareCity = enabled
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
    // Cheap synchronous eligibility gate shows/hides the AI path instantly;
    // the async probe then refines it (it also catches a missing model).
    avatarSupported = AvatarGenerator.isAvailableSync
    avatarSupported = await AvatarGenerator.isSupported
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
    guard avatarSupported == true else {
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
      // `.failed` is ambiguous: ImageCreator returns the same `creationFailed`
      // for a guardrail-rejected prompt (e.g. wording that implies a person)
      // and for a model that's still downloading. The UI copy covers both and
      // offers the Image Playground affordance for the latter.
      avatarMaySetupNeeded = (error == .failed)
    } catch {
      avatarPreviewPNG = nil
      avatarError = error.localizedDescription
    }
    isGeneratingAvatar = false
  }

  // Open the system Image Playground app (surfaces/primes the model download).
  func openImagePlayground() {
    AvatarGenerator.openImagePlayground()
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
      showSuccess("Profile icon updated.")
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
      showSuccess("Profile icon updated.")
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
      showSuccess("Profile icon removed.")
      await refreshFeedOnly()
    } catch {
      avatarError = error.localizedDescription
    }
    isUploadingAvatar = false
  }

  @discardableResult
  func createInvite() async -> Bool {
    guard let config, isConfigured, !isBusy else { return false }
    isBusy = true
    defer { isBusy = false }
    do {
      let invite = try await client(for: config).createInvite()
      latestInviteURL = invite.inviteURL
      await refreshInvites()
      return true
    } catch {
      lastError = error.localizedDescription
      return false
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
    guard let config, isConfigured else { return }
    do {
      let payload = currentSnapshotPayload(config: config, mode: .offline, now: Date())
      try await client(for: config).publish(payload)
    } catch {
      lastError = error.localizedDescription
    }
  }

  private func publishCurrentSnapshotAndFetch() async {
    guard let config, isConfigured else { return }
    isBusy = true
    lastError = nil
    let now = Date()
    let payload = currentSnapshotPayload(config: config, mode: .offline, now: now)
    do {
      try await client(for: config).publish(payload)
      lastDeviceStatusPayload = payload
      feed = preservingYouSnapshot(try await client(for: config).feed(), fallbackPayload: payload)
      lastSyncedAt = Date()
    } catch {
      lastError = error.localizedDescription
    }
    isBusy = false
  }

  private func startLoop() {
    syncProviders()
    loopTask?.cancel()
    loopTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(180))
        await self?.scanPublishAndFetch()
      }
    }
  }

  // Music and weather cards for this publish, gated on the sharing toggles.
  // Reads ONLY cached provider state — never awaits — so the publish + feed are
  // never blocked behind a provider (weather's location resolution in
  // particular can hang on the permission prompt). A provider with nothing
  // cached yet just drops its card from this publish and appears on the next.
  private func sharedExtraCards(config: VibesConfig) -> [StatusCard] {
    var cards: [StatusCard] = []
    if config.sharing.cards.music, let playing = musicProvider.current {
      cards.append(playing.card)
    }
    if config.sharing.cards.weather, let snapshot = weatherProvider.latest {
      cards.append(snapshot.card(shareCity: config.sharing.weather.shareCity))
    }
    return cards
  }

  // Kick a weather refresh off the publish path. The new reading lands in
  // weatherProvider.latest for a subsequent publish; this publish doesn't wait.
  private func refreshWeatherInBackground() {
    guard let config, config.sharing.cards.weather else { return }
    let weatherConfig = config.sharing.weather
    weatherRefreshTask?.cancel()
    weatherRefreshTask = Task { [weak self] in
      await self?.weatherProvider.refresh(config: weatherConfig)
    }
  }

  // Start/stop the now-playing observers to match the sharing toggle. Called
  // on launch (startLoop) and whenever the toggle flips.
  private func syncProviders() {
    guard let config else { return }
    if config.sharing.cards.music {
      musicProvider.onChange = { [weak self] in self?.scheduleMusicPublish() }
      musicProvider.start()
      musicProvider.seedFromRunningPlayers()
    } else {
      musicProvider.stop()
    }
    // Start resolving weather (and its location prompt) in the background so a
    // reading is cached before the next publish — never on the feed's path.
    if config.sharing.cards.weather {
      refreshWeatherInBackground()
    }
  }

  // A track change shouldn't wait up to three minutes for the next loop tick,
  // but it also shouldn't publish every skip while someone hunts for a song —
  // give the dust 15 seconds to settle.
  private func scheduleMusicPublish() {
    musicPublishTask?.cancel()
    musicPublishTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(15))
      guard !Task.isCancelled else { return }
      await self?.scanPublishAndFetch()
    }
  }

  private func enabledSharingCards() -> [String] {
    guard let cards = config?.sharing.cards else { return [] }
    var enabled: [String] = ["git_stats", "repo_aliases"]
    if cards.music { enabled.append("music") }
    if cards.weather { enabled.append("weather") }
    return enabled
  }

  private func client(for config: VibesConfig) -> RelayClient {
    RelayClient(baseURL: config.server.relayURL, token: token)
  }

  private func currentSnapshotPayload(config: VibesConfig, mode: PresenceMode, now: Date) -> StatusPayload {
    let dayWindow = VibesDayWindow.current(
      now: now,
      timezone: config.identity.timezone ?? TimeZone.current.identifier
    )
    var payload = StatusBuilder.payload(
      config: config,
      mode: mode,
      manualStatus: manualStatus,
      stats: stats,
      now: now,
      dayWindow: dayWindow
    )
    if mode == .offline {
      if let lastDeviceStatusPayload {
        payload.day = lastDeviceStatusPayload.day
        payload.dayTimezone = lastDeviceStatusPayload.dayTimezone
        payload.dayStartAt = lastDeviceStatusPayload.dayStartAt
        payload.dayEndAt = lastDeviceStatusPayload.dayEndAt
        payload.cards = lastDeviceStatusPayload.cards
      } else {
        payload.cards = []
      }
    }
    return payload
  }

  private func preservingYouSnapshot(_ nextFeed: FeedResponse, fallbackPayload: StatusPayload) -> FeedResponse {
    guard fallbackPayload.mode == .offline, nextFeed.you.cards.isEmpty, !fallbackPayload.cards.isEmpty else {
      return nextFeed
    }
    var snapshot = nextFeed
    snapshot.you.cards = fallbackPayload.cards
    snapshot.you.manualStatus = fallbackPayload.manualStatus
    snapshot.you.day = fallbackPayload.day
    snapshot.you.updatedAt = fallbackPayload.updatedAt
    return snapshot
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

  private func showSuccess(_ message: String) {
    successMessage = message
  }

  private func scheduleSuccessMessageDismissal() {
    successMessageDismissTask?.cancel()
    guard let message = successMessage else {
      successMessageDismissTask = nil
      return
    }
    successMessageDismissTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(60))
      guard !Task.isCancelled, self?.successMessage == message else { return }
      self?.successMessage = nil
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
