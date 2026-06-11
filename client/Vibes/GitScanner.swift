import Foundation

struct GitScanner {
  func scan(repos: [RepoConfig], dayWindow: VibesDayWindow, now: Date = Date()) async -> DailyGitStats {
    var total = DailyGitStats()
    for repo in repos {
      guard FileManager.default.fileExists(atPath: repo.path) else { continue }
      let stats = scanRepo(repo: repo, dayWindow: dayWindow, now: now)
      if stats.hasActivity {
        total.reposTouched += 1
        total.repoAliases.append(repo.alias)
      }
      total.commits += stats.commits
      total.filesChanged += stats.filesChanged
      total.insertions += stats.insertions
      total.deletions += stats.deletions
      total.uncommittedInsertions += stats.uncommittedInsertions
      total.uncommittedDeletions += stats.uncommittedDeletions
      if let activity = stats.latestActivity,
         total.latestActivity == nil || activity > total.latestActivity! {
        total.latestActivity = activity
      }
    }
    total.repoAliases.sort()
    return total
  }

  private func scanRepo(repo: RepoConfig, dayWindow: VibesDayWindow, now: Date) -> DailyGitStats {
    var stats = DailyGitStats()
    guard let authorEmail = configuredUserEmail(repo.path) else {
      scanWorkingTree(repo: repo, into: &stats)
      if stats.hasActivity {
        stats.latestActivity = now
      }
      return stats
    }

    let log = runGit([
      "-C", repo.path,
      "log",
      "--since=\(DateFormatters.isoWithFractional.string(from: dayWindow.startAt))",
      "--until=\(DateFormatters.isoWithFractional.string(from: min(now, dayWindow.endAt)))",
      "--numstat",
      "--pretty=format:__VIBES_COMMIT__%ae"
    ])
    var includeCurrentCommit = false
    for line in log.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix("__VIBES_COMMIT__") {
        let email = line.replacingOccurrences(of: "__VIBES_COMMIT__", with: "")
        includeCurrentCommit = email.caseInsensitiveCompare(authorEmail) == .orderedSame
        if includeCurrentCommit {
          stats.commits += 1
        }
      } else if includeCurrentCommit {
        parseNumstat(line, committed: true, into: &stats)
      }
    }

    scanWorkingTree(repo: repo, into: &stats)
    if stats.hasActivity {
      stats.latestActivity = now
    }
    return stats
  }

  private func scanWorkingTree(repo: RepoConfig, into stats: inout DailyGitStats) {
    let unstaged = runGit(["-C", repo.path, "diff", "--numstat"])
    for line in unstaged.split(separator: "\n") {
      parseNumstat(line, committed: false, into: &stats)
    }
    let staged = runGit(["-C", repo.path, "diff", "--cached", "--numstat"])
    for line in staged.split(separator: "\n") {
      parseNumstat(line, committed: false, into: &stats)
    }
  }

  private func parseNumstat(_ line: Substring, committed: Bool, into stats: inout DailyGitStats) {
    let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count >= 2 else { return }
    let inserted = Int(parts[0]) ?? 0
    let deleted = Int(parts[1]) ?? 0
    if committed {
      stats.filesChanged += 1
      stats.insertions += inserted
      stats.deletions += deleted
    } else {
      stats.uncommittedInsertions += inserted
      stats.uncommittedDeletions += deleted
    }
  }

  private func runGit(_ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git"] + arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    do {
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return "" }
      return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    } catch {
      return ""
    }
  }

  private func configuredUserEmail(_ path: String) -> String? {
    let email = runGit(["-C", path, "config", "--get", "user.email"])
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return email.isEmpty ? nil : email
  }
}

struct VibesDayWindow: Equatable {
  var day: String
  var timezone: String
  var startAt: Date
  var endAt: Date

  static func current(now: Date = Date(), timezone identifier: String) -> VibesDayWindow {
    let timezone = TimeZone(identifier: identifier) ?? .current
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timezone
    let start = calendar.startOfDay(for: now)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)

    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = timezone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"

    return VibesDayWindow(
      day: formatter.string(from: now),
      timezone: timezone.identifier,
      startAt: start,
      endAt: end
    )
  }
}

struct StatusPayload: Codable {
  var deviceID: String
  var deviceLabel: String
  var mode: PresenceMode
  var manualStatus: String?
  var day: String
  var dayTimezone: String
  var dayStartAt: Date
  var dayEndAt: Date
  var updatedAt: Date
  var cards: [StatusCard]

  enum CodingKeys: String, CodingKey {
    case deviceID = "device_id"
    case deviceLabel = "device_label"
    case mode
    case manualStatus = "manual_status"
    case day
    case dayTimezone = "day_timezone"
    case dayStartAt = "day_start_at"
    case dayEndAt = "day_end_at"
    case updatedAt = "updated_at"
    case cards
  }
}

struct RelayClient {
  var baseURL: URL
  var token: String

  func register(displayName: String, deviceLabel: String) async throws -> RegisteredIdentity {
    try await send(
      path: "/api/register",
      method: "POST",
      body: RegisterRequest(
        displayName: displayName,
        deviceLabel: deviceLabel,
        timezone: TimeZone.current.identifier
      ),
      requiresAuth: false
    )
  }

  func publish(_ payload: StatusPayload) async throws {
    let _: PublishResponse = try await send(
      path: "/api/status",
      method: "POST",
      body: payload
    )
  }

  func feed() async throws -> FeedResponse {
    try await send(path: "/api/feed", method: "GET", body: Optional<String>.none)
  }

  func me() async throws -> AccountResponse {
    try await send(path: "/api/me", method: "GET", body: Optional<String>.none)
  }

  // Upload a freshly generated PNG as the current profile icon. The body is raw
  // image bytes (not JSON), so this can't use the generic `send<>`; the short
  // prompt/style ride along as headers since the body is binary.
  func uploadAvatar(pngData: Data, prompt: String, style: String) async throws -> AvatarUploadResult {
    try await sendRaw(
      path: "/api/avatar",
      method: "POST",
      body: pngData,
      contentType: "image/png",
      headers: [
        "X-Avatar-Prompt": prompt,
        "X-Avatar-Style": style
      ]
    )
  }

  // Set a two-color gradient profile icon (rendered client-side; no PNG upload).
  // PUTs JSON `{ start, end }` as "#RRGGBB" hex; the server validates, stores, and
  // returns the updated avatar fields. Reuses the JSON `send<>` (it already takes
  // an arbitrary method).
  func setAvatarGradient(start: String, end: String) async throws -> AvatarGradientResult {
    try await send(
      path: "/api/avatar/gradient",
      method: "PUT",
      body: AvatarGradientRequest(start: start, end: end)
    )
  }

  // Clear the current profile icon, reverting to initials.
  func deleteAvatar() async throws {
    let _: OKResponse = try await send(
      path: "/api/avatar",
      method: "DELETE",
      body: Optional<String>.none
    )
  }

  func createInvite() async throws -> CreatedInvite {
    try await send(path: "/api/invites", method: "POST", body: EmptyBody())
  }

  // Mint a pairing code for adding another Mac to this account.
  func createDeviceLinkCode() async throws -> DeviceLinkCode {
    try await send(path: "/api/devices/link-codes", method: "POST", body: EmptyBody())
  }

  // Exchange a pairing code (typed on the new Mac) for a fresh per-device
  // token plus account info — the same response shape as register, so the
  // setup flow is shared.
  func claimDeviceLinkCode(code: String, deviceLabel: String) async throws -> RegisteredIdentity {
    try await send(
      path: "/api/devices/link-codes/claim",
      method: "POST",
      body: ClaimLinkCodeRequest(code: code, deviceLabel: deviceLabel),
      requiresAuth: false
    )
  }

  // The account's active devices (labeled tokens), with the caller flagged.
  func listDevices() async throws -> DeviceListResponse {
    try await send(path: "/api/devices", method: "GET", body: Optional<String>.none)
  }

  // Mint a fresh labeled token using this client's (already trusted) token —
  // the iCloud-Keychain welcome-back path, so the synced credential never
  // becomes the new Mac's working token.
  func mintDeviceToken(label: String) async throws -> RegisteredIdentity {
    try await send(path: "/api/tokens", method: "POST", body: MintTokenRequest(label: label))
  }

  func revokeToken(id: String) async throws {
    let _: OKResponse = try await send(
      path: "/api/tokens/revoke",
      method: "POST",
      body: RevokeTokenRequest(tokenId: id)
    )
  }

  func acceptInvite(code: String) async throws -> AcceptInviteResult {
    try await send(
      path: "/api/invites/\(code)/accept",
      method: "POST",
      body: Optional<String>.none
    )
  }

  func listInvites() async throws -> InviteListResponse {
    try await send(path: "/api/invites", method: "GET", body: Optional<String>.none)
  }

  func revokeInvite(id: String) async throws {
    let _: OKResponse = try await send(
      path: "/api/invites/\(id)/revoke",
      method: "POST",
      body: Optional<String>.none
    )
  }

  private func send<Response: Decodable, Body: Encodable>(
    path: String,
    method: String,
    body: Body?,
    requiresAuth: Bool = true
  ) async throws -> Response {
    guard baseURL.isAllowedRelayTransport else {
      throw RelayClientError.insecureRelayURL
    }
    var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
    request.httpMethod = method
    if requiresAuth {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONCoding.encoder.encode(body)
    }

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw RelayClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      if let error = try? JSONCoding.decoder.decode(ErrorEnvelope.self, from: data) {
        throw RelayClientError.serverResponse(
          message: error.error.message,
          status: http.statusCode,
          code: error.error.code
        )
      }
      throw RelayClientError.serverResponse(
        message: "Relay returned HTTP \(http.statusCode).",
        status: http.statusCode,
        code: nil
      )
    }
    return try JSONCoding.decoder.decode(Response.self, from: data)
  }

  // Sibling of `send<>` for raw-byte request bodies (the generic one is JSON
  // only). Same HTTPS guard, bearer auth, and error-envelope decoding; the body
  // is posted verbatim with the given content type. Header values are sanitized
  // to a header-safe ASCII subset so a stray newline/control char can't break
  // the request.
  private func sendRaw<Response: Decodable>(
    path: String,
    method: String,
    body: Data,
    contentType: String,
    headers: [String: String] = [:]
  ) async throws -> Response {
    guard baseURL.isAllowedRelayTransport else {
      throw RelayClientError.insecureRelayURL
    }
    var request = URLRequest(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
    for (name, value) in headers {
      request.setValue(value.headerSafe, forHTTPHeaderField: name)
    }
    request.httpBody = body

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw RelayClientError.invalidResponse
    }
    guard (200..<300).contains(http.statusCode) else {
      if let error = try? JSONCoding.decoder.decode(ErrorEnvelope.self, from: data) {
        throw RelayClientError.serverResponse(
          message: error.error.message,
          status: http.statusCode,
          code: error.error.code
        )
      }
      throw RelayClientError.serverResponse(
        message: "Relay returned HTTP \(http.statusCode).",
        status: http.statusCode,
        code: nil
      )
    }
    return try JSONCoding.decoder.decode(Response.self, from: data)
  }
}

struct EmptyBody: Codable {}
struct PublishResponse: Codable { var ok: Bool }
struct OKResponse: Codable { var ok: Bool }

struct AccountResponse: Codable {
  var user: UserSummary
  var houseStyle: HouseStyle?

  enum CodingKeys: String, CodingKey {
    case user
    case houseStyle = "house_style"
  }
}

struct AvatarUploadResult: Codable {
  var id: String
  var avatarURL: String

  enum CodingKeys: String, CodingKey {
    case id
    case avatarURL = "avatar_url"
  }
}

struct AvatarGradientRequest: Codable {
  var start: String
  var end: String
}

// The updated avatar fields the server echoes back after setting a gradient.
// Decoded loosely (all optional) so future field additions don't break decoding.
struct AvatarGradientResult: Codable {
  var avatarKind: String?
  var avatarGradient: AvatarGradient?
  var avatarURL: String?

  enum CodingKeys: String, CodingKey {
    case avatarKind = "avatar_kind"
    case avatarGradient = "avatar_gradient"
    case avatarURL = "avatar_url"
  }
}

struct CreatedInvite: Codable {
  var id: String
  var inviteURL: URL
  var expiresAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case inviteURL = "invite_url"
    case expiresAt = "expires_at"
  }
}

struct InviteListResponse: Codable {
  var invites: [InviteSummary]
}

struct ErrorEnvelope: Codable {
  struct RelayErrorBody: Codable {
    var code: String
    var message: String
  }
  var error: RelayErrorBody
}

enum RelayClientError: LocalizedError {
  case invalidResponse
  case insecureRelayURL
  case serverResponse(message: String, status: Int, code: String?)

  var errorDescription: String? {
    switch self {
    case .invalidResponse: "Relay returned an invalid response."
    case .insecureRelayURL: "Relay URL must use HTTPS unless it is localhost."
    case .serverResponse(let message, _, _): message
    }
  }

  var statusCode: Int? {
    switch self {
    case .serverResponse(_, let status, _): status
    default: nil
    }
  }
}

private extension URL {
  var isAllowedRelayTransport: Bool {
    if scheme == "https" { return true }
    guard scheme == "http", let host = host(percentEncoded: false)?.lowercased() else { return false }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
  }
}

enum StatusBuilder {
  static func payload(
    config: VibesConfig,
    mode: PresenceMode,
    manualStatus: String,
    stats: DailyGitStats,
    now: Date = Date(),
    dayWindow: VibesDayWindow? = nil
  ) -> StatusPayload {
    let window = dayWindow ?? VibesDayWindow.current(
      now: now,
      timezone: config.identity.timezone ?? TimeZone.current.identifier
    )
    return StatusPayload(
      deviceID: config.device.id,
      deviceLabel: config.device.label,
      mode: mode,
      manualStatus: manualStatus.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
      day: window.day,
      dayTimezone: window.timezone,
      dayStartAt: window.startAt,
      dayEndAt: window.endAt,
      updatedAt: now,
      cards: buildCards(stats: stats)
    )
  }

  private static func buildCards(stats: DailyGitStats) -> [StatusCard] {
    var cards: [StatusCard] = []
    cards.append(
      StatusCard(
        type: "git_stats",
        enabled: true,
        summary: stats.summary,
        data: [
          "commits": .int(stats.commits),
          "files_changed": .int(stats.filesChanged),
          "insertions": .int(stats.insertions),
          "deletions": .int(stats.deletions),
          "uncommitted_insertions": .int(stats.uncommittedInsertions),
          "uncommitted_deletions": .int(stats.uncommittedDeletions),
          "repos_touched": .int(stats.reposTouched)
        ]
      )
    )

    if !stats.repoAliases.isEmpty {
      cards.append(
        StatusCard(
          type: "repo_aliases",
          enabled: true,
          summary: stats.repoAliases.joined(separator: ", "),
          data: ["aliases": .array(stats.repoAliases.map { .string($0) })]
        )
      )
    }
    return cards
  }

  static func vibesDay(_ date: Date, timezone: String) -> String {
    VibesDayWindow.current(now: date, timezone: timezone).day
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }

  // Strip control characters (newlines, CR, etc.) so a user-typed prompt can be
  // safely passed as an HTTP header value.
  var headerSafe: String {
    unicodeScalars.filter { $0 >= " " && $0 != "\u{7F}" }
      .map(String.init)
      .joined()
  }
}
